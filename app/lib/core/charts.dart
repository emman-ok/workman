// Charts in the app's colours. Owned by AppWand.
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import 'format.dart' show formatNumber;
import 'i18n.dart';
import 'icons.dart';
import 'lists.dart' show Skeleton, SkeletonBox;
import 'theme.dart' show AppStyle, appStyle;
import 'widgets.dart' show AppSurface;

/// A value from the API as a number: a num, or a String (DECIMAL columns
/// arrive as text). Anything else, null included, is 0.
double chartNum(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;
  return number.isFinite ? number : 0;
}

/// The colours charts give their series and slices, in order: the brand
/// colour first, then others that sit well beside it in this theme.
List<Color> chartColors(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  if (appStyle == AppStyle.monochrome) {
    return [for (final alpha in const [255, 170, 120, 84, 56, 36]) scheme.onSurface.withAlpha(alpha)];
  }
  final dark = scheme.brightness == Brightness.dark;
  final base = HSLColor.fromColor(scheme.primary);
  return [
    scheme.primary,
    for (final turn in const [150.0, 40.0, 210.0, 90.0, 270.0, 320.0])
      base
          .withHue((base.hue + turn) % 360)
          .withSaturation(base.saturation.clamp(0.45, 0.75).toDouble())
          .withLightness(dark ? 0.66 : 0.46)
          .toColor(),
  ];
}

/// One line of an AppLineChart, or one set of bars of an AppBarChart.
class ChartSeries {
  const ChartSeries({required this.label, required this.values, this.color});

  /// What the legend and the tooltip call it.
  final String label;

  /// One value per label, as the API sent them (num or String). A null is a
  /// gap in a line and an empty bar.
  final List<dynamic> values;

  /// Its colour; left out, the next of chartColors.
  final Color? color;
}

/// One slice of an AppPieChart.
class ChartSlice {
  const ChartSlice({required this.label, required this.value, this.color});

  final String label;

  /// As the API sent it (num or String).
  final dynamic value;

  /// Its colour; left out, the next of chartColors.
  final Color? color;
}

/// A card with a heading over a chart.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, this.subtitle, this.trailing, required this.child});

  final String title;

  /// A line under the title: the period, the unit, a total.
  final String? subtitle;

  /// At the heading's end: a period picker, a figure.
  final Widget? trailing;

  /// The chart.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
            ]),
          ),
          if (trailing != null) Padding(padding: const EdgeInsetsDirectional.only(start: 12), child: trailing),
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

/// Values over time or in order, as one or more lines.
class AppLineChart extends StatelessWidget {
  const AppLineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 240,
    this.area = false,
    this.curved = true,
    this.fromZero = true,
    this.dots,
    this.legend,
    this.format,
  });

  /// What each point along the bottom is called (a date, a month).
  final List<String> labels;
  final List<ChartSeries> series;
  final double height;

  /// Fills under each line.
  final bool area;
  final bool curved;

  /// Whether the value axis starts at zero, or just under the lowest value.
  final bool fromZero;

  /// A dot on each point; left out, only while there are few points.
  final bool? dots;

  /// The series' names under the chart; left out, shown with two or more.
  final bool? legend;

  /// How a value reads in the tooltip (formatMoney); formatNumber when left out.
  final String Function(num value)? format;

  @override
  Widget build(BuildContext context) {
    final count = labels.length;
    if (count == 0 || series.every((s) => s.values.every((v) => v == null))) return _ChartEmpty(height: height);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = _seriesColors(context, series);
    final scale = _Scale.of([
      for (final s in series)
        for (final v in s.values.take(count))
          if (v != null) chartNum(v),
    ], fromZero: fromZero);
    final sharp = appStyle == AppStyle.brutalism;
    final withDots = dots ?? count <= 16;
    final read = format ?? formatNumber;

    final chart = LayoutBuilder(builder: (context, box) {
      final plot = math.max(0.0, box.maxWidth - _axisWidth - _edge);
      final every = _labelEvery(context, labels, plot / math.max(1, count - 1));
      return LineChart(
        LineChartData(
          minX: count == 1 ? -0.5 : 0,
          maxX: count == 1 ? 0.5 : (count - 1).toDouble(),
          minY: scale.min,
          maxY: scale.max,
          gridData: _grid(scheme, scale),
          borderData: FlBorderData(show: false),
          titlesData: _titles(theme, scale, labels, every),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => scheme.inverseSurface,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) {
                final style = TextStyle(color: scheme.onInverseSurface, fontSize: 13, fontWeight: FontWeight.w600);
                return [
                  for (var i = 0; i < spots.length; i++)
                    LineTooltipItem(
                      (i == 0 ? '${_at(labels, spots[i].x.round())}\n' : '') +
                          (series.length > 1 ? '${series[spots[i].barIndex].label}: ' : '') +
                          read(spots[i].y),
                      style,
                    ),
                ];
              },
            ),
          ),
          lineBarsData: [
            for (var s = 0; s < series.length; s++)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < count; i++)
                    i < series[s].values.length && series[s].values[i] != null
                        ? FlSpot(i.toDouble(), chartNum(series[s].values[i]))
                        : FlSpot.nullSpot,
                ],
                color: colors[s],
                barWidth: sharp ? 3 : 2.5,
                isCurved: curved && !sharp,
                preventCurveOverShooting: true,
                isStrokeCapRound: !sharp,
                isStrokeJoinRound: !sharp,
                dotData: FlDotData(show: withDots),
                belowBarData: BarAreaData(
                  show: area,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colors[s].withAlpha(sharp ? 56 : 72), colors[s].withAlpha(sharp ? 56 : 0)],
                  ),
                ),
              ),
          ],
        ),
        duration: _duration(context),
      );
    });

    return _withLegend(
      context,
      chart: SizedBox(height: height, child: Padding(padding: _inset, child: chart)),
      show: legend ?? series.length > 1,
      items: [for (var s = 0; s < series.length; s++) _LegendItem(series[s].label, colors[s])],
    );
  }
}

