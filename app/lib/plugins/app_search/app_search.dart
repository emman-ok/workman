// App search: a search box in the app's header (an icon where there is no
// room, and in the grid layout's greeting). It opens a panel that looks for
// the typed text in the tables chosen in AppWand and lists the records found
// under their table; choosing one opens its page. Ctrl+K (⌘K) opens it too.
// The API does the searching (api/src/plugins/app-search). Owned by AppWand
// (Plugins).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/app_plugin.dart';
import '../../core/theme.dart' show AppStyle, appStyle;
import '../../core/uploads.dart' show AppImage;
import '../../core/widgets.dart';
import 'settings.g.dart';

const AppPlugin plugin = AppPlugin(id: 'app-search', headerAction: _headerAction);

Widget _headerAction(BuildContext context, {required bool compact, Color? color}) =>
    AppSearchButton(compact: compact, color: color);

/// Shorter text is not sent: the API answers it with nothing.
const int _minLength = 2;

/// The text in the empty box: the one set in AppWand, or "Search".
String get _placeholder => searchPlaceholder.trim().isEmpty ? tr('Search') : tr(searchPlaceholder.trim());

/// A record the search found, and how its page opens.
class _Hit {
  const _Hit({required this.title, required this.subtitle, required this.path, required this.push, this.photo});
  final String title;
  final String subtitle;

  /// Its picture, a stored path or a link: empty for a record without one,
  /// null for a table whose results show no pictures.
  final String? photo;

  /// The app route that opens it.
  final String path;

  /// Whether it opens over the page the person is on (a record's own page);
  /// a list takes the place of that page.
  final bool push;
}

/// One table's results under its heading.
class _Group {
  const _Group(this.label, this.hits);
  final String label;
  final List<_Hit> hits;
}

List<_Group> _read(Object? answer) {
  final groups = answer is Map ? answer['groups'] : null;
  return [
    if (groups is List)
      for (final group in groups)
        if (group is Map && group['items'] is List)
          _Group('${group['label'] ?? ''}', [
            for (final item in group['items'] as List)
              if (item is Map && item['path'] is String)
                _Hit(
                  title: '${item['title'] ?? ''}',
                  subtitle: '${item['subtitle'] ?? ''}',
                  photo: item.containsKey('photo') ? '${item['photo'] ?? ''}' : null,
                  path: item['path'] as String,
                  push: item['push'] == true,
                ),
          ]),
  ];
}

/// The search box in the app's header: a box with the placeholder on a wide
/// window, an icon button on a narrow one or when [compact].
class AppSearchButton extends ConsumerStatefulWidget {
  const AppSearchButton({super.key, this.compact = false, this.color});
  final bool compact;

  /// The colour of the icon and the text; the header's own when null.
  final Color? color;

  @override
  ConsumerState<AppSearchButton> createState() => _AppSearchButtonState();
}

class _AppSearchButtonState extends ConsumerState<AppSearchButton> {
  /// The boxes on screen, the last built last: Ctrl+K opens the search from that one.
  static final List<_AppSearchButtonState> _shown = [];
  static bool _listening = false;
  static bool _open = false;

  @override
  void initState() {
    super.initState();
    _shown.add(this);
    if (!_listening) {
      _listening = true;
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    _shown.remove(this);
    super.dispose();
  }

  static bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return false;
    if (_shown.isEmpty) return false;
    _shown.last._search();
    return true;
  }

