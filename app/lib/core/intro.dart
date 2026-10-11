// Owned by AppWand. The intro: a few welcome slides shown once on each
// device, after the start-up screen and before sign-in. The slides are
// written in AppWand (Intro) into intro.g.dart; no page builds a welcome or
// onboarding screen of its own.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'intro.g.dart';
import 'theme.dart' show AppStyle, appStyle;

/// How the slides are laid out, picked in AppWand (Intro): the picture in
/// the middle over the text; the picture filling the screen with the text
/// and buttons on a panel at the bottom; the slide in a card on the brand
/// colour; or the picture on one side and the text on the other.
enum IntroLayout { centered, fullImage, card, split }

/// One slide: a picture (an image under assets/, or else the icon) over a
/// title and a text, both in English and shown through tr().
class IntroSlide {
  const IntroSlide(this.title, this.text, this.icon, {this.image});
  final String title;
  final String text;
  final IconData icon;
  final String? image;
}

/// Whether the intro has been seen on this device; the router shows the
/// slides to a signed-out person until it has.
final introSeenProvider = NotifierProvider<IntroSeen, bool>(IntroSeen.new);

class IntroSeen extends Notifier<bool> {
  static const String _key = 'intro_seen';
  static bool _saved = false;

  /// Reads the saved state; main() awaits it before runApp. A debug run
  /// forgets it, so the slides can be looked at again while the app is built.
  static Future<void> load() async {
    if (kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    _saved = prefs.getBool(_key) ?? false;
  }

  @override
  bool build() => _saved;

  /// The slides were read or skipped: they are not shown here again.
  Future<void> done() async {
    state = true;
    _saved = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}

class IntroPage extends ConsumerStatefulWidget {
  const IntroPage({super.key});

  @override
  ConsumerState<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends ConsumerState<IntroPage> {
  final PageController _pages = PageController();
  int _index = 0;

  bool get _last => _index >= appIntro.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // The router leaves the intro once it is seen.
  void _finish() => ref.read(introSeenProvider.notifier).done();

  void _go(int index) {
    if (index < 0 || index >= appIntro.length) return;
    // The split layout has no pager: its slide is swapped in place.
    if (!_pages.hasClients) {
      setState(() => _index = index);
    } else if (MediaQuery.of(context).disableAnimations) {
      _pages.jumpToPage(index);
    } else {
      _pages.animateToPage(index, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  void _next() {
    if (_last) {
      _finish();
    } else {
      _go(_index + 1);
    }
  }

  /// A sideways flick over a part that is not the pager moves a slide on or back.
  void _swipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 200) return;
    final forward = (velocity < 0) != (Directionality.of(context) == TextDirection.rtl);
    _go(_index + (forward ? 1 : -1));
  }

  /// The language button and Skip; in [color] where they sit on a picture or on the brand colour.
  Widget _top({Color? color}) {
    final row = SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const LanguageButton(),
            const Spacer(),
            if (appIntroSkip && !_last)
              TextButton(
                onPressed: _finish,
                style: color == null ? null : TextButton.styleFrom(foregroundColor: color),
                child: Text(tr('Skip')),
              ),
          ],
        ),
      ),
    );
    if (color == null) return row;
    return Theme(
      data: Theme.of(context).copyWith(
        iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: color)),
      ),
      child: row,
    );
  }

  /// The dots, then Back and Next / "Get started". The colours are for a
  /// background that is not the page's own (the card layout's brand colour).
  Widget _controls({Color? fill, Color? onFill, Color? plain, Color? dot, Color? dotRest, bool start = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (appIntro.length > 1) _Dots(count: appIntro.length, index: _index, onTap: _go, color: dot, rest: dotRest),
        const SizedBox(height: 24),
        Row(
          children: [
            if (_index > 0) ...[
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => _go(_index - 1),
                  style: plain == null ? null : TextButton.styleFrom(foregroundColor: plain),
                  child: Text(tr('Back')),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _next,
                  style: fill == null ? null : FilledButton.styleFrom(backgroundColor: fill, foregroundColor: onFill),
                  child: Text(_last ? tr('Get started') : tr('Next')),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The slides side by side, dragged by a finger or a mouse.
  Widget _pager(Widget Function(IntroSlide slide) page) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: PageView.builder(
        controller: _pages,
        itemCount: appIntro.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) => page(appIntro[index]),
      ),
    );
  }

  /// [child] fading in over the slide it replaces.
  Widget _swap(Widget child, {bool start = false}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      layoutBuilder: (current, previous) => Stack(
        alignment: start ? AlignmentDirectional.topStart : Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final Widget page = switch (appIntroLayout) {
      IntroLayout.centered => _centered(context),
      IntroLayout.fullImage => _fullImage(context),
      IntroLayout.card => _card(context),
      IntroLayout.split => _split(context),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(_index + (rtl ? -1 : 1)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_index + (rtl ? 1 : -1)),
      },
      child: Focus(autofocus: true, child: page),
    );
  }

  /// The picture in the middle, the title and text under it.
  Widget _centered(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _top(),
            Expanded(child: _pager((slide) => _PlainSlide(slide: slide))),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: _controls()),
            ),
          ],
        ),
      ),
    );
  }

  /// The picture fills the screen; the text and the buttons sit on a panel at
  /// the bottom (a card over the picture on a wide window).
  Widget _fullImage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 700;
    final strong = appStyle == AppStyle.brutalism;
    final radius = Radius.circular(strong ? 0 : 28);
    final panel = GestureDetector(
      onHorizontalDragEnd: _swipe,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + (wide ? 0 : media.padding.bottom)),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: wide ? BorderRadius.all(radius) : BorderRadius.vertical(top: radius),
          border: strong ? Border.all(color: scheme.onSurface, width: 3) : null,
          boxShadow: strong ? null : const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, -4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _swap(_Texts(key: ValueKey(_index), slide: appIntro[_index])),
            ),
            const SizedBox(height: 20),
            _controls(),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _pager((slide) => _Backdrop(slide: slide)),
          const _TopShade(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(bottom: false, child: _top(color: Colors.white)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: wide
                ? Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + media.padding.bottom),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: panel),
                  )
                : panel,
          ),
        ],
      ),
    );
  }

  /// The slide in a card on the brand colour.
  Widget _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onPrimary;
    return Scaffold(
      backgroundColor: scheme.primary,
      body: SafeArea(
        child: Column(
          children: [
            _top(color: on),
            Expanded(child: _pager((slide) => _CardSlide(slide: slide))),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _controls(fill: on, onFill: scheme.primary, plain: on, dot: on, dotRest: on.withAlpha(90)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The picture on one side and the text on the other from 840 wide;
  /// narrower, the picture on top and the text under it.
  Widget _split(BuildContext context) {
    final slide = appIntro[_index];
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 840;
          final picture = AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: SizedBox.expand(key: ValueKey(_index), child: _Backdrop(slide: slide)),
          );
          final side = Column(
            children: [
              if (wide) _top(),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _swap(_Texts(key: ValueKey(_index), slide: slide, start: true, large: wide), start: true),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: _controls(start: true)),
              ),
            ],
          );
          final Widget content = wide
              ? Row(
                  children: [
                    Expanded(child: picture),
                    Expanded(child: SafeArea(child: side)),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(
                      height: box.maxHeight * 0.42,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          picture,
                          const _TopShade(),
                          Align(
                            alignment: Alignment.topCenter,
                            child: SafeArea(bottom: false, child: _top(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: SafeArea(top: false, child: side)),
                  ],
                );
          return GestureDetector(behavior: HitTestBehavior.translucent, onHorizontalDragEnd: _swipe, child: content);
        },
      ),
    );
  }
}

/// Whether the look has square corners (Brutalism, Flat).
bool get _square => appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;

/// A slide's icon on a tinted circle (a square in the square looks).
class _IconMark extends StatelessWidget {
  const _IconMark({required this.slide});
  final IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strong = appStyle == AppStyle.brutalism;
    return Container(
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: _square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: _square ? BorderRadius.circular(strong ? 0 : 12) : null,
        border: strong ? Border.all(color: scheme.onSurface, width: 3) : null,
      ),
      child: Icon(slide.icon, size: 76, color: scheme.onPrimaryContainer),
    );
  }
}

