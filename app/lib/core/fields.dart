// Form fields. Owned by AppWand.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'api_client.dart';
import 'format.dart' show formatDate, formatDateTime;
import 'i18n.dart';
import 'icons.dart';

String _requiredText() => tr('This field is required.');

/// What the API sent for a date (a String, a DateTime or null) as a local
/// DateTime, null when there is none.
DateTime? toDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse('$value')?.toLocal();
}

/// A date as a DATE column takes it, "2026-03-02"; null for none.
String? apiDate(DateTime? date) {
  if (date == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
}

/// Two dates from the API as a range, null unless both are there in order.
DateTimeRange? toDateRange(dynamic start, dynamic end) {
  final from = toDate(start);
  final to = toDate(end);
  return from == null || to == null || to.isBefore(from) ? null : DateTimeRange(start: from, end: to);
}

/// A search-and-pick panel: a dialog on wide screens, a sheet from the bottom
/// on a phone.
Future<T?> _showFieldPanel<T>(BuildContext context, {required WidgetBuilder builder}) {
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: builder(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.75, child: builder(context)),
    ),
  );
}

/// The inside of a panel: its title, a search box, the list and a footer.
class _FieldPanel extends StatelessWidget {
  const _FieldPanel({required this.title, required this.child, this.onSearch, this.onSubmitted, this.footer});

  final String title;
  final Widget child;
  final ValueChanged<String>? onSearch;
  final ValueChanged<String>? onSubmitted;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 0),
        child: Row(children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
          ),
          IconButton(
            tooltip: tr('Close'),
            icon: const Icon(AppIcons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]),
      ),
      if (onSearch != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            // A phone's keyboard would cover half the list before anything is read.
            autofocus: MediaQuery.sizeOf(context).width >= 600,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(hintText: tr('Search'), prefixIcon: const Icon(AppIcons.search)),
            onChanged: onSearch,
            onSubmitted: onSubmitted,
          ),
        ),
      Expanded(child: child),
      if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: footer),
    ]);
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(action!)),
          ],
        ]),
      ),
    );
  }
}

/// A field that is tapped to pick its value: drawn as the theme draws a text
/// field, so every style of the app shows it like the fields around it.
class _PickerShell extends StatefulWidget {
  const _PickerShell({
    required this.text,
    required this.icon,
    required this.onTap,
    this.label,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.onClear,
  });

  /// The value as text; empty shows the label in the field.
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final String? helperText;
  final String? errorText;
  final bool enabled;

  /// Adds a clear button while there is a value.
  final VoidCallback? onClear;

  @override
  State<_PickerShell> createState() => _PickerShellState();
}

class _PickerShellState extends State<_PickerShell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = widget.text.isEmpty;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      child: InkWell(
        onTap: widget.enabled ? widget.onTap : null,
        onFocusChange: (value) => setState(() => _focused = value),
        // The field's own border shows the focus; an ink over a shape only the theme knows would not fit it.
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: InputDecorator(
          isEmpty: empty,
          isFocused: _focused,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helperText,
            errorText: widget.errorText,
            enabled: widget.enabled,
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.onClear != null && !empty && widget.enabled)
                IconButton(
                  tooltip: tr('Clear'),
                  icon: const Icon(AppIcons.close, size: 18),
                  onPressed: widget.onClear,
                ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Icon(widget.icon, size: 20),
              ),
            ]),
          ),
          child: Text(widget.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge),
        ),
      ),
    );
  }
}

// ── A foreign key ───────────────────────────────────────────────────────────

/// What a row of the API is called when the page gives no display: its name,
/// title or the like.
String _rowLabel(Map<String, dynamic> row, String Function(Map<String, dynamic> row)? display) {
  if (display != null) return display(row);
  for (final key in const ['name', 'title', 'label', 'full_name', 'code', 'email']) {
    final value = row[key];
    if (value != null && '$value'.isNotEmpty) return '$value';
  }
  final names = [row['first_name'], row['last_name']].where((v) => v != null && '$v'.isNotEmpty).join(' ');
  if (names.isNotEmpty) return names;
  for (final value in row.values) {
    if (value is String && value.isNotEmpty) return value;
  }
  return '#${row['id'] ?? ''}';
}

/// A foreign key as a searchable picker. It opens a panel that searches
/// [path], a list route of the API (GET answering { items, total }, taking
/// ?search, ?page and ?limit), as the person types, loads more rows as the
/// list is scrolled, and hands back the chosen row's id.
class RelationField extends ConsumerStatefulWidget {
  const RelationField({
    super.key,
    required this.path,
    required this.value,
    required this.onChanged,
    this.label,
    this.selected,
    this.display,
    this.subtitle,
    this.query = const {},
    this.valueKey = 'id',
    this.required = false,
    this.clearable,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
  });

