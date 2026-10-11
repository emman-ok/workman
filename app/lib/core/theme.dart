// Owned by AppWand. The look is picked in AppWand ("App theme"). Every style
// keeps the Material widgets and changes only this theme and AppSurface
// (core/widgets.dart), so pages never depend on the style.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The brand colour; the whole palette is derived from it. Set in AppWand.
const Color seedColor = Color(0xFF3B6FD4);

/// The side menu's background (the rail and the drawer), or null for the
/// style's own. Set in AppWand.
// ignore: unnecessary_nullable_for_final_variable_declarations
const Color? menuColor = null;

/// The app header's background (the app bar, the top bar of links and the
/// home grid's greeting), or null for the style's own. Set in AppWand.
// ignore: unnecessary_nullable_for_final_variable_declarations
const Color? headerColor = null;

/// The colour of text and icons on [background]: light on a dark colour,
/// dark on a light one.
Color onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Colors.white : const Color(0xFF1B1B1F);

/// The app's logo under assets/, or null. Set in AppWand.
// ignore: unnecessary_nullable_for_final_variable_declarations
const String? logoAsset = 'assets/logo.png';

/// The looks an app can be drawn in.
enum AppStyle {
  materialYou,
  material,
  monochrome,
  flat,
  fluent,
  cupertino,
  brutalism,
  softUi,
  glossy,
  claymorphism,
  bento,
}

/// The look this app is drawn in. Set in AppWand.
const AppStyle appStyle = AppStyle.flat;

/// Light, dark or as the device is set, until someone picks otherwise. Set in AppWand.
const ThemeMode defaultThemeMode = ThemeMode.system;

/// Whether people can switch between light and dark themselves
/// (ThemeModeSetting, on the Account page). Set in AppWand.
const bool themeSwitch = true;

/// The ways showSnack (core/widgets.dart) can show a short message.
enum NoticeStyle { snackbar, floating, toast, tinted, filled, minimal, banner }

/// How this app shows short messages. Set in AppWand.
const NoticeStyle noticeStyle = NoticeStyle.snackbar;

/// The ways PagedList (core/lists.dart) sets the rows of a list apart.
enum ListRowStyle { divider, card, none }

/// How this app's lists set their rows apart, and the space between rows.
/// Set in AppWand.
const ListRowStyle listRowStyle = ListRowStyle.card;
const double listRowGap = 12;

/// The ways PagedList (core/lists.dart) can behave at the ends of a list:
/// each device's own way, a bounce everywhere, or a stop everywhere.
enum ListScroll { platform, bouncing, clamping }

/// How this app's lists behave at their ends. Set in AppWand.
const ListScroll listScroll = ListScroll.platform;

/// The ways WizardForm (core/wizard.dart) can show where a form in steps
/// stands: numbered steps, a row of dots, or a bar that fills.
enum WizardIndicator { numbers, dots, bar }

/// How this app's forms in steps show their progress. Set in AppWand.
const WizardIndicator wizardIndicator = WizardIndicator.numbers;

/// The ways DetailSection (core/details.dart) can lay out a record's fields:
/// the label beside its value, over it, in a table of two columns, as
/// "Label: value" one after another, or over it in several columns.
enum DetailStyle { horizontal, vertical, table, inline, columns }

/// How this app's record pages show a label and its value. Set in AppWand.
const DetailStyle detailStyle = DetailStyle.table;

/// The ways a TabBar can mark the chosen tab: a line under it, a pill behind
/// it in the brand colour or in a tint of it, or a dot under its name.
enum TabStyle { underline, pills, soft, dot }

/// How this app's tab bars mark the chosen tab (buildTheme's tabBarTheme, so
/// every TabBar follows it). Set in AppWand.
const TabStyle tabStyle = TabStyle.soft;

/// The ways the Account page (core/system_pages.dart) can be laid out:
/// sections under one another, a cover banner, a card beside the details,
/// or tabs.
enum AccountLayout { sections, cover, split, tabs }

/// How this app's Account page is laid out. Set in AppWand.
const AccountLayout accountLayout = AccountLayout.sections;

/// The ways a page can come on screen (appPage, core/transitions.dart).
enum AppTransition { platform, fade, fadeThrough, slide, slideUp, zoom, none }