/// Values compared across categories or periods, as bars.
class AppBarChart extends StatelessWidget {
  const AppBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 240,
    this.stacked = false,
    this.horizontal = false,
    this.legend,
    this.format,
    this.onTap,
  });

  /// What each bar (or group of bars) is called.
  final List<String> labels;
  final List<ChartSeries> series;

  /// The chart's height. A horizontal chart is as tall as its rows instead.
  final double height;

  /// Several series on top of each other in one bar, in place of side by side.
  final bool stacked;

  /// A row per label with its bar under it: for a ranking ("Top products") or
  /// long labels. It draws the first series only.
  final bool horizontal;

  /// The series' names under the chart; left out, shown with two or more.
  final bool? legend;

  /// How a value reads (formatMoney); formatNumber when left out.
  final String Function(num value)? format;

  /// A tap on the bar (or row) of this label.
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final count = labels.length;
    if (count == 0 || series.isEmpty || series.every((s) => s.values.every((v) => v == null))) {
      return _ChartEmpty(height: horizontal ? 120 : height);
    }
    final colors = _seriesColors(context, series);
    final read = format ?? formatNumber;
    if (horizontal) return _rows(context, colors.first, read);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    double value(int s, int i) => i < series[s].values.length ? chartNum(series[s].values[i]) : 0;
    // A stack only makes sense for amounts that add up, so it ignores negatives.
    double part(int s, int i) => math.max(0, value(s, i));
    final scale = _Scale.of([
      for (var i = 0; i < count; i++)
        if (stacked)
          [for (var s = 0; s < series.length; s++) part(s, i)].fold<double>(0, (sum, v) => sum + v)
        else
          for (var s = 0; s < series.length; s++) value(s, i),
    ]);
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;

    final chart = LayoutBuilder(builder: (context, box) {
      final plot = math.max(0.0, box.maxWidth - _axisWidth - _edge);
      final every = _labelEvery(context, labels, plot / count);
      final rods = stacked ? 1 : series.length;
      final width = ((plot / count) * 0.68 / rods - (rods > 1 ? 2 : 0)).clamp(3.0, 36.0).toDouble();
      final radius = square ? BorderRadius.zero : BorderRadius.vertical(top: Radius.circular(math.min(6, width / 2)));
      return BarChart(
        BarChartData(
          minY: scale.min,
          maxY: scale.max,
          alignment: BarChartAlignment.spaceAround,
          gridData: _grid(scheme, scale),
          borderData: FlBorderData(show: false),
          titlesData: _titles(theme, scale, labels, every),
          barTouchData: BarTouchData(
            touchCallback: (event, response) {
              final spot = response?.spot;
              if (onTap != null && event is FlTapUpEvent && spot != null) onTap!(spot.touchedBarGroupIndex);
            },
            mouseCursorResolver: (event, response) =>
                onTap != null && response?.spot != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => scheme.inverseSurface,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              maxContentWidth: 200,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final style = TextStyle(color: scheme.onInverseSurface, fontSize: 13, fontWeight: FontWeight.w600);
                final lines = <String>[
                  _at(labels, groupIndex),
                  if (stacked && series.length > 1)
                    for (var s = 0; s < series.length; s++) '${series[s].label}: ${read(part(s, groupIndex))}'
                  else
                    (series.length > 1 ? '${series[rodIndex].label}: ' : '') + read(rod.toY),
                ];
                return BarTooltipItem(lines.join('\n'), style);
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < count; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: stacked
                    ? [_stack(i, colors, part, width, radius)]
                    : [
                        for (var s = 0; s < series.length; s++)
                          BarChartRodData(toY: value(s, i), color: colors[s], width: width, borderRadius: radius),
                      ],
              ),
          ],
        ),
        duration: _duration(context),
      );
    });

    return _withLegend(
      context,
      chart: SizedBox(height: height, child: Padding(padding: _inset, child: chart)),
      show: legend ?? series.length > 1,
      items: [for (var s = 0; s < series.length; s++) _LegendItem(series[s].label, colors[s])],
    );
  }

  BarChartRodData _stack(int i, List<Color> colors, double Function(int s, int i) part, double width, BorderRadius radius) {
    final items = <BarChartRodStackItem>[];
    var top = 0.0;
    for (var s = 0; s < series.length; s++) {
      final next = top + part(s, i);
      if (next > top) items.add(BarChartRodStackItem(top, next, colors[s]));
      top = next;
    }
    return BarChartRodData(toY: top, color: Colors.transparent, width: width, borderRadius: radius, rodStackItems: items);
  }

  Widget _rows(BuildContext context, Color color, String Function(num value) read) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final values = [for (var i = 0; i < labels.length; i++) i < series.first.values.length ? chartNum(series.first.values[i]) : 0.0];
    final most = values.fold<double>(0, (a, b) => math.max(a, b.abs()));
    final radius = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat ? BorderRadius.zero : BorderRadius.circular(5);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < labels.length; i++)
        InkWell(
          onTap: onTap == null ? null : () => onTap!(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
                const SizedBox(width: 12),
                Text(read(values[i]), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: radius,
                child: LinearProgressIndicator(
                  value: most == 0 ? 0 : (values[i].abs() / most).clamp(0.0, 1.0).toDouble(),
                  minHeight: 10,
                  color: color,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// The shares of a whole, as a ring (or a full pie) beside its legend.
class AppPieChart extends StatefulWidget {
  const AppPieChart({
    super.key,
    required this.slices,
    this.height = 220,
    this.donut = true,
    this.maxSlices = 6,
    this.showTotal = true,
    this.totalLabel,
    this.format,
    this.onTap,
  });

  /// Largest first, as the API should send them.
  final List<ChartSlice> slices;
  final double height;

  /// A ring with the total in its middle; false is a full pie.
  final bool donut;

  /// Slices past this many are added up into one "Other" slice.
  final int maxSlices;

  /// The total in the ring's middle.
  final bool showTotal;

  /// The word under that total; "Total" in the app's language when left out.
  final String? totalLabel;

  /// How a value reads (formatMoney); formatNumber when left out.
  final String Function(num value)? format;

  /// A tap on a slice or its legend row, by its index in slices ("Other" has none).
  final void Function(int index)? onTap;

  @override
  State<AppPieChart> createState() => _AppPieChartState();
}

class _AppPieChartState extends State<AppPieChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = chartColors(context);
    final read = widget.format ?? formatNumber;

    // Only amounts above zero have a share.
    final shown = <_Share>[];
    var other = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      final value = chartNum(widget.slices[i].value);
      if (value <= 0) continue;
      if (shown.length < math.max(1, widget.maxSlices)) {
        shown.add(_Share(widget.slices[i].label, value, widget.slices[i].color ?? palette[shown.length % palette.length], i));
      } else {
        other += value;
      }
    }
    if (other > 0) shown.add(_Share(tr('Other'), other, scheme.outline, -1));
    if (shown.isEmpty) return _ChartEmpty(height: widget.height);
    final total = shown.fold<double>(0, (sum, s) => sum + s.value);

    Widget ring(double side) {
      final outer = side / 2 - 6;
      final hole = widget.donut ? outer * 0.62 : 0.0;
      return SizedBox(
        width: side,
        height: side,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(
            PieChartData(
              sectionsSpace: shown.length > 1 ? 2 : 0,
              centerSpaceRadius: hole,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  final index = response?.touchedSection?.touchedSectionIndex ?? -1;
                  if (event is FlTapUpEvent && index >= 0 && index < shown.length && shown[index].index >= 0) {
                    widget.onTap?.call(shown[index].index);
                  }
                  final next = event.isInterestedForInteractions ? index : -1;
                  if (next != _touched && mounted) setState(() => _touched = next);
                },
              ),
              sections: [
                for (var i = 0; i < shown.length; i++)
                  PieChartSectionData(
                    value: shown[i].value,
                    color: shown[i].color,
                    radius: outer - hole + (i == _touched ? 6 : 0),
                    showTitle: false,
                  ),
              ],
            ),
            duration: _duration(context),
          ),
          if (widget.donut && widget.showTotal)
            IgnorePointer(
              child: SizedBox(
                width: hole * 1.6,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(read(total), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    widget.totalLabel ?? tr('Total'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ),
        ]),
      );
    }

    final legend = Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < shown.length; i++)
        InkWell(
          onTap: widget.onTap == null || shown[i].index < 0 ? null : () => widget.onTap!(shown[i].index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              _Dot(shown[i].color),
              const SizedBox(width: 10),
              Expanded(child: Text(shown[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 12),
              Text(read(shown[i].value), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(
                width: 48,
                child: Text(
                  '${(shown[i].value / total * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ]),
          ),
        ),
    ]);

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 440) {
        return Row(children: [
          ring(math.min(widget.height, box.maxWidth * 0.42)),
          const SizedBox(width: 24),
          Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: legend))),
        ]);
      }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        ring(math.min(widget.height, box.maxWidth)),
        const SizedBox(height: 12),
        legend,
      ]);
    });
  }
}