/// A slide's picture shown whole: its image, or else its icon.
class _Picture extends StatelessWidget {
  const _Picture({required this.slide});
  final IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    final icon = FittedBox(fit: BoxFit.scaleDown, child: _IconMark(slide: slide));
    final image = slide.image;
    if (image == null) return Center(child: icon);
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(appStyle == AppStyle.brutalism ? 0 : 16),
        child: Image.asset(image, fit: BoxFit.contain, errorBuilder: (context, error, stack) => icon),
      ),
    );
  }
}

/// A slide's picture filling its box: its image, cropped to fill, or else
/// its icon large on the brand colour.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.slide});
  final IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plain = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.45)!],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.3),
        child: Icon(slide.icon, size: 132, color: scheme.onPrimary.withAlpha(235)),
      ),
    );
    final image = slide.image;
    if (image == null) return plain;
    return Image.asset(
      image,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      // The panel covers the foot of the picture: keep what is above the middle.
      alignment: const Alignment(0, -0.4),
      errorBuilder: (context, error, stack) => plain,
    );
  }
}

/// A shade along the top of a picture, so the language button and Skip can be read on it.
class _TopShade extends StatelessWidget {
  const _TopShade();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        child: SizedBox(
          height: 140,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x8C000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A slide's title and text, centred or from the start.
class _Texts extends StatelessWidget {
  const _Texts({super.key, required this.slide, this.start = false, this.large = false});
  final IntroSlide slide;
  final bool start;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = start ? TextAlign.start : TextAlign.center;
    final title = large ? theme.textTheme.headlineMedium : theme.textTheme.headlineSmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(tr(slide.title), textAlign: align, style: title?.copyWith(fontWeight: FontWeight.w700)),
        if (slide.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            tr(slide.text),
            textAlign: align,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// The centred layout's slide: the picture over the title and text.
class _PlainSlide extends StatelessWidget {
  const _PlainSlide({required this.slide});
  final IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // A short window (a phone on its side) scrolls rather than overflows.
        final pictureHeight = (box.maxHeight * 0.42).clamp(120.0, 300.0);
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: pictureHeight, child: _Picture(slide: slide)),
                  const SizedBox(height: 32),
                  _Texts(slide: slide),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The card layout's slide: the picture, title and text in a card.
class _CardSlide extends StatelessWidget {
  const _CardSlide({required this.slide});
  final IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strong = appStyle == AppStyle.brutalism;
    return LayoutBuilder(
      builder: (context, box) {
        final pictureHeight = (box.maxHeight * 0.38).clamp(110.0, 260.0);
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(strong ? 0 : (_square ? 8 : 28)),
                  border: strong ? Border.all(color: scheme.onSurface, width: 3) : null,
                  boxShadow: strong ? null : const [BoxShadow(color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: pictureHeight, child: _Picture(slide: slide)),
                    const SizedBox(height: 24),
                    _Texts(slide: slide),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Where the slides stand: a mark per slide, the current one longer. A tap opens that slide.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.onTap, this.color, this.rest});
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  /// The current mark's colour and the others', where the background is not the page's own.
  final Color? color;
  final Color? rest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == index ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == index ? (color ?? scheme.primary) : (rest ?? scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(_square ? 0 : 4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