/// How this app's pages come on screen, unless router.g.dart gives a page
/// its own. Set in AppWand.
const AppTransition appTransition = AppTransition.platform;

/// The app's Google Fonts family, or null for the style's own. Fetched the
/// first time it is shown and kept on the device. Set in AppWand.
// ignore: unnecessary_nullable_for_final_variable_declarations
const String? appFont = null;

/// What the start-up screen (core/splash.dart) can show.
enum SplashStyle { logoName, logo, wordmark, pulse, minimal }

/// What this app's start-up screen shows. Set in AppWand.
const SplashStyle splashStyle = SplashStyle.logoName;

/// The start-up screen's background, light and dark. The native launch
/// screens (Android, iOS, web) are written with the same colours, so the
/// hand-over to the app doesn't show. Set in AppWand.
const Color splashBackground = Color(0xFF3B6FD4);
const Color splashBackgroundDark = Color(0xFF3B6FD4);

/// Whether the start-up screen shows a small progress indicator. Set in AppWand.
const bool splashSpinner = false;

/// The shortest time the start-up screen stays. Set in AppWand.
const Duration splashMinimum = Duration(milliseconds: 1000);

/// What a style changes on top of Material 3.
class _Look {
  const _Look({
    required this.radius,
    this.buttonRadius,
    this.fieldRadius = 4,
    this.outline = 1,
    this.strong = false,
    this.cardBorder = true,
    this.elevation = 0,
    this.ripple = true,
    this.filledFields = false,
    this.underline = false,
    this.headingWeight,
    this.fontFamily,
    this.platform,
    this.variant = DynamicSchemeVariant.tonalSpot,
  });

  /// Corners of cards and dialogs.
  final double radius;

  /// Corners of buttons; null for pill-shaped.
  final double? buttonRadius;
  final double fieldRadius;

  /// Border width, and whether borders are drawn in the text colour.
  final double outline;
  final bool strong;
  final bool cardBorder;
  final double elevation;
  final bool ripple;
  final bool filledFields;
  final bool underline;
  final FontWeight? headingWeight;
  final String? fontFamily;
  final TargetPlatform? platform;
  final DynamicSchemeVariant variant;
}

const Map<AppStyle, _Look> _looks = {
  AppStyle.materialYou: _Look(radius: 12),
  AppStyle.material: _Look(
    radius: 4,
    buttonRadius: 4,
    cardBorder: false,
    elevation: 2,
    filledFields: true,
    underline: true,
    variant: DynamicSchemeVariant.fidelity,
  ),
  AppStyle.monochrome: _Look(radius: 8, buttonRadius: 8, fieldRadius: 8, variant: DynamicSchemeVariant.monochrome),
  AppStyle.flat: _Look(
    radius: 6,
    buttonRadius: 6,
    fieldRadius: 6,
    cardBorder: false,
    filledFields: true,
    variant: DynamicSchemeVariant.fidelity,
  ),
  AppStyle.fluent: _Look(radius: 8, buttonRadius: 4, fieldRadius: 4, ripple: false, fontFamily: 'Segoe UI'),
  AppStyle.cupertino: _Look(
    radius: 12,
    buttonRadius: 10,
    fieldRadius: 10,
    cardBorder: false,
    ripple: false,
    filledFields: true,
    headingWeight: FontWeight.w700,
    platform: TargetPlatform.iOS,
    variant: DynamicSchemeVariant.fidelity,
  ),
  AppStyle.brutalism: _Look(
    radius: 0,
    buttonRadius: 0,
    fieldRadius: 0,
    outline: 2.5,
    strong: true,
    headingWeight: FontWeight.w900,
    variant: DynamicSchemeVariant.fidelity,
  ),
  AppStyle.softUi: _Look(radius: 20, buttonRadius: 14, fieldRadius: 14, cardBorder: false, filledFields: true),
  AppStyle.glossy: _Look(
    radius: 18,
    fieldRadius: 14,
    cardBorder: false,
    elevation: 3,
    variant: DynamicSchemeVariant.vibrant,
  ),
  AppStyle.claymorphism: _Look(
    radius: 28,
    fieldRadius: 18,
    cardBorder: false,
    filledFields: true,
    headingWeight: FontWeight.w800,
  ),
  AppStyle.bento: _Look(
    radius: 24,
    buttonRadius: 14,
    fieldRadius: 14,
    cardBorder: false,
    filledFields: true,
    headingWeight: FontWeight.w700,
    variant: DynamicSchemeVariant.fidelity,
  ),
};

