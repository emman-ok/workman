// In-app notifications: a bell in the app's header with a badge of how many
// are unread. It opens a panel of the latest records of the tables chosen in
// AppWand, newest first; choosing one marks it read and opens its page. The
// API does the reading (api/src/plugins/app-notifications). Owned by AppWand
// (Plugins).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/app_plugin.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/format.dart';
import '../../core/uploads.dart';
import '../../core/widgets.dart';
import 'settings.g.dart';

const AppPlugin plugin = AppPlugin(id: 'app-notifications', headerAction: _headerAction);

Widget _headerAction(BuildContext context, {required bool compact, Color? color}) => NotificationsButton(color: color);

/// One notification: a record of a table chosen in AppWand.
class AppNotification {
  const AppNotification({
    required this.key,
    required this.table,
    required this.id,
    required this.title,
    required this.detail,
    required this.image,
    required this.time,
    required this.read,
    required this.tracked,
    required this.path,
    required this.push,
  });

  /// `<table>:<id>`.
  final String key;
  final String table;
  final String id;
  final String title;
  final String detail;

  /// A stored path or a URL; null for none.
  final String? image;
  final DateTime? time;
  final bool read;

  /// Whether reading it is kept in the database (the table has a read
  /// column); otherwise it is read once the panel has been opened.
  final bool tracked;

  /// The app route that opens it; null when no page shows its table.
  final String? path;

  /// Whether it opens over the page the person is on (a record's own page);
  /// a list takes the place of that page.
  final bool push;

  AppNotification asRead() => AppNotification(
        key: key,
        table: table,
        id: id,
        title: title,
        detail: detail,
        image: image,
        time: time,
        read: true,
        tracked: tracked,
        path: path,
        push: push,
      );

  static AppNotification? from(Object? json) {
    if (json is! Map || json['table'] is! String) return null;
    final image = '${json['image'] ?? ''}'.trim();
    return AppNotification(
      key: '${json['key'] ?? ''}',
      table: json['table'] as String,
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      detail: '${json['detail'] ?? ''}',
      image: image.isEmpty ? null : image,
      time: DateTime.tryParse('${json['time'] ?? ''}')?.toLocal(),
      read: json['read'] == true,
      tracked: json['tracked'] == true,
      path: json['path'] is String ? json['path'] as String : null,
      push: json['push'] == true,
    );
  }
}

/// What the bell shows.
class NotificationsState {
  const NotificationsState({this.items = const [], this.unread = 0, this.loaded = false, this.error});

  /// The latest, newest first.
  final List<AppNotification> items;

  /// Every unread one, listed or not.
  final int unread;

  /// Whether the API has answered since sign-in.
  final bool loaded;
  final String? error;
}

final notificationsProvider = NotifierProvider<NotificationsController, NotificationsState>(NotificationsController.new);

/// Asks the API for the notifications: at sign-in, every
/// [notificationsInterval] seconds while the app is in front (when set in
/// AppWand), and after any change made in the app.
class NotificationsController extends Notifier<NotificationsState> {
  Timer? _timer;

  /// Counts the requests sent, so a slow answer never replaces a later one.
  int _asked = 0;

  /// The signed-in account's id; empty when signed out.
  String _account = '';

  /// When this account last looked at the panel on this device, by the API's
  /// clock: what a table without a read column counts as unread from.
  String? _since;

  /// The API's clock at its last answer.
  String? _now;

  String get _sinceKey => 'notifications.since.$_account';

