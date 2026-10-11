// The parts of a page that shows one record. Owned by AppWand.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'i18n.dart';
import 'icons.dart';
import 'theme.dart' show AppStyle, DetailStyle, appStyle, detailStyle;
import 'uploads.dart' show AppImage;
import 'widgets.dart' show AppSurface, showSnack;

// For a section given a layout of its own (DetailSection(style: ...)).
export 'theme.dart' show DetailStyle;

/// The body of a page that shows one record: its parts under one another,
/// scrolling, centred at [maxWidth] on wide screens.
class DetailView extends StatelessWidget {
  const DetailView({super.key, required this.children, this.maxWidth = 960, this.onRefresh});

  final List<Widget> children;
  final double maxWidth;

  /// Adds pull to refresh.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
    final refresh = onRefresh;
    return refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
  }
}

/// A page's own layout of labels and values, in place of the app's
/// detailStyle. router.g.dart puts it around a page given one in AppWand.
class DetailLook extends InheritedWidget {
  const DetailLook({super.key, required this.style, required super.child});
  final DetailStyle style;

  /// The layout in force at [context]: the page's own, else the app's.
  static DetailStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailLook>()?.style ?? detailStyle;

  @override
  bool updateShouldNotify(DetailLook oldWidget) => style != oldWidget.style;
}

/// A short word about a record in a tinted pill: its status, its type.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.color, this.icon});

  final String text;

  /// The pill's colour; the brand colour when left out.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.primary;
    final dark = theme.brightness == Brightness.dark;
    // The colour itself is too light to read on its tint in a dark theme,
    // and too pale in a light one: pull it towards the text colour.
    final ink = Color.lerp(tone, theme.colorScheme.onSurface, dark ? 0.35 : 0.3)!;
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withAlpha(dark ? 56 : 34),
        borderRadius: BorderRadius.circular(square ? 4 : 999),
        border: appStyle == AppStyle.brutalism ? Border.all(color: theme.colorScheme.onSurface, width: 1.5) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 16, color: ink), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: ink, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

/// One number of a DetailHeader.
class DetailStat {
  const DetailStat(this.label, this.value, {this.icon, this.onTap});

  final String label;

  /// Shown as text; null or empty shows a dash.
  final Object? value;
  final IconData? icon;

  /// Makes the stat a link, e.g. to the list it counts.
  final VoidCallback? onTap;
}

