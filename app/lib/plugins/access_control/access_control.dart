// Roles & permissions: a page in the menu, for those allowed to manage them,
// to create roles, tick what each may do on every page, and give people their
// role. The API keeps and checks them (api/src/plugins/access-control); the
// app reads what the signed-in account may do with AuthState.can. Owned by
// AppWand (Plugins).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_plugin.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/widgets.dart';

const String _manage = 'access.manage';

const AppPlugin plugin = AppPlugin(
  id: 'access-control',
  wrap: _wrap,
  pages: [
    PluginPage(
      title: 'Roles & permissions',
      route: '/access-control',
      icon: AppIcons.shield,
      permission: _manage,
      group: 'Settings',
      builder: _page,
    ),
  ],
);

Widget _page(Map<String, String> params) => const AccessControlPage();

Widget _wrap(Widget child) => _PermissionRefresher(child: child);

/// Reads the account's permissions again when the app comes back to the
/// front and every few minutes, so a change made by an administrator shows
/// without signing in again.
class _PermissionRefresher extends ConsumerStatefulWidget {
  const _PermissionRefresher({required this.child});
  final Widget child;

  @override
  ConsumerState<_PermissionRefresher> createState() => _PermissionRefresherState();
}

class _PermissionRefresherState extends ConsumerState<_PermissionRefresher> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 5), (timer) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => ref.read(authProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) => widget.child;
}

String _actionLabel(String action) => switch (action) {
      'view' => tr('View'),
      'create' => tr('Add'),
      'edit' => tr('Edit'),
      'delete' => tr('Delete'),
      'export' => tr('Export'),
      'import' => tr('Import'),
      'all' => tr('All records'),
      _ => action,
    };

String _peopleLabel(int count) => count == 1 ? tr('1 person') : tr('{count} people', {'count': count});

class _Role {
  _Role(Map<String, dynamic> json)
      : key = '${json['key']}',
        name = '${json['name'] ?? json['key']}',
        description = '${json['description'] ?? ''}',
        protected = json['protected'] == true,
        isDefault = json['isDefault'] == true,
        people = json['people'] is num ? (json['people'] as num).toInt() : 0,
        permissions = {if (json['permissions'] is List) for (final item in json['permissions'] as List) '$item'};

  final String key;
  final String name;
  final String description;

  /// An administrator role: every permission, always.
  final bool protected;

  /// The role people without one are treated as.
  final bool isDefault;
  final int people;
  final Set<String> permissions;
}

class _PageInfo {
  _PageInfo(Map<String, dynamic> json)
      : id = '${json['id']}',
        title = '${json['title'] ?? json['id']}',
        actions = [if (json['actions'] is List) for (final item in json['actions'] as List) '$item'];

  final String id;
  final String title;
  final List<String> actions;
}

class _Meta {
  _Meta(Map<String, dynamic> json)
      : pages = [if (json['pages'] is List) for (final item in json['pages'] as List) _PageInfo(Map<String, dynamic>.from(item as Map))],
        roles = [if (json['roles'] is List) for (final item in json['roles'] as List) _Role(Map<String, dynamic>.from(item as Map))],
        canAssign = json['canAssign'] != false,
        youId = json['you'] is Map ? '${(json['you'] as Map)['id']}' : '',
        youAdmin = json['you'] is Map && (json['you'] as Map)['admin'] == true;

  final List<_PageInfo> pages;
  final List<_Role> roles;

  /// Whether the accounts table has a role column.
  final bool canAssign;
  final String youId;

  /// Only administrators make others administrators.
  final bool youAdmin;
}

Future<dynamic> _call(WidgetRef ref, String method, String path, {Map<String, dynamic>? query, Object? data}) =>
    ref.read(apiClientProvider).send(ApiCall(method, path, query: query, data: data));

/// The Roles & permissions page: the roles, each with its permissions and
/// the accounts that have it.
class AccessControlPage extends ConsumerStatefulWidget {
  const AccessControlPage({super.key});

  @override
  ConsumerState<AccessControlPage> createState() => _AccessControlPageState();
}

