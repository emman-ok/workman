// Saving a list as a CSV or Excel file. Owned by AppWand.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth/auth_controller.dart';
import 'exports.g.dart';
import 'format.dart' show formatNumber;
import 'i18n.dart';
import 'icons.dart';
import 'lists.dart' show SelectionController;
import 'widgets.dart' show showSnack;

const Map<String, String> _formatLabels = {'csv': 'CSV', 'xlsx': 'Excel'};

/// An app-bar button that saves a list page's rows as a file, through the
/// page's GET /export route. [page] is the page's id; [query] is what the
/// list sends besides the page (search, sort, filters), so the file holds
/// what the list shows. With a [selection] that has rows picked, only those
/// rows are exported.
///
/// The formats offered, the file's name and who may export are set in
/// AppWand (exports.g.dart): the button shows nothing for a page without an
/// export, or for a role that may not use it.
class ExportButton extends ConsumerStatefulWidget {
  const ExportButton({super.key, required this.page, this.query = const {}, this.selection});
  final String page;
  final Map<String, dynamic> query;
  final SelectionController? selection;

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _busy = false;

  String _fileName(ExportConfig config, String format) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final day = config.dateInName ? '-${now.year}-${two(now.month)}-${two(now.day)}' : '';
    return '${config.fileName}$day.$format';
  }

  Future<void> _export(ExportConfig config, String format) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ids = widget.selection?.ids ?? const <Object>{};
      final file = await ref.read(apiClientProvider).download('/${widget.page}/export', query: {
        for (final entry in widget.query.entries)
          if (entry.key != 'page' && entry.key != 'limit') entry.key: entry.value,
        'format': format,
        'tz': DateTime.now().timeZoneOffset.inMinutes,
        if (ids.isNotEmpty) 'ids': ids.join(','),
      });
      // The system's save dialog; a browser downloads the file.
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: tr('Save the export'),
        fileName: _fileName(config, format),
        type: FileType.custom,
        allowedExtensions: [format],
        bytes: file.bytes,
      );
      if (!mounted || (saved == null && !kIsWeb)) return;
      final rows = int.tryParse(file.headers['x-export-rows'] ?? '');
      final total = int.tryParse(file.headers['x-export-total'] ?? '');
      if (rows == null) {
        showSnack(context, tr('Exported'));
      } else if (total != null && total > rows) {
        showSnack(
          context,
          tr('Exported the first {rows} of {total} rows. Narrow the list to export the rest.', {'rows': formatNumber(rows), 'total': formatNumber(total)}),
        );
      } else {
        showSnack(context, rows == 1 ? tr('Exported 1 row') : tr('Exported {rows} rows', {'rows': formatNumber(rows)}));
      }
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = appExports[widget.page];
    if (config == null || config.formats.isEmpty || !ref.watch(authProvider).allows('${widget.page}.export', config.roles)) {
      return const SizedBox.shrink();
    }
    if (_busy) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    String label(String format) => _formatLabels[format] ?? format.toUpperCase();
    if (config.formats.length == 1) {
      final format = config.formats.first;
      return IconButton(
        tooltip: tr('Export as {format}', {'format': label(format)}),
        onPressed: () => _export(config, format),
        icon: const Icon(AppIcons.download),
      );
    }
    return PopupMenuButton<String>(
      tooltip: tr('Export'),
      icon: const Icon(AppIcons.download),
      onSelected: (format) => _export(config, format),
      itemBuilder: (context) => [
        for (final format in config.formats) PopupMenuItem(value: format, child: Text(tr('Export as {format}', {'format': label(format)}))),
      ],
    );
  }
}