  /// The list route to search, relative to /api: '/customers'.
  final String path;

  /// The chosen row's id (the foreign key column's value), null for none.
  final Object? value;

  /// The id and the row picked; both null when the field is cleared.
  final void Function(Object? id, Map<String, dynamic>? row) onChanged;
  final String? label;

  /// The row [value] points at, when the page already has it (the record's
  /// included parent, record['customer']), so its name shows at once. Without
  /// it the field asks the route for that one row, at [path] plus the id.
  final Map<String, dynamic>? selected;

  /// What a row is called; its name, title or the like when left out.
  final String Function(Map<String, dynamic> row)? display;

  /// A second line for a row in the list.
  final String? Function(Map<String, dynamic> row)? subtitle;

  /// Sent with every search, to narrow the rows offered: {'status': 'active'}.
  final Map<String, dynamic> query;

  /// The row's key the value is taken from.
  final String valueKey;
  final bool required;

  /// Whether the value can be removed; when left out, unless [required].
  final bool? clearable;
  final String? Function(Object? value)? validator;
  final String? helperText;

  /// The API's error for this field.
  final String? errorText;
  final bool enabled;

  @override
  ConsumerState<RelationField> createState() => _RelationFieldState();
}

class _RelationFieldState extends ConsumerState<RelationField> {
  /// The row of the value, once known.
  Map<String, dynamic>? _row;
  bool _looking = false;

  bool _isValue(Map<String, dynamic>? row) =>
      row != null && widget.value != null && '${row[widget.valueKey]}' == '${widget.value}';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(RelationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ('${widget.value}' != '${oldWidget.value}' || !identical(widget.selected, oldWidget.selected)) _resolve();
  }

  void _resolve() {
    if (widget.value == null) {
      _row = null;
    } else if (_isValue(widget.selected)) {
      _row = widget.selected;
    } else if (!_isValue(_row)) {
      _row = null;
      _lookUp(widget.value!);
    }
  }

  /// Asks the list route for the one row, as a page's single-row route answers it.
  Future<void> _lookUp(Object value) async {
    _looking = true;
    Map<String, dynamic>? row;
    try {
      final data = await ref.read(apiClientProvider).get('${widget.path}/$value');
      if (data is Map) row = Map<String, dynamic>.from(data);
    } catch (e) {
      // The route answers no single row, or the row is gone: the value shows as its number.
      row = null;
    }
    if (!mounted || '${widget.value}' != '$value') return;
    setState(() {
      _looking = false;
      if (_isValue(row)) _row = row;
    });
  }

  String get _text {
    if (widget.value == null) return '';
    final row = _row;
    if (row != null) return _rowLabel(row, widget.display);
    return _looking ? '…' : '#${widget.value}';
  }

  Future<void> _open(FormFieldState<Object> field) async {
    final picked = await _showFieldPanel<Map<String, dynamic>>(
      context,
      builder: (context) => _RelationPanel(field: widget),
    );
    if (picked == null || !mounted) return;
    setState(() => _row = picked);
    final id = picked[widget.valueKey];
    field.didChange(id);
    widget.onChanged(id, picked);
  }

  void _clear(FormFieldState<Object> field) {
    setState(() => _row = null);
    field.didChange(null);
    widget.onChanged(null, null);
  }

  @override
  Widget build(BuildContext context) {
    final clearable = widget.clearable ?? !widget.required;
    return FormField<Object>(
      initialValue: widget.value,
      enabled: widget.enabled,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) {
        if (widget.value == null) return widget.required ? _requiredText() : null;
        return widget.validator?.call(widget.value);
      },
      builder: (field) => _PickerShell(
        label: widget.label,
        text: _text,
        icon: AppIcons.expandMore,
        helperText: widget.helperText,
        errorText: widget.errorText ?? field.errorText,
        enabled: widget.enabled,
        onTap: () => _open(field),
        onClear: clearable ? () => _clear(field) : null,
      ),
    );
  }
}

class _RelationPanel extends ConsumerStatefulWidget {
  const _RelationPanel({required this.field});

  final RelationField field;

  @override
  ConsumerState<_RelationPanel> createState() => _RelationPanelState();
}

class _RelationPanelState extends ConsumerState<_RelationPanel> {
  static const _limit = 20;

  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  Timer? _timer;
  String _search = '';
  int _page = 0;
  int _total = 0;

  /// Goes up with every new search, so an answer that arrives late is dropped.
  int _run = 0;
  bool _loading = false;
  Object? _error;

  bool get _more => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Starts the list again from its first page.
  void _restart() {
    _run++;
    _items.clear();
    _page = 0;
    _total = 0;
    _next();
  }

  /// Loads the page after the last one loaded.
  void _next() {
    _loading = true;
    _error = null;
    _fetch(_run, _page + 1);
  }