ColorScheme _scheme(Brightness brightness, _Look look) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness, dynamicSchemeVariant: look.variant);
  switch (appStyle) {
    case AppStyle.monochrome:
      // Greys throughout; the brand colour only where the primary colour goes.
      final accent = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
      return scheme.copyWith(
        primary: accent.primary,
        onPrimary: accent.onPrimary,
        primaryContainer: accent.primaryContainer,
        onPrimaryContainer: accent.onPrimaryContainer,
      );
    case AppStyle.brutalism:
      final ink = dark ? Colors.white : Colors.black;
      return scheme.copyWith(
        surface: dark ? const Color(0xFF111111) : Colors.white,
        onSurface: ink,
        outline: ink,
        outlineVariant: ink,
      );
    case AppStyle.softUi:
      // Cards are the colour of the background; only their shadows raise them.
      final base = Color.lerp(dark ? const Color(0xFF292D32) : const Color(0xFFE4E8EE), seedColor, 0.05)!;
      return scheme.copyWith(
        surface: base,
        surfaceContainerLowest: base,
        surfaceContainerLow: base,
        surfaceContainer: base,
        surfaceContainerHigh: base,
      );
    default:
      return scheme;
  }
}

Color _background(ColorScheme scheme, bool dark) => switch (appStyle) {
  AppStyle.material => dark ? const Color(0xFF121212) : const Color(0xFFFAFAFA),
  AppStyle.fluent => dark ? scheme.surface : scheme.surfaceContainerLow,
  AppStyle.cupertino => dark ? Colors.black : const Color(0xFFF2F2F7),
  AppStyle.brutalism => Color.lerp(scheme.surface, seedColor, 0.08)!,
  AppStyle.glossy => scheme.surfaceContainerLow,
  // A pastel of the brand colour, which the white clay stands out from.
  AppStyle.claymorphism => Color.lerp(scheme.surface, scheme.primaryContainer, dark ? 0.18 : 0.45)!,
  // A quiet grey the tiles sit on.
  AppStyle.bento => Color.lerp(dark ? const Color(0xFF0E0E10) : const Color(0xFFF1F1F4), seedColor, 0.03)!,
  _ => scheme.surface,
};

/// The fill of cards and AppSurface; null for Material's own.
Color? _cardColor(ColorScheme scheme, bool dark) => switch (appStyle) {
  AppStyle.material => dark ? const Color(0xFF1E1E1E) : Colors.white,
  AppStyle.flat => scheme.surfaceContainerHigh,
  AppStyle.fluent => dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
  AppStyle.cupertino => dark ? const Color(0xFF1C1C1E) : Colors.white,
  AppStyle.brutalism || AppStyle.softUi => scheme.surface,
  AppStyle.glossy => scheme.surfaceContainerLowest,
  AppStyle.claymorphism => dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
  AppStyle.bento => dark ? const Color(0xFF1C1C1F) : Colors.white,
  _ => null,
};

Color? _fieldFill(ColorScheme scheme, bool dark) => switch (appStyle) {
  AppStyle.cupertino => dark ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EF),
  AppStyle.bento => dark ? const Color(0xFF2A2A2E) : const Color(0xFFE7E7EC),
  AppStyle.softUi => Color.lerp(scheme.surface, dark ? Colors.black : const Color(0xFF8A94A6), dark ? 0.25 : 0.12),
  _ => null,
};