/// A small line with no axes, for a stat card: how a number has moved.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 40, this.width, this.color, this.area = true});

  /// Oldest first, as the API sent them (num or String).
  final List<dynamic> values;
  final double height;

  /// Left out, as wide as its parent allows.
  final double? width;

  /// Left out, the brand colour.
  final Color? color;

  /// Fills under the line.
  final bool area;

  @override
  Widget build(BuildContext context) {
    final line = color ?? Theme.of(context).colorScheme.primary;
    final points = [for (final v in values) chartNum(v)];
    if (points.length < 2) return SizedBox(width: width, height: height);
    final low = points.reduce(math.min);
    final high = points.reduce(math.max);
    final pad = high == low ? 1.0 : (high - low) * 0.12;
    final sharp = appStyle == AppStyle.brutalism;
    return SizedBox(
      width: width,
      height: height,
      child: ExcludeSemantics(
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (points.length - 1).toDouble(),
            minY: low - pad,
            maxY: high + pad,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i])],
                color: line,
                barWidth: 2,
                isCurved: !sharp,
                preventCurveOverShooting: true,
                isStrokeCapRound: !sharp,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: area,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [line.withAlpha(64), line.withAlpha(0)],
                  ),
                ),
              ),
            ],
          ),
          duration: _duration(context),
        ),
      ),
    );
  }
}