  Future<void> _fetch(int run, int page) async {
    try {
      final data = await ref.read(apiClientProvider).get(widget.field.path, query: {
        ...widget.field.query,
        'page': page,
        'limit': _limit,
        if (_search.isNotEmpty) 'search': _search,
      });
      if (!mounted || run != _run) return;
      final list = data is Map ? data['items'] : data;
      final rows = [
        for (final row in list is List ? list : const <dynamic>[])
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      final total = data is Map ? num.tryParse('${data['total']}')?.toInt() : null;
      setState(() {
        _items.addAll(rows);
        _page = page;
        // A route that gives no total has more while its pages come back full.
        _total = total ?? _items.length + (rows.length >= _limit ? 1 : 0);
        if (rows.isEmpty) _total = _items.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _nearEnd() {
    if (_loading || _error != null || !_more || _scroll.position.extentAfter > 200) return;
    setState(_next);
  }

  void _onSearch(String text) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || text.trim() == _search) return;
      setState(() {
        _search = text.trim();
        _restart();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final Widget body;
    if (_items.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty && _error != null) {
      body = _PanelMessage(text: errorMessage(_error!), action: tr('Retry'), onAction: () => setState(_restart));
    } else if (_items.isEmpty) {
      body = _PanelMessage(text: tr('Nothing found.'));
    } else {
      final tail = _more || _loading || _error != null;
      body = ListView.builder(
        controller: _scroll,
        itemCount: _items.length + (tail ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return _error != null
                ? ListTile(
                    title: Text(errorMessage(_error!)),
                    trailing: TextButton(onPressed: () => setState(_next), child: Text(tr('Retry'))),
                  )
                : const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
          }
          final row = _items[index];
          final chosen = field.value != null && '${row[field.valueKey]}' == '${field.value}';
          final subtitle = field.subtitle?.call(row) ?? '';
          return ListTile(
            title: Text(_rowLabel(row, field.display)),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            selected: chosen,
            trailing: chosen ? const Icon(AppIcons.check) : null,
            onTap: () => Navigator.of(context).pop(row),
          );
        },
      );
    }
    return _FieldPanel(
      title: field.label ?? tr('Select'),
      onSearch: _onSearch,
      // Enter takes the first row found.
      onSubmitted: (text) {
        if (_items.isNotEmpty && !_loading) Navigator.of(context).pop(_items.first);
      },
      child: body,
    );
  }
}

// ── Several values of a fixed set ───────────────────────────────────────────

/// Several values picked from a fixed set, as chips. A short set shows every
/// option as a chip to tick; a longer one shows the picked values with an Add
/// chip that opens a searchable checklist.
class MultiSelectField<T> extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.label,
    this.min,
    this.max,
    this.inlineLimit = 8,
    this.required = false,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
  });

  /// Value → what it is called, in the order offered.
  final Map<T, String> options;

  /// The picked values.
  final List<T> values;

  /// The picked values, in the options' order.
  final ValueChanged<List<T>> onChanged;
  final String? label;

  /// How few and how many may be picked.
  final int? min;
  final int? max;

  /// Up to this many options, each is a chip in the field itself.
  final int inlineLimit;
  final bool required;
  final String? Function(List<T> values)? validator;
  final String? helperText;

  /// The API's error for this field.
  final String? errorText;
  final bool enabled;

  /// The picked values in the options' order, then the ones no longer offered.
  List<T> _ordered(Set<T> picked) => [
        for (final key in options.keys)
          if (picked.contains(key)) key,
        for (final value in picked)
          if (!options.containsKey(value)) value,
      ];

  String? _validate() {
    if (required && values.isEmpty) return _requiredText();
    if (min != null && values.length < min!) return tr('Choose at least {count}.', {'count': min});
    if (max != null && values.length > max!) return tr('Choose at most {count}.', {'count': max});
    return validator?.call(values);
  }

  @override
  Widget build(BuildContext context) {
    final picked = values.toSet();
    final full = max != null && picked.length >= max!;
    return FormField<List<T>>(
      initialValue: values,
      enabled: enabled,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => _validate(),
      builder: (field) {
        void change(Set<T> next) {
          final list = _ordered(next);
          field.didChange(list);
          onChanged(list);
        }

        Future<void> add() async {
          final next = await _showFieldPanel<Set<T>>(
            context,
            builder: (context) => _ChecklistPanel<T>(
              title: label ?? tr('Select'),
              options: options,
              picked: picked,
              max: max,
            ),
          );
          if (next != null && field.mounted) change(next);
        }

        return InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
            errorText: errorText ?? field.errorText,
            enabled: enabled,
          ),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (options.length <= inlineLimit)
              for (final option in options.entries)
                FilterChip(
                  label: Text(option.value),
                  selected: picked.contains(option.key),
                  onSelected: !enabled || (full && !picked.contains(option.key))
                      ? null
                      : (on) => change(on ? {...picked, option.key} : ({...picked}..remove(option.key))),
                )
            else ...[
              for (final value in _ordered(picked))
                InputChip(
                  label: Text(options[value] ?? '$value'),
                  onDeleted: enabled ? () => change({...picked}..remove(value)) : null,
                ),
              if (enabled && !full)
                ActionChip(
                  avatar: const Icon(AppIcons.add, size: 18),
                  label: Text(picked.isEmpty ? tr('Select') : tr('Add')),
                  onPressed: add,
                ),
            ],
          ]),
        );
      },
    );
  }
}