class _AccessControlPageState extends ConsumerState<AccessControlPage> {
  _Meta? _meta;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await _call(ref, 'GET', '/access/meta');
      if (mounted) {
        setState(() {
          _meta = _Meta(Map<String, dynamic>.from(json as Map));
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  /// Whether the roles tab shows the chosen role beside the list (wide screens).
  bool _wide = false;

  /// The role chosen in the list; the first one until one is chosen.
  String? _selected;

  /// Whether the role beside the list has changes not saved yet.
  bool _dirty = false;

  /// The role shown beside the list.
  String? get _current {
    final roles = _meta?.roles ?? const <_Role>[];
    return roles.any((role) => role.key == _selected) ? _selected : roles.firstOrNull?.key;
  }

  /// Asks before changes not saved yet are dropped.
  Future<bool> _mayLeave() async {
    if (!_dirty) return true;
    final leave = await showConfirmDialog(
      context,
      title: tr('Leave without saving?'),
      message: tr('The changes to this role will be lost.'),
    );
    if (leave) _dirty = false;
    return leave;
  }

  /// Wide screens show the role beside the list; phones open it as a page.
  Future<void> _open(_Role role) async {
    final meta = _meta;
    if (meta == null) return;
    if (_wide) {
      if (role.key == _current || !await _mayLeave()) return;
      if (mounted) setState(() => _selected = role.key);
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (context) => _RolePage(meta: meta, role: role)),
    );
    await _saved(false);
  }

  /// A role changed hands: the roles' counts are read again.
  Future<void> _peopleChanged() => _load();

  /// A role was saved or deleted: the roles, and this account's own
  /// permissions (the role may be its own), are read again.
  Future<void> _saved(bool deleted) async {
    _dirty = false;
    if (deleted) _selected = null;
    await _load();
    await ref.read(authProvider.notifier).refresh();
  }

  Future<void> _add() async {
    final meta = _meta;
    if (meta == null || !await _mayLeave() || !mounted) return;
    final created = await showDialog<_Role>(context: context, builder: (context) => _NewRoleDialog(meta: meta));
    if (created == null || !mounted) return;
    await _load();
    final role = _meta?.roles.where((r) => r.key == created.key).firstOrNull;
    if (role != null && mounted) await _open(role);
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final Widget body;
    if (meta == null) {
      body = _error == null ? const LoadingView() : ErrorView(message: _error!, onRetry: _load);
    } else {
      body = _RolesView(
        meta: meta,
        selected: _current,
        onOpen: _open,
        onRefresh: _load,
        onWide: (wide) => _wide = wide,
        onDirty: (dirty) => _dirty = dirty,
        onDone: _saved,
        onPeopleChanged: _peopleChanged,
      );
    }
    return AppScaffold(
      title: tr('Roles & permissions'),
      actions: [
        if (meta != null) IconButton(tooltip: tr('New role'), icon: const Icon(AppIcons.add), onPressed: _add),
      ],
      body: body,
    );
  }
}

/// The roles. On a wide screen the chosen role (its permissions and its
/// accounts) is beside the list; on a phone a role opens as a page of its own.
class _RolesView extends StatefulWidget {
  const _RolesView({
    required this.meta,
    required this.selected,
    required this.onOpen,
    required this.onRefresh,
    required this.onWide,
    required this.onDirty,
    required this.onDone,
    required this.onPeopleChanged,
  });

  final _Meta meta;

  /// The role shown beside the list on a wide screen.
  final String? selected;
  final ValueChanged<_Role> onOpen;
  final Future<void> Function() onRefresh;

  /// Told at every layout whether the role is beside the list.
  final ValueChanged<bool> onWide;
  final ValueChanged<bool> onDirty;
  final void Function(bool deleted) onDone;

  /// Someone was given another role.
  final Future<void> Function() onPeopleChanged;

  @override
  State<_RolesView> createState() => _RolesViewState();
}

class _RolesViewState extends State<_RolesView> {
  /// The list takes this much of a wide screen; the role gets the rest.
  static const double _listWidth = 340;

  /// From this width on, the role is beside the list.
  static const double _wideFrom = 900;

  /// The tab of the role beside the list, kept when another role is chosen.
  int _tab = 0;

  Widget _list(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final roles = widget.meta.roles;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: roles.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final role = roles[index];
          final chosen = wide && role.key == widget.selected;
          final notes = [
            if (role.protected) tr('Administrator: every permission'),
            if (role.isDefault) tr('Also for people without a role'),
            _peopleLabel(role.people),
          ];
          return AppSurface(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: chosen ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.12), scheme.surface) : null,
            onTap: () => widget.onOpen(role),
            child: ListTile(
              selected: chosen,
              leading: Icon(role.protected ? AppIcons.shield : AppIcons.badge),
              title: Text(role.name),
              subtitle: Text(
                [if (role.description.isNotEmpty) role.description, notes.join(' · ')].join('\n'),
                style: muted,
              ),
              trailing: wide ? null : const Icon(AppIcons.chevronRight),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideFrom;
      widget.onWide(wide);
      if (!wide) return _list(context, wide: false);
      final role = widget.meta.roles.where((r) => r.key == widget.selected).firstOrNull;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: _listWidth, child: _list(context, wide: true)),
        const VerticalDivider(width: 1),
        Expanded(
          child: role == null
              ? EmptyView(message: tr('Choose a role to see what it may do.'), icon: AppIcons.shield)
              : _RoleEditor(
                  // A role of its own state: choosing another starts from that role's permissions.
                  key: ValueKey(role.key),
                  meta: widget.meta,
                  role: role,
                  heading: true,
                  tab: _tab,
                  onTab: (tab) => _tab = tab,
                  onDirty: widget.onDirty,
                  onDone: widget.onDone,
                  onPeopleChanged: widget.onPeopleChanged,
                ),
        ),
      ]);
    });
  }
}