// ── The period a dashboard shows ────────────────────────────────────────────

/// The periods a DateRangeControl offers.
enum DatePreset { today, last7Days, last30Days, last90Days, thisMonth, lastMonth, thisYear, custom }

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
DateTime _shiftDay(DateTime value, int days) => DateTime(value.year, value.month, value.day + days);
String _dayText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

/// A run of whole days, both ends included: a preset that moves with today
/// ("Last 30 days"), or days picked by hand.
class AppDateRange {
  const AppDateRange.preset(this.preset)
      : _from = null,
        _to = null;

  AppDateRange.custom(DateTime from, DateTime to)
      : preset = DatePreset.custom,
        _from = _day(from.isAfter(to) ? to : from),
        _to = _day(from.isAfter(to) ? from : to);

  final DatePreset preset;
  final DateTime? _from;
  final DateTime? _to;

  /// Its first day.
  DateTime get from {
    final today = _day(DateTime.now());
    switch (preset) {
      case DatePreset.today:
        return today;
      case DatePreset.last7Days:
        return _shiftDay(today, -6);
      case DatePreset.last30Days:
        return _shiftDay(today, -29);
      case DatePreset.last90Days:
        return _shiftDay(today, -89);
      case DatePreset.thisMonth:
        return DateTime(today.year, today.month);
      case DatePreset.lastMonth:
        return DateTime(today.year, today.month - 1);
      case DatePreset.thisYear:
        return DateTime(today.year);
      case DatePreset.custom:
        return _from ?? _shiftDay(today, -29);
    }
  }

  /// Its last day.
  DateTime get to {
    final today = _day(DateTime.now());
    switch (preset) {
      case DatePreset.lastMonth:
        return DateTime(today.year, today.month, 0);
      case DatePreset.custom:
        return _to ?? today;
      default:
        return today;
    }
  }

  /// How many days it has.
  int get days {
    final first = from;
    final last = to;
    return DateTime.utc(last.year, last.month, last.day).difference(DateTime.utc(first.year, first.month, first.day)).inDays + 1;
  }

  /// The period before it, of the same length: what "vs. last period" compares with.
  DateTime get previousFrom => _shiftDay(from, -days);
  DateTime get previousTo => _shiftDay(from, -1);

  /// The days it covers, as text.
  String get dates {
    final first = from;
    final last = to;
    if (first == last) return DateFormat.yMMMd().format(first);
    return '${first.year == last.year ? DateFormat.MMMd().format(first) : DateFormat.yMMMd().format(first)} – ${DateFormat.yMMMd().format(last)}';
  }

  /// What it is called: the preset's name, or its days.
  String get label {
    switch (preset) {
      case DatePreset.today:
        return tr('Today');
      case DatePreset.last7Days:
        return tr('Last 7 days');
      case DatePreset.last30Days:
        return tr('Last 30 days');
      case DatePreset.last90Days:
        return tr('Last 90 days');
      case DatePreset.thisMonth:
        return tr('This month');
      case DatePreset.lastMonth:
        return tr('Last month');
      case DatePreset.thisYear:
        return tr('This year');
      case DatePreset.custom:
        return dates;
    }
  }

