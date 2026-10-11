import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/widgets.dart';

final _projectOptionsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/milestones/options/projects', query: {'limit': 100});
  final items = List<Map<String, dynamic>>.from((data as Map)['items'] as List);
  return {for (final p in items) '${p['id']}': '${p['name']}'};
});

class MilestonesPage extends ConsumerStatefulWidget {
  const MilestonesPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<MilestonesPage> createState() => _MilestonesPageState();
}

class _MilestonesPageState extends ConsumerState<MilestonesPage> {
  final PagedListController _controller = PagedListController();
  String _search = '';
  String _sort = 'due_date';
  String _order = 'asc';
  Map<String, String> _filters = {};

  @override
  void initState() {
    super.initState();
    _filters = {
      for (final f in const ['project_id', 'status'])
        if ((widget.params[f] ?? '').isNotEmpty) f: widget.params[f]!,
    };
  }

  Future<dynamic> _fetch(int page, int limit) {
    return ref.read(apiClientProvider).get('/milestones', query: {
      'page': page,
      'limit': limit,
      if (_search.isNotEmpty) 'search': _search,
      'sort': _sort,
      'order': _order,
      ..._filters,
    });
  }

  Future<void> _reach(Map<String, dynamic> row) async {
    try {
      await ref.read(apiClientProvider).patch('/milestones/${row['id']}/reach');
      if (!mounted) return;
      showSnack(context, tr('Milestone marked as reached'));
      _controller.refresh();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Delete milestone?'),
      message: tr('Delete {name}? This cannot be undone.', {'name': row['title']}),
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).delete('/milestones/${row['id']}');
      if (!mounted) return;
      _controller.remove([row['id']]);
      showSnack(context, tr('Milestone deleted'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _open(String path) async {
    final result = await context.push<bool>(path);
    if (result == true) _controller.refresh();
  }

  Widget _stateBadge(String state) {
    switch (state) {
      case 'done':
        return StatusBadge(tr('Done'), color: Colors.green);
      case 'late':
        return StatusBadge(tr('Late'), color: Colors.red);
      default:
        return StatusBadge(tr('Upcoming'), color: Colors.blue);
    }
  }

  Widget _row(BuildContext context, Map<String, dynamic> row) {
    final auth = ref.watch(authProvider);
    final canEdit = auth.can('milestones.edit');
    final canDelete = auth.can('milestones.delete');
    final state = '${row['state']}';
    final project = row['project'] is Map ? '${(row['project'] as Map)['name']}' : '';
    final theme = Theme.of(context);
    final subtitle = row['reached_at'] != null
        ? tr('{project} · Reached {date}', {'project': project, 'date': formatDate(row['reached_at'])})
        : tr('{project} · Due {date}', {'project': project, 'date': formatDate(row['due_date'])});
    final canReach = canEdit && state != 'done';
    final hasMenu = canReach || canDelete;
    return ListTile(
      title: Text('${row['title']}', style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      onTap: canEdit ? () => _open('/milestones/${row['id']}/edit') : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stateBadge(state),
          if (hasMenu)
            PopupMenuButton<String>(
              icon: Icon(AppIcons.moreVert),
              onSelected: (v) {
                if (v == 'reach') {
                  _reach(row);
                } else if (v == 'delete') {
                  _delete(row);
                }
              },
              itemBuilder: (_) => [
                if (canReach) PopupMenuItem<String>(value: 'reach', child: Text(tr('Mark as reached'))),
                if (canDelete) PopupMenuItem<String>(value: 'delete', child: Text(tr('Delete'))),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final projects = ref.watch(_projectOptionsProvider).valueOrNull ?? <String, String>{};
    final query = Uri(queryParameters: {
      if (_search.isNotEmpty) 'search': _search,
      'sort': _sort,
      'order': _order,
      ..._filters,
    }).query;

    return AppScaffold(
      title: tr('Milestones'),
      actions: [
        SortMenu(
          fields: {
            'due_date': tr('Due date'),
            'title': tr('Title'),
            'status': tr('Status'),
          },
          sort: _sort,
          order: _order,
          onChanged: (sort, order) => setState(() {
            _sort = sort;
            _order = order;
          }),
        ),
      ],
      floatingActionButton: auth.can('milestones.create')
          ? FloatingActionButton(
              onPressed: () => _open('/milestones/new'),
              child: Icon(AppIcons.add),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              ListSearchField(
                hint: tr('Search milestones'),
                initialValue: _search,
                onChanged: (v) => setState(() => _search = v),
              ),
              FilterBar(
                filters: [
                  ListFilter(field: 'project_id', label: tr('Project'), options: projects),
                  ListFilter(
                    field: 'status',
                    label: tr('Status'),
                    options: {
                      'done': tr('Done'),
                      'upcoming': tr('Upcoming'),
                      'late': tr('Late'),
                    },
                  ),
                ],
                values: _filters,
                onChanged: (v) => setState(() => _filters = v),
              ),
              Expanded(
                child: PagedList(
                  controller: _controller,
                  query: query,
                  paging: Paging.loadMore,
                  refreshable: true,
                  skeleton: false,
                  fetch: _fetch,
                  itemBuilder: _row,
                  emptyMessage: tr('No milestones found.'),
                  emptyIcon: AppIcons.flag,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
