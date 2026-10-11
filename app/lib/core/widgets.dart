// Shared page chrome and small widgets. Owned by AppWand.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';

import '../app/router.g.dart' show appActions, appActionsInHeader, appActionsOnDashboard, appContentMaxWidth, appLayout, appMenu, appMenuCompact, appMenuHidden, appMenuList, appMenuUnderHeader, appTitle;
import 'auth/auth_controller.dart';
import 'i18n.dart';
import 'icons.dart';
import 'lists.dart' show PageActions;
import 'plugins.g.dart' show appPlugins;
import 'theme.dart'
    show AppStyle, NoticeStyle, appStyle, headerColor, logoAsset, menuColor, noticeStyle, onColor, themeSwitch;
import 'theme_mode.dart';
import 'uploads.dart' show AppImage, fileUrl;

// ErrorView's message almost always comes from errorMessage; pages that keep
// their API calls in a providers file would otherwise have to import it too.
export 'api_client.dart' show errorMessage;
export '../app/router.g.dart' show appTitle;
// tr(), the app's texts in the language in use, and its language setting.
export 'i18n.dart';
// AppIcons, the app's icons in the icon set picked in AppWand.
export 'icons.dart';
// The list parts (PagedList and the rest), so a list page needs one import.
export 'lists.dart';
// The charts (AppLineChart, AppBarChart, AppPieChart, Sparkline, ChartCard).
export 'charts.dart';
// Forms in steps (WizardForm, WizardStep, WizardSummary).
export 'wizard.dart';
// A record's page (DetailView, DetailHeader, DetailSection, DetailTabs, StatusBadge).
export 'details.dart';
// The form fields (RelationField, MultiSelectField, DateField, DateRangeField, MoneyField, PhoneField).
export 'fields.dart';
export 'export.dart';
export 'import.dart';

/// How the app lays out its navigation; router.g.dart sets appLayout.
enum NavLayout {
  /// A drawer on phones, a rail down the side on wide screens.
  sidebar,

  /// A tab bar along the bottom on phones, a rail on wide screens.
  tabs,

  /// Links across the app bar on wide screens, a drawer on phones.
  topbar,

  /// The home screen ('/') is a grid of cards, one per menu page; every other
  /// page has a button back to it.
  grid,
}

class MenuEntry {
  const MenuEntry(this.title, this.route, this.icon, {this.roles = const [], this.subtitle = '', this.permission, this.group = '', this.plugin = false});

  /// A page a plugin adds (its PluginPage has this route), put here in
  /// AppWand's App Menu: menuFor lists it for those the plugin lets in.
  final bool plugin;

  /// In English; shown through tr().
  final String title;
  final String route;
  final IconData icon;

  /// Roles that see the entry; empty for everyone.
  final List<String> roles;

  /// With the Roles & permissions plugin, what the role must be allowed
  /// (the page's id, then '.view') in place of [roles]; null for a page open to everyone.
  final String? permission;

  /// One line about the page, shown on its card in the grid layout.
  final String subtitle;

  /// The label the entry is listed under ("Main", "Settings"), in English and
  /// shown through tr(); empty for none. Set in AppWand (App Menu). The side
  /// menu's list, the drawer and the grid layout show it; the rail, the bottom
  /// tabs and the top links have no room for labels.
  final String group;
}

/// One of the app's main things to do ("New sale", "Check in"), set in AppWand
/// (App Menu) and listed in router.g.dart's appActions: a button that opens
/// a page of the app.
class AppAction {
  const AppAction(this.label, this.route, this.icon, {this.roles = const [], this.permission});

  /// In English; shown through tr().
  final String label;
  final String route;
  final IconData icon;

  /// Who may open its page, as a MenuEntry says it.
  final List<String> roles;
  final String? permission;
}

/// The app's quick actions [auth] may use, the main one first.
List<AppAction> actionsFor(AuthState auth) => [
      if (auth.isSignedIn)
        for (final action in appActions)
          if (auth.allows(action.permission, action.roles)) action,
    ];

/// Opens [action]'s page: a page of the menu is gone to; any other is pushed
/// over where the person is, so Back returns there.
void _openAction(GoRouter router, AppAction action) {
  if (router.state.matchedLocation == action.route) return;
  if (appMenu.any((m) => m.route == action.route)) {
    router.go(action.route);
  } else {
    router.push(action.route);
  }
}

/// A quick action's fill and text over [background], whose own text is [on]:
/// the brand colour where it stands out, else the background's text colour
/// (a header or a side menu in the brand colour).
({Color fill, Color text}) _actionColors(ColorScheme scheme, Color background, Color on) {
  final stands = (background.computeLuminance() - scheme.primary.computeLuminance()).abs() > 0.2;
  return stands ? (fill: scheme.primary, text: scheme.onPrimary) : (fill: on, text: background);
}

