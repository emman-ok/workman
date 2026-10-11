import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/widgets.dart';
import '../../plugins/record_ownership/record_ownership.dart';

final _projectOptionsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/tasks/options/projects', query: {'limit': 100});
  final items = List<Map<String, dynamic>>.from((data as Map)['items'] as List);
  return {for (final r in items) '${r['id']}': '${r['name']}'};
});

final _userOptionsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/tasks/options/users', query: {'limit': 100});
  final items = List<Map<String, dynamic>>.from((data as Map)['items'] as List);
  return {for (final r in items) '${r['id']}': '${r['name']}'};
});

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final PagedListController _controller = PagedListController();
  String _search = '';
  String _sort = 'created_at';
  String _order = 'desc';
  Map<String, String> _filters = {};

  @override
  void initState() {
    super.initState();
    _filters = {
      for (final f in const ['status', 'priority', 'project_id', 'assignee_id', 'deadline'])
        if ((widget.params[f] ?? '').isNotEmpty) f: widget.params[f]!,
    };
  }

  String _statusLabel(String status) => switch (status) {
        'todo' => tr('To do'),
        'in_progress' => tr('In progress'),
        'done' => tr('Done'),
        _ => status,
      };

  String _priorityLabel(String priority) => switch (priority) {
        'low' => tr('Low'),
        'medium' => tr('Medium'),
        'high' => tr('High'),
        'urgent' => tr('Urgent'),
        _ => priority,
      };

  Color _statusColor(String status) => switch (status) {
        'done' => Colors.green,
        'in_progress' => Colors.blue,
        _ => Colors.grey,
      };

  Color _priorityColor(String priority) => switch (priority) {
        'urgent' => Colors.red,
        'high' => Colors.orange,
        'medium' => Colors.blue,
        _ => Colors.grey,
      };

  String _nested(Map<String, dynamic> row, String key) {
    final v = row[key];
    if (v is Map) return '${v['name'] ?? ''}';
    return '';
  }

  bool _overdue(Map<String, dynamic> row) {
    final d = DateTime.tryParse('${row['deadline'] ?? ''}');
    if (d == null || row['status'] == 'done') return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day));
  }

  String? _nextStatus(Map<String, dynamic> row) => switch ('${row['status']}') {
        'todo' => 'in_progress',
        'in_progress' => 'done',
        _ => null,
      };

  Map<String, dynamic> _queryMap() => {
        if (_search.isNotEmpty) 'search': _search,
        'sort': _sort,
        'order': _order,
        ..._filters,
      };

  Future<void> _open(Map<String, dynamic> row) async {
    final result = await context.push<bool>('/tasks/${row['id']}');
    if (result == true) _controller.refresh();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await context.push<bool>('/tasks/${row['id']}/edit');
    if (result == true) _controller.refresh();
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    try {
      await ref.read(apiClientProvider).patch('/tasks/${row['id']}/status', data: {'status': status});
      if (!mounted) return;
      showSnack(context, tr('Task moved to {status}', {'status': _statusLabel(status)}));
      _controller.refresh();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Delete task?'),
      message: tr('Delete {name}? This cannot be undone.', {'name': row['title']}),
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).delete('/tasks/${row['id']}');
      _controller.remove([row['id']]);
      if (!mounted) return;
      showSnack(context, tr('Task deleted'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Widget _statusBadge(Map<String, dynamic> row) {
    final s = '${row['status']}';
    return StatusBadge(_statusLabel(s), color: _statusColor(s));
  }

  Widget _priorityBadge(Map<String, dynamic> row) {
    final p = '${row['priority']}';
    return StatusBadge(_priorityLabel(p), color: _priorityColor(p));
  }

  Widget _tile(BuildContext context, Map<String, dynamic> row, bool canEdit, bool canDelete, bool everyone) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = _nested(row, 'project');
    final assignee = _nested(row, 'assignee');
    final line1 = [
      if (project.isNotEmpty) project,
      if (everyone && assignee.isNotEmpty) assignee,
    ].join(' · ');
    final hasDeadline = '${row['deadline'] ?? ''}'.isNotEmpty;
    final overdue = _overdue(row);
    final current = '${row['status']}';
    final menuItems = <PopupMenuEntry<String>>[
      if (canEdit)
        for (final s in const ['todo', 'in_progress', 'done'])
          if (s != current)
            PopupMenuItem<String>(value: s, child: Text(tr('Move to {status}', {'status': _statusLabel(s)}))),
      if (canEdit) PopupMenuItem<String>(value: 'edit', child: Text(tr('Edit'))),
      if (canDelete) PopupMenuItem<String>(value: 'delete', child: Text(tr('Delete'))),
    ];
    return ListTile(
      onTap: () => _open(row),
      title: Text('${row['title']}', style: textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (line1.isNotEmpty)
            Text(line1, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _priorityBadge(row),
              if (hasDeadline)
                Text(
                  tr('Due {date}', {'date': formatDate(row['deadline'])}),
                  style: textTheme.bodySmall?.copyWith(color: overdue ? scheme.error : scheme.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusBadge(row),
          if (menuItems.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(AppIcons.moreVert),
              onSelected: (v) {
                if (v == 'edit') {
                  _edit(row);
                } else if (v == 'delete') {
                  _delete(row);
                } else {
                  _setStatus(row, v);
                }
              },
              itemBuilder: (_) => menuItems,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final canCreate = auth.can('tasks.create');
    final canEdit = auth.can('tasks.edit');
    final canDelete = auth.can('tasks.delete');
    final everyone = seesEveryone(auth, 'tasks', 'tasks');
    final projects = ref.watch(_projectOptionsProvider).valueOrNull ?? <String, String>{};
    final users = everyone ? (ref.watch(_userOptionsProvider).valueOrNull ?? <String, String>{}) : <String, String>{};
    final scheme = Theme.of(context).colorScheme;

    final queryKey = Uri(queryParameters: {
      'search': _search,
      'sort': _sort,
      'order': _order,
      ..._filters,
    }).query;

    final filters = <ListFilter>[
      ListFilter(
        field: 'status',
        label: tr('Status'),
        options: {
          'todo': tr('To do'),
          'in_progress': tr('In progress'),
          'done': tr('Done'),
        },
      ),
      ListFilter(
        field: 'priority',
        label: tr('Priority'),
        options: {
          'low': tr('Low'),
          'medium': tr('Medium'),
          'high': tr('High'),
          'urgent': tr('Urgent'),
        },
      ),
      ListFilter(field: 'project_id', label: tr('Project'), options: projects),
      ListFilter(
        field: 'deadline',
        label: tr('Deadline'),
        options: {
          'overdue': tr('Overdue'),
          'today': tr('Due today'),
          'week': tr('Due this week'),
        },
      ),
    ];

    final assigneeSelected = _filters['assignee_id'] ?? '';

    final rowActionCount = (canEdit ? 2 : 0) + (canDelete ? 1 : 0);

    return AppScaffold(
      title: tr('Tasks'),
      actions: [
        ExportButton(page: 'tasks', query: _queryMap()),
        SortMenu(
          fields: {
            'created_at': tr('Newest'),
            'title': tr('Title'),
            'deadline': tr('Deadline'),
            'priority': tr('Priority'),
            'status': tr('Status'),
          },
          sort: _sort,
          order: _order,
          onChanged: (s, o) => setState(() {
            _sort = s;
            _order = o;
          }),
        ),
      ],
      floatingActionButton: canCreate
          ? FloatingActionButton(
              tooltip: tr('New task'),
              onPressed: () async {
                final result = await context.push<bool>('/tasks/new');
                if (result == true) _controller.refresh();
              },
              child: const Icon(AppIcons.add),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListSearchField(
            hint: tr('Search tasks'),
            initialValue: _search,
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
          FilterBar(
            filters: filters,
            values: _filters,
            onChanged: (v) => setState(() => _filters = v),
            trailing: [
              if (everyone && users.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: tr('Assignee'),
                  icon: Icon(
                    AppIcons.person,
                    color: assigneeSelected.isEmpty ? null : scheme.primary,
                  ),
                  onSelected: (v) => setState(() {
                    final next = Map<String, String>.from(_filters);
                    if (v.isEmpty) {
                      next.remove('assignee_id');
                    } else {
                      next['assignee_id'] = v;
                    }
                    _filters = next;
                  }),
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: '',
                      child: Text(tr('All assignees')),
                    ),
                    for (final e in users.entries)
                      CheckedPopupMenuItem<String>(
                        value: e.key,
                        checked: e.key == assigneeSelected,
                        child: Text(e.value),
                      ),
                  ],
                ),
            ],
          ),
          Expanded(
            child: PagedList(
              controller: _controller,
              paging: Paging.pages,
              refreshable: true,
              query: queryKey,
              emptyMessage: tr('No tasks found.'),
              emptyIcon: AppIcons.checklist,
              fetch: (page, limit) => ref.read(apiClientProvider).get('/tasks', query: {
                'page': page,
                'limit': limit,
                ..._queryMap(),
              }),
              itemBuilder: (context, row) => _tile(context, row, canEdit, canDelete, everyone),
              sort: _sort,
              order: _order,
              onSort: (s, o) => setState(() {
                _sort = s;
                _order = o;
              }),
              onRowTap: (row) => _open(row),
              columns: [
                TableColumn(
                  label: tr('Title'),
                  sortKey: 'title',
                  flex: 2,
                  cell: (context, row) => Text('${row['title']}'),
                ),
                TableColumn(
                  label: tr('Project'),
                  flex: 1,
                  cell: (context, row) => Text(_nested(row, 'project')),
                ),
                if (everyone)
                  TableColumn(
                    label: tr('Assignee'),
                    flex: 1,
                    cell: (context, row) => Text(_nested(row, 'assignee')),
                  ),
                TableColumn(
                  label: tr('Priority'),
                  sortKey: 'priority',
                  width: 120,
                  cell: (context, row) => _priorityBadge(row),
                ),
                TableColumn(
                  label: tr('Status'),
                  sortKey: 'status',
                  width: 130,
                  cell: (context, row) => _statusBadge(row),
                ),
                TableColumn(
                  label: tr('Deadline'),
                  sortKey: 'deadline',
                  width: 130,
                  cell: (context, row) {
                    final has = '${row['deadline'] ?? ''}'.isNotEmpty;
                    if (!has) return const Text('—');
                    return Text(
                      formatDate(row['deadline']),
                      style: _overdue(row) ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
                    );
                  },
                ),
              ],
              rowActionsWidth: 48.0 * rowActionCount,
              rowActions: rowActionCount == 0
                  ? null
                  : (context, row) {
                      final next = _nextStatus(row);
                      return [
                        if (canEdit)
                          if (next != null)
                            IconButton(
                              tooltip: tr('Move to {status}', {'status': _statusLabel(next)}),
                              icon: const Icon(AppIcons.arrowForward),
                              onPressed: () => _setStatus(row, next),
                            )
                          else
                            const SizedBox(width: 48),
                        if (canEdit)
                          IconButton(
                            tooltip: tr('Edit'),
                            icon: const Icon(AppIcons.edit),
                            onPressed: () => _edit(row),
                          ),
                        if (canDelete)
                          IconButton(
                            tooltip: tr('Delete'),
                            icon: const Icon(AppIcons.delete),
                            onPressed: () => _delete(row),
                          ),
                      ];
                    },
            ),
          ),
        ],
      ),
    );
  }
}