class _NewRoleDialog extends ConsumerStatefulWidget {
  const _NewRoleDialog({required this.meta});
  final _Meta meta;

  @override
  ConsumerState<_NewRoleDialog> createState() => _NewRoleDialogState();
}

class _NewRoleDialogState extends ConsumerState<_NewRoleDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _copyFrom = '';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = tr('Enter a name for the role.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final json = await _call(ref, 'POST', '/access/roles', data: {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        if (_copyFrom.isNotEmpty) 'copyFrom': _copyFrom,
      });
      if (mounted) Navigator.of(context).pop(_Role(Map<String, dynamic>.from(json as Map)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copyable = widget.meta.roles.where((role) => !role.protected).toList();
    return AlertDialog(
      title: Text(tr('New role')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              decoration: InputDecoration(labelText: tr('Name'), errorText: _error, counterText: ''),
              onSubmitted: (value) => _create(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              maxLength: 255,
              decoration: InputDecoration(labelText: tr('Description'), counterText: ''),
            ),
            if (copyable.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _copyFrom,
                decoration: InputDecoration(labelText: tr('Start with the permissions of')),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('No permissions'))),
                  for (final role in copyable) DropdownMenuItem(value: role.key, child: Text(role.name)),
                ],
                onChanged: (value) => setState(() => _copyFrom = value ?? ''),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _busy ? null : _create, child: Text(tr('Create'))),
      ],
    );
  }
}

/// One role as a page of its own, on a phone.
class _RolePage extends ConsumerStatefulWidget {
  const _RolePage({required this.meta, required this.role});
  final _Meta meta;
  final _Role role;

  @override
  ConsumerState<_RolePage> createState() => _RolePageState();
}

class _RolePageState extends ConsumerState<_RolePage> {
  late _Meta _meta = widget.meta;
  bool _dirty = false;

  _Role get _role => _meta.roles.where((r) => r.key == widget.role.key).firstOrNull ?? widget.role;

  /// A role changed hands: the roles' counts are read again.
  Future<void> _reload() async {
    try {
      final json = await _call(ref, 'GET', '/access/meta');
      if (mounted) setState(() => _meta = _Meta(Map<String, dynamic>.from(json as Map)));
    } catch (e) {
      // The counts stay as they were; the list of accounts is already right.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showConfirmDialog(
          context,
          title: tr('Leave without saving?'),
          message: tr('The changes to this role will be lost.'),
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_role.name)),
        body: SafeArea(
          child: _RoleEditor(
            meta: _meta,
            role: _role,
            onDirty: (dirty) => setState(() => _dirty = dirty),
            onDone: (deleted) => Navigator.of(context).pop(),
            onPeopleChanged: _reload,
          ),
        ),
      ),
    );
  }
}