/// The app's quick actions in the header, before the account menu, on every
/// page: the main one as a filled button (only its icon on a narrow window),
/// the second as an outlined button from 1100 wide, the rest behind an arrow.
class _HeaderActionButton extends ConsumerWidget {
  const _HeaderActionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = actionsFor(ref.watch(authProvider));
    if (actions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = IconTheme.of(context).color ?? scheme.onSurface;
    final colors = _actionColors(scheme, headerColor ?? theme.appBarTheme.backgroundColor ?? scheme.surface, on);
    final first = actions.first;
    final router = GoRouter.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    PopupMenuButton<AppAction> menu(List<AppAction> items, {Widget? child, Widget? icon}) => PopupMenuButton<AppAction>(
          tooltip: tr('Quick actions'),
          onSelected: (action) => _openAction(router, action),
          itemBuilder: (context) => [
            for (final action in items)
              PopupMenuItem<AppAction>(
                value: action,
                child: Row(children: [Icon(action.icon), const SizedBox(width: 12), Text(tr(action.label))]),
              ),
          ],
          icon: icon,
          child: child,
        );

    final Widget button;
    if (wide) {
      // A desktop window has room for the second one by name too.
      final shown = width >= 1100 && actions.length > 1 ? 2 : 1;
      button = Row(mainAxisSize: MainAxisSize.min, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: colors.fill, foregroundColor: colors.text),
          onPressed: () => _openAction(router, first),
          icon: Icon(first.icon, size: 18),
          label: Text(tr(first.label)),
        ),
        if (shown == 2) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: on, side: BorderSide(color: on.withAlpha(90))),
            onPressed: () => _openAction(router, actions[1]),
            icon: Icon(actions[1].icon, size: 18),
            label: Text(tr(actions[1].label)),
          ),
        ],
        if (actions.length > shown) menu(actions.sublist(shown), icon: Icon(AppIcons.expandMore, color: on)),
      ]);
    } else if (actions.length == 1) {
      button = IconButton(
        tooltip: tr(first.label),
        style: IconButton.styleFrom(backgroundColor: colors.fill, foregroundColor: colors.text),
        onPressed: () => _openAction(router, first),
        icon: Icon(first.icon),
      );
    } else {
      // Several, with no room for a label: one button that lists them all.
      button = menu(
        actions,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: colors.fill, shape: BoxShape.circle),
          child: Icon(first.icon, color: colors.text),
        ),
      );
    }
    // Centred, so a bar that stretches its actions keeps the button its own height.
    return Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: button));
  }
}

/// The app's quick actions as a row of large buttons, the main one filled:
/// what a home or dashboard page puts first in its body. Nothing when the app
/// has none, the signed-in person may open none, or AppWand's App Menu has
/// them off the dashboard (router.g.dart's appActionsOnDashboard).
class QuickActions extends ConsumerWidget {
  const QuickActions({super.key, this.padding = const EdgeInsets.only(bottom: 16)});

  /// The space around the row; none of it is taken when there is no action.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!appActionsOnDashboard) return const SizedBox.shrink();
    final actions = actionsFor(ref.watch(authProvider));
    if (actions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final router = GoRouter.of(context);
    final size = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
      textStyle: WidgetStatePropertyAll(theme.textTheme.titleMedium),
    );
    return Padding(
      padding: padding,
      child: Wrap(spacing: 12, runSpacing: 12, children: [
        for (var i = 0; i < actions.length; i++)
          if (i == 0)
            FilledButton.icon(
              style: size,
              onPressed: () => _openAction(router, actions[i]),
              icon: Icon(actions[i].icon),
              label: Text(tr(actions[i].label)),
            )
          else
            FilledButton.tonalIcon(
              style: size,
              onPressed: () => _openAction(router, actions[i]),
              icon: Icon(actions[i].icon),
              label: Text(tr(actions[i].label)),
            ),
      ]),
    );
  }
}

/// The app's quick actions at the head of the phone's drawer, each a button
/// as wide as the menu, the main one filled.
class _DrawerActions extends ConsumerWidget {
  const _DrawerActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = actionsFor(ref.watch(authProvider));
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final colors = _actionColors(scheme, scheme.surface, scheme.onSurface);
    final router = GoRouter.of(context);
    void open(AppAction action) {
      Scaffold.of(context).closeDrawer();
      _openAction(router, action);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          if (i == 0)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: colors.fill, foregroundColor: colors.text),
              onPressed: () => open(actions[i]),
              icon: Icon(actions[i].icon, size: 18),
              label: Text(tr(actions[i].label)),
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: scheme.onSurface),
              onPressed: () => open(actions[i]),
              icon: Icon(actions[i].icon, size: 18),
              label: Text(tr(actions[i].label)),
            ),
        ],
      ]),
    );
  }
}

/// What sets a menu group apart in the list of items: its label, or a line
/// where entries without a label follow a group that has one.
class _MenuGroupLabel extends StatelessWidget {
  const _MenuGroupLabel(this.group, {required this.first, this.compact = false});
  final String group;

  /// Whether it heads the menu, where the space above it is already there.
  final bool first;

  /// Whether the menu's items are the short ones, so the label sits closer.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (group.isEmpty) {
      return Padding(padding: EdgeInsets.fromLTRB(28, compact ? 6 : 8, 28, compact ? 6 : 8), child: const Divider(height: 1));
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(28, first ? 4 : (compact ? 14 : 20), 16, compact ? 4 : 8),
      child: Text(
        tr(group),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// The menu as [auth] sees it: the app's pages its role may open, and the
/// plugins' pages (Roles & permissions, the Trash) where router.g.dart's
/// appMenu puts them, with the icon and group set in AppWand. A plugin page
/// appMenu does not name goes after the last entry of its own group, or at
/// the end when the menu has no such group, unless it is in appMenuHidden.
List<MenuEntry> menuFor(AuthState auth) {
  final pages = {
    for (final plugin in appPlugins)
      for (final page in plugin.pages)
        if (!page.footer) page.route: page,
  };
  final menu = <MenuEntry>[];
  for (final m in appMenu) {
    if (m.plugin) {
      final page = pages.remove(m.route);
      if (page != null && auth.isSignedIn && page.allows(auth)) menu.add(m);
    } else if (auth.allows(m.permission, m.roles)) {
      menu.add(m);
    }
  }
  if (!auth.isSignedIn) return menu;
  for (final page in pages.values) {
    if (appMenuHidden.contains(page.route) || !page.allows(auth)) continue;
    final entry = MenuEntry(page.title, page.route, page.icon, permission: page.permission, group: page.group);
    final last = page.group.isEmpty ? -1 : menu.lastIndexWhere((m) => m.group == page.group);
    menu.insert(last < 0 ? menu.length : last + 1, entry);
  }
  return menu;
}

/// The plugins' pages kept out of the menu (PluginPage.footer) that [auth]
/// may open: icon buttons at the foot of the side menu (the Trash).
List<MenuEntry> footerFor(AuthState auth) => [
      if (auth.isSignedIn)
        for (final plugin in appPlugins)
          for (final page in plugin.pages)
            if (page.footer && page.allows(auth)) MenuEntry(page.title, page.route, page.icon, permission: page.permission),
    ];

/// The icon buttons at the foot of the side menu, one per [entries]; in a row
/// under a list of items, one under another in the rail.
class _MenuFooter extends StatelessWidget {
  const _MenuFooter({required this.entries, this.axis = Axis.horizontal, this.onOpen});
  final List<MenuEntry> entries;
  final Axis axis;

  /// Run before a page opens (the phone's drawer closes).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // GoRouter's state, not GoRouterState.of: AppShell's menu is above the pages.
    final location = GoRouter.of(context).state.matchedLocation;
    return Material(
      type: MaterialType.transparency,
      child: Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: [
        for (final entry in entries)
          IconButton(
            tooltip: tr(entry.title),
            color: location == entry.route ? scheme.primary : scheme.onSurfaceVariant,
            onPressed: () {
              onOpen?.call();
              if (location != entry.route) context.go(entry.route);
            },
            icon: Icon(entry.icon),
          ),
      ]),
    );
  }
}

