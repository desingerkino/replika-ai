package ru.kinoprop.replika_recorder;

import android.Manifest;
import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.MediaRecorder;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.util.DisplayMetrics;

import androidx.annotation.NonNull;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Запись экрана приложения в mp4 (MediaProjection + MediaRecorder) и
 * сохранение видео в галерею (MediaStore, папка Movies/Replika).
 */
public class ReplikaRecorderPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {

    private static final String CHANNEL = "ru.kinoprop.replika/recorder";
    private static final int REQ_PROJECTION = 7421;
    private static final int REQ_STORAGE = 7422;

    private final Handler main = new Handler(Looper.getMainLooper());

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding binding;

    // Состояние записи.
    private MethodChannel.Result pendingStart;
    private boolean wantMic = true;
    private int projectionCode;
    private Intent projectionData;
    private MediaProjection projection;
    private MediaProjection.Callback projectionCallback;
    private VirtualDisplay display;
    private MediaRecorder recorder;
    private File outFile;
    private boolean recording = false;
    private String finishedPath; // файл, завершённый самой системой (кнопка «стоп» в шторке)

    private MethodChannel.Result pendingStorage;

    // ---------- FlutterPlugin ----------

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding b) {
        context = b.getApplicationContext();
        channel = new MethodChannel(b.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding b) {
        channel.setMethodCallHandler(null);
        channel = null;
        finishRecording(); // не оставляем открытый рекордер
    }

    // ---------- ActivityAware ----------

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding b) {
        attach(b);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detach();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding b) {
        attach(b);
    }

    @Override
    public void onDetachedFromActivity() {
        detach();
    }

    private void attach(ActivityPluginBinding b) {
        binding = b;
        activity = b.getActivity();
        b.addActivityResultListener(this);
        b.addRequestPermissionsResultListener(this);
    }

    private void detach() {
        if (binding != null) {
            binding.removeActivityResultListener(this);
            binding.removeRequestPermissionsResultListener(this);
        }
        binding = null;
        activity = null;
    }

    // ---------- MethodCallHandler ----------

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "isSupported":
                result.success(Build.VERSION.SDK_INT >= 21);
                break;
            case "requestGalleryAccess":
                requestGalleryAccess(result);
                break;
            case "start":
                Boolean mic = call.argument("microphone");
                start(mic == null || mic, result);
                break;
            case "stop":
                result.success(finishRecording());
                break;
            case "saveToGallery":
                saveToGallery(call.argument("path"), call.argument("name"), result);
                break;
            default:
                result.notImplemented();
        }
    }

    // ---------- Запись ----------

    private void start(boolean mic, MethodChannel.Result result) {
        if (recording || pendingStart != null) {
            result.error("busy", "Запись уже идёт", null);
            return;
        }
        if (activity == null) {
            result.error("unavailable", "Нет активного экрана", null);
            return;
        }
        wantMic = mic;
        finishedPath = null;
        MediaProjectionManager mpm = (MediaProjectionManager) context.getSystemService(Context.MEDIA_PROJECTION_SERVICE);
        if (mpm == null) {
            result.error("unavailable", "Запись экрана недоступна", null);
            return;
        }
        pendingStart = result;
        try {
            activity.startActivityForResult(mpm.createScreenCaptureIntent(), REQ_PROJECTION);
        } catch (Exception e) {
            pendingStart = null;
            result.error("failed", String.valueOf(e.getMessage()), null);
        }
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQ_PROJECTION) {
            return false;
        }
        final MethodChannel.Result result = pendingStart;
        if (result == null) {
            return true;
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingStart = null;
            result.error("denied", "Запись экрана не разрешена", null);
            return true;
        }
        projectionCode = resultCode;
        projectionData = data;
        // Android 14: служба переднего плана должна запуститься ДО getMediaProjection.
        ReplikaRecorderService.start(context, new ReplikaRecorderService.Listener() {
            @Override
            public void onReady() {
                beginRecording();
            }

            @Override
            public void onFailed(Exception e) {
                MethodChannel.Result r = pendingStart;
                pendingStart = null;
                if (r != null) {
                    r.error("failed", String.valueOf(e.getMessage()), null);
                }
            }
        });
        return true;
    }

    private void beginRecording() {
        final MethodChannel.Result result = pendingStart;
        pendingStart = null;
        if (result == null) {
            ReplikaRecorderService.stop(context);
            return;
        }
        try {
            MediaProjectionManager mpm = (MediaProjectionManager) context.getSystemService(Context.MEDIA_PROJECTION_SERVICE);
            projection = mpm.getMediaProjection(projectionCode, projectionData);
            projectionData = null;
            if (projection == null) {
                throw new IllegalStateException("MediaProjection недоступен");
            }
            // Android 14 требует колбэк до создания виртуального экрана.
            projectionCallback = new MediaProjection.Callback() {
                @Override
                public void onStop() {
                    // Систему остановили сами (кнопка в шторке): корректно закрываем файл.
                    finishedPath = finishRecording();
                }
            };
            projection.registerCallback(projectionCallback, main);

            DisplayMetrics m = new DisplayMetrics();
            activity.getWindowManager().getDefaultDisplay().getRealMetrics(m);
            int w = m.widthPixels;
            int h = m.heightPixels;
            int longSide = Math.max(w, h);
            if (longSide > 1920) {
                float k = 1920f / longSide;
                w = Math.round(w * k);
                h = Math.round(h * k);
            }
            w -= w % 2;
            h -= h % 2;

            outFile = new File(context.getCacheDir(), "replika_rec_" + System.currentTimeMillis() + ".mp4");
            boolean micOk = wantMic && hasMic();
            try {
                recorder = buildRecorder(w, h, micOk);
            } catch (Exception e) {
                if (!micOk) {
                    throw e;
                }
                // Микрофон занят/недоступен — пишем хотя бы картинку.
                releaseRecorderQuietly();
                recorder = buildRecorder(w, h, false);
            }
            display = projection.createVirtualDisplay("replika_call", w, h, m.densityDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, recorder.getSurface(), null, null);
            recorder.start();
            recording = true;
            result.success(null);
        } catch (Exception e) {
            cleanupAfterError();
            result.error("failed", String.valueOf(e.getMessage()), null);
        }
    }

    private MediaRecorder buildRecorder(int w, int h, boolean mic) throws Exception {
        MediaRecorder r = Build.VERSION.SDK_INT >= 31 ? new MediaRecorder(context) : new MediaRecorder();
        try {
            if (mic) {
                r.setAudioSource(MediaRecorder.AudioSource.MIC);
            }
            r.setVideoSource(MediaRecorder.VideoSource.SURFACE);
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            r.setVideoEncoder(MediaRecorder.VideoEncoder.H264);
            if (mic) {
                r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
                r.setAudioEncodingBitRate(128000);
                r.setAudioSamplingRate(44100);
            }
            r.setVideoSize(w, h);
            r.setVideoFrameRate(30);
            r.setVideoEncodingBitRate(8 * 1000 * 1000);
            r.setOutputFile(outFile.getAbsolutePath());
            r.prepare();
            return r;
        } catch (Exception e) {
            try {
                r.release();
            } catch (Exception ignored) {
            }
            throw e;
        }
    }

    private boolean hasMic() {
        return Build.VERSION.SDK_INT < 23
                || context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }

    private void releaseRecorderQuietly() {
        if (recorder != null) {
            try {
                recorder.release();
            } catch (Exception ignored) {
            }
            recorder = null;
        }
    }

    private void cleanupAfterError() {
        releaseRecorderQuietly();
        if (display != null) {
            try {
                display.release();
            } catch (Exception ignored) {
            }
            display = null;
        }
        stopProjection();
        if (outFile != null) {
            //noinspection ResultOfMethodCallIgnored
            outFile.delete();
            outFile = null;
        }
        recording = false;
        ReplikaRecorderService.stop(context);
    }

    private void stopProjection() {
        if (projection != null) {
            try {
                if (projectionCallback != null) {
                    projection.unregisterCallback(projectionCallback);
                }
                projection.stop();
            } catch (Exception ignored) {
            }
            projection = null;
            projectionCallback = null;
        }
    }

    /** Останавливает запись и закрывает файл. Возвращает путь или null. Можно вызывать повторно. */
    private String finishRecording() {
        if (!recording) {
            String p = finishedPath;
            finishedPath = null;
            return p;
        }
        recording = false;
        String path = outFile != null ? outFile.getAbsolutePath() : null;
        boolean ok = true;
        try {
            recorder.stop();
        } catch (RuntimeException e) {
            ok = false; // слишком короткая запись — данных нет
        }
        releaseRecorderQuietly();
        if (display != null) {
            try {
                display.release();
            } catch (Exception ignored) {
            }
            display = null;
        }
        stopProjection();
        ReplikaRecorderService.stop(context);
        File f = outFile;
        outFile = null;
        if (!ok || f == null || !f.exists() || f.length() == 0) {
            if (f != null) {
                //noinspection ResultOfMethodCallIgnored
                f.delete();
            }
            return null;
        }
        return path;
    }

    // ---------- Галерея ----------

    private boolean needsStoragePermission() {
        return Build.VERSION.SDK_INT >= 23 && Build.VERSION.SDK_INT <= 28;
    }

    private boolean hasStoragePermission() {
        return !needsStoragePermission()
                || context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestGalleryAccess(MethodChannel.Result result) {
        if (hasStoragePermission()) {
            result.success(true);
            return;
        }
        if (activity == null || pendingStorage != null) {
            result.success(false);
            return;
        }
        pendingStorage = result;
        activity.requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, REQ_STORAGE);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != REQ_STORAGE) {
            return false;
        }
        MethodChannel.Result r = pendingStorage;
        pendingStorage = null;
        if (r != null) {
            r.success(grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED);
        }
        return true;
    }

    private void saveToGallery(final String path, final String name, final MethodChannel.Result result) {
        if (path == null || name == null) {
            result.error("save_failed", "Не указан файл", null);
            return;
        }
        final File src = new File(path);
        if (!src.exists()) {
            result.error("save_failed", "Файл записи не найден", null);
            return;
        }
        if (!hasStoragePermission()) {
            result.error("no_access", "Нет доступа к памяти", null);
            return;
        }
        new Thread(() -> {
            try {
                copyToGallery(src, name);
                main.post(() -> result.success(true));
            } catch (final Exception e) {
                main.post(() -> result.error("save_failed", String.valueOf(e.getMessage()), null));
            }
        }).start();
    }

    private Uri copyToGallery(File src, String name) throws Exception {
        if (Build.VERSION.SDK_INT >= 29) {
            ContentResolver resolver = context.getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.Video.Media.DISPLAY_NAME, name);
            values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
            values.put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Replika");
            values.put(MediaStore.Video.Media.IS_PENDING, 1);
            Uri uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
            if (uri == null) {
                throw new IllegalStateException("MediaStore не создал запись");
            }
            try (InputStream in = new FileInputStream(src);
                 OutputStream out = resolver.openOutputStream(uri)) {
                if (out == null) {
                    throw new IllegalStateException("Нельзя открыть файл в галерее");
                }
                copy(in, out);
            } catch (Exception e) {
                resolver.delete(uri, null, null);
                throw e;
            }
            ContentValues done = new ContentValues();
            done.put(MediaStore.Video.Media.IS_PENDING, 0);
            resolver.update(uri, done, null, null);
            return uri;
        }
        File dir = new File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Replika");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("Не удалось создать папку Movies/Replika");
        }
        File dst = new File(dir, name);
        try (InputStream in = new FileInputStream(src); OutputStream out = new FileOutputStream(dst)) {
            copy(in, out);
        }
        MediaScannerConnection.scanFile(context, new String[]{dst.getAbsolutePath()}, new String[]{"video/mp4"}, null);
        return Uri.fromFile(dst);
    }

    private static void copy(InputStream in, OutputStream out) throws Exception {
        byte[] buf = new byte[64 * 1024];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
        out.flush();
    }
}