/// One role, in two tabs: Permissions (its name, and what it may do on every
/// page) and Role accounts (the people who have it). Beside the list of roles
/// on a wide screen, the body of [_RolePage] on a phone.
class _RoleEditor extends ConsumerStatefulWidget {
  const _RoleEditor({
    super.key,
    required this.meta,
    required this.role,
    required this.onDirty,
    required this.onDone,
    required this.onPeopleChanged,
    this.heading = false,
    this.tab = 0,
    this.onTab,
  });

  final _Meta meta;
  final _Role role;

  /// The role's name on top, where no app bar shows it.
  final bool heading;

  /// The tab it opens on, and told when another is chosen.
  final int tab;
  final ValueChanged<int>? onTab;

  /// Someone was given another role.
  final Future<void> Function() onPeopleChanged;

  /// Told when the first change is made, and when the changes are saved.
  final ValueChanged<bool> onDirty;

  /// The role was saved, or deleted.
  final void Function(bool deleted) onDone;

  @override
  ConsumerState<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends ConsumerState<_RoleEditor> with SingleTickerProviderStateMixin {
  late final _name = TextEditingController(text: widget.role.name);
  late final _description = TextEditingController(text: widget.role.description);
  late final Set<String> _granted = {...widget.role.permissions};
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.tab.clamp(0, 1));
  bool _busy = false;
  bool _changed = false;

  _Role get _role => widget.role;
  List<_PageInfo> get _pages => widget.meta.pages;