TextTheme _text(TextTheme text, _Look look) {
  final weight = look.headingWeight;
  if (weight == null) return text;
  TextStyle? heavy(TextStyle? style) => style?.copyWith(fontWeight: weight);
  return text.copyWith(
    displayLarge: heavy(text.displayLarge),
    displayMedium: heavy(text.displayMedium),
    displaySmall: heavy(text.displaySmall),
    headlineLarge: heavy(text.headlineLarge),
    headlineMedium: heavy(text.headlineMedium),
    headlineSmall: heavy(text.headlineSmall),
    titleLarge: heavy(text.titleLarge),
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

/// [text] in [appFont]. The weights are set first, so each style loads the
/// weight it is drawn in.
TextTheme _font(TextTheme text) => appFont == null ? text : GoogleFonts.getTextTheme(appFont!, text);

/// The light on a filled button, drawn over its colour: Glossy's hard
/// highlight across the top half (the Aero "gel" button) and Claymorphism's
/// soft light from above. Null for every other style.
ButtonLayerBuilder? _buttonShine() {
  final (colors, stops) = switch (appStyle) {
    AppStyle.glossy => (
      const [Color(0x80FFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x1F000000)],
      const [0.0, 0.5, 0.5, 1.0],
    ),
    AppStyle.claymorphism => (
      const [Color(0x47FFFFFF), Color(0x00FFFFFF), Color(0x24000000)],
      const [0.0, 0.5, 1.0],
    ),
    _ => (const <Color>[], const <double>[]),
  };
  if (colors.isEmpty) return null;
  return (context, states, child) {
    final content = child ?? const SizedBox.shrink();
    if (states.contains(WidgetState.disabled)) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ),
      ),
      child: content,
    );
  };
}

/// The chosen tab's mark where it is not Material's line: a pill behind the
/// whole tab, or a dot under its name. TabBar hands it the tab's (or, for the
/// dot, the label's) box.
class _TabMark extends Decoration {
  const _TabMark({required this.color, this.radius = 0, this.side = BorderSide.none, this.dot = false});
  final Color color;
  final double radius;
  final BorderSide side;
  final bool dot;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _TabMarkPainter(this);
}

class _TabMarkPainter extends BoxPainter {
  _TabMarkPainter(this.mark);
  final _TabMark mark;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final box = offset & (configuration.size ?? Size.zero);
    final paint = Paint()..color = mark.color;
    final radius = Radius.circular(mark.radius);
    if (mark.dot) {
      final dot = Rect.fromCenter(center: Offset(box.center.dx, box.bottom - 5), width: 6, height: 6);
      canvas.drawRRect(RRect.fromRectAndRadius(dot, radius), paint);
      return;
    }
    // Clear of the bar's edges and of the tabs beside it.
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTRB(box.left + 2, box.top + 5, box.right - 2, box.bottom - 5),
      radius,
    );
    canvas.drawRRect(pill, paint);
    if (mark.side != BorderSide.none) canvas.drawRRect(pill, mark.side.toPaint());
  }
}