/// The app's logo, or nothing when it has none.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = logoAsset;
    if (asset == null) return const SizedBox.shrink();
    return Image.asset(asset, height: size, fit: BoxFit.contain);
  }
}

/// The light/dark setting: the device's theme, light or dark, kept on the
/// device. Nothing when the app has no switch (theme.dart's themeSwitch).
/// The Account page (/account) already shows it.
class ThemeModeSetting extends ConsumerWidget {
  const ThemeModeSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!themeSwitch) return const SizedBox.shrink();
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: ThemeMode.system, icon: const Icon(AppIcons.brightnessAuto), label: Text(tr('System'))),
        ButtonSegment(value: ThemeMode.light, icon: const Icon(AppIcons.lightMode), label: Text(tr('Light'))),
        ButtonSegment(value: ThemeMode.dark, icon: const Icon(AppIcons.darkMode), label: Text(tr('Dark'))),
      ],
      selected: {watchThemeMode(ref)},
      onSelectionChanged: (value) => ref.read(themeChoiceProvider.notifier).set(value.first),
    );
  }
}

/// The settings of the plugins added in AppWand (biometric unlock), each a
/// heading and an AppSurface with 24px above it. Nothing when no plugin has
/// any. The Account page (/account) already shows it.
class PluginSettings extends StatelessWidget {
  const PluginSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = [
      for (final plugin in appPlugins)
        if (plugin.accountSection != null) plugin.accountSection!(context),
    ];
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections);
  }
}

/// What sits in the app's header before the account menu: the app's quick
/// actions (when AppWand's App Menu has them in the header, and unless
/// [actions] is false: the grid's home shows them under its greeting), then
/// what the plugins added in AppWand put there (the search box).
List<Widget> _headerActions(BuildContext context, {bool compact = false, Color? color, bool actions = true}) => [
      if (actions && appActionsInHeader) const _HeaderActionButton(),
      for (final plugin in appPlugins)
        if (plugin.headerAction != null) plugin.headerAction!(context, compact: compact, color: color),
    ];

/// The sign-in buttons of the plugins added in AppWand ("Continue with
/// Google"), with their own spacing above; nothing when there are none. The
/// sign-in and create-account screens show it under their main button.
class PluginSignInButtons extends StatelessWidget {
  const PluginSignInButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final plugin in appPlugins)
        if (plugin.signInButtons != null) plugin.signInButtons!(context),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons);
  }
}

/// A card drawn in the app's style (theme.dart's appStyle). Pages use it
/// wherever they would use a Card: a Card cannot draw every style (Brutalism's
/// hard shadow, Soft UI's raised surface, Glossy's sheen, Claymorphism's
/// puffed-up clay).
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// A fill in place of the style's surface colour, e.g. a tinted stat card.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final shape = theme.cardTheme.shape;
    final radius = (shape is RoundedRectangleBorder ? shape.borderRadius : BorderRadius.circular(12))
        .resolve(Directionality.of(context));
    final fill = color ?? theme.cardTheme.color ?? scheme.surfaceContainerLow;
    final content = Padding(padding: padding, child: child);

    final decoration = switch (appStyle) {
      AppStyle.brutalism => BoxDecoration(
          color: fill,
          borderRadius: radius,
          border: Border.all(color: scheme.onSurface, width: 2.5),
          boxShadow: [BoxShadow(color: scheme.onSurface, offset: const Offset(5, 5))],
        ),
      AppStyle.softUi => BoxDecoration(
          color: fill,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: dark ? Colors.white.withAlpha(16) : Colors.white.withAlpha(235),
              offset: const Offset(-6, -6),
              blurRadius: 16,
            ),
            BoxShadow(color: Colors.black.withAlpha(dark ? 130 : 40), offset: const Offset(6, 6), blurRadius: 16),
          ],
        ),
      AppStyle.glossy => BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(fill, Colors.white, dark ? 0.12 : 0.75)!, fill, Color.lerp(fill, scheme.primary, 0.10)!],
          ),
          border: Border.all(color: Colors.white.withAlpha(dark ? 40 : 200)),
          boxShadow: [BoxShadow(color: scheme.primary.withAlpha(dark ? 70 : 50), offset: const Offset(0, 8), blurRadius: 24)],
        ),
      AppStyle.claymorphism => BoxDecoration(
          color: fill,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Color.lerp(scheme.primary, Colors.black, 0.35)!.withAlpha(dark ? 120 : 60),
              offset: const Offset(0, 12),
              blurRadius: 28,
              spreadRadius: -4,
            ),
          ],
        ),
      _ => null,
    };
    // Clay is lit from inside its edges too, which a BoxDecoration cannot draw.
    final inner = appStyle == AppStyle.claymorphism ? _ClayPainter(radius, dark) : null;

    if (decoration == null) {
      return Card(
        margin: margin,
        color: color,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      );
    }
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: decoration,
        child: CustomPaint(
          painter: inner,
          child: Material(
            type: MaterialType.transparency,
            child: onTap == null ? content : InkWell(onTap: onTap, borderRadius: radius, child: content),
          ),
        ),
      ),
    );
  }
}