class _ChecklistPanel<T> extends StatefulWidget {
  const _ChecklistPanel({required this.title, required this.options, required this.picked, this.max});

  final String title;
  final Map<T, String> options;
  final Set<T> picked;
  final int? max;

  @override
  State<_ChecklistPanel<T>> createState() => _ChecklistPanelState<T>();
}

class _ChecklistPanelState<T> extends State<_ChecklistPanel<T>> {
  late final Set<T> _picked = {...widget.picked};
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = _search.toLowerCase();
    final shown = [
      for (final option in widget.options.entries)
        if (words.isEmpty || option.value.toLowerCase().contains(words)) option,
    ];
    final full = widget.max != null && _picked.length >= widget.max!;
    return _FieldPanel(
      title: widget.title,
      onSearch: (text) => setState(() => _search = text.trim()),
      footer: Row(children: [
        Expanded(
          child: Text(
            tr('{count} selected', {'count': _picked.length}),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(_picked), child: Text(tr('Done'))),
      ]),
      child: shown.isEmpty
          ? _PanelMessage(text: tr('Nothing found.'))
          : ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final option = shown[index];
                final on = _picked.contains(option.key);
                return CheckboxListTile(
                  value: on,
                  title: Text(option.value),
                  onChanged: full && !on
                      ? null
                      : (value) => setState(() => value == true ? _picked.add(option.key) : _picked.remove(option.key)),
                );
              },
            ),
    );
  }
}

// ── Dates ───────────────────────────────────────────────────────────────────

/// A date, picked from a calendar; with [withTime], a date and a time.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.firstDate,
    this.lastDate,
    this.withTime = false,
    this.required = false,
    this.clearable,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? label;

  /// The days that can be picked; 1900 to 2100 when left out.
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// Also asks for the time of day.
  final bool withTime;
  final bool required;

  /// Whether the value can be removed; when left out, unless [required].
  final bool? clearable;
  final String? Function(DateTime? value)? validator;
  final String? helperText;

  /// The API's error for this field.
  final String? errorText;
  final bool enabled;

  Future<void> _pick(BuildContext context, FormFieldState<DateTime> field) async {
    final first = firstDate ?? DateTime(1900);
    final last = lastDate ?? DateTime(2100, 12, 31);
    final now = value?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.isBefore(first) ? first : (now.isAfter(last) ? last : now),
      firstDate: first,
      lastDate: last,
    );
    if (date == null) return;
    var picked = date;
    if (withTime) {
      if (!context.mounted) return;
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
      if (time == null) return;
      picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }
    if (!field.mounted) return;
    field.didChange(picked);
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final date = value;
    return FormField<DateTime>(
      initialValue: value,
      enabled: enabled,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (ignored) {
        if (value == null) return required ? _requiredText() : null;
        return validator?.call(value);
      },
      builder: (field) => _PickerShell(
        label: label,
        text: date == null ? '' : (withTime ? formatDateTime(date) : formatDate(date)),
        icon: AppIcons.calendar,
        helperText: helperText,
        errorText: errorText ?? field.errorText,
        enabled: enabled,
        onTap: () => _pick(context, field),
        onClear: clearable ?? !required
            ? () {
                field.didChange(null);
                onChanged(null);
              }
            : null,
      ),
    );
  }
}

