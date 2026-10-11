// Owned by AppWand. The start-up screen, shown while the saved session is
// checked and for at least splashMinimum. Its look is picked in AppWand
// ("App theme", Splash), and the native launch screens (Android, iOS, web)
// are written to match: the same background, and the logo the same size in
// the middle, so the hand-over to the app doesn't show.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.g.dart' show appTitle;
import 'theme.dart';

/// The box the logo fits in, in logical pixels. The native launch screens
/// draw it at the same size.
const double splashLogoSize = 132;

/// True until the start-up screen has been on screen for splashMinimum; the
/// router keeps it there until then.
final splashHoldProvider = NotifierProvider<SplashHold, bool>(SplashHold.new);

class SplashHold extends Notifier<bool> {
  @override
  bool build() {
    if (splashMinimum <= Duration.zero) return false;
    final timer = Timer(splashMinimum, () => state = false);
    ref.onDispose(timer.cancel);
    return true;
  }
}

/// The start-up screen's background in [brightness].
Color splashColor(Brightness brightness) => brightness == Brightness.dark ? splashBackgroundDark : splashBackground;

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (splashStyle == SplashStyle.pulse) {
      _motion.repeat(reverse: true);
    } else {
      _motion.forward();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = splashColor(theme.brightness);
    final light = ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    final ink = light ? Colors.white : const Color(0xFF1C1B1F);
    final asset = logoAsset;
    final logoStyle = splashStyle == SplashStyle.logoName || splashStyle == SplashStyle.logo || splashStyle == SplashStyle.pulse;
    final showLogo = asset != null && logoStyle;
    // Without a logo, the logo styles show the name in its place.
    final nameInMiddle = splashStyle == SplashStyle.wordmark || (logoStyle && !showLogo);

    // What the native launch screen didn't show fades in.
    final fadeIn = CurvedAnimation(parent: _motion, curve: const Interval(0.15, 0.6, curve: Curves.easeOut));
    final pulse = Tween<double>(begin: 1, end: 0.9).animate(CurvedAnimation(parent: _motion, curve: Curves.easeInOut));

    Widget? middle;
    if (showLogo) {
      middle = SizedBox.square(dimension: splashLogoSize, child: Image.asset(asset, fit: BoxFit.contain));
    } else if (nameInMiddle) {
      middle = Text(
        appTitle,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineLarge?.copyWith(color: ink, fontWeight: FontWeight.w800),
      );
      if (splashStyle != SplashStyle.pulse) middle = FadeTransition(opacity: fadeIn, child: middle);
    }
    if (middle != null && splashStyle == SplashStyle.pulse) middle = ScaleTransition(scale: pulse, child: middle);

    final nameBelow = showLogo && splashStyle == SplashStyle.logoName;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: light ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: background,
        body: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              if (middle != null) Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: middle)),
              if (nameBelow)
                Positioned(
                  left: 32,
                  right: 32,
                  top: box.maxHeight / 2 + splashLogoSize / 2 + 24,
                  child: FadeTransition(
                    opacity: fadeIn,
                    child: Text(
                      appTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(color: ink, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              if (splashSpinner)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 56,
                  child: Center(
                    child: FadeTransition(
                      opacity: splashStyle == SplashStyle.pulse ? const AlwaysStoppedAnimation(1.0) : fadeIn,
                      child: SizedBox.square(
                        dimension: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: ink.withAlpha(200)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