/// Claymorphism's inner light: a highlight inside the top and start edges of
/// a surface and a shade inside the bottom and end ones, which is what makes
/// it look puffed up.
class _ClayPainter extends CustomPainter {
  const _ClayPainter(this.radius, this.dark);
  final BorderRadius radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = radius.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(shape);
    // A blurred frame just outside the shape, pushed in from one corner.
    void edge(Color color, Offset offset) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawRRect(shape.inflate(6).shift(offset), paint);
    }

    edge(Colors.black.withAlpha(dark ? 90 : 30), const Offset(-6, -6));
    edge(Colors.white.withAlpha(dark ? 28 : 200), const Offset(6, 6));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClayPainter old) => old.radius != radius || old.dark != dark;
}

/// What draws the menu around the pages, by layout and window width: a
/// drawer (the page's own), or a rail, bottom tabs or top links (AppShell's).
/// railUnder is the rail below a header across the whole window
/// (router.g.dart's appMenuUnderHeader).
enum _Chrome { none, drawer, rail, railUnder, tabs, topLinks }

_Chrome _chromeOf(BuildContext context, int entries) {
  if (appLayout == NavLayout.grid || entries == 0) return _Chrome.none;
  final wide = MediaQuery.sizeOf(context).width >= 900;
  if (entries >= 2 && wide) {
    if (appLayout == NavLayout.topbar) return _Chrome.topLinks;
    return appMenuUnderHeader ? _Chrome.railUnder : _Chrome.rail;
  }
  if (entries >= 2 && appLayout == NavLayout.tabs) return _Chrome.tabs;
  return _Chrome.drawer;
}

/// The side menu (the rail, the drawer) in the colour picked for it in AppWand
/// (theme.dart's menuColor), its text and icons light or dark to suit it. The
/// style's own colours when none is picked.
Widget _menuColors(BuildContext context, Widget menu) {
  final color = menuColor;
  if (color == null) return menu;
  final theme = Theme.of(context);
  final on = onColor(color);
  return Theme(
    data: theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        surface: color,
        surfaceContainerLow: color,
        surfaceTint: Colors.transparent,
        onSurface: on,
        onSurfaceVariant: on.withAlpha(200),
        secondaryContainer: on.withAlpha(40),
        onSecondaryContainer: on,
      ),
    ),
    child: menu,
  );
}

/// The colour of the app's name over the side menu; null for the style's own.
Color? get _onMenu {
  final color = menuColor;
  return color == null ? null : onColor(color);
}

/// The app's navigation around its pages: router.g.dart's ShellRoute puts
/// every page inside it. The rail, the bottom tabs and the top links stay put
/// while pages come and go (appPage, core/transitions.dart), so only the page
/// moves. A drawer belongs to the page's own AppScaffold.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  /// Where the router is; the menu marks the entry it belongs to.
  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// The last menu page shown; it stays marked while pages are pushed over it.
  String? _current;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final menu = menuFor(auth);
    final footer = footerFor(auth);
    if (menu.any((m) => m.route == widget.location)) _current = widget.location;
    // A page opened from the menu's foot (the Trash) is no menu entry: none is marked.
    if (footer.any((m) => m.route == widget.location)) _current = null;
    final selected = menu.indexWhere((m) => m.route == _current);
    // Clipped, so a page sliding in or out never draws over the menu.
    final page = ClipRect(child: widget.child);

    // The side menu; under a header it leaves the logo and the name to the header.
    // As a list (router.g.dart's appMenuList) the whole item is marked, not the icon.
    Widget rail({required bool named}) => appMenuList
        ? _MenuDrawer(menu: menu, selected: selected, side: true, named: named, footer: footer)
        : _menuColors(
          context,
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: selected < 0 ? null : selected,
            leading: named
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(children: [
                      const AppLogo(size: 36),
                      const SizedBox(height: 8),
                      Text(appTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _onMenu)),
                    ]),
                  )
                : null,
            destinations: [
              for (final m in menu) NavigationRailDestination(icon: Icon(m.icon), label: Text(tr(m.title))),
            ],
            onDestinationSelected: (i) => context.go(menu[i].route),
            trailing: footer.isEmpty
                ? null
                : Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MenuFooter(entries: footer, axis: Axis.vertical),
                      ),
                    ),
                  ),
          ),
        );

    switch (_chromeOf(context, menu.length)) {
      case _Chrome.rail:
        return Material(child: Row(children: [
          rail(named: true),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ]));
      case _Chrome.railUnder:
        // The header runs across the whole window with the app's name and the
        // account menu, and the menu sits below it; each page's title and
        // actions head its body (AppScaffold).
        return Material(child: Column(children: [
          AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 20,
            title: Row(children: [
              const AppLogo(size: 32),
              if (logoAsset != null) const SizedBox(width: 12),
              Flexible(child: Text(appTitle, overflow: TextOverflow.ellipsis)),
            ]),
            actions: [if (auth.isSignedIn) ...[..._headerActions(context), const _UserMenu()], const SizedBox(width: 8)],
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Row(children: [
                rail(named: false),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ]),
            ),
          ),
        ]));
      case _Chrome.tabs:
        return Material(child: Column(children: [
          Expanded(child: MediaQuery.removePadding(context: context, removeBottom: true, child: page)),
          _BottomTabs(menu: menu, selected: selected),
        ]));
      case _Chrome.topLinks:
        // The bar carries the app's name, the menu and the account menu; each
        // page's title and actions head its body (AppScaffold).
        return Material(child: Column(children: [
          AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 20,
            title: Row(children: [
              const AppLogo(size: 32),
              if (logoAsset != null) const SizedBox(width: 12),
              Text(appTitle),
              const SizedBox(width: 32),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var i = 0; i < menu.length; i++) _TopLink(entry: menu[i], selected: i == selected),
                  ]),
                ),
              ),
            ]),
            actions: [if (auth.isSignedIn) ...[..._headerActions(context), const _UserMenu()], const SizedBox(width: 8)],
          ),
          Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: page)),
        ]));
      default:
        return widget.child;
    }
  }
}