/// A first and a last day, picked together from one calendar.
class DateRangeField extends StatelessWidget {
  const DateRangeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.firstDate,
    this.lastDate,
    this.required = false,
    this.clearable,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
  });

  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  final String? label;

  /// The days that can be picked; 1900 to 2100 when left out.
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool required;

  /// Whether the value can be removed; when left out, unless [required].
  final bool? clearable;
  final String? Function(DateTimeRange? value)? validator;
  final String? helperText;

  /// The API's error for this field.
  final String? errorText;
  final bool enabled;

  Future<void> _pick(BuildContext context, FormFieldState<DateTimeRange> field) async {
    final first = firstDate ?? DateTime(1900);
    final last = lastDate ?? DateTime(2100, 12, 31);
    final current = value;
    final inRange = current != null && !current.start.isBefore(first) && !current.end.isAfter(last);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: inRange ? current : null,
      // Full screen suits a phone; a wide window gets the calendar as a panel in its middle.
      builder: (context, child) => child == null || MediaQuery.sizeOf(context).width < 600
          ? (child ?? const SizedBox.shrink())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
                child: child,
              ),
            ),
    );
    if (picked == null || !field.mounted) return;
    field.didChange(picked);
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final range = value;
    return FormField<DateTimeRange>(
      initialValue: value,
      enabled: enabled,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (ignored) {
        if (value == null) return required ? _requiredText() : null;
        return validator?.call(value);
      },
      builder: (field) => _PickerShell(
        label: label,
        text: range == null ? '' : '${formatDate(range.start)} – ${formatDate(range.end)}',
        icon: AppIcons.calendar,
        helperText: helperText,
        errorText: errorText ?? field.errorText,
        enabled: enabled,
        onTap: () => _pick(context, field),
        onClear: clearable ?? !required
            ? () {
                field.didChange(null);
                onChanged(null);
              }
            : null,
      ),
    );
  }
}

// ── Money ───────────────────────────────────────────────────────────────────

/// An amount of money: digits with the decimal mark of the person's language,
/// shown with its thousands grouped once the field is left, handed back as a
/// number.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    this.value,
    required this.onChanged,
    this.label,
    this.symbol = r'$',
    this.decimals = 2,
    this.min = 0,
    this.max,
    this.required = false,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.textInputAction,
  });

  /// The amount as the API sent it: a num, a String ("120.50") or null.
  final dynamic value;

  /// The amount as a number, null when the field is empty or cannot be read.
  final ValueChanged<num?> onChanged;
  final String? label;

  /// Shown before the amount; '' for none.
  final String symbol;

  /// How many decimal places the amount keeps.
  final int decimals;

  /// The least and the most allowed; null for no limit (min: null takes a negative amount).
  final num? min;
  final num? max;
  final bool required;
  final String? Function(num? value)? validator;
  final String? helperText;

  /// The API's error for this field.
  final String? errorText;
  final bool enabled;
  final TextInputAction? textInputAction;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  num? _value;

  /// Something is typed that is not an amount.
  bool _invalid = false;

  static num? _numOf(dynamic value) => value == null ? null : (value is num ? value : num.tryParse('$value'));

  @override
  void initState() {
    super.initState();
    _value = _numOf(widget.value);
    _controller.text = _grouped(_value);
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(MoneyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _numOf(widget.value);
    // What is being typed is left alone; a value set from outside (a loaded record) shows.
    if (next == _value || _focus.hasFocus) return;
    _value = next;
    _invalid = false;
    _controller.text = _grouped(next);
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// The decimal mark people type: the language's when it is a dot or a comma.
  String get _mark {
    final mark = NumberFormat.decimalPattern().symbols.DECIMAL_SEP;
    return mark == ',' ? ',' : '.';
  }

  /// As shown while the field is left: "1,234.50".
  String _grouped(num? value) =>
      value == null ? '' : NumberFormat.decimalPatternDigits(decimalDigits: widget.decimals).format(value);

  /// As typed: "1234.5".
  String _plain(num? value) {
    if (value == null) return '';
    var text = value.toStringAsFixed(widget.decimals);
    if (text.contains('.')) text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return text.replaceAll('.', _mark);
  }

  num? _rounded(num? value) => value == null ? null : num.parse(value.toStringAsFixed(widget.decimals));

  /// What was typed as a number. A dot and a comma together: the later one is
  /// the decimal mark. One of them alone is the decimal mark, unless it is the
  /// other mark of the language and sets off groups of three digits.
  num? _parse(String typed) {
    var text = typed.replaceAll(RegExp(r'\s'), '');
    if (text.isEmpty) return null;
    final dot = text.lastIndexOf('.');
    final comma = text.lastIndexOf(',');
    if (dot >= 0 && comma >= 0) {
      text = dot > comma ? text.replaceAll(',', '') : text.replaceAll('.', '').replaceAll(',', '.');
    } else if (dot >= 0 || comma >= 0) {
      final mark = dot >= 0 ? '.' : ',';
      final parts = text.split(mark);
      final whole = parts.first.replaceAll('-', '');
      final groups = mark != _mark &&
          whole.isNotEmpty &&
          whole.length <= 3 &&
          parts.skip(1).every((group) => group.length == 3);
      text = groups ? text.replaceAll(mark, '') : text.replaceAll(mark, '.');
    }
    return num.tryParse(text);
  }

  void _focusChanged() {
    if (_invalid) return;
    if (_focus.hasFocus) {
      final text = _plain(_value);
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      return;
    }
    final rounded = _rounded(_value);
    if (rounded != _value) {
      _value = rounded;
      widget.onChanged(rounded);
    }
    _controller.text = _grouped(_value);
  }

  String? _validate() {
    if (_invalid) return tr('Enter a valid amount.');
    final value = _value;
    if (value == null) return widget.required ? _requiredText() : null;
    if (widget.min != null && value < widget.min!) return tr('Must be at least {min}.', {'min': _grouped(widget.min)});
    if (widget.max != null && value > widget.max!) return tr('Must be at most {max}.', {'max': _grouped(widget.max)});
    return widget.validator?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final signed = widget.min == null || widget.min! < 0;
    return FormField<num>(
      initialValue: _value,
      enabled: widget.enabled,
      validator: (value) => _validate(),
      builder: (field) => TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals > 0, signed: signed),
        textInputAction: widget.textInputAction,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(signed ? r'[0-9.,\- ]' : r'[0-9., ]'))],
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          errorText: widget.errorText ?? field.errorText,
          prefixText: widget.symbol.isEmpty ? null : '${widget.symbol} ',
        ),
        onChanged: (text) {
          final value = _parse(text);
          _invalid = text.trim().isNotEmpty && value == null;
          _value = value;
          field.didChange(value);
          widget.onChanged(value);
        },
      ),
    );
  }
}

