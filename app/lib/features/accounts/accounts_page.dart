import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/uploads.dart';
import 'package:app/core/widgets.dart';
import 'package:app/core/details.dart';

const _roles = ['admin', 'project_manager', 'team_member'];

String _roleLabel(String role) => switch (role) {
      'admin' => tr('Admin'),
      'project_manager' => tr('Project manager'),
      'team_member' => tr('Team member'),
      _ => role,
    };

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  final PagedListController _list = PagedListController();
  final SelectionController _selection = SelectionController();
  String _search = '';
  String _sort = 'name';
  String _order = 'asc';
  Map<String, String> _filters = {};

  @override
  void initState() {
    super.initState();
    _filters = {
      for (final f in const ['role', 'is_active'])
        if ((widget.params[f] ?? '').isNotEmpty) f: widget.params[f]!,
    };
    _selection.addListener(_onSelection);
  }

  void _onSelection() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelection);
    _selection.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _extraQuery => {
        if (_search.isNotEmpty) 'search': _search,
        'sort': _sort,
        'order': _order,
        ..._filters,
      };

  String get _queryKey => Uri(queryParameters: {
        for (final e in _extraQuery.entries) e.key: '${e.value}',
      }).query;

  bool _isSelf(Map<String, dynamic> row) {
    final me = ref.read(authProvider).user;
    return me != null && '${me['id']}' == '${row['id']}';
  }

  void _setSort(String sort, String order) {
    setState(() {
      _sort = sort;
      _order = order;
    });
  }

  Future<void> _openEdit(Map<String, dynamic> row) async {
    final result = await context.push<bool>('/accounts/${row['id']}/edit');
    if (result == true) _list.refresh();
  }

  Future<void> _setActive(Map<String, dynamic> row, bool value) async {
    try {
      await ref.read(apiClientProvider).patch('/accounts/${row['id']}/active', data: {'is_active': value});
      if (!mounted) return;
      showSnack(context, value ? tr('Account activated') : tr('Account deactivated'));
      _list.refresh();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _setRole(Map<String, dynamic> row, String role) async {
    try {
      await ref.read(apiClientProvider).patch('/accounts/${row['id']}/role', data: {'role': role});
      if (!mounted) return;
      showSnack(context, tr('Role changed'));
      _list.refresh();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _deleteOne(Map<String, dynamic> row) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Delete account'),
      message: tr('Delete {name}? This cannot be undone.', {'name': '${row['name']}'}),
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiClientProvider).post('/accounts/bulk-delete', data: {'ids': [row['id']]});
      if (!mounted) return;
      _list.remove([row['id']]);
      _selection.clear();
      showSnack(context, tr('Account deleted'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _deleteSelected() async {
    final ids = [..._selection.ids];
    if (ids.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: tr('Delete accounts'),
      message: tr('Delete {count} selected accounts? This cannot be undone.', {'count': ids.length}),
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiClientProvider).post('/accounts/bulk-delete', data: {'ids': ids});
      if (!mounted) return;
      _list.remove(ids);
      _selection.clear();
      showSnack(context, tr('Accounts deleted'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Widget _menu(BuildContext context, Map<String, dynamic> row) {
    final auth = ref.watch(authProvider);
    final canEdit = auth.can('accounts.edit');
    final canDelete = auth.can('accounts.delete');
    final self = _isSelf(row);
    final active = row['is_active'] == true;
    final role = '${row['role']}';
    final items = <PopupMenuEntry<String>>[];
    if (canEdit) {
      items.add(PopupMenuItem<String>(value: 'edit', child: Text(tr('Edit'))));
      if (!self) {
        items.add(PopupMenuItem<String>(
          value: active ? 'deactivate' : 'activate',
          child: Text(active ? tr('Deactivate') : tr('Activate')),
        ));
        items.add(const PopupMenuDivider());
        for (final r in _roles) {
          items.add(PopupMenuItem<String>(
            value: 'role:$r',
            enabled: r != role,
            child: Text(tr('Set role: {role}', {'role': _roleLabel(r)})),
          ));
        }
      }
    }
    if (canDelete && !self) {
      if (items.isNotEmpty) items.add(const PopupMenuDivider());
      items.add(PopupMenuItem<String>(value: 'delete', child: Text(tr('Delete'))));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: tr('Actions'),
      icon: const Icon(AppIcons.moreVert),
      itemBuilder: (_) => items,
      onSelected: (value) {
        if (value == 'edit') {
          _openEdit(row);
        } else if (value == 'activate') {
          _setActive(row, true);
        } else if (value == 'deactivate') {
          _setActive(row, false);
        } else if (value == 'delete') {
          _deleteOne(row);
        } else if (value.startsWith('role:')) {
          _setRole(row, value.substring(5));
        }
      },
    );
  }

  Widget _activeBadge(Map<String, dynamic> row) {
    final active = row['is_active'] == true;
    return StatusBadge(active ? tr('Active') : tr('Inactive'), color: active ? Colors.green : Colors.grey);
  }

  Widget _roleBadge(Map<String, dynamic> row) {
    final role = '${row['role']}';
    final color = switch (role) {
      'admin' => Colors.red,
      'project_manager' => Colors.blue,
      _ => Colors.grey,
    };
    return StatusBadge(_roleLabel(role), color: color);
  }

  Widget _row(BuildContext context, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final selected = _selection.isSelected(row['id']);
    final canDelete = ref.watch(authProvider).can('accounts.delete');
    return ListTile(
      selected: selected,
      onLongPress: canDelete ? () => _selection.toggle(row['id']) : null,
      onTap: () {
        if (_selection.active) {
          _selection.toggle(row['id']);
        } else if (ref.read(authProvider).can('accounts.edit')) {
          _openEdit(row);
        }
      },
      leading: _selection.active
          ? Checkbox(value: selected, onChanged: (_) => _selection.toggle(row['id']))
          : AppImage(row['photo'], width: 40, height: 40, circle: true, preview: false),
      title: Text('${row['name']}', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${row['email']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(_roleLabel('${row['role']}'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_activeBadge(row), _menu(context, row)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final canCreate = auth.can('accounts.create');
    final canDelete = auth.can('accounts.delete');
    final canEdit = auth.can('accounts.edit');
    final key = _queryKey;

    return AppScaffold(
      title: tr('Accounts'),
      actions: [
        ExportButton(page: 'accounts', query: _extraQuery, selection: _selection),
        SortMenu(
          fields: {
            'name': tr('Name'),
            'email': tr('Email'),
            'role': tr('Role'),
            'created_at': tr('Created'),
          },
          sort: _sort,
          order: _order,
          onChanged: _setSort,
        ),
      ],
      floatingActionButton: canCreate
          ? FloatingActionButton(
              tooltip: tr('New account'),
              onPressed: () async {
                final result = await context.push<bool>('/accounts/new');
                if (result == true) _list.refresh();
              },
              child: const Icon(AppIcons.add),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListSearchField(
            hint: tr('Search by name or email'),
            initialValue: _search,
            onChanged: (v) => setState(() => _search = v),
          ),
          FilterBar(
            filters: [
              ListFilter(
                field: 'role',
                label: tr('Role'),
                options: {for (final r in _roles) r: _roleLabel(r)},
              ),
              ListFilter(
                field: 'is_active',
                label: tr('Status'),
                options: {'true': tr('Active'), 'false': tr('Inactive')},
              ),
            ],
            values: _filters,
            onChanged: (v) => setState(() => _filters = v),
          ),
          if (_selection.active)
            SelectionBar(
              controller: _selection,
              onSelectAll: () => _selection.selectAll(_list.items.map((r) => r['id'])),
              actions: [
                if (canDelete)
                  IconButton(
                    tooltip: tr('Delete selected'),
                    icon: const Icon(AppIcons.delete),
                    onPressed: _deleteSelected,
                  ),
              ],
            ),
          Expanded(
            child: PagedList(
              controller: _list,
              selection: _selection,
              paging: Paging.pages,
              refreshable: true,
              query: key,
              sort: _sort,
              order: _order,
              onSort: _setSort,
              emptyMessage: tr('No accounts found.'),
              emptyIcon: AppIcons.people,
              fetch: (page, limit) => ref.read(apiClientProvider).get('/accounts', query: {
                'page': page,
                'limit': limit,
                ..._extraQuery,
              }),
              itemBuilder: _row,
              columns: [
                TableColumn(
                  label: tr('Name'),
                  sortKey: 'name',
                  flex: 2,
                  cell: (context, row) => Text('${row['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                TableColumn(
                  label: tr('Email'),
                  sortKey: 'email',
                  flex: 2,
                  cell: (context, row) => Text('${row['email']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                TableColumn(
                  label: tr('Role'),
                  sortKey: 'role',
                  width: 170,
                  cell: (context, row) => _roleBadge(row),
                ),
                TableColumn(
                  label: tr('Status'),
                  width: 120,
                  cell: (context, row) => _activeBadge(row),
                ),
                TableColumn(
                  label: tr('Created'),
                  sortKey: 'created_at',
                  width: 130,
                  cell: (context, row) => Text(formatDate(row['created_at'])),
                ),
              ],
              onRowTap: (row) {
                if (_selection.active) {
                  _selection.toggle(row['id']);
                } else if (canEdit) {
                  _openEdit(row);
                }
              },
              rowActions: (context, row) => [_menu(context, row)],
              rowActionsWidth: 48,
            ),
          ),
        ],
      ),
    );
  }
}