  Future<void> _search() async {
    if (_open || !mounted) return;
    _open = true;
    final router = GoRouter.of(context);
    final api = ref.read(apiClientProvider);
    try {
      final hit = await showDialog<_Hit>(context: context, builder: (context) => _SearchDialog(api: api));
      if (hit == null) return;
      if (hit.push) {
        router.push(hit.path);
      } else {
        router.go(hit.path);
      }
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = widget.color ?? IconTheme.of(context).color ?? theme.colorScheme.onSurface;
    if (widget.compact || MediaQuery.sizeOf(context).width < 1100) {
      return IconButton(
        tooltip: tr('Search'),
        color: widget.color,
        icon: const Icon(AppIcons.search),
        onPressed: _search,
      );
    }
    final square = appStyle == AppStyle.brutalism || appStyle == AppStyle.flat;
    final apple = theme.platform == TargetPlatform.macOS || theme.platform == TargetPlatform.iOS;
    final text = theme.textTheme.bodyMedium;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: on.withAlpha(22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(square ? 0 : 10),
            side: BorderSide(color: on.withAlpha(60)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _search,
            child: SizedBox(
              width: 240,
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Icon(AppIcons.search, size: 20, color: on.withAlpha(200)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text?.copyWith(color: on.withAlpha(190)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(apple ? '⌘K' : 'Ctrl K', style: text?.copyWith(color: on.withAlpha(150))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The search panel, at the top of the window: the box, then the records
/// found under their table. Up and Down move through them, Enter opens one.
class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.api});
  final ApiClient api;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final TextEditingController _text = TextEditingController();
  Timer? _timer;

  /// Counts the searches sent, so a slow answer never replaces a later one.
  int _asked = 0;

  /// The text the results on screen are for; empty until the first answer.
  String _term = '';
  List<_Group> _groups = const [];

  /// A key per result, to scroll the marked one into view.
  List<GlobalKey> _keys = const [];
  bool _loading = false;
  String? _error;

  /// The result Enter opens.
  int _active = 0;

  List<_Hit> get _hits => [for (final group in _groups) ...group.hits];

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _show(List<_Group> groups, {String term = '', String? error}) {
    setState(() {
      _groups = groups;
      _keys = [for (final group in groups) for (var i = 0; i < group.hits.length; i++) GlobalKey()];
      _term = term;
      _error = error;
      _loading = false;
      _active = 0;
    });
  }

  void _changed(String value) {
    _timer?.cancel();
    final term = value.trim();
    if (term.length < _minLength) {
      // Whatever is still on its way is for text no longer in the box.
      _asked++;
      _show(const []);
      return;
    }
    setState(() => _loading = true);
    _timer = Timer(const Duration(milliseconds: 300), () => _find(term));
  }

  Future<void> _find(String term) async {
    final asked = ++_asked;
    try {
      // Past the plugins' layers: results are never kept for offline.
      final answer = await widget.api.send(ApiCall('GET', '/app-search', query: {'q': term}));
      if (!mounted || asked != _asked) return;
      _show(_read(answer), term: term);
    } catch (e) {
      if (!mounted || asked != _asked) return;
      _show(const [], term: term, error: errorMessage(e));
    }
  }

  void _move(int by) {
    final count = _hits.length;
    if (count == 0) return;
    setState(() => _active = (_active + by).clamp(0, count - 1));
    WidgetsBinding.instance.addPostFrameCallback((timestamp) {
      final marked = _active < _keys.length ? _keys[_active].currentContext : null;
      if (marked == null) return;
      Scrollable.ensureVisible(
        marked,
        alignmentPolicy: by > 0 ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Enter: the marked result, once the results are for the text in the box.
  void _submit() {
    final hits = _hits;
    if (_loading || _active >= hits.length) return;
    Navigator.of(context).pop(hits[_active]);
  }

  Widget _row(BuildContext context, _Hit hit, int index) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: _keys[index],
      selected: index == _active,
      selectedTileColor: scheme.primary.withAlpha(28),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      // The record's picture, where its table has a photo field (a tinted box while it has none).
      leading: hit.photo == null ? null : AppImage(hit.photo, width: 40, height: 40, radius: 8, preview: false),
      title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: hit.subtitle.isEmpty ? null : Text(hit.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(AppIcons.chevronRight, size: 20),
      onTap: () => Navigator.of(context).pop(hit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final typed = _text.text.trim();
    Widget status(String message) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Text(message, style: muted),
        );

    final Widget body;
    if (typed.length < _minLength) {
      body = status(tr('Type at least 2 characters to search.'));
    } else if (_error != null) {
      body = status(_error!);
    } else if (_keys.isEmpty) {
      body = status(_loading || _term.isEmpty ? tr('Searching…') : tr('No results for "{term}"', {'term': _term}));
    } else {
      var index = 0;
      body = SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                tr(group.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            for (final hit in group.hits) _row(context, hit, index++),
          ],
        ]),
      );
    }

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 540),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            // Up and Down belong to the results, not to the caret.
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: TextField(
                controller: _text,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.titleMedium,
                onChanged: _changed,
                onEditingComplete: _submit,
                decoration: InputDecoration(
                  hintText: _placeholder,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    IconButton(
                      tooltip: tr('Close'),
                      icon: const Icon(AppIcons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(child: body),
        ]),
      ),
    );
  }
}