/// A page's body in a centred column appContentMaxWidth wide (router.g.dart),
/// or the whole width when the app is fluid.
Widget _contained(Widget body) {
  final width = appContentMaxWidth;
  if (width == null) return body;
  return Align(
    alignment: Alignment.topCenter,
    child: SizedBox(width: width, height: double.infinity, child: body),
  );
}

/// The chrome every page uses: app bar, drawer, user menu. AppShell draws the
/// rest of the navigation around it. On wide windows a fixed-width app keeps
/// the body (and, under AppShell's top bar, the page's heading) in a centred column.
class AppScaffold extends ConsumerWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whether this page was pushed over another. Not GoRouter.canPop(): an open
    // menu or dialog makes that true, which would swap the navigation out,
    // rebuild the body and open popup menus at the window's corner. Nor the
    // route's canPop: the drawer makes that true as it opens, which would take
    // the drawer away mid-open and leave its disposed focus scope behind.
    final canPop = !(ModalRoute.of(context)?.isFirst ?? true);
    final location = GoRouterState.of(context).matchedLocation;
    final auth = ref.watch(authProvider);
    final menu = menuFor(auth);
    final selected = menu.indexWhere((m) => m.route == location);

    // Pushed pages (details, forms) show a back button instead of the drawer.
    // The grid layout has no menu chrome: its pages lead back to the grid at '/'.
    final chrome = _chromeOf(context, menu.length);
    final useDrawer = chrome == _Chrome.drawer && !canPop;
    final useGridButton = appLayout == NavLayout.grid && !canPop && location != '/';

    if (chrome == _Chrome.topLinks || chrome == _Chrome.railUnder) {
      // AppShell's top bar has the app's name and the account menu (and, with top links, the menu).
      return Scaffold(
        body: _contained(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(canPop ? 12 : 24, 20, 16, 8),
            child: Row(children: [
              if (canPop) ...[const BackButton(), const SizedBox(width: 4)],
              Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
              ...?actions,
            ]),
          ),
          Expanded(child: body),
        ])),
        floatingActionButton: floatingActionButton,
      );
    }

    // On a phone the bar has no room for the page's actions beside the app's
    // own (the quick action, what the plugins put there, the account menu):
    // past four buttons in all, the page's leave the bar. The page's search box
    // (ListSearchField) shows them beside it; a page without one gets them in
    // a row of their own under the title.
    final own = actions ?? const <Widget>[];
    final shared = !auth.isSignedIn
        ? 0
        : 1 + (!appActionsInHeader || actionsFor(auth).isEmpty ? 0 : 1) + appPlugins.where((plugin) => plugin.headerAction != null).length;
    final below = own.isNotEmpty && own.length + shared > 4 && MediaQuery.sizeOf(context).width < 600;

    return _MovedActions(
      actions: below ? own : const <Widget>[],
      builder: (context, taken) => Scaffold(
        appBar: AppBar(
          leading: useGridButton
              ? IconButton(tooltip: tr('All pages'), icon: const Icon(AppIcons.apps), onPressed: () => context.go('/'))
              : null,
          title: Text(title),
          actions: [
            if (!below) ...own,
            if (auth.isSignedIn) ...[
              if (own.isNotEmpty && !below) const _ActionsDivider(),
              ..._headerActions(context),
              const _UserMenu(),
            ],
            const SizedBox(width: 8),
          ],
          bottom: below && !taken ? _ActionsRow(own) : null,
        ),
        drawer: useDrawer ? _MenuDrawer(menu: menu, selected: selected, footer: footerFor(auth)) : null,
        body: _contained(body),
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}

/// Hands the page's [actions] that left a phone's app bar to the page's search
/// box (PageActions), and tells [builder] whether one took them.
class _MovedActions extends StatefulWidget {
  const _MovedActions({required this.actions, required this.builder});
  final List<Widget> actions;
  final Widget Function(BuildContext context, bool taken) builder;

  @override
  State<_MovedActions> createState() => _MovedActionsState();
}

class _MovedActionsState extends State<_MovedActions> {
  // Never disposed: a search box going away with the page still counts down.
  final ValueNotifier<int> _claims = ValueNotifier(0);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _claims,
      builder: (context, claims, child) => PageActions(
        actions: widget.actions,
        claims: _claims,
        child: Builder(builder: (context) => widget.builder(context, claims > 0)),
      ),
    );
  }
}

/// The page's actions in a row of their own under the app bar's title, at its
/// end and scrolling sideways when they are many, in the bar's own colours.
class _ActionsRow extends StatelessWidget implements PreferredSizeWidget {
  const _ActionsRow(this.actions);
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).appBarTheme.foregroundColor;
    final row = SizedBox(
      height: 48,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: actions),
        ),
      ),
    );
    if (color == null) return row;
    return IconTheme.merge(
      data: IconThemeData(color: color),
      child: IconButtonTheme(
        data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: color)),
        child: row,
      ),
    );
  }
}