  /// What the API is asked with (api/src/period.js reads it): the two days
  /// and this device's time zone.
  Map<String, dynamic> get query => {
        'from': _dayText(from),
        'to': _dayText(to),
        'tz': DateTime.now().timeZoneOffset.inMinutes,
      };

  @override
  bool operator ==(Object other) => other is AppDateRange && other.preset == preset && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);
}

/// The period the dashboards show. A page's provider watches it and sends
/// its query, so every number and chart follows the DateRangeControl.
final dateRangeProvider = StateProvider<AppDateRange>((ref) => const AppDateRange.preset(DatePreset.last30Days));

/// A chart's label for a point the API grouped by day ('2026-10-05') or by
/// month ('2026-10'), as period.js's bucket gives them.
String periodLabel(dynamic bucket) {
  final text = '${bucket ?? ''}';
  if (RegExp(r'^\d{4}-\d{2}$').hasMatch(text)) {
    final month = DateTime.tryParse('$text-01');
    return month == null ? text : DateFormat.yMMM().format(month);
  }
  final day = DateTime.tryParse(text);
  return day == null ? text : DateFormat.MMMd().format(day);
}

/// The button that picks dateRangeProvider's period: the presets, and
/// "Custom range" through the date picker.
class DateRangeControl extends ConsumerWidget {
  const DateRangeControl({super.key, this.presets, this.compact = false});

  /// The presets offered; all of them when left out. "Custom range" is always there.
  final List<DatePreset>? presets;

  /// Only the calendar icon, for a narrow place.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dateRangeProvider);
    final offered = [
      for (final preset in presets ?? DatePreset.values)
        if (preset != DatePreset.custom) preset,
    ];

    Future<void> pickDays() async {
      final today = _day(DateTime.now());
      final notifier = ref.read(dateRangeProvider.notifier);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(today.year - 10),
        lastDate: today,
        initialDateRange: DateTimeRange(start: range.from, end: range.to),
      );
      if (picked != null) notifier.state = AppDateRange.custom(picked.start, picked.end);
    }

    return MenuAnchor(
      menuChildren: [
        for (final preset in offered)
          MenuItemButton(
            leadingIcon: Icon(range.preset == preset ? AppIcons.check : null),
            onPressed: () => ref.read(dateRangeProvider.notifier).state = AppDateRange.preset(preset),
            child: Text(AppDateRange.preset(preset).label),
          ),
        MenuItemButton(
          leadingIcon: Icon(range.preset == DatePreset.custom ? AppIcons.check : null),
          onPressed: pickDays,
          child: Text(tr('Custom range')),
        ),
      ],
      builder: (context, controller, child) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (compact) {
          return IconButton(tooltip: '${range.label} (${range.dates})', icon: const Icon(AppIcons.calendar), onPressed: toggle);
        }
        return Tooltip(
          message: range.dates,
          child: OutlinedButton.icon(
            onPressed: toggle,
            icon: const Icon(AppIcons.calendar, size: 18),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(range.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              const Icon(AppIcons.expandMore, size: 18),
            ]),
          ),
        );
      },
    );
  }
}

// ── Stat cards ──────────────────────────────────────────────────────────────

/// How a number moved against the one before it: an arrow and the change in
/// percent, green when that is good and red when it is not. Nothing while
/// either number is missing.
class StatDelta extends StatelessWidget {
  const StatDelta({super.key, required this.value, required this.previous, this.lowerIsBetter = false});

  /// Now and before, as the API sent them (num or String).
  final dynamic value;
  final dynamic previous;