/// The top of a record's page: its picture or icon, name, a line under it, a
/// badge, buttons, and a row of stats.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.image,
    this.icon,
    this.avatar = false,
    this.badge,
    this.stats = const [],
    this.actions = const [],
  });

  final String title;
  final String? subtitle;

  /// The record's picture, a stored path or a URL.
  final dynamic image;

  /// Shown in a tinted box when there is no picture.
  final IconData? icon;

  /// A person: the picture in a circle, or the first letter of [title].
  final bool avatar;

  /// Beside the title, usually a StatusBadge.
  final Widget? badge;
  final List<DetailStat> stats;

  /// Buttons for what can be done with the record, at the end on wide
  /// screens and under the title on narrow ones.
  final List<Widget> actions;

  Widget? _leading(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = image == null ? '' : '$image'.trim();
    const size = 64.0;
    if (path.isNotEmpty) {
      return AppImage(path, width: size, height: size, circle: avatar, radius: avatar ? 0 : 12, title: title);
    }
    if (icon == null && !avatar) return null;
    final letter = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: avatar ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: avatar ? null : BorderRadius.circular(appStyle == AppStyle.brutalism ? 0 : 12),
      ),
      child: icon != null
          ? Icon(icon, size: 30, color: scheme.onPrimaryContainer)
          : Text(letter,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 600;
      final leading = _leading(context);
      final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
      final name = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (badge != null) badge!,
        ]),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle!, style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
          ),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (leading != null) ...[leading, const SizedBox(width: 16)],
          Expanded(child: name),
          if (wide && actions.isNotEmpty) ...[const SizedBox(width: 16), buttons],
        ]),
        if (!wide && actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: buttons),
        if (stats.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 16), child: _Stats(stats: stats, width: box.maxWidth)),
      ]);
    });
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats, required this.width});
  final List<DetailStat> stats;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const gap = 12.0;
    final most = width >= 720 ? 4 : (width >= 420 ? 2 : 1);
    final across = stats.length < most ? stats.length : most;
    final tile = (width - gap * (across - 1)) / across;
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (final stat in stats)
        SizedBox(
          width: tile.floorToDouble(),
          child: AppSurface(
            onTap: stat.onTap,
            child: Row(children: [
              if (stat.icon != null) ...[
                Icon(stat.icon, color: scheme.primary),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _shown(stat.value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stat.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              if (stat.onTap != null) Icon(AppIcons.chevronRight, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
    ]);
  }
}

String _shown(Object? value) {
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty ? '—' : text;
}

/// One field of a record in a DetailSection: what it is called and its value.
class DetailField {
  const DetailField(
    this.label,
    this.value, {
    this.child,
    this.icon,
    this.copy = false,
    this.onTap,
    this.wide = false,
  });

  final String label;

  /// Shown as text; null or empty shows a dash.
  final Object? value;

  /// Shown in place of the text: a StatusBadge, an AppImage, a row of chips.
  final Widget? child;

  /// A small icon before the label.
  final IconData? icon;

  /// Adds a button that copies the value.
  final bool copy;

  /// Makes the value a link, e.g. to the record it names.
  final VoidCallback? onTap;

  /// A long text: takes a whole row where fields sit side by side (the
  /// columns and inline styles).
  final bool wide;

  bool get isEmpty => child == null && (value == null || '$value'.trim().isEmpty);
}

/// A group of a record's fields under a heading, each a label and its value,
/// laid out as the app's detailStyle says.
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.fields,
    this.style,
    this.columns,
    this.hideEmpty = false,
    this.surface = true,
  });

  final String? title;
  final IconData? icon;

  /// At the end of the heading, e.g. an Edit button.
  final Widget? trailing;
  final List<DetailField> fields;

  /// This section's own layout; the page's or the app's when left out.
  final DetailStyle? style;

  /// How many fields sit side by side in the columns style; by the width
  /// when left out.
  final int? columns;

  /// Leaves out the fields that have no value, in place of a dash.
  final bool hideEmpty;

  /// False draws the section without its card, inside something that is
  /// one already.
  final bool surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = hideEmpty ? [for (final f in fields) if (!f.isEmpty) f] : fields;
    final look = style ?? DetailLook.of(context);

    final heading = title == null && trailing == null
        ? null
        : Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: scheme.primary), const SizedBox(width: 8)],
            Expanded(
              child: Text(title ?? '', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing!,
          ]);

    final body = LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      switch (look) {
        case DetailStyle.vertical:
          return _stack([for (final f in shown) _Pair(field: f)], 14);
        case DetailStyle.horizontal:
          if (width < 420) return _stack([for (final f in shown) _Pair(field: f)], 14);
          final label = (width * 0.34).clamp(120.0, 220.0);
          return _stack([for (final f in shown) _Line(field: f, labelWidth: label)], 12);
        case DetailStyle.table:
          return _Table(fields: shown, labelWidth: (width * (width < 420 ? 0.4 : 0.32)).clamp(104.0, 240.0));
        case DetailStyle.inline:
          return Wrap(spacing: 28, runSpacing: 12, children: [
            for (final f in shown)
              if (f.wide) SizedBox(width: width, child: _Inline(field: f)) else _Inline(field: f),
          ]);
        case DetailStyle.columns:
          const gap = 24.0;
          final wanted = columns ?? (width >= 840 ? 3 : (width >= 480 ? 2 : 1));
          final across = wanted < 1 ? 1 : wanted;
          final cell = ((width - gap * (across - 1)) / across).floorToDouble();
          return Wrap(spacing: gap, runSpacing: 16, children: [
            for (final f in shown) SizedBox(width: f.wide ? width : cell, child: _Pair(field: f)),
          ]);
      }
    });

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading != null) ...[heading, const SizedBox(height: 14)],
        if (shown.isEmpty)
          Text(tr('Nothing to show.'), style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
        else
          body,
      ],
    );
    return surface ? AppSurface(child: content) : content;
  }

  static Widget _stack(List<Widget> rows, double gap) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            rows[i],
          ],
        ],
      );
}

/// A field's label: quiet, so the value stands out beside or under it.
class _Label extends StatelessWidget {
  const _Label({required this.field, this.colon = false});
  final DetailField field;
  final bool colon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final text = Text(
      colon ? '${field.label}:' : field.label,
      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
    );
    if (field.icon == null) return text;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(field.icon, size: 16, color: muted),
      const SizedBox(width: 6),
      Flexible(child: text),
    ]);
  }
}

/// A field's value: the text in the stronger colour and weight, a link, the
/// field's own widget, or a dash.
class _Value extends StatelessWidget {
  const _Value({required this.field});
  final DetailField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final custom = field.child;
    if (custom != null) return Align(alignment: AlignmentDirectional.centerStart, child: custom);
    if (field.isEmpty) {
      return Text('—', style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant));
    }
    final value = '${field.value}'.trim();
    final link = field.onTap != null;
    Widget text = Text(
      value,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: link ? scheme.primary : scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
    if (link) {
      text = InkWell(onTap: field.onTap, borderRadius: BorderRadius.circular(4), child: text);
    }
    if (!field.copy) return text;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Flexible(child: text),
      const SizedBox(width: 4),
      SizedBox(
        width: 28,
        height: 24,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 16,
          tooltip: tr('Copy'),
          icon: const Icon(AppIcons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) showSnack(context, tr('Copied'));
          },
        ),
      ),
    ]);
  }
}