/// A short line in the app bar between the page's actions and the account menu.
class _ActionsDivider extends StatelessWidget {
  const _ActionsDivider();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: SizedBox(height: 24, child: VerticalDivider(width: 1, thickness: 1, color: color.withAlpha(70))),
    );
  }
}

/// The signed-in account's role as a small pill, in [color] over a tint of it.
class _RoleChip extends StatelessWidget {
  const _RoleChip(this.label, {required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        border: Border.all(color: color.withAlpha(90)),
        borderRadius: BorderRadius.circular(square ? 0 : 999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
      ),
    );
  }
}

/// The signed-in account's photo in a circle, or the first letter of its name
/// (or email) in [color] over a tint of it while it has none.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.size, required this.color});
  final Map<String, dynamic>? user;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final photo = fileUrl(user?['photo']);
    if (photo != null) return AppImage(photo, width: size, height: size, circle: true, preview: false);
    final name = '${user?['name'] ?? user?['email'] ?? ''}'.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(36),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: name.isEmpty
          ? Icon(AppIcons.account, size: size * 0.6, color: color)
          : Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(color: color, fontSize: size * 0.42, fontWeight: FontWeight.w600, height: 1),
            ),
    );
  }
}

/// The app's name at the head of the side menu and the phone's drawer, with
/// the signed-in account's role under it (the name and photo are in the app
/// bar's account menu).
class _MenuTitle extends ConsumerWidget {
  const _MenuTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider).roleLabel;
    final theme = Theme.of(context);
    final color = _onMenu ?? theme.colorScheme.onSurface;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(
        appTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleLarge?.copyWith(color: _onMenu),
      ),
      if (role.isNotEmpty)
        Text(
          role,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: color.withAlpha(170)),
        ),
    ]);
  }
}

/// The signed-in account's menu: who is signed in and their role, the Account
/// page (with the theme setting) and Sign out. On a wide window the name and
/// the role show beside the icon, unless [compact] (the grid's greeting has them).
class _UserMenu extends ConsumerWidget {
  const _UserMenu({this.color, this.compact = false});
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);
    final name = '${auth.user?['name'] ?? auth.user?['email'] ?? ''}'.trim();
    final role = auth.roleLabel;
    final on = color ?? IconTheme.of(context).color ?? theme.colorScheme.onSurface;
    final open = !compact && MediaQuery.sizeOf(context).width >= 900 && (name.isNotEmpty || role.isNotEmpty);
    // Where the layout shows no side menu (bottom tabs, top links, the grid),
    // the pages kept at its foot are here instead.
    final chrome = _chromeOf(context, menuFor(auth).length);
    final extra = chrome == _Chrome.none || chrome == _Chrome.tabs || chrome == _Chrome.topLinks
        ? footerFor(auth)
        : const <MenuEntry>[];
    return PopupMenuButton<String>(
      tooltip: tr('Account'),
      icon: open
          ? null
          : (fileUrl(auth.user?['photo']) == null
              ? Icon(AppIcons.account, color: color)
              : _Avatar(user: auth.user, size: 28, color: on)),
      child: !open
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _Avatar(user: auth.user, size: 28, color: on),
                if (name.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(color: on),
                    ),
                  ),
                ],
                if (role.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: _RoleChip(role, color: on),
                  ),
                ],
              ]),
            ),
      onSelected: (value) {
        if (value.startsWith('/') && GoRouter.of(context).state.matchedLocation != value) context.go(value);
        // GoRouter's state, not GoRouterState.of: AppShell's top bar has this menu too.
        if (value == 'account' && GoRouter.of(context).state.matchedLocation != '/account') context.push('/account');
        if (value == 'logout') ref.read(authProvider.notifier).logout();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name),
            if (role.isNotEmpty) Text(role, style: theme.textTheme.bodyMedium),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'account',
          child: Row(children: [const Icon(AppIcons.manageAccounts), const SizedBox(width: 12), Text(tr('Account'))]),
        ),
        for (final entry in extra)
          PopupMenuItem<String>(
            value: entry.route,
            child: Row(children: [Icon(entry.icon), const SizedBox(width: 12), Text(tr(entry.title))]),
          ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(children: [const Icon(AppIcons.logout), const SizedBox(width: 12), Text(tr('Sign out'))]),
        ),
      ],
    );
  }
}

/// The grid layout's home screen: a greeting, then a card for every menu page
/// the signed-in account may open.
class AppLauncherPage extends ConsumerWidget {
  const AppLauncherPage({super.key, this.params = const {}});
  final Map<String, String> params;