  /// For numbers that should go down (costs, open tickets, days to answer).
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    if (value == null || previous == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = chartNum(value);
    final before = chartNum(previous);
    final change = now - before;
    final String text;
    if (before == 0) {
      text = change == 0 ? '0%' : tr('New');
    } else {
      final percent = change / before.abs() * 100;
      final size = percent.abs();
      final sign = percent > 0 ? '+' : percent < 0 ? '-' : '';
      text = size >= 999.5
          ? '$sign>999%'
          : size >= 10 || size == size.roundToDouble()
              ? '$sign${size.round()}%'
              : '$sign${size.toStringAsFixed(1)}%';
    }
    final Color color;
    if (change == 0 || appStyle == AppStyle.monochrome) {
      color = scheme.onSurfaceVariant;
    } else if ((change > 0) != lowerIsBetter) {
      color = scheme.brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    } else {
      color = scheme.error;
    }
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(square ? 0 : 999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (change != 0) ...[
          Icon(change > 0 ? AppIcons.arrowUp : AppIcons.arrowDown, size: 14, color: color),
          const SizedBox(width: 2),
        ],
        Text(text, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// A dashboard's number: its label, the value, how it moved against the
/// period before, and a small line of its history.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.previous,
    this.compare,
    this.format,
    this.icon,
    this.trend,
    this.lowerIsBetter = false,
    this.color,
    this.onTap,
    this.loading = false,
  });

  final String label;

  /// The number, as the API sent it (num or String); a dash while null.
  final dynamic value;

  /// The same number for the period before; left out, the card shows no change.
  final dynamic previous;

  /// What the change is against; "vs. last period" in the app's language when left out.
  final String? compare;

  /// How the value reads (formatMoney); formatNumber when left out.
  final String Function(num value)? format;
  final IconData? icon;

  /// The number's history, oldest first, drawn as a Sparkline beside it.
  final List<dynamic>? trend;

  /// For numbers that should go down: a fall is then the green one.
  final bool lowerIsBetter;

  /// A fill in place of the style's surface colour.
  final Color? color;

  /// Makes the card a link (the list page it counts), with a chevron.
  final VoidCallback? onTap;

  /// Skeletons in place of the number, while it loads.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final read = format ?? formatNumber;
    final line = trend;
    return AppSurface(
      onTap: loading ? null : onTap,
      color: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 20, color: scheme.primary), const SizedBox(width: 8)],
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          ),
          if (onTap != null) Icon(AppIcons.chevronRight, size: 20, color: muted),
        ]),
        const SizedBox(height: 8),
        if (loading) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Skeleton(child: SkeletonBox(width: 96, height: 28)),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4),
            child: Skeleton(child: SkeletonBox(width: 132, height: 14)),
          ),
        ] else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value == null ? '—' : read(chartNum(value)),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (line != null && line.length > 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: Sparkline(values: line, width: 88, height: 36),
              ),
          ]),
          if (value != null && previous != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                StatDelta(value: value, previous: previous, lowerIsBetter: lowerIsBetter),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    compare ?? tr('vs. last period'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

// ── Gauge ───────────────────────────────────────────────────────────────────

/// A stretch of an AppGauge's scale with a colour of its own: the arc takes
/// the colour of the first band its value is within.
class GaugeBand {
  const GaugeBand({required this.upTo, required this.color});

  /// Where the band ends (it starts where the one before ended).
  final dynamic upTo;
  final Color color;
}

/// One number against a scale, as an arc: how far a target is met, how full
/// something is.
class AppGauge extends StatelessWidget {
  const AppGauge({
    super.key,
    required this.value,
    required this.max,
    this.min = 0,
    this.label,
    this.target,
    this.bands,
    this.height = 180,
    this.color,
    this.format,
  });

  /// The number and the scale's ends, as the API sent them (num or String).
  final dynamic value;
  final dynamic max;
  final dynamic min;

  /// The word under the number in the middle.
  final String? label;

  /// A mark on the scale: the goal, a limit.
  final dynamic target;

  /// Colours by where the value stands, lowest band first; left out, [color].
  final List<GaugeBand>? bands;
  final double height;

  /// The arc's colour; left out, the brand colour.
  final Color? color;

  /// How the numbers read (formatMoney); formatNumber when left out.
  final String Function(num value)? format;

  @override
  Widget build(BuildContext context) {
    final low = chartNum(min);
    final high = chartNum(max);
    if (value == null || high <= low) return _ChartEmpty(height: height);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final read = format ?? formatNumber;
    final now = chartNum(value);
    double place(double number) => ((number - low) / (high - low)).clamp(0.0, 1.0).toDouble();

    var arc = color ?? scheme.primary;
    final steps = bands;
    if (steps != null && steps.isNotEmpty) {
      arc = steps.last.color;
      for (final band in steps) {
        if (now <= chartNum(band.upTo)) {
          arc = band.color;
          break;
        }
      }
    }
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;

    return Semantics(
      label: '${label == null ? '' : '$label: '}${read(now)}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: LayoutBuilder(builder: (context, box) {
            // The arc spans 240 degrees, so it is one and a half radii tall.
            const ends = 22.0;
            final stroke = (height * 0.1).clamp(10.0, 20.0).toDouble();
            final radius = math.max(8.0, math.min((height - ends - stroke) / 1.5, (box.maxWidth - stroke) / 2));
            final width = radius * 2 + stroke;
            final arcHeight = radius * 1.5 + stroke;
            return Center(
              child: SizedBox(
                width: width,
                height: arcHeight + ends,
                child: Stack(children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: arcHeight,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: place(now)),
                      duration: _duration(context) * 2,
                      curve: Curves.easeOutCubic,
                      builder: (context, shown, child) => CustomPaint(
                        painter: _GaugePainter(
                          fraction: shown,
                          color: arc,
                          track: scheme.surfaceContainerHighest,
                          stroke: stroke,
                          round: !square,
                          mark: target == null ? null : place(chartNum(target)),
                          markColor: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: stroke / 2 + radius - 22,
                    left: stroke + 8,
                    right: stroke + 8,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(read(now), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      if (label != null && label!.isNotEmpty)
                        Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: muted),
                    ]),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    // The scale runs left to right whatever the language.
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(children: [
                        Expanded(child: Text(read(low), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted)),
                        Expanded(
                          child: Text(read(high), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: muted),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
    required this.round,
    required this.mark,
    required this.markColor,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double stroke;
  final bool round;
  final double? mark;
  final Color markColor;

  // From the lower left, over the top, to the lower right.
  static const double _start = math.pi * 5 / 6;
  static const double _sweep = math.pi * 4 / 3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width - stroke) / 2;
    final centre = Offset(size.width / 2, stroke / 2 + radius);
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = round ? StrokeCap.round : StrokeCap.butt;
    canvas.drawArc(rect, _start, _sweep, false, paint..color = track);
    if (fraction > 0) canvas.drawArc(rect, _start, _sweep * fraction, false, paint..color = color);
    final at = mark;
    if (at != null) {
      final angle = _start + _sweep * at;
      final way = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        centre + way * (radius - stroke / 2),
        centre + way * (radius + stroke / 2),
        Paint()
          ..color = markColor
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke ||
      old.round != round ||
      old.mark != mark ||
      old.markColor != markColor;
}

// ── Heatmap ─────────────────────────────────────────────────────────────────

/// A grid of cells shaded by their value: how much, by two things at once
/// (orders by weekday and hour, sales by product and month).
class AppHeatmap extends StatelessWidget {
  const AppHeatmap({
    super.key,
    required this.columns,
    required this.rows,
    required this.values,
    this.cellHeight = 28,
    this.showValues = false,
    this.legend = true,
    this.color,
    this.format,
    this.onTap,
  });

  /// What each column is called, along the bottom (hours, months).
  final List<String> columns;

  /// What each row is called, down the side (weekdays, products).
  final List<String> rows;

  /// A list per row holding a value per column, as the API sent them (num or
  /// String). A null or a missing value is an empty cell.
  final List<List<dynamic>> values;
  final double cellHeight;

  /// Writes each value in its cell; for a small grid.
  final bool showValues;

  /// The "Less … More" scale under the grid.
  final bool legend;

  /// The colour of the highest value; left out, the brand colour.
  final Color? color;

  /// How a value reads in the tooltip (formatMoney); formatNumber when left out.
  final String Function(num value)? format;

  /// A tap on a cell.
  final void Function(int row, int column)? onTap;

  @override
  Widget build(BuildContext context) {
    dynamic at(int row, int column) => row < values.length && column < values[row].length ? values[row][column] : null;
    final all = [
      for (var r = 0; r < rows.length; r++)
        for (var c = 0; c < columns.length; c++)
          if (at(r, c) != null) chartNum(at(r, c)),
    ];
    if (all.isEmpty) return const _ChartEmpty(height: 160);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final read = format ?? formatNumber;
    final compact = NumberFormat.compact();
    final high = all.reduce(math.max);
    final low = math.min(0.0, all.reduce(math.min));
    final base = color ?? chartColors(context).first.withAlpha(255);
    final blank = scheme.surfaceContainerHighest;
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;
    final radius = BorderRadius.circular(square ? 0 : 4);

    Color shade(double share) => Color.lerp(base.withAlpha(40), base, share)!;
    Color fill(dynamic value) {
      if (value == null) return blank;
      final number = chartNum(value);
      if (number == 0 && low == 0) return blank;
      return shade(high == low ? 1 : ((number - low) / (high - low)).clamp(0.0, 1.0).toDouble());
    }

    Widget cell(int r, int c, double width) {
      final value = at(r, c);
      final colour = fill(value);
      Widget box = Container(
        width: width,
        height: cellHeight,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: colour, borderRadius: radius),
        child: showValues && value != null
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  format == null ? compact.format(chartNum(value)) : read(chartNum(value)),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Color.alphaBlend(colour, scheme.surface).computeLuminance() > 0.45 ? Colors.black87 : Colors.white,
                  ),
                ),
              )
            : null,
      );
      if (onTap != null) {
        box = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(onTap: () => onTap!(r, c), child: box),
        );
      }
      return Tooltip(
        message: '${rows[r]} · ${columns[c]}: ${value == null ? '—' : read(chartNum(value))}',
        waitDuration: const Duration(milliseconds: 150),
        child: box,
      );
    }

    return LayoutBuilder(builder: (context, box) {
      const gap = 3.0;
      final count = columns.length;
      final side = math.min(_widest(context, rows, style), 112.0) + 10;
      final least = showValues ? 40.0 : 14.0;
      final cellWidth = math.max(least, (box.maxWidth - side - gap * (count - 1)) / count);
      final scrolls = side + cellWidth * count + gap * (count - 1) > box.maxWidth + 0.5;
      // Every how many column labels fit without touching.
      final every = math.max(1, ((_widest(context, columns, style) + 6) / (cellWidth + gap)).ceil());

      final grid = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var r = 0; r < rows.length; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: side,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: Text(rows[r], maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                ),
              ),
              for (var c = 0; c < count; c++)
                Padding(
                  padding: EdgeInsetsDirectional.only(end: c == count - 1 ? 0 : gap),
                  child: cell(r, c, cellWidth),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: side),
            for (var c = 0; c < count; c++)
              SizedBox(
                width: cellWidth + (c == count - 1 ? 0 : gap),
                child: c % every == 0
                    ? Text(
                        columns[c],
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        textAlign: every == 1 ? TextAlign.center : TextAlign.start,
                        style: style,
                      )
                    : null,
              ),
          ]),
        ),
      ]);

      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        scrolls ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid) : grid,
        if (legend)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(tr('Less'), style: style),
              const SizedBox(width: 8),
              for (final share in const [0.0, 0.33, 0.66, 1.0])
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsetsDirectional.only(end: 3),
                  decoration: BoxDecoration(color: shade(share), borderRadius: radius),
                ),
              const SizedBox(width: 5),
              Text(tr('More'), style: style),
            ]),
          ),
      ]);
    });
  }
}

