import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/widgets.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  final PagedListController _controller = PagedListController();
  String _search = '';
  String _sort = 'created_at';
  String _order = 'desc';
  Map<String, String> _filters = {};

  @override
  void initState() {
    super.initState();
    _filters = {
      for (final f in const ['status', 'priority'])
        if ((widget.params[f] ?? '').isNotEmpty) f: widget.params[f]!,
    };
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'planning':
        return tr('Planning');
      case 'active':
        return tr('Active');
      case 'on_hold':
        return tr('On hold');
      case 'completed':
        return tr('Completed');
      case 'cancelled':
        return tr('Cancelled');
      default:
        return status;
    }
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'low':
        return tr('Low');
      case 'medium':
        return tr('Medium');
      case 'high':
        return tr('High');
      case 'urgent':
        return tr('Urgent');
      default:
        return priority;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'planning':
        return Colors.blue;
      case 'on_hold':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _statusBadge(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    if (status.isEmpty) return const SizedBox.shrink();
    return StatusBadge(_statusLabel(status), color: _statusColor(status));
  }

  Widget _priorityBadge(Map<String, dynamic> row) {
    final priority = '${row['priority'] ?? ''}';
    if (priority.isEmpty) return const SizedBox.shrink();
    return StatusBadge(_priorityLabel(priority), color: _priorityColor(priority));
  }

  String _managerName(Map<String, dynamic> row) {
    final manager = row['manager'];
    if (manager is Map) return '${manager['name'] ?? ''}';
    return '';
  }

  String _deadlineText(Map<String, dynamic> row) {
    if (row['deadline'] == null) return '';
    return formatDate(row['deadline']);
  }

  num _progress(Map<String, dynamic> row) {
    return num.tryParse('${row['progress'] ?? 0}') ?? 0;
  }

  String _progressText(Map<String, dynamic> row) {
    final total = num.tryParse('${row['task_count'] ?? 0}') ?? 0;
    if (total == 0) return tr('No tasks yet');
    final done = num.tryParse('${row['done_count'] ?? 0}') ?? 0;
    return tr('{done} of {total} tasks done ({percent}%)', {
      'done': done,
      'total': total,
      'percent': _progress(row),
    });
  }

  Future<dynamic> _fetch(int page, int limit) {
    return ref.read(apiClientProvider).get('/projects', query: {
      'page': page,
      'limit': limit,
      if (_search.isNotEmpty) 'search': _search,
      'sort': _sort,
      'order': _order,
      ..._filters,
    });
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Delete project?'),
      message: tr('Delete {name}? This cannot be undone.', {'name': row['name']}),
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).delete('/projects/${row['id']}');
      _controller.remove([row['id']]);
      if (!mounted) return;
      showSnack(context, tr('Project deleted'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await context.push('/projects/${row['id']}/edit');
    if (result == true) _controller.refresh();
  }

  Future<void> _create() async {
    final result = await context.push('/projects/new');
    if (result == true) _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final canCreate = auth.can('projects.create');
    final canEdit = auth.can('projects.edit');
    final canDelete = auth.can('projects.delete');

    final query = Uri(queryParameters: {
      'search': _search,
      'sort': _sort,
      'order': _order,
      ..._filters,
    }).query;

    final actionCount = (canEdit ? 1 : 0) + (canDelete ? 1 : 0);

    return AppScaffold(
      title: tr('Projects'),
      actions: [
        ExportButton(page: 'projects', query: {
          'search': _search,
          'sort': _sort,
          'order': _order,
          ..._filters,
        }),
        SortMenu(
          fields: {
            'name': tr('Name'),
            'deadline': tr('Deadline'),
            'status': tr('Status'),
            'created_at': tr('Created'),
          },
          sort: _sort,
          order: _order,
          onChanged: (sort, order) => setState(() {
            _sort = sort;
            _order = order;
          }),
        ),
      ],
      floatingActionButton: canCreate
          ? FloatingActionButton(
              tooltip: tr('New project'),
              onPressed: _create,
              child: const Icon(AppIcons.add),
            )
          : null,
      body: Column(
        children: [
          ListSearchField(
            hint: tr('Search projects'),
            onChanged: (value) => setState(() => _search = value),
          ),
          FilterBar(
            filters: [
              ListFilter(
                field: 'status',
                label: tr('Status'),
                options: {
                  'planning': tr('Planning'),
                  'active': tr('Active'),
                  'on_hold': tr('On hold'),
                  'completed': tr('Completed'),
                  'cancelled': tr('Cancelled'),
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
            ],
            values: _filters,
            onChanged: (v) => setState(() => _filters = v),
          ),
          Expanded(
            child: PagedList(
              controller: _controller,
              paging: Paging.pages,
              refreshable: true,
              skeleton: false,
              query: query,
              fetch: _fetch,
              emptyMessage: tr('No projects found.'),
              emptyIcon: AppIcons.folder,
              sort: _sort,
              order: _order,
              onSort: (sort, order) => setState(() {
                _sort = sort;
                _order = order;
              }),
              onRowTap: (row) => context.push('/projects/${row['id']}'),
              rowActionsWidth: actionCount == 0 ? 96 : 48.0 * actionCount,
              rowActions: actionCount == 0
                  ? null
                  : (context, row) => [
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
                      ],
              columns: [
                TableColumn(
                  label: tr('Name'),
                  sortKey: 'name',
                  flex: 2,
                  cell: (context, row) => Text('${row['name'] ?? ''}'),
                ),
                TableColumn(
                  label: tr('Status'),
                  sortKey: 'status',
                  width: 130,
                  cell: (context, row) => _statusBadge(row),
                ),
                TableColumn(
                  label: tr('Priority'),
                  width: 120,
                  cell: (context, row) => _priorityBadge(row),
                ),
                TableColumn(
                  label: tr('Manager'),
                  flex: 1,
                  cell: (context, row) {
                    final name = _managerName(row);
                    return Text(name.isEmpty ? '-' : name);
                  },
                ),
                TableColumn(
                  label: tr('Deadline'),
                  sortKey: 'deadline',
                  width: 130,
                  cell: (context, row) {
                    final text = _deadlineText(row);
                    return Text(text.isEmpty ? '-' : text);
                  },
                ),
                TableColumn(
                  label: tr('Progress'),
                  numeric: true,
                  width: 110,
                  cell: (context, row) => Text('${_progress(row)}%'),
                ),
              ],
              itemBuilder: (context, row) {
                final theme = Theme.of(context);
                final parts = <String>[];
                final manager = _managerName(row);
                if (manager.isNotEmpty) parts.add(manager);
                final deadline = _deadlineText(row);
                if (deadline.isNotEmpty) {
                  parts.add(tr('Due {date}', {'date': deadline}));
                }
                final priority = '${row['priority'] ?? ''}';
                if (priority.isNotEmpty) {
                  parts.add(tr('{priority} priority', {'priority': _priorityLabel(priority)}));
                }
                parts.add(_progressText(row));
                return ListTile(
                  title: Text(
                    '${row['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    parts.join(' · '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: _statusBadge(row),
                  onTap: () => context.push('/projects/${row['id']}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