  /// Icon colours, taken in turn so neighbouring cards differ.
  static const List<Color> _tints = [
    Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFEA580C), Color(0xFF9333EA),
    Color(0xFFDB2777), Color(0xFF0891B2), Color(0xFFCA8A04), Color(0xFF4F46E5),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final menu = menuFor(auth);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = '${auth.user?['name'] ?? ''}'.trim();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1500 ? 5 : (width >= 1100 ? 4 : (width >= 700 ? 3 : 2));
    // A fixed-width app keeps the cards in its centred column; a fluid one fills the window.
    final max = appContentMaxWidth;
    final side = max != null && width > max + 40 ? (width - max) / 2 : 20.0;
    // The header's own colour when AppWand set one, else the brand colour.
    final own = headerColor;
    final header = own ?? scheme.primary;
    final onHeader = own == null ? scheme.onPrimary : onColor(own);
    // The cards in runs of one menu group (MenuEntry.group), each under its label.
    final runs = <List<MenuEntry>>[];
    for (final m in menu) {
      if (runs.isEmpty || runs.last.first.group != m.group) runs.add([]);
      runs.last.add(m);
    }

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [header, Color.lerp(header, Colors.white, own == null ? 0.3 : 0.12)!],
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(appStyle == AppStyle.brutalism || appStyle == AppStyle.flat ? 0 : 28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(side + 4, 20, side - 4, 32),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const AppLogo(size: 32),
                        if (logoAsset != null) const SizedBox(width: 12),
                        Flexible(child: Text(appTitle, style: theme.textTheme.titleMedium?.copyWith(color: onHeader))),
                      ]),
                      const SizedBox(height: 24),
                      Row(children: [
                        if (auth.isSignedIn) ...[
                          _Avatar(user: auth.user, size: 64, color: onHeader),
                          const SizedBox(width: 16),
                        ],
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name.isEmpty ? tr('Welcome back') : tr('Hello,'),
                                style: theme.textTheme.titleMedium?.copyWith(color: onHeader.withAlpha(220))),
                            if (name.isNotEmpty)
                              Text(name,
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(color: onHeader, fontWeight: FontWeight.bold)),
                            if (auth.roleLabel.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _RoleChip(auth.roleLabel, color: onHeader),
                            ],
                          ]),
                        ),
                      ]),
                    ]),
                  ),
                  if (auth.isSignedIn) ...[
                    ..._headerActions(context, compact: true, color: onHeader, actions: false),
                    _UserMenu(color: onHeader, compact: true),
                  ],
                ]),
              ),
            ),
          ),
        ),
        // The app's main things to do, before the cards.
        SliverToBoxAdapter(child: QuickActions(padding: EdgeInsets.fromLTRB(side, 24, side, 0))),
        if (menu.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 24, side, 0),
            sliver: SliverToBoxAdapter(child: EmptyView(message: tr('Nothing to open yet.'), icon: AppIcons.apps)),
          ),
        for (final run in runs) ...[
          if (run.first.group.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side + 4, 24, side, 0),
              sliver: SliverToBoxAdapter(
                child: Text(tr(run.first.group),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, run.first.group.isEmpty ? 24 : 12, side, 0),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 184,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _LauncherCard(entry: run[i], tint: _tints[menu.indexOf(run[i]) % _tints.length]),
                childCount: run.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

class _LauncherCard extends StatelessWidget {
  const _LauncherCard({required this.entry, required this.tint});
  final MenuEntry entry;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSurface(
      onTap: () => context.go(entry.route),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: tint.withAlpha(36), borderRadius: BorderRadius.circular(16)),
            child: Icon(entry.icon, color: tint, size: 28),
          ),
          const Spacer(),
          Icon(AppIcons.chevronRight, color: scheme.onSurfaceVariant),
        ]),
        const Spacer(),
        Text(tr(entry.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (entry.subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(tr(entry.subtitle),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ]),
    );
  }
}

/// The menu as a list of full-width items: the phone's drawer, and with
/// [side] the menu that stays beside the pages on wide windows (AppShell,
/// router.g.dart's appMenuList), flat and square against the page.
class _MenuDrawer extends StatelessWidget {
  const _MenuDrawer({
    required this.menu,
    required this.selected,
    this.side = false,
    this.named = true,
    this.footer = const [],
  });
  final List<MenuEntry> menu;
  final int selected;
  final bool side;

  /// Pages kept out of the menu, as icon buttons at its foot (footerFor).
  final List<MenuEntry> footer;

  /// Whether the logo and the app's name head the menu.
  final bool named;

  static const double sideWidth = 264;

  /// A compact item's height (router.g.dart's appMenuCompact).
  static const double compactHeight = 40;

  /// Short items, beside the pages only: a phone's drawer keeps items a
  /// finger can hit.
  bool get _compact => side && appMenuCompact;

  @override
  Widget build(BuildContext context) {
    if (!side) return _drawer(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: sideWidth,
      child: Theme(
        data: theme.copyWith(
          drawerTheme: theme.drawerTheme.copyWith(elevation: 0, shape: const RoundedRectangleBorder(), width: sideWidth),
          navigationDrawerTheme: _compact
              ? theme.navigationDrawerTheme.copyWith(
                  tileHeight: compactHeight,
                  indicatorSize: const Size(336, compactHeight),
                )
              : null,
        ),
        // A context under the theme above, so the menu's colours keep it.
        child: Builder(builder: _drawer),
      ),
    );
  }

  Widget _drawer(BuildContext context) {
    if (footer.isEmpty) return _menuColors(context, _items(context));
    // The foot stays put over the menu's own background while the items scroll.
    return _menuColors(
      context,
      Stack(children: [
        _items(context),
        PositionedDirectional(
          start: 16,
          bottom: 12,
          child: SafeArea(
            child: _MenuFooter(entries: footer, onOpen: side ? null : () => Scaffold.of(context).closeDrawer()),
          ),
        ),
      ]),
    );
  }

  Widget _items(BuildContext context) {
    return NavigationDrawer(
        selectedIndex: selected < 0 ? null : selected,
        onDestinationSelected: (i) {
          if (!side) Scaffold.of(context).closeDrawer();
          context.go(menu[i].route);
        },
        children: [
          if (named)
            Padding(
              padding: _compact ? const EdgeInsets.fromLTRB(28, 16, 16, 10) : const EdgeInsets.fromLTRB(28, 24, 16, 16),
              child: Row(children: [
                const AppLogo(size: 36),
                if (logoAsset != null) const SizedBox(width: 12),
                const Expanded(child: _MenuTitle()),
              ]),
            )
          else
            const SizedBox(height: 12),
          // On a phone the header shows only the main action's icon: here they are by name.
          if (!side) const _DrawerActions(),
          for (var i = 0; i < menu.length; i++) ...[
            // A label where the menu group changes (MenuEntry.group); it is no destination.
            if (menu[i].group != (i == 0 ? '' : menu[i - 1].group))
              _MenuGroupLabel(menu[i].group, first: i == 0, compact: _compact),
            NavigationDrawerDestination(
              icon: Icon(menu[i].icon, size: _compact ? 20 : null),
              label: Text(tr(menu[i].title)),
            ),
          ],
          // Room for the buttons at the foot, so the last item scrolls clear of them.
          if (footer.isNotEmpty) const SizedBox(height: 72),
        ],
    );
  }
}

