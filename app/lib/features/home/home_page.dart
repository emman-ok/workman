import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/widgets.dart';

final _homeProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.watch(dataVersionProvider);
  final range = ref.watch(dateRangeProvider);
  final data = await ref.watch(apiClientProvider).get('/home', query: range.query);
  return Map<String, dynamic>.from(data as Map);
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_homeProvider);
    return AppScaffold(
      title: tr('Dashboard'),
      actions: [
        IconButton(
          tooltip: tr('Refresh'),
          icon: const Icon(AppIcons.refresh),
          onPressed: () => ref.invalidate(_homeProvider),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(_homeProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const QuickActions(),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: DateRangeControl(),
                    ),
                    const SizedBox(height: 12),
                    async.when(
                      skipLoadingOnRefresh: false,
                      data: (d) => _Content(data: d),
                      loading: () => const _Content(data: null),
                      error: (e, _) => SizedBox(
                        height: 320,
                        child: ErrorView(
                          message: errorMessage(e),
                          onRetry: () => ref.invalidate(_homeProvider),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _rows(Map<String, dynamic>? d, String key) {
  if (d == null) return [];
  final v = d[key];
  if (v is! List) return [];
  return [for (final e in v) Map<String, dynamic>.from(e as Map)];
}

num? _val(Map<String, dynamic>? d, String key, [String field = 'value']) {
  if (d == null) return null;
  final m = d[key];
  if (m is! Map) return null;
  return num.tryParse('${m[field]}');
}

String _statusLabel(dynamic s) {
  switch ('$s') {
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
    case 'todo':
      return tr('To do');
    case 'in_progress':
      return tr('In progress');
    case 'done':
      return tr('Done');
    case 'pending':
      return tr('Pending');
    case 'reached':
      return tr('Reached');
    case 'late':
      return tr('Late');
    default:
      return '$s'.replaceAll('_', ' ');
  }
}

String _priorityLabel(dynamic p) {
  switch ('$p') {
    case 'low':
      return tr('Low');
    case 'medium':
      return tr('Medium');
    case 'high':
      return tr('High');
    case 'urgent':
      return tr('Urgent');
    case 'critical':
      return tr('Critical');
    default:
      return '$p'.replaceAll('_', ' ');
  }
}

bool _isPast(dynamic v) {
  final d = DateTime.tryParse('$v');
  if (d == null) return false;
  final n = DateTime.now();
  return d.isBefore(DateTime(n.year, n.month, n.day));
}

String _name(dynamic m) {
  if (m is Map) return '${m['name'] ?? ''}';
  return '';
}

class _Content extends ConsumerWidget {
  const _Content({required this.data});
  final Map<String, dynamic>? data;

  Widget _twoUp(Widget a, Widget b) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a, const SizedBox(height: 16), b],
      );
    });
  }

  Widget _listCard(
    BuildContext context, {
    required String title,
    required bool loading,
    required List<Map<String, dynamic>> rows,
    required String empty,
    required Widget Function(Map<String, dynamic> r) tile,
  }) {
    final theme = Theme.of(context);
    Widget body;
    if (loading) {
      body = const SkeletonList(count: 4);
    } else if (rows.isEmpty) {
      body = AppSurface(
        child: Text(empty, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    } else {
      body = AppSurface(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [for (final r in rows) tile(r)]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        body,
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(authProvider);
    final canProjects = auth.can('projects.view');
    final canTasks = auth.can('tasks.view');
    final canMilestones = auth.can('milestones.view');
    final d = data;
    final loading = d == null;

    final overdue = _val(d, 'overdueTasks');
    final byDay = _rows(d, 'completedByDay');
    final trend = [for (final r in byDay) r['count']];

    final cards = <Widget>[
      StatCard(
        label: tr('Active projects'),
        value: _val(d, 'activeProjects'),
        icon: AppIcons.folder,
        loading: loading,
        onTap: canProjects ? () => context.push('/projects?status=active') : null,
      ),
      StatCard(
        label: tr('Open tasks'),
        value: _val(d, 'openTasks'),
        icon: AppIcons.checklist,
        loading: loading,
        onTap: canTasks ? () => context.push('/tasks') : null,
      ),
      StatCard(
        label: tr('Overdue tasks'),
        value: overdue,
        icon: AppIcons.warning,
        color: (overdue ?? 0) > 0 ? scheme.error : null,
        loading: loading,
        onTap: canTasks ? () => context.push('/tasks') : null,
      ),
      StatCard(
        label: tr('Tasks completed'),
        value: _val(d, 'completedTasks'),
        previous: _val(d, 'completedTasks', 'previous'),
        trend: trend.length > 1 ? trend : null,
        icon: AppIcons.checkCircle,
        loading: loading,
        onTap: canTasks ? () => context.push('/tasks?status=done') : null,
      ),
    ];

    final statusRows = _rows(d, 'projectsByStatus');
    final priorityRows = _rows(d, 'tasksByPriority');

    final projectChart = ChartCard(
      title: tr('Projects by status'),
      child: loading
          ? const Skeleton(child: SkeletonBox(height: 220))
          : AppPieChart(
              slices: [
                for (final r in statusRows)
                  ChartSlice(label: _statusLabel(r['status']), value: r['count']),
              ],
              totalLabel: tr('Projects'),
              onTap: canProjects
                  ? (i) {
                      if (i >= 0 && i < statusRows.length) {
                        context.push('/projects?status=${statusRows[i]['status']}');
                      }
                    }
                  : null,
            ),
    );

    final taskChart = ChartCard(
      title: tr('Tasks by priority'),
      child: loading
          ? const Skeleton(child: SkeletonBox(height: 220))
          : AppBarChart(
              labels: [for (final r in priorityRows) _priorityLabel(r['priority'])],
              series: [
                ChartSeries(
                  label: tr('Tasks'),
                  values: [for (final r in priorityRows) r['count']],
                ),
              ],
              horizontal: true,
              onTap: canTasks
                  ? (i) {
                      if (i >= 0 && i < priorityRows.length) {
                        context.push('/tasks?priority=${priorityRows[i]['priority']}');
                      }
                    }
                  : null,
            ),
    );

    final projectList = _listCard(
      context,
      title: tr('Project deadlines'),
      loading: loading,
      rows: _rows(d, 'projectDeadlines'),
      empty: tr('No project deadlines.'),
      tile: (r) => ListTile(
        title: Text('${r['name'] ?? ''}', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_statusLabel(r['status'])} · ${_priorityLabel(r['priority'])}',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: Text(
          formatDate(r['deadline']),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _isPast(r['deadline']) ? scheme.error : null,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: canProjects ? () => context.push('/projects/${r['id']}') : null,
      ),
    );

    final taskList = _listCard(
      context,
      title: tr('Task deadlines'),
      loading: loading,
      rows: _rows(d, 'taskDeadlines'),
      empty: tr('No task deadlines.'),
      tile: (r) {
        final project = _name(r['project']);
        final status = _statusLabel(r['status']);
        return ListTile(
          title: Text('${r['title'] ?? ''}', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            project.isEmpty ? status : '$project · $status',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            formatDate(r['deadline']),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _isPast(r['deadline']) ? scheme.error : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: canTasks ? () => context.push('/tasks/${r['id']}') : null,
        );
      },
    );

    final milestoneList = _listCard(
      context,
      title: tr('Upcoming milestones'),
      loading: loading,
      rows: _rows(d, 'upcomingMilestones'),
      empty: tr('No upcoming milestones.'),
      tile: (r) {
        final late = _isPast(r['due_date']);
        return ListTile(
          leading: const Icon(AppIcons.flag),
          title: Text('${r['title'] ?? ''}', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            _name(r['project']),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatDate(r['due_date']),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: late ? scheme.error : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (late) Text(tr('Late'), style: theme.textTheme.labelSmall?.copyWith(color: scheme.error)),
            ],
          ),
          onTap: canMilestones ? () => context.push('/milestones') : null,
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 4 : 2;
          final w = (c.maxWidth - 12 * (cols - 1)) / cols;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final card in cards) SizedBox(width: w, child: card)],
          );
        }),
        const SizedBox(height: 16),
        _twoUp(projectChart, taskChart),
        const SizedBox(height: 16),
        _twoUp(projectList, taskList),
        const SizedBox(height: 16),
        milestoneList,
        const SizedBox(height: 16),
      ],
    );
  }
}
