package ru.kinoprop.replika_recorder;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

/**
 * Служба переднего плана на время записи экрана. Без неё Android 10+ не даёт
 * получить MediaProjection. Сама ничего не пишет: после startForeground
 * сообщает плагину «готово», дальше работает плагин.
 */
public class ReplikaRecorderService extends Service {
    interface Listener {
        void onReady();

        void onFailed(Exception e);
    }

    private static final String CHANNEL_ID = "replika_recording";
    private static final int NOTIFICATION_ID = 7421;

    private static volatile Listener listener;

    static void start(Context context, Listener l) {
        listener = l;
        Intent intent = new Intent(context, ReplikaRecorderService.class);
        if (Build.VERSION.SDK_INT >= 26) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    static void stop(Context context) {
        listener = null;
        context.stopService(new Intent(context, ReplikaRecorderService.class));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        final Listener l = listener;
        try {
            startForegroundCompat();
        } catch (Exception e) {
            if (l != null) {
                l.onFailed(e);
            }
            stopSelf();
            return START_NOT_STICKY;
        }
        if (l != null) {
            new Handler(Looper.getMainLooper()).post(l::onReady);
        }
        return START_NOT_STICKY;
    }

    private void startForegroundCompat() {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "Запись видеозвонка", NotificationManager.IMPORTANCE_LOW);
            if (nm != null) {
                nm.createNotificationChannel(channel);
            }
            builder = new Notification.Builder(this, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(this);
        }
        Notification notification = builder
                .setContentTitle("Реплика")
                .setContentText("Идёт запись видеозвонка")
                .setSmallIcon(getApplicationInfo().icon)
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