  /// The actions any page has, as the table's columns.
  List<String> get _columns => [
        for (final action in const ['view', 'create', 'edit', 'delete', 'export', 'import', 'all'])
          if (_pages.any((page) => page.actions.contains(action))) action,
      ];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) widget.onTab?.call(_tabs.index);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_changed) widget.onDirty(true);
    _changed = true;
  }

  bool _has(_PageInfo page, String action) => _granted.contains('${page.id}.$action');

  /// Any action needs the page's view; without view nothing is left.
  void _set(_PageInfo page, String action, bool on) {
    setState(() {
      _touch();
      if (on) {
        _granted
          ..add('${page.id}.$action')
          ..add('${page.id}.view');
      } else if (action == 'view') {
        _granted.removeAll([for (final a in page.actions) '${page.id}.$a']);
      } else {
        _granted.remove('${page.id}.$action');
      }
    });
  }

  void _setPage(_PageInfo page, bool on) {
    setState(() {
      _touch();
      final keys = [for (final a in page.actions) '${page.id}.$a'];
      on ? _granted.addAll(keys) : _granted.removeAll(keys);
    });
  }

  void _setColumn(String action, bool on) {
    for (final page in _pages) {
      if (page.actions.contains(action)) _set(page, action, on);
    }
  }

  /// true: every action, false: none, null: some.
  bool? _pageState(_PageInfo page) {
    final count = page.actions.where((a) => _has(page, a)).length;
    return count == 0 ? false : (count == page.actions.length ? true : null);
  }

  bool? _columnState(String action) {
    final with_ = _pages.where((page) => page.actions.contains(action)).toList();
    final count = with_.where((page) => _has(page, action)).length;
    return count == 0 ? false : (count == with_.length ? true : null);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, tr('Enter a name for the role.'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _call(ref, 'PATCH', '/access/roles/${Uri.encodeComponent(_role.key)}', data: {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        if (!_role.protected) 'permissions': _granted.toList(),
      });
      if (!mounted) return;
      showSnack(context, tr('Saved'));
      setState(() {
        _busy = false;
        _changed = false;
      });
      widget.onDirty(false);
      widget.onDone(false);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, errorMessage(e), error: true);
      }
    }
  }

  Future<void> _delete() async {
    var moveTo = '';
    if (_role.people > 0) {
      final others = widget.meta.roles.where((r) => r.key != _role.key && (!r.protected || widget.meta.youAdmin)).toList();
      final picked = await showDialog<String>(
        context: context,
        builder: (context) => _MovePeopleDialog(role: _role, others: others),
      );
      if (picked == null) return;
      moveTo = picked;
    } else {
      final sure = await showConfirmDialog(
        context,
        title: tr('Delete this role?'),
        message: tr('"{name}" will be gone. Nobody has it.', {'name': _role.name}),
      );
      if (!sure) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _call(
        ref,
        'DELETE',
        '/access/roles/${Uri.encodeComponent(_role.key)}',
        query: {if (moveTo.isNotEmpty) 'moveTo': moveTo},
      );
      if (!mounted) return;
      showSnack(context, tr('Role deleted'));
      widget.onDirty(false);
      widget.onDone(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, errorMessage(e), error: true);
      }
    }
  }

  Widget _table(ThemeData theme) {
    const cell = 84.0;
    final columns = _columns;
    final heading = theme.textTheme.labelLarge;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Expanded(child: Text(tr('Page'), style: heading)),
          for (final action in columns)
            SizedBox(
              width: cell,
              child: Column(children: [
                Text(_actionLabel(action), style: heading),
                Checkbox(
                  tristate: true,
                  value: _columnState(action),
                  onChanged: (value) => _setColumn(action, _columnState(action) != true),
                ),
              ]),
            ),
        ]),
      ),
      const Divider(height: 1),
      for (final page in _pages) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(children: [
            Checkbox(
              tristate: true,
              value: _pageState(page),
              onChanged: (value) => _setPage(page, _pageState(page) != true),
            ),
            Expanded(child: Text(tr(page.title), style: theme.textTheme.bodyLarge)),
            for (final action in columns)
              SizedBox(
                width: cell,
                child: page.actions.contains(action)
                    ? Checkbox(value: _has(page, action), onChanged: (value) => _set(page, action, value ?? false))
                    : const SizedBox.shrink(),
              ),
          ]),
        ),
        const Divider(height: 1),
      ],
    ]);
  }

  Widget _cards(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final page in _pages) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Checkbox(
                tristate: true,
                value: _pageState(page),
                onChanged: (value) => _setPage(page, _pageState(page) != true),
              ),
              Expanded(child: Text(tr(page.title), style: theme.textTheme.titleSmall)),
            ]),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final action in page.actions)
                  FilterChip(
                    label: Text(_actionLabel(action)),
                    selected: _has(page, action),
                    onSelected: (value) => _set(page, action, value),
                  ),
              ]),
            ),
          ]),
        ),
        const Divider(height: 1),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final canDelete = !_role.protected && !_role.isDefault;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.heading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Expanded(child: Text(_role.name, style: theme.textTheme.titleLarge)),
                if (_changed) Text(tr('Not saved yet'), style: muted),
              ]),
            ),
          // Drawn as the app's tab style says (theme.dart's tabStyle).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(height: 44, text: tr('Permissions')), Tab(height: 44, text: tr('Role accounts'))],
            ),
          ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              _permissions(theme, muted, canDelete),
              _RoleAccounts(meta: widget.meta, role: _role, onChanged: widget.onPeopleChanged),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _permissions(ThemeData theme, TextStyle? muted, bool canDelete) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          AppSurface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _name,
                maxLength: 100,
                decoration: InputDecoration(labelText: tr('Name'), counterText: ''),
                onChanged: (value) => setState(_touch),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                maxLength: 255,
                decoration: InputDecoration(labelText: tr('Description'), counterText: ''),
                onChanged: (value) => setState(_touch),
              ),
              const SizedBox(height: 12),
              Text(_peopleLabel(_role.people), style: muted),
            ]),
          ),
          const SizedBox(height: 24),
          Text(tr('Permissions'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_role.protected)
            AppSurface(
              child: Row(children: [
                const Icon(AppIcons.shield),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('This is an administrator role: it always has every permission.'))),
              ]),
            )
          else ...[
            AppSurface(
              padding: EdgeInsets.zero,
              child: _pages.isEmpty
                  ? Padding(padding: const EdgeInsets.all(16), child: Text(tr('The app has no pages behind sign-in yet.'), style: muted))
                  : LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth >= 260 + _columns.length * 84 ? _table(theme) : _cards(theme),
                    ),
            ),
            const SizedBox(height: 16),
            AppSurface(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SwitchListTile(
                title: Text(tr('Manage roles and permissions')),
                subtitle: Text(tr('Open this page, change roles and give people their role.')),
                value: _granted.contains(_manage),
                onChanged: (value) => setState(() {
                  _touch();
                  value ? _granted.add(_manage) : _granted.remove(_manage);
                }),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(children: [
            if (canDelete)
              TextButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(AppIcons.delete),
                label: Text(tr('Delete role')),
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(AppIcons.save),
              label: Text(tr('Save')),
            ),
          ]),
    ]);
  }
}