/// The width of the widest of [labels] in [style].
double _widest(BuildContext context, List<String> labels, TextStyle? style) {
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest;
}

// ── Shared parts ────────────────────────────────────────────────────────────

/// The room the value axis takes on the left.
const double _axisWidth = 46;

class _Share {
  const _Share(this.label, this.value, this.color, this.index);
  final String label;
  final double value;
  final Color color;

  /// Its place in AppPieChart.slices; -1 for "Other".
  final int index;
}

class _LegendItem {
  const _LegendItem(this.label, this.color);
  final String label;
  final Color color;
}

/// The value axis: round steps that cover the values.
class _Scale {
  const _Scale(this.min, this.max, this.step);
  final double min;
  final double max;
  final double step;

  static _Scale of(List<double> values, {bool fromZero = true}) {
    var low = values.isEmpty ? 0.0 : values.reduce(math.min);
    var high = values.isEmpty ? 0.0 : values.reduce(math.max);
    if (fromZero) {
      low = math.min(low, 0);
      high = math.max(high, 0);
    }
    if (high == low) {
      final pad = high == 0 ? 1.0 : high.abs() * 0.1;
      high += pad;
      if (!fromZero) low -= pad;
    }
    final rough = (high - low) / 4;
    final size = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final unit = rough / size;
    final step = (unit <= 1 ? 1 : unit <= 2 ? 2 : unit <= 2.5 ? 2.5 : unit <= 5 ? 5 : 10) * size;
    return _Scale((low / step).floor() * step, (high / step).ceil() * step, step);
  }
}

