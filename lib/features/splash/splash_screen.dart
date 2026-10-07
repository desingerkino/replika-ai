import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/glass_background.dart';
import '../../design_system/loading_indicator.dart';
import '../../design_system/replika_logo.dart';

/// Стартовый экран REPLIKA MESSENGER по эталону docs/brand/splash_reference.png.
///
/// Экран собран на «холсте» эталона ([design], 393 пункта в ширину) и целиком
/// масштабируется под телефон: на более высоких экранах чуть обрезаются края
/// волн, на более низких — верх и низ; сфера, надписи и полоса остаются в
/// центре и не искажаются. Время, сеть, батарея и Dynamic Island — настоящие,
/// системные: экран только делает значки белыми.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onFinished});

  /// Полоса загрузки дошла до конца.
  final VoidCallback? onFinished;

  /// Холст эталона в пунктах.
  static const Size design = Size(393, 393 * 1419 / 686);

  static const Duration appearDuration = Duration(milliseconds: 1200);
  static const Duration glowDuration = Duration(seconds: 3);
  static const Duration loadingDuration = Duration(milliseconds: 2500);

  /// Без анимаций экран не задерживает запуск дольше этого.
  static const Duration reducedMotionHold = Duration(milliseconds: 600);

  // Раскладка в пунктах холста (сняты с эталона).
  static const Offset orbCenter = Offset(195.4, 291.0);
  static const double orbDiameter = 246.3;
  static const double nameCapCenter = 441.4;
  static const double subCapCenter = 477.2;
  static const double barCenter = 528.2;
  static const double statusCapCenter = 558.6;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _appear =
      AnimationController(vsync: this, duration: SplashScreen.appearDuration);
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: SplashScreen.glowDuration);
  // preserve: при системном «уменьшении движения» Flutter сам сжимает
  // длительность анимаций, а эта ещё и отсчитывает время показа экрана.
  late final AnimationController _loading = AnimationController(
    vsync: this,
    duration: SplashScreen.loadingDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  late final Animation<double> _appearCurve =
      CurvedAnimation(parent: _appear, curve: Curves.easeOutCubic);
  late final Animation<double> _reveal =
      CurvedAnimation(parent: _appear, curve: const Interval(0, 0.45, curve: Curves.easeOut));
  late final Animation<double> _glowCurve = CurvedAnimation(parent: _glow, curve: Curves.easeInOut);
  late final Animation<double> _loadingCurve =
      CurvedAnimation(parent: _loading, curve: Curves.easeInOut);

  bool _started = false;
  bool _reduceMotion = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _loading.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_finished) {
        _finished = true;
        widget.onFinished?.call();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      // Статичный экран: всё сразу на месте, полоса заполнена.
      _appear.value = 1;
      _glow.value = 1;
      _loading
        ..duration = SplashScreen.reducedMotionHold
        ..forward();
    } else {
      _appear.forward();
      _glow.repeat(reverse: true);
      _loading.forward();
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    _glow.dispose();
    _loading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const design = SplashScreen.design;
    final orbSide = ReplikaOrb.sideFor(SplashScreen.orbDiameter);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: ColoredBox(
        color: GlassPalette.navy,
        child: SizedBox.expand(
          child: MediaQuery.withNoTextScaling(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: design.width,
                height: design.height,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_appear, _glow, _loading]),
                  builder: (context, _) {
                    final reveal = _reveal.value;
                    return Stack(
                      children: [
                        Positioned.fill(child: GlassBackground(reveal: reveal)),
                        Positioned(
                          left: SplashScreen.orbCenter.dx - orbSide / 2,
                          top: SplashScreen.orbCenter.dy - orbSide / 2,
                          child: ReplikaOrb(
                            diameter: SplashScreen.orbDiameter,
                            appear: _appearCurve.value,
                            glow: _glowCurve.value,
                          ),
                        ),
                        _line(
                          capCenter: SplashScreen.nameCapCenter,
                          fontSize: SplashLogotype.nameSize,
                          child: Opacity(opacity: reveal, child: const SplashLogotype()),
                        ),
                        _line(
                          capCenter: SplashScreen.subCapCenter,
                          fontSize: SplashLogotype.subSize,
                          child: Opacity(opacity: reveal, child: const SplashSubtitle()),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: SplashScreen.barCenter - (5.2 + GlassLoadingBar.glowPad * 2) / 2,
                          child: Center(
                            child: Opacity(
                              opacity: reveal,
                              child: GlassLoadingBar(
                                progress: _reduceMotion ? 1 : _loadingCurve.value,
                              ),
                            ),
                          ),
                        ),
                        _line(
                          capCenter: SplashScreen.statusCapCenter,
                          fontSize: SplashStatusText.size,
                          child: Opacity(opacity: reveal, child: const SplashStatusText()),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Строка текста, у которой середина заглавных букв стоит на [capCenter].
  /// У Inter при высоте строки 1.0 она на 0.4365 кегля ниже верха строки.
  static Widget _line({required double capCenter, required double fontSize, required Widget child}) {
    return Positioned(
      left: 0,
      right: 0,
      top: capCenter - fontSize * 0.4365,
      child: Center(child: child),
    );
  }
}

/// «REPLIKA»: разреженные заглавные, белый с переходом в голубой, свечение.
class SplashLogotype extends StatelessWidget {
  const SplashLogotype({super.key});

  static const String text = 'REPLIKA';
  static const double nameSize = 32.3;
  static const double subSize = 17.3;
  static const double spacing = 20.1;

  static const TextStyle _base = TextStyle(
    inherit: false,
    fontFamily: 'Inter',
    fontSize: nameSize,
    fontWeight: FontWeight.w400,
    letterSpacing: spacing,
    height: 1,
    decoration: TextDecoration.none,
    textBaseline: TextBaseline.alphabetic,
  );

  @override
  Widget build(BuildContext context) {
    // Разрядка добавляется и после последней буквы — сдвигаем, чтобы слово
    // стояло ровно по центру.
    return Padding(
      padding: const EdgeInsets.only(left: spacing),
      child: Stack(
        children: [
          // Свечение: буквы невидимы, видны только их размытые тени.
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: _base.copyWith(
              color: const Color(0x00000000),
              shadows: const [
                Shadow(color: Color(0x704678FF), blurRadius: 11),
                Shadow(color: Color(0x384678FF), blurRadius: 4),
              ],
            ),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Color(0xFFF2F3F7),
                Color(0xFFE8EAF0),
                Color(0xFF8ABFF7),
                Color(0xFF66AEF4),
                Color(0xFF7AB1F7),
                Color(0xFFB9AAF7),
              ],
              stops: [0, 0.30, 0.42, 0.56, 0.82, 1],
            ).createShader(Rect.fromLTWH(0, 0, bounds.width - spacing, bounds.height)),
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: _base.copyWith(color: const Color(0xFFFFFFFF)),
            ),
          ),
        ],
      ),
    );
  }
}

/// «MESSENGER»: вторая строка, меньше и голубая.
class SplashSubtitle extends StatelessWidget {
  const SplashSubtitle({super.key});

  static const String text = 'MESSENGER';
  static const double spacing = 7.5;

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: spacing),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          inherit: false,
          fontFamily: 'Inter',
          fontSize: SplashLogotype.subSize,
          fontWeight: FontWeight.w400,
          letterSpacing: spacing,
          height: 1,
          color: Color(0xFF4A94E6),
          decoration: TextDecoration.none,
          textBaseline: TextBaseline.alphabetic,
          shadows: [Shadow(color: Color(0x552864FF), blurRadius: 7)],
        ),
      ),
    );
  }
}

/// «Загрузка...» под полосой.
class SplashStatusText extends StatelessWidget {
  const SplashStatusText({super.key});

  static const String text = 'Загрузка...';
  static const double size = 12.6;

  @override
  Widget build(BuildContext context) {
    return const Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        inherit: false,
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.3,
        height: 1,
        color: Color(0xE6D6D8EC),
        decoration: TextDecoration.none,
        textBaseline: TextBaseline.alphabetic,
      ),
    );
  }
}