// ── Phone numbers ───────────────────────────────────────────────────────────

/// A country a phone number can be of.
class PhoneCountry {
  const PhoneCountry(this.code, this.dial, this.name);

  /// Its two letters: "GH".
  final String code;

  /// Its calling code, without the plus: "233".
  final String dial;
  final String name;

  static final List<PhoneCountry> all = [
    for (final line in _countries.trim().split('\n'))
      if (line.trim().split(':') case [final code, final dial, final name]) PhoneCountry(code, dial, name),
  ];

  /// The countries a shared calling code is taken as.
  static const Map<String, String> _first = {'1': 'US', '7': 'RU'};

  static PhoneCountry? byCode(String? code) {
    final wanted = (code ?? '').toUpperCase();
    for (final country in all) {
      if (country.code == wanted) return country;
    }
    return null;
  }

  /// The country of a full number's digits (no plus), by its longest calling
  /// code; [prefer] wins where several countries share it.
  static PhoneCountry? ofNumber(String digits, {PhoneCountry? prefer}) {
    PhoneCountry? found;
    for (final country in all) {
      if (!digits.startsWith(country.dial)) continue;
      if (found == null || country.dial.length > found.dial.length) {
        found = country;
      } else if (country.dial.length == found.dial.length && _first[country.dial] == country.code) {
        found = country;
      }
    }
    return found != null && prefer != null && prefer.dial == found.dial ? prefer : found;
  }
}

/// A phone number: the country's calling code, picked from a list, and the
/// number. It hands back the whole international number, "+233241234567".
class PhoneField extends StatefulWidget {
  const PhoneField({
    super.key,
    this.value,
    required this.onChanged,
    this.label,
    this.country,
    this.required = false,
    this.validator,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.textInputAction,
  });

  /// The stored number: "+233241234567". One without a plus is taken as a
  /// number of the starting country.
  final String? value;

  /// The whole number with its plus and calling code, null when empty.
  final ValueChanged<String?> onChanged;
  final String? label;

  /// The two letters of the country to start on ("GH"); the device's region
  /// when left out.
  final String? country;
  final bool required;
  final String? Function(String? value)? validator;
  final String? helperText;

  /// The API's error for this field.
  final String? errorText;
  final bool enabled;
  final TextInputAction? textInputAction;

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  final _controller = TextEditingController();
  late PhoneCountry _country;

  /// What onChanged was last given, so the page handing it back changes nothing.
  String? _sent;