/// Every TabBar as tabStyle says; null for Material's own underline.
TabBarThemeData? _tabBar(ColorScheme scheme, _Look look) {
  // A pill's ends follow the style's buttons; square styles get square marks.
  final double radius = look.buttonRadius ?? 999;
  final frame = look.strong ? BorderSide(color: scheme.onSurface, width: look.outline) : BorderSide.none;
  // The hover and press tint is a square over the tab, which a pill would sit in.
  const noTint = WidgetStatePropertyAll<Color?>(Colors.transparent);
  switch (tabStyle) {
    case TabStyle.underline:
      return null;
    case TabStyle.pills:
      return TabBarThemeData(
        indicator: _TabMark(color: scheme.primary, radius: radius, side: frame),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        overlayColor: noTint,
      );
    case TabStyle.soft:
      return TabBarThemeData(
        indicator: _TabMark(color: scheme.primaryContainer, radius: radius, side: frame),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: scheme.onPrimaryContainer,
        unselectedLabelColor: scheme.onSurfaceVariant,
        overlayColor: noTint,
      );
    case TabStyle.dot:
      return TabBarThemeData(
        indicator: _TabMark(color: scheme.primary, radius: look.radius == 0 ? 0 : 999, dot: true),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final look = _looks[appStyle]!;
  final dark = brightness == Brightness.dark;
  final scheme = _scheme(brightness, look);
  final background = _background(scheme, dark);
  final cardColor = _cardColor(scheme, dark);
  final classic = appStyle == AppStyle.material;
  final modern = appStyle == AppStyle.materialYou;
  // Glossy and Claymorphism buttons glow in the brand colour.
  final glow = appStyle == AppStyle.glossy || appStyle == AppStyle.claymorphism;
  // The header's own colour, the same in light and dark.
  final header = headerColor;

  final line = BorderSide(color: look.strong ? scheme.onSurface : scheme.outlineVariant, width: look.outline);
  final strongLine = look.strong ? line : BorderSide.none;
  OutlinedBorder buttonShape([BorderSide side = BorderSide.none]) => look.buttonRadius == null
      ? StadiumBorder(side: side)
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(look.buttonRadius!), side: side);
  final smallShape = look.buttonRadius == null ? null : buttonShape(strongLine);

  // Flat, Cupertino, Soft UI, Claymorphism and Bento fields are filled shapes
  // without an outline.
  final borderless = look.filledFields && !look.underline;
  InputBorder fieldBorder(BorderSide side) => look.underline
      ? UnderlineInputBorder(borderSide: side)
      : OutlineInputBorder(borderRadius: BorderRadius.circular(look.fieldRadius), borderSide: side);
  final fieldLine = borderless
      ? BorderSide.none
      : BorderSide(color: look.strong ? scheme.onSurface : scheme.outline, width: look.strong ? look.outline : 1);

  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    platform: look.platform,
    fontFamily: appFont == null ? look.fontFamily : null,
    splashFactory: look.ripple ? null : NoSplash.splashFactory,
    scaffoldBackgroundColor: background,
  );

  return base.copyWith(
    textTheme: _font(_text(base.textTheme, look)),
    primaryTextTheme: _font(base.primaryTextTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: header ?? (classic ? scheme.primary : (modern ? null : background)),
      foregroundColor: header != null ? onColor(header) : (classic ? scheme.onPrimary : null),
      elevation: classic ? 4 : 0,
      scrolledUnderElevation: modern ? null : (classic ? 4 : 0),
      surfaceTintColor: modern && header == null ? null : Colors.transparent,
      shadowColor: classic ? Colors.black : null,
      centerTitle: appStyle == AppStyle.cupertino ? true : null,
      shape: look.strong
          ? Border(bottom: line)
          : (appStyle == AppStyle.fluent ? Border(bottom: BorderSide(color: scheme.outlineVariant)) : null),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: look.elevation,
      shadowColor: appStyle == AppStyle.glossy ? scheme.primary.withAlpha(90) : null,
      surfaceTintColor: modern ? null : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(look.radius),
        side: look.cardBorder ? line : BorderSide.none,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: look.filledFields,
      fillColor: _fieldFill(scheme, dark),
      border: fieldBorder(fieldLine),
      enabledBorder: fieldBorder(fieldLine),
      focusedBorder: fieldBorder(BorderSide(color: scheme.primary, width: look.strong ? look.outline : 2)),
      errorBorder: fieldBorder(BorderSide(color: scheme.error, width: look.strong ? look.outline : 1)),
      focusedErrorBorder: fieldBorder(BorderSide(color: scheme.error, width: look.strong ? look.outline : 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape(strongLine),
        elevation: glow ? 4 : (classic ? 2 : 0),
        shadowColor: glow ? scheme.primary : null,
        backgroundBuilder: _buttonShine(),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: buttonShape(strongLine),
        elevation: switch (appStyle) {
          AppStyle.flat || AppStyle.brutalism || AppStyle.cupertino || AppStyle.softUi || AppStyle.bento => 0,
          _ => null,
        },
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: buttonShape(), side: look.strong ? line : null),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: buttonShape())),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: classic ? const CircleBorder() : smallShape,
      elevation: switch (appStyle) {
        AppStyle.flat || AppStyle.brutalism || AppStyle.softUi || AppStyle.bento => 0,
        _ => null,
      },
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: modern ? null : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(look.radius == 0 ? 0 : look.radius + 8),
        side: strongLine,
      ),
    ),
    chipTheme: smallShape == null ? null : ChipThemeData(shape: smallShape),
    navigationBarTheme: NavigationBarThemeData(
      indicatorShape: smallShape,
      backgroundColor: modern ? null : (cardColor ?? background),
    ),
    navigationRailTheme: NavigationRailThemeData(indicatorShape: smallShape),
    navigationDrawerTheme: NavigationDrawerThemeData(indicatorShape: smallShape),
    tabBarTheme: _tabBar(scheme, look),
    dividerTheme: look.strong ? DividerThemeData(color: scheme.onSurface, thickness: 2) : null,
  );
}