  @override
  NotificationsState build() {
    final id = ref.watch(authProvider.select((auth) => auth.user?['id']));
    // A record changed in the app may be a notification, or have been one.
    ref.listen(dataVersionProvider, (previous, next) => refresh());
    _timer?.cancel();
    ref.onDispose(() => _timer?.cancel());
    _asked++;
    _since = null;
    _now = null;
    _account = id == null ? '' : '$id';
    if (_account.isEmpty) return const NotificationsState();
    final seconds = int.tryParse(notificationsInterval) ?? 30;
    if (notificationsPoll) {
      _timer = Timer.periodic(Duration(seconds: seconds < 10 ? 10 : seconds), (timer) {
        // Not while the app is hidden: it asks again when it comes back.
        final life = WidgetsBinding.instance.lifecycleState;
        if (life == null || life == AppLifecycleState.resumed) refresh();
      });
    }
    Future.microtask(_start);
    return const NotificationsState();
  }

  Future<void> _start() async {
    final account = _account;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (account != _account) return;
      _since = prefs.getString(_sinceKey);
    } catch (e) {
      // Without the saved time, everything in a table without a read column counts as seen.
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_account.isEmpty) return;
    final asked = ++_asked;
    try {
      // Past the plugins' layers: notifications are never kept for offline.
      final answer = await ref.read(apiClientProvider).send(
            ApiCall('GET', '/app-notifications', query: {if (_since != null) 'since': _since}),
          );
      if (asked != _asked) return;
      final map = answer is Map ? answer : const {};
      final now = map['now'];
      if (now is String) _now = now;
      // The first time on this device: what is already there counts as seen.
      if (_since == null && _now != null) await _keep(_now!);
      if (asked != _asked) return;
      final unread = map['unread'];
      final items = <AppNotification>[];
      if (map['items'] is List) {
        for (final json in map['items'] as List) {
          final item = AppNotification.from(json);
          if (item != null) items.add(item);
        }
      }
      state = NotificationsState(
        items: items,
        unread: unread is num ? unread.toInt() : 0,
        loaded: true,
      );
    } catch (e) {
      if (asked != _asked) return;
      // The ones already shown stay; the panel says what went wrong.
      state = NotificationsState(items: state.items, unread: state.unread, loaded: true, error: errorMessage(e));
    }
  }

  Future<void> _keep(String time) async {
    _since = time;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sinceKey, time);
    } catch (e) {
      // Kept for this run only.
    }
  }

  /// The panel was opened: what a table without a read column has is seen.
  Future<void> seen() async {
    if (_now == null || _now == _since) return;
    await _keep(_now!);
    await refresh();
  }

  /// Marks [item] read, in the database when its table keeps it there.
  Future<void> markRead(AppNotification item) async {
    if (item.read || !item.tracked) return;
    state = NotificationsState(
      items: [for (final one in state.items) one.key == item.key ? one.asRead() : one],
      unread: state.unread > 0 ? state.unread - 1 : 0,
      loaded: true,
    );
    try {
      // A change like any other: pages showing the row reload, and so does the bell.
      await ref.read(apiClientProvider).post('/app-notifications/read', data: {'table': item.table, 'id': item.id});
    } catch (e) {
      await refresh();
    }
  }

  /// Marks everything read. Null when done, else what went wrong.
  Future<String?> markAllRead() async {
    try {
      if (_now != null) await _keep(_now!);
      await ref.read(apiClientProvider).post('/app-notifications/read-all');
      await refresh();
      return null;
    } catch (e) {
      return errorMessage(e);
    }
  }
}

/// The bell in the app's header, with a badge of how many are unread.
class NotificationsButton extends ConsumerStatefulWidget {
  const NotificationsButton({super.key, this.color});

  /// The icon's colour; the header's own when null.
  final Color? color;

  @override
  ConsumerState<NotificationsButton> createState() => _NotificationsButtonState();
}

class _NotificationsButtonState extends ConsumerState<NotificationsButton> with WidgetsBindingObserver {
  static bool _open = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(notificationsProvider.notifier).refresh();
  }

  Future<void> _show() async {
    if (_open || !mounted) return;
    _open = true;
    final router = GoRouter.of(context);
    try {
      final item = await showDialog<AppNotification>(context: context, builder: (context) => const _NotificationsPanel());
      final path = item?.path;
      if (path == null) return;
      if (item!.push) {
        router.push(path);
      } else {
        router.go(path);
      }
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notificationsProvider.select((state) => state.unread));
    return IconButton(
      tooltip: unread > 0 ? tr('{count} unread notifications', {'count': '$unread'}) : tr('Notifications'),
      color: widget.color,
      onPressed: _show,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(AppIcons.notifications),
      ),
    );
  }
}