/// Deleting a role people have: which role they get.
class _MovePeopleDialog extends StatefulWidget {
  const _MovePeopleDialog({required this.role, required this.others});
  final _Role role;
  final List<_Role> others;

  @override
  State<_MovePeopleDialog> createState() => _MovePeopleDialogState();
}

class _MovePeopleDialogState extends State<_MovePeopleDialog> {
  String? _moveTo;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Delete this role?')),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('{people} have "{name}". Choose the role they get.', {'people': _peopleLabel(widget.role.people), 'name': widget.role.name})),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _moveTo,
            decoration: InputDecoration(labelText: tr('Move them to')),
            items: [for (final role in widget.others) DropdownMenuItem(value: role.key, child: Text(role.name))],
            onChanged: (value) => setState(() => _moveTo = value),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Cancel'))),
        FilledButton(
          onPressed: _moveTo == null ? null : () => Navigator.of(context).pop(_moveTo),
          child: Text(tr('Delete')),
        ),
      ],
    );
  }
}

/// The accounts that have one role, each with its role to change, and Add
/// people to give the role to others.
class _RoleAccounts extends ConsumerStatefulWidget {
  const _RoleAccounts({required this.meta, required this.role, required this.onChanged});
  final _Meta meta;
  final _Role role;

  /// A role changed hands: the roles' counts are read again.
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_RoleAccounts> createState() => _RoleAccountsState();
}

class _RoleAccountsState extends ConsumerState<_RoleAccounts> with AutomaticKeepAliveClientMixin {
  String _search = '';

  /// Raised when someone joins or leaves the role, so the list is read again.
  int _version = 0;

  @override
  bool get wantKeepAlive => true;

  Future<void> _changed() async {
    if (mounted) setState(() => _version++);
    await widget.onChanged();
  }

  Future<void> _add() async {
    var added = false;
    await showDialog<void>(
      context: context,
      builder: (context) => _AddPeopleDialog(meta: widget.meta, role: widget.role, onAdded: () => added = true),
    );
    if (added) await _changed();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final meta = widget.meta;
    final role = widget.role;
    // Only an administrator makes others administrators.
    final canAdd = meta.canAssign && (!role.protected || meta.youAdmin);
    return Column(children: [
      Row(children: [
        Expanded(child: ListSearchField(hint: tr('Search people'), onChanged: (value) => setState(() => _search = value))),
        if (canAdd)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: FilledButton.tonalIcon(onPressed: _add, icon: const Icon(AppIcons.add), label: Text(tr('Add people'))),
          ),
      ]),
      if (!meta.canAssign)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(tr('The accounts table has no role column, so roles cannot be given yet.')),
        ),
      Expanded(
        child: PagedList(
          query: '$_version $_search',
          paging: Paging.infinite,
          skeleton: true,
          emptyIcon: AppIcons.people,
          emptyMessage: _search.isEmpty ? tr('Nobody has this role yet.') : tr('No people found.'),
          padding: const EdgeInsets.only(bottom: 24),
          fetch: (page, limit) => _call(ref, 'GET', '/access/people', query: {
            'page': page,
            'limit': limit,
            'role': role.key,
            if (_search.isNotEmpty) 'search': _search,
          }),
          itemBuilder: (context, row) => _PersonTile(key: ValueKey(row['id']), meta: meta, row: row, onChanged: _changed),
        ),
      ),
    ]);
  }
}

/// The accounts with another role (or none), to give them this one.
class _AddPeopleDialog extends ConsumerStatefulWidget {
  const _AddPeopleDialog({required this.meta, required this.role, required this.onAdded});
  final _Meta meta;
  final _Role role;
  final VoidCallback onAdded;

  @override
  ConsumerState<_AddPeopleDialog> createState() => _AddPeopleDialogState();
}