/// The label over the value.
class _Pair extends StatelessWidget {
  const _Pair({required this.field});
  final DetailField field;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_Label(field: field), const SizedBox(height: 3), _Value(field: field)],
      );
}

/// The label in a column of its own, the value beside it.
class _Line extends StatelessWidget {
  const _Line({required this.field, required this.labelWidth});
  final DetailField field;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            // The label's smaller type sits a little lower, on the value's line.
            child: Padding(padding: const EdgeInsets.only(top: 2), child: _Label(field: field)),
          ),
          const SizedBox(width: 16),
          Expanded(child: _Value(field: field)),
        ],
      );
}

/// "Label: value" on one line, one after another.
class _Inline extends StatelessWidget {
  const _Inline({required this.field});
  final DetailField field;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: _Label(field: field, colon: true)),
          const SizedBox(width: 8),
          Flexible(child: _Value(field: field)),
        ],
      );
}

/// A table of two columns: the labels on a tinted column, a line under each row.
class _Table extends StatelessWidget {
  const _Table({required this.fields, required this.labelWidth});
  final List<DetailField> fields;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hard = appStyle == AppStyle.brutalism;
    final line = BorderSide(color: hard ? scheme.onSurface : scheme.outlineVariant, width: hard ? 1.5 : 1);
    final radius = BorderRadius.circular(hard || appStyle == AppStyle.flat ? 0 : 10);
    return Container(
      decoration: BoxDecoration(border: Border.fromBorderSide(line), borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < fields.length; i++)
          Container(
            decoration: BoxDecoration(border: i > 0 ? Border(top: line) : null),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: labelWidth,
                  color: scheme.surfaceContainerHighest.withAlpha(120),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  alignment: AlignmentDirectional.centerStart,
                  child: _Label(field: fields[i]),
                ),
                Container(width: line.width, color: line.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Align(alignment: AlignmentDirectional.centerStart, child: _Value(field: fields[i])),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// One tab of a DetailTabs.
class DetailTab {
  const DetailTab({required this.label, this.count, this.icon, required this.builder});

  final String label;

  /// How many rows the tab holds, shown beside its label.
  final int? count;
  final IconData? icon;

  /// The tab's content, built when it is first opened: a short list of
  /// related rows, a DetailSection.
  final WidgetBuilder builder;
}

/// Tabs inside a record's page, for its related lists. The chosen tab is as
/// tall as its content, so the page scrolls as one.
class DetailTabs extends StatefulWidget {
  const DetailTabs({super.key, required this.tabs, this.initial = 0, this.surface = true});

  final List<DetailTab> tabs;
  final int initial;

  /// False draws the tabs without their card.
  final bool surface;

  @override
  State<DetailTabs> createState() => _DetailTabsState();
}

class _DetailTabsState extends State<DetailTabs> with TickerProviderStateMixin {
  late TabController _tabs;
  final _opened = <int>{};

  @override
  void initState() {
    super.initState();
    _start(widget.initial);
  }

  void _start(int index) {
    final count = widget.tabs.length;
    final first = count == 0 ? 0 : index.clamp(0, count - 1);
    _tabs = TabController(length: count, vsync: this, initialIndex: first)..addListener(_changed);
    _opened
      ..removeWhere((i) => i >= count)
      ..add(first);
  }

  void _changed() {
    if (!mounted) return;
    setState(() => _opened.add(_tabs.index));
  }

  @override
  void didUpdateWidget(DetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      final index = _tabs.index;
      _tabs
        ..removeListener(_changed)
        ..dispose();
      _start(index);
    }
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (widget.tabs.isEmpty) return const SizedBox.shrink();
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final tab in widget.tabs)
              Tab(
                height: 44,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (tab.icon != null) ...[Icon(tab.icon, size: 18), const SizedBox(width: 8)],
                  Text(tab.label),
                  if (tab.count != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(appStyle == AppStyle.brutalism ? 0 : 999),
                      ),
                      child: Text('${tab.count}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // An opened tab stays built, so it keeps what it loaded.
        for (var i = 0; i < widget.tabs.length; i++)
          if (_opened.contains(i))
            Offstage(
              offstage: i != _tabs.index,
              child: TickerMode(enabled: i == _tabs.index, child: Builder(builder: widget.tabs[i].builder)),
            ),
      ],
    );
    return widget.surface
        ? AppSurface(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: content)
        : content;
  }
}