/// The bottom tab bar: up to five tabs, the rest behind "More".
class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.menu, required this.selected});
  final List<MenuEntry> menu;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final overflow = menu.length > 5;
    final tabs = overflow ? menu.take(4).toList() : menu;
    final more = overflow ? menu.skip(4).toList() : const <MenuEntry>[];
    final index = selected < 0 ? 0 : (selected < tabs.length ? selected : tabs.length);

    void openMore() {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
            for (final m in more)
              ListTile(
                leading: Icon(m.icon),
                title: Text(tr(m.title)),
                selected: menu.indexOf(m) == selected,
                onTap: () {
                  Navigator.of(sheet).pop();
                  context.go(m.route);
                },
              ),
          ]),
        ),
      );
    }

    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => i < tabs.length ? context.go(tabs[i].route) : openMore(),
      destinations: [
        for (final m in tabs) NavigationDestination(icon: Icon(m.icon), label: tr(m.title)),
        if (overflow) NavigationDestination(icon: const Icon(AppIcons.moreHoriz), label: tr('More')),
      ],
    );
  }
}

/// One menu entry in the top bar.
class _TopLink extends StatelessWidget {
  const _TopLink({required this.entry, required this.selected});
  final MenuEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Classic Material's app bar is the brand colour, and AppWand can give the
    // header its own: links take the bar's text colour.
    final onBar = AppBarTheme.of(context).foregroundColor;
    final own = headerColor == null ? null : onBar;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: () => context.go(entry.route),
        icon: Icon(entry.icon, size: 20),
        label: Text(tr(entry.title)),
        style: TextButton.styleFrom(
          foregroundColor: own ?? (selected ? scheme.onSecondaryContainer : (onBar ?? scheme.onSurfaceVariant)),
          backgroundColor: selected ? (own?.withAlpha(40) ?? scheme.secondaryContainer) : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.error, size: 48, color: scheme.error),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh), label: Text(tr('Try again'))),
          ],
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon = AppIcons.inbox});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

Future<bool> showConfirmDialog(BuildContext context, {required String title, required String message}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('Confirm'))),
      ],
    ),
  );
  return result ?? false;
}

/// A short message about what just happened ("Saved", an error), drawn in the
/// app's notification style (theme.dart's noticeStyle): a snackbar, a toast
/// or a banner. Safe to call right before context.pop().
void showSnack(BuildContext context, String message, {bool error = false}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final messenger = ScaffoldMessenger.of(context);
  final icon = error ? AppIcons.error : AppIcons.checkCircle;
  messenger.hideCurrentSnackBar();

  switch (noticeStyle) {
    case NoticeStyle.snackbar:
      messenger.showSnackBar(SnackBar(
        content: Text(message, style: TextStyle(color: error ? scheme.onError : null)),
        backgroundColor: error ? scheme.error : null,
      ));
    case NoticeStyle.floating:
      final foreground = error ? scheme.onErrorContainer : scheme.onInverseSurface;
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? scheme.errorContainer : scheme.inverseSurface,
        showCloseIcon: true,
        closeIconColor: foreground,
        content: Row(children: [
          Icon(icon, color: error ? scheme.error : scheme.inversePrimary),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(color: foreground))),
        ]),
      ));
    case NoticeStyle.banner:
      _showBanner(messenger, scheme, message, icon, error);
    case NoticeStyle.toast || NoticeStyle.tinted || NoticeStyle.filled || NoticeStyle.minimal:
      final shape = theme.cardTheme.shape;
      toastification.show(
        context: context,
        // The root overlay outlives the page, so a toast shown before a pop stays.
        overlayState: Overlay.of(context, rootOverlay: true),
        type: error ? ToastificationType.error : ToastificationType.success,
        style: switch (noticeStyle) {
          NoticeStyle.tinted => ToastificationStyle.flatColored,
          NoticeStyle.filled => ToastificationStyle.fillColored,
          NoticeStyle.minimal => ToastificationStyle.minimal,
          _ => ToastificationStyle.flat,
        },
        title: Text(message, maxLines: 4),
        alignment: MediaQuery.sizeOf(context).width >= 600 ? Alignment.topRight : Alignment.topCenter,
        autoCloseDuration: Duration(seconds: error ? 6 : 4),
        showProgressBar: noticeStyle == NoticeStyle.toast,
        borderRadius: shape is RoundedRectangleBorder ? shape.borderRadius : null,
        borderSide: appStyle == AppStyle.brutalism ? BorderSide(color: scheme.onSurface, width: 2.5) : null,
        dragToClose: true,
        pauseOnHover: true,
      );
  }
}

/// The banner on show, so an older banner's timer leaves a newer one alone.
ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>? _banner;

void _showBanner(ScaffoldMessengerState messenger, ColorScheme scheme, String message, IconData icon, bool error) {
  messenger.hideCurrentMaterialBanner();
  final foreground = error ? scheme.onErrorContainer : scheme.onSecondaryContainer;
  final banner = messenger.showMaterialBanner(MaterialBanner(
    leading: Icon(icon, color: error ? scheme.error : scheme.primary),
    content: Text(message, style: TextStyle(color: foreground)),
    backgroundColor: error ? scheme.errorContainer : scheme.secondaryContainer,
    actions: [
      TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: Text(tr('Dismiss'), style: TextStyle(color: foreground))),
    ],
  ));
  _banner = banner;
  Timer(Duration(seconds: error ? 7 : 4), () {
    if (messenger.mounted && identical(_banner, banner)) messenger.hideCurrentMaterialBanner();
  });
}