  static String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    _country = PhoneCountry.byCode(widget.country) ??
        PhoneCountry.byCode(WidgetsBinding.instance.platformDispatcher.locale.countryCode) ??
        PhoneCountry.byCode('US')!;
    _read(widget.value);
    _sent = widget.value;
  }

  @override
  void didUpdateWidget(PhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value || widget.value == _sent) return;
    _read(widget.value);
    _sent = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Splits a stored number into its country and the rest.
  void _read(String? value) {
    final text = (value ?? '').trim();
    final digits = _digits(text);
    if (text.startsWith('+')) {
      final found = PhoneCountry.ofNumber(digits, prefer: _country);
      if (found != null) {
        _country = found;
        _controller.text = digits.substring(found.dial.length);
        return;
      }
    }
    _controller.text = digits;
  }

  /// The number inside the country, without the 0 people dial at home (Italy keeps its own).
  String get _national {
    final digits = _digits(_controller.text);
    return _country.code == 'IT' ? digits : digits.replaceFirst(RegExp(r'^0+'), '');
  }

  String? get _number => _national.isEmpty ? null : '+${_country.dial}$_national';

  void _emit(FormFieldState<String> field) {
    final number = _number;
    _sent = number;
    field.didChange(number);
    widget.onChanged(number);
  }

  void _typed(FormFieldState<String> field, String text) {
    // A whole number pasted or typed with its plus: its country is taken from it.
    if (text.trimLeft().startsWith('+')) {
      final digits = _digits(text);
      final found = PhoneCountry.ofNumber(digits, prefer: _country);
      if (found != null) {
        final rest = digits.substring(found.dial.length);
        setState(() => _country = found);
        _controller.value = TextEditingValue(text: rest, selection: TextSelection.collapsed(offset: rest.length));
      }
    }
    _emit(field);
  }

  Future<void> _pickCountry(FormFieldState<String> field) async {
    final picked = await _showFieldPanel<PhoneCountry>(
      context,
      builder: (context) => _CountryPanel(current: _country),
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
    _emit(field);
  }

  String? _validate() {
    final national = _national;
    if (national.isEmpty) return widget.required ? _requiredText() : null;
    if (national.length < 4 || _country.dial.length + national.length > 15) return tr('Enter a valid phone number.');
    return widget.validator?.call(_number);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormField<String>(
      initialValue: widget.value,
      enabled: widget.enabled,
      validator: (value) => _validate(),
      builder: (field) => TextField(
        controller: _controller,
        enabled: widget.enabled,
        keyboardType: TextInputType.phone,
        textInputAction: widget.textInputAction,
        // A number reads the same way in every language.
        textDirection: TextDirection.ltr,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+() \-]'))],
        decoration: InputDecoration(
          labelText: widget.label ?? tr('Phone number'),
          helperText: widget.helperText,
          errorText: widget.errorText ?? field.errorText,
          prefixIcon: Tooltip(
            message: _country.name,
            child: InkWell(
              onTap: widget.enabled ? () => _pickCountry(field) : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    '${_country.code} +${_country.dial}',
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const Icon(AppIcons.expandMore, size: 18),
                ]),
              ),
            ),
          ),
        ),
        onChanged: (text) => _typed(field, text),
      ),
    );
  }
}

class _CountryPanel extends StatefulWidget {
  const _CountryPanel({required this.current});

  final PhoneCountry current;

  @override
  State<_CountryPanel> createState() => _CountryPanelState();
}

class _CountryPanelState extends State<_CountryPanel> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final words = _search.toLowerCase();
    final digits = _search.replaceAll(RegExp(r'\D'), '');
    final shown = [
      for (final country in PhoneCountry.all)
        if (words.isEmpty ||
            country.name.toLowerCase().contains(words) ||
            country.code.toLowerCase() == words ||
            (digits.isNotEmpty && country.dial.startsWith(digits)))
          country,
    ];
    return _FieldPanel(
      title: tr('Country'),
      onSearch: (text) => setState(() => _search = text.trim()),
      onSubmitted: (text) {
        if (shown.isNotEmpty) Navigator.of(context).pop(shown.first);
      },
      child: shown.isEmpty
          ? _PanelMessage(text: tr('Nothing found.'))
          : ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final country = shown[index];
                final chosen = country.code == widget.current.code;
                return ListTile(
                  title: Text(country.name),
                  selected: chosen,
                  trailing: Text('+${country.dial}', textDirection: TextDirection.ltr),
                  onTap: () => Navigator.of(context).pop(country),
                );
              },
            ),
    );
  }
}

