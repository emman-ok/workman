import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/widgets.dart';

class TeamsPage extends ConsumerStatefulWidget {
  const TeamsPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends ConsumerState<TeamsPage> {
  final PagedListController _controller = PagedListController();
  String _search = '';
  String _sort = 'name';
  String _order = 'asc';

  Future<dynamic> _fetch(int page, int limit) {
    return ref.read(apiClientProvider).get('/teams', query: {
      'page': page,
      'limit': limit,
      'search': _search,
      'sort': _sort,
      'order': _order,
    });
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Delete team'),
      message: tr('Delete {name}? Its members and project links will be removed.', {'name': row['name']}),
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiClientProvider).delete('/teams/${row['id']}');
      _controller.remove([row['id']]);
      if (!mounted) return;
      showSnack(context, tr('Team deleted'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _openNew() async {
    final result = await context.push<bool>('/teams/new');
    if (result == true) _controller.refresh();
  }

  Widget _row(BuildContext context, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final canDelete = ref.watch(authProvider).can('teams.delete');
    final memberCount = num.tryParse('${row['member_count']}')?.toInt() ?? 0;
    final projects = (row['projects'] is List) ? List<dynamic>.from(row['projects'] as List) : <dynamic>[];
    final names = [
      for (final p in projects)
        if (p is Map && p['name'] != null) '${p['name']}'
    ];
    final description = (row['description'] ?? '').toString().trim();
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return ListTile(
      onTap: () => context.push('/teams/${row['id']}'),
      title: Text('${row['name']}', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty) Text(description, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            names.isEmpty ? tr('No projects yet') : tr('Projects: {names}', {'names': names.join(', ')}),
            style: muted,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(memberCount == 1 ? tr('1 member') : tr('{count} members', {'count': memberCount})),
          if (canDelete)
            IconButton(
              tooltip: tr('Delete'),
              icon: Icon(AppIcons.delete, color: theme.colorScheme.error),
              onPressed: () => _delete(row),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(authProvider).can('teams.create');
    final query = Uri(queryParameters: {'search': _search, 'sort': _sort, 'order': _order}).query;

    return AppScaffold(
      title: tr('Teams'),
      actions: [
        SortMenu(
          fields: {
            'name': tr('Name'),
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
              tooltip: tr('New team'),
              onPressed: _openNew,
              child: Icon(AppIcons.add),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              ListSearchField(
                hint: tr('Search teams'),
                initialValue: _search,
                onChanged: (value) => setState(() => _search = value.trim()),
              ),
              Expanded(
                child: PagedList(
                  controller: _controller,
                  query: query,
                  fetch: _fetch,
                  itemBuilder: _row,
                  paging: Paging.loadMore,
                  refreshable: true,
                  sort: _sort,
                  order: _order,
                  emptyMessage: tr('No teams found.'),
                  emptyIcon: AppIcons.group,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