String _at(List<String> labels, int index) => index >= 0 && index < labels.length ? labels[index] : '';

/// The widest a label along the bottom may be.
const double _labelWidth = 72;

/// Room for the top value's text and the last point's dot, inside the height.
const double _edge = 8;
const EdgeInsets _inset = EdgeInsets.only(top: 10, right: _edge);

/// Every how many labels fit along the bottom without touching, when each
/// has [slot] of width. The first and last are pushed inwards by up to half
/// their width, hence the half more.
int _labelEvery(BuildContext context, List<String> labels, double slot) {
  final style = Theme.of(context).textTheme.bodySmall;
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
    if (widest >= _labelWidth) break;
  }
  final need = math.min(widest, _labelWidth) * 1.5 + 8;
  return slot <= 0 ? labels.length : math.max(1, (need / slot).ceil());
}

Duration _duration(BuildContext context) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 250);

List<Color> _seriesColors(BuildContext context, List<ChartSeries> series) {
  final palette = chartColors(context);
  return [for (var s = 0; s < series.length; s++) series[s].color ?? palette[s % palette.length]];
}

FlGridData _grid(ColorScheme scheme, _Scale scale) => FlGridData(
      drawVerticalLine: false,
      horizontalInterval: scale.step,
      getDrawingHorizontalLine: (value) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
    );

FlTitlesData _titles(ThemeData theme, _Scale scale, List<String> labels, int every) {
  final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
  final compact = NumberFormat.compact();
  const none = AxisTitles(sideTitles: SideTitles(showTitles: false));
  return FlTitlesData(
    topTitles: none,
    rightTitles: none,
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: _axisWidth,
        interval: scale.step,
        getTitlesWidget: (value, meta) =>
            SideTitleWidget(meta: meta, child: Text(compact.format(value), maxLines: 1, style: style)),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 30,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if ((value - index).abs() > 0.01 || index < 0 || index >= labels.length || index % every != 0) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _labelWidth),
              child: Text(labels[index], maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          );
        },
      ),
    ),
  );
}

Widget _withLegend(BuildContext context, {required Widget chart, required bool show, required List<_LegendItem> items}) {
  if (!show) return chart;
  final theme = Theme.of(context);
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    chart,
    const SizedBox(height: 12),
    Wrap(spacing: 16, runSpacing: 8, alignment: WrapAlignment.center, children: [
      for (final item in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          _Dot(item.color),
          const SizedBox(width: 8),
          Text(item.label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
    ]),
  ]);
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: square ? BoxShape.rectangle : BoxShape.circle),
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Center(
        child: Text(tr('No data yet.'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }
}