/// Code:calling code:name, by name. A country inside +1 has its own four digits.
const String _countries = """
AF:93:Afghanistan
AL:355:Albania
DZ:213:Algeria
AS:1684:American Samoa
AD:376:Andorra
AO:244:Angola
AI:1264:Anguilla
AG:1268:Antigua and Barbuda
AR:54:Argentina
AM:374:Armenia
AW:297:Aruba
AU:61:Australia
AT:43:Austria
AZ:994:Azerbaijan
BS:1242:Bahamas
BH:973:Bahrain
BD:880:Bangladesh
BB:1246:Barbados
BY:375:Belarus
BE:32:Belgium
BZ:501:Belize
BJ:229:Benin
BM:1441:Bermuda
BT:975:Bhutan
BO:591:Bolivia
BA:387:Bosnia and Herzegovina
BW:267:Botswana
BR:55:Brazil
VG:1284:British Virgin Islands
BN:673:Brunei
BG:359:Bulgaria
BF:226:Burkina Faso
BI:257:Burundi
KH:855:Cambodia
CM:237:Cameroon
CA:1:Canada
CV:238:Cape Verde
KY:1345:Cayman Islands
CF:236:Central African Republic
TD:235:Chad
CL:56:Chile
CN:86:China
CO:57:Colombia
KM:269:Comoros
CG:242:Congo
CD:243:Congo (DRC)
CK:682:Cook Islands
CR:506:Costa Rica
HR:385:Croatia
CU:53:Cuba
CW:599:Curaçao
CY:357:Cyprus
CZ:420:Czechia
DK:45:Denmark
DJ:253:Djibouti
DM:1767:Dominica
DO:1809:Dominican Republic
EC:593:Ecuador
EG:20:Egypt
SV:503:El Salvador
GQ:240:Equatorial Guinea
ER:291:Eritrea
EE:372:Estonia
SZ:268:Eswatini
ET:251:Ethiopia
FK:500:Falkland Islands
FO:298:Faroe Islands
FJ:679:Fiji
FI:358:Finland
FR:33:France
GF:594:French Guiana
PF:689:French Polynesia
GA:241:Gabon
GM:220:Gambia
GE:995:Georgia
DE:49:Germany
GH:233:Ghana
GI:350:Gibraltar
GR:30:Greece
GL:299:Greenland
GD:1473:Grenada
GP:590:Guadeloupe
GU:1671:Guam
GT:502:Guatemala
GN:224:Guinea
GW:245:Guinea-Bissau
GY:592:Guyana
HT:509:Haiti
HN:504:Honduras
HK:852:Hong Kong
HU:36:Hungary
IS:354:Iceland
IN:91:India
ID:62:Indonesia
IR:98:Iran
IQ:964:Iraq
IE:353:Ireland
IL:972:Israel
IT:39:Italy
CI:225:Ivory Coast
JM:1876:Jamaica
JP:81:Japan
JO:962:Jordan
KZ:7:Kazakhstan
KE:254:Kenya
KI:686:Kiribati
XK:383:Kosovo
KW:965:Kuwait
KG:996:Kyrgyzstan
LA:856:Laos
LV:371:Latvia
LB:961:Lebanon
LS:266:Lesotho
LR:231:Liberia
LY:218:Libya
LI:423:Liechtenstein
LT:370:Lithuania
LU:352:Luxembourg
MO:853:Macao
MG:261:Madagascar
MW:265:Malawi
MY:60:Malaysia
MV:960:Maldives
ML:223:Mali
MT:356:Malta
MH:692:Marshall Islands
MQ:596:Martinique
MR:222:Mauritania
MU:230:Mauritius
MX:52:Mexico
FM:691:Micronesia
MD:373:Moldova
MC:377:Monaco
MN:976:Mongolia
ME:382:Montenegro
MS:1664:Montserrat
MA:212:Morocco
MZ:258:Mozambique
MM:95:Myanmar
NA:264:Namibia
NR:674:Nauru
NP:977:Nepal
NL:31:Netherlands
NC:687:New Caledonia
NZ:64:New Zealand
NI:505:Nicaragua
NE:227:Niger
NG:234:Nigeria
KP:850:North Korea
MK:389:North Macedonia
MP:1670:Northern Mariana Islands
NO:47:Norway
OM:968:Oman
PK:92:Pakistan
PW:680:Palau
PS:970:Palestine
PA:507:Panama
PG:675:Papua New Guinea
PY:595:Paraguay
PE:51:Peru
PH:63:Philippines
PL:48:Poland
PT:351:Portugal
PR:1787:Puerto Rico
QA:974:Qatar
RE:262:Réunion
RO:40:Romania
RU:7:Russia
RW:250:Rwanda
KN:1869:Saint Kitts and Nevis
LC:1758:Saint Lucia
VC:1784:Saint Vincent and the Grenadines
WS:685:Samoa
SM:378:San Marino
ST:239:São Tomé and Príncipe
SA:966:Saudi Arabia
SN:221:Senegal
RS:381:Serbia
SC:248:Seychelles
SL:232:Sierra Leone
SG:65:Singapore
SX:1721:Sint Maarten
SK:421:Slovakia
SI:386:Slovenia
SB:677:Solomon Islands
SO:252:Somalia
ZA:27:South Africa
KR:82:South Korea
SS:211:South Sudan
ES:34:Spain
LK:94:Sri Lanka
SD:249:Sudan
SR:597:Suriname
SE:46:Sweden
CH:41:Switzerland
SY:963:Syria
TW:886:Taiwan
TJ:992:Tajikistan
TZ:255:Tanzania
TH:66:Thailand
TL:670:Timor-Leste
TG:228:Togo
TO:676:Tonga
TT:1868:Trinidad and Tobago
TN:216:Tunisia
TR:90:Turkey
TM:993:Turkmenistan
TC:1649:Turks and Caicos Islands
TV:688:Tuvalu
UG:256:Uganda
UA:380:Ukraine
AE:971:United Arab Emirates
GB:44:United Kingdom
US:1:United States
VI:1340:US Virgin Islands
UY:598:Uruguay
UZ:998:Uzbekistan
VU:678:Vanuatu
VE:58:Venezuela
VN:84:Vietnam
YE:967:Yemen
ZM:260:Zambia
ZW:263:Zimbabwe
""";