/// How long ago [time] was, in a few words; the date once it is a week old.
String _ago(DateTime time) {
  final passed = DateTime.now().difference(time);
  if (passed.inMinutes < 1) return tr('Just now');
  if (passed.inMinutes < 60) return tr('{count} min ago', {'count': '${passed.inMinutes}'});
  if (passed.inHours < 24) return tr('{count} h ago', {'count': '${passed.inHours}'});
  if (passed.inDays < 7) return tr('{count} d ago', {'count': '${passed.inDays}'});
  return formatDate(time);
}

/// The panel under the bell: the latest notifications, newest first.
class _NotificationsPanel extends ConsumerStatefulWidget {
  const _NotificationsPanel();

  @override
  ConsumerState<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends ConsumerState<_NotificationsPanel> {
  /// The ones that were new when the panel opened, in tables without a read
  /// column: opening the panel reads them, and they keep their mark until it closes.
  Set<String> _fresh = const {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = ref.read(notificationsProvider);
    _fresh = {for (final item in state.items) if (!item.read && !item.tracked) item.key};
    Future.microtask(() => ref.read(notificationsProvider.notifier).seen());
  }

  bool _unread(AppNotification item) => !item.read || _fresh.contains(item.key);

  Future<void> _readAll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref.read(notificationsProvider.notifier).markAllRead();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _fresh = const {};
    });
  }

  void _choose(AppNotification item) {
    ref.read(notificationsProvider.notifier).markRead(item);
    setState(() => _fresh = {..._fresh}..remove(item.key));
    // Nothing to open when no page shows its table: it is read, and stays listed.
    if (item.path != null) Navigator.of(context).pop(item);
  }

  Widget _picture(BuildContext context, AppNotification item) {
    if (item.image != null) return AppImage(item.image, width: 40, height: 40, circle: true, preview: false);
    final scheme = Theme.of(context).colorScheme;
    final letter = item.title.trim().isEmpty ? '?' : item.title.trim().substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.primary.withAlpha(30),
      foregroundColor: scheme.primary,
      child: Text(letter),
    );
  }

  Widget _row(BuildContext context, AppNotification item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = _unread(item);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      tileColor: unread ? scheme.primary.withAlpha(16) : null,
      leading: _picture(context, item),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: item.detail.isEmpty && item.time == null
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (item.detail.isNotEmpty) Text(item.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (item.time != null)
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(_ago(item.time!), style: muted)),
            ]),
      trailing: unread
          ? Container(width: 10, height: 10, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle))
          : null,
      onTap: () => _choose(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(notificationsProvider);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final anyUnread = state.unread > 0 || state.items.any(_unread);

    final Widget body;
    if (!state.loaded) {
      body = const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    } else if (state.items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.notifications, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(state.error ?? tr('No notifications yet.'), textAlign: TextAlign.center, style: muted),
        ]),
      );
    } else {
      body = ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: state.items.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) => _row(context, state.items[index]),
      );
    }

    final problem = _error ?? (state.items.isEmpty ? null : state.error);
    return Dialog(
      alignment: AlignmentDirectional.topEnd,
      insetPadding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 580),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(children: [
              Expanded(child: Text(tr('Notifications'), style: theme.textTheme.titleMedium)),
              if (anyUnread)
                TextButton(onPressed: _busy ? null : _readAll, child: Text(tr('Mark all as read'))),
              IconButton(
                tooltip: tr('Close'),
                icon: const Icon(AppIcons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const Divider(height: 1),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Text(problem, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
            ),
          Flexible(child: body),
        ]),
      ),
    );
  }
}
