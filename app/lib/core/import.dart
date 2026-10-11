// Importing a CSV or Excel file into a list. Owned by AppWand.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth/auth_controller.dart';
import 'format.dart' show formatNumber;
import 'i18n.dart';
import 'icons.dart';
import 'imports.g.dart';

const Map<String, String> _formatLabels = {'csv': 'CSV', 'xlsx': 'Excel'};

/// An app-bar button that imports a CSV or Excel file into a list page's
/// table, through the page's POST /import route. [page] is the page's id;
/// [onImported] runs once rows were added or changed, to reload the list.
///
/// It opens a dialog that names the headings the file needs, checks the
/// chosen file and says what it would do before anything is written. The
/// columns, the file types and who may import are set in AppWand
/// (imports.g.dart): the button shows nothing for a page without an import,
/// or for a role that may not use it.
class ImportButton extends ConsumerWidget {
  const ImportButton({super.key, required this.page, this.onImported});
  final String page;
  final VoidCallback? onImported;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = appImports[page];
    if (config == null || config.formats.isEmpty || !ref.watch(authProvider).allows('$page.import', config.roles)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: tr('Import'),
      icon: const Icon(AppIcons.upload),
      onPressed: () async {
        final changed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _ImportDialog(page: page, config: config),
        );
        if (changed != true) return;
        // Totals on other pages (a dashboard) follow, like after any write.
        ref.read(dataVersionProvider.notifier).bump();
        onImported?.call();
      },
    );
  }
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.page, required this.config});
  final String page;
  final ImportConfig config;

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  String? _name;
  List<int>? _bytes;

  /// The API's answer for the chosen file: the check, then the import.
  Map<String, dynamic>? _result;
  String? _error;
  bool _busy = false;

  /// Whether rows were written, so the list reloads when the dialog closes.
  bool _changed = false;

  ImportConfig get _config => widget.config;

  int _count(String key) => (num.tryParse('${_result?[key]}') ?? 0).toInt();

  bool get _checked => _result != null && _result!['check'] == true;
  bool get _finished => _result != null && _result!['check'] != true;
  bool get _imported => _finished && _result!['imported'] == true;

  /// Whether the checked file has rows to write. With "all or nothing", a
  /// row with a problem holds back the whole file.
  bool get _ready =>
      _checked && _count('created') + _count('updated') > 0 && !(_config.allOrNothing && _count('failed') > 0);

  String get _formats => _config.formats.map((f) => _formatLabels[f] ?? f.toUpperCase()).join(' ${tr('or')} ');

  Future<void> _choose() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: tr('Choose the file to import'),
      type: FileType.custom,
      allowedExtensions: _config.formats,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    _name = file.name;
    _bytes = bytes;
    await _send(check: true);
  }

  Future<void> _send({required bool check}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (check) _result = null;
    });
    try {
      final data = await ref.read(apiClientProvider).upload(
        '/${widget.page}/import',
        bytes: _bytes!,
        filename: _name!,
        query: {'check': check ? 1 : null, 'tz': DateTime.now().timeZoneOffset.inMinutes},
      );
      if (!mounted) return;
      setState(() {
        _result = Map<String, dynamic>.from(data as Map);
        if (_imported && _count('created') + _count('updated') > 0) _changed = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// An empty CSV file with the headings, to fill in.
  Future<void> _template() async {
    String quote(String text) => text.contains(RegExp('[",\r\n]')) ? '"${text.replaceAll('"', '""')}"' : text;
    final line = _config.columns.map((c) => quote(c.label)).join(',');
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: tr('Save the template'),
        fileName: '${widget.page}-template.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        // The byte order mark makes Excel read the file as UTF-8.
        bytes: Uint8List.fromList(utf8.encode('﻿$line\r\n')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  String _rows(int n) => n == 1 ? tr('1 row') : tr('{count} rows', {'count': formatNumber(n)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(tr('Import')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_result == null) ..._intro(theme) else ..._summary(theme),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_checked ? tr('Importing {file}…', {'file': _name}) : tr('Reading {file}…', {'file': _name}))),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _Line(icon: AppIcons.error, color: theme.colorScheme.error, text: _error!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(_changed),
          child: Text(_imported ? tr('Done') : (_changed ? tr('Close') : tr('Cancel'))),
        ),
        if (!_imported)
          if (_ready)
            FilledButton(
              onPressed: _busy ? null : () => _send(check: false),
              child: Text(tr('Import {rows}', {'rows': _rows(_count('created') + _count('updated'))})),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _choose,
              icon: const Icon(AppIcons.attachFile, size: 18),
              label: Text(_result == null ? tr('Choose a file') : tr('Choose another file')),
            ),
      ],
    );
  }

  /// Before a file is chosen: what it should look like.
  List<Widget> _intro(ThemeData theme) {
    final soft = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final match = _config.matchBy;
    return [
      Text(
        _config.columns.isEmpty
            ? tr('Choose a {formats} file. Its first row holds the names of the columns, and each row under it becomes a row of the list.', {'formats': _formats})
            : tr('Choose a {formats} file whose first row has these headings. Each row under it becomes a row of the list.', {'formats': _formats}),
      ),
      if (_config.columns.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final column in _config.columns)
              Chip(
                label: Text(column.required ? '${column.label} *' : column.label),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          [
            if (_config.columns.any((c) => c.required)) tr('* cannot be left empty in a new row.'),
            tr('The order does not matter, and other columns of the file are ignored.'),
          ].join(' '),
          style: soft,
        ),
      ],
      const SizedBox(height: 8),
      Text(
        switch (_config.mode) {
          'update' => tr('A row whose {column} is already in the list is updated; the others are added. An empty cell leaves the value as it is.', {'column': match}),
          'skip' => tr('A row whose {column} is already in the list is left as it is; the others are added.', {'column': match}),
          _ => tr('Every row of the file is added.'),
        },
        style: soft,
      ),
      Text(tr('At most {rows} at a time. Nothing is saved until you have seen what the file holds.', {'rows': _rows(_config.maxRows)}), style: soft),
      if (_config.columns.isNotEmpty && _config.formats.contains('csv')) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _busy ? null : _template,
          icon: const Icon(AppIcons.download, size: 18),
          label: Text(tr('Download a template')),
        ),
      ],
    ];
  }

  /// After the check or the import: what the file holds, or what was done.
  List<Widget> _summary(ThemeData theme) {
    final scheme = theme.colorScheme;
    final created = _count('created');
    final updated = _count('updated');
    final skipped = _count('skipped');
    final failed = _count('failed');
    final errors = [
      for (final e in (_result!['errors'] as List? ?? const []))
        if (e is Map) e,
    ];
    final ignored = [for (final name in (_result!['ignored'] as List? ?? const [])) '$name'];
    final held = !_imported && _config.allOrNothing && failed > 0;
    return [
      Text('$_name · ${_rows(_count('total'))}', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      if (_finished && !_imported)
        _Line(icon: AppIcons.error, color: scheme.error, text: tr('Nothing was imported.'))
      else ...[
        if (created > 0)
          _Line(
            icon: _imported ? AppIcons.checkCircle : AppIcons.addCircle,
            color: scheme.primary,
            text: _imported ? tr('{rows} added', {'rows': _rows(created)}) : tr('{rows} will be added', {'rows': _rows(created)}),
          ),
        if (updated > 0)
          _Line(
            icon: _imported ? AppIcons.checkCircle : AppIcons.edit,
            color: scheme.primary,
            text: _imported ? tr('{rows} updated', {'rows': _rows(updated)}) : tr('{rows} will be updated', {'rows': _rows(updated)}),
          ),
        if (created + updated == 0 && !held)
          _Line(icon: AppIcons.info, color: scheme.onSurfaceVariant, text: tr('There is nothing to import in this file.')),
      ],
      if (skipped > 0)
        _Line(icon: AppIcons.info, color: scheme.onSurfaceVariant, text: skipped == 1 ? tr('1 row already in the list, left as it is') : tr('{rows} already in the list, left as they are', {'rows': _rows(skipped)})),
      if (failed > 0)
        _Line(
          icon: AppIcons.warning,
          color: scheme.error,
          text: held
              ? (failed == 1
                  ? tr('1 row has a problem. Nothing is imported until the file has none: fix it and choose the file again.')
                  : tr('{rows} have a problem. Nothing is imported until the file has none: fix them and choose the file again.', {'rows': _rows(failed)}))
              : switch ((failed == 1, _imported)) {
                  (true, true) => tr('1 row has a problem and was left out'),
                  (true, false) => tr('1 row has a problem and will be left out'),
                  (false, true) => tr('{rows} have a problem and were left out', {'rows': _rows(failed)}),
                  (false, false) => tr('{rows} have a problem and will be left out', {'rows': _rows(failed)}),
                },
        ),
      if (errors.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withAlpha(90),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              for (final e in errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(tr('Row {row}: {message}', {'row': e['row'], 'message': e['message']})),
                ),
              if (failed > errors.length) Text(tr('And {count} more.', {'count': formatNumber(failed - errors.length)})),
            ],
          ),
        ),
      ],
      if (ignored.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          tr('Not imported (no such column in the list): {columns}', {'columns': ignored.join(', ')}),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ];
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