class _AddPeopleDialogState extends ConsumerState<_AddPeopleDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(tr('Add people to "{name}"', {'name': widget.role.name}), style: theme.textTheme.titleLarge),
          ),
          ListSearchField(hint: tr('Search people'), onChanged: (value) => setState(() => _search = value)),
          Expanded(
            child: PagedList(
              query: _search,
              paging: Paging.infinite,
              refreshable: false,
              emptyIcon: AppIcons.people,
              emptyMessage: tr('No people found.'),
              padding: EdgeInsets.zero,
              fetch: (page, limit) => _call(ref, 'GET', '/access/people', query: {
                'page': page,
                'limit': limit,
                'except': widget.role.key,
                if (_search.isNotEmpty) 'search': _search,
              }),
              itemBuilder: (context, row) => _AddPersonTile(
                key: ValueKey(row['id']),
                meta: widget.meta,
                role: widget.role,
                row: row,
                onAdded: widget.onAdded,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Done'))),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AddPersonTile extends ConsumerStatefulWidget {
  const _AddPersonTile({super.key, required this.meta, required this.role, required this.row, required this.onAdded});
  final _Meta meta;
  final _Role role;
  final Map<String, dynamic> row;
  final VoidCallback onAdded;

  @override
  ConsumerState<_AddPersonTile> createState() => _AddPersonTileState();
}

class _AddPersonTileState extends ConsumerState<_AddPersonTile> {
  bool _busy = false;
  bool _added = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    try {
      await _call(ref, 'PATCH', '/access/people/${Uri.encodeComponent('${widget.row['id']}')}', data: {'role': widget.role.key});
      widget.onAdded();
      if (mounted) setState(() => _added = true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final row = widget.row;
    final name = '${row['name'] ?? ''}'.trim();
    final email = '${row['email'] ?? ''}'.trim();
    final shown = name.isNotEmpty ? name : email;
    final isYou = '${row['id']}' == meta.youId;
    final current = meta.roles.where((r) => r.key == '${row['role'] ?? ''}').firstOrNull;
    // Your own role, and an administrator's by anyone who is not one, stay as they are.
    final locked = _busy || isYou || ((current?.protected ?? false) && !meta.youAdmin);
    final has = current?.name ?? (row['role'] == null ? tr('No role') : '${row['role']}');
    return ListTile(
      leading: CircleAvatar(child: Text(shown.isEmpty ? '?' : shown.characters.first.toUpperCase())),
      title: Text(isYou ? tr('{name} (you)', {'name': shown}) : shown),
      subtitle: Text([if (name.isNotEmpty && email.isNotEmpty) email, has].join(' · ')),
      trailing: _added
          ? Text(tr('Added'), style: Theme.of(context).textTheme.labelLarge)
          : FilledButton.tonal(onPressed: locked ? null : _add, child: Text(tr('Add'))),
    );
  }
}

class _PersonTile extends ConsumerStatefulWidget {
  const _PersonTile({super.key, required this.meta, required this.row, required this.onChanged});
  final _Meta meta;
  final Map<String, dynamic> row;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_PersonTile> createState() => _PersonTileState();
}

class _PersonTileState extends ConsumerState<_PersonTile> {
  bool _busy = false;

  String? get _role => widget.row['role'] == null ? null : '${widget.row['role']}';

  Future<void> _change(String? role) async {
    if (role == _role) return;
    setState(() => _busy = true);
    try {
      await _call(ref, 'PATCH', '/access/people/${Uri.encodeComponent('${widget.row['id']}')}', data: {'role': role});
      widget.row['role'] = role;
      if (mounted) showSnack(context, tr('Role changed'));
      await widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final row = widget.row;
    final name = '${row['name'] ?? ''}'.trim();
    final email = '${row['email'] ?? ''}'.trim();
    final shown = name.isNotEmpty ? name : email;
    final isYou = '${row['id']}' == meta.youId;
    final role = _role;
    final known = meta.roles.any((r) => r.key == role);
    final holdsAdmin = meta.roles.any((r) => r.key == role && r.protected);
    // Your own role, and an administrator's by anyone who is not one, stay as they are.
    final locked = _busy || isYou || !meta.canAssign || (holdsAdmin && !meta.youAdmin);
    return ListTile(
      leading: CircleAvatar(child: Text(shown.isEmpty ? '?' : shown.characters.first.toUpperCase())),
      title: Text(isYou ? tr('{name} (you)', {'name': shown}) : shown),
      subtitle: name.isNotEmpty && email.isNotEmpty ? Text(email) : null,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: DropdownButton<String>(
          isExpanded: true,
          underline: const SizedBox.shrink(),
          value: known ? role : null,
          hint: Text(role ?? tr('No role')),
          items: [
            for (final r in meta.roles)
              DropdownMenuItem(value: r.key, enabled: !r.protected || meta.youAdmin, child: Text(r.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: locked ? null : _change,
        ),
      ),
    );
  }
}
