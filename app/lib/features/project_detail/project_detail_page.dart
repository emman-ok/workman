import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/widgets.dart';
import 'package:app/features/project_detail/project_detail_provider.dart';

const _statuses = ['planned', 'active', 'on_hold', 'completed'];
const _taskDone = ['done', 'completed'];
const _milestoneDone = ['reached', 'completed', 'done'];

String _human(String v) {
  if (v.isEmpty) return v;
  final s = v.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

String _statusLabel(String s) => switch (s) {
      'planned' => tr('Planned'),
      'active' => tr('Active'),
      'on_hold' => tr('On hold'),
      'completed' => tr('Completed'),
      _ => _human(s),
    };

Color _statusColor(String s) => switch (s) {
      'planned' => Colors.blue,
      'active' => Colors.green,
      'on_hold' => Colors.orange,
      'completed' => Colors.grey,
      _ => Colors.grey,
    };

String _priorityLabel(String s) => switch (s) {
      'low' => tr('Low'),
      'medium' => tr('Medium'),
      'high' => tr('High'),
      'urgent' => tr('Urgent'),
      _ => _human(s),
    };

Color _priorityColor(String s) => switch (s) {
      'low' => Colors.grey,
      'medium' => Colors.blue,
      'high' => Colors.orange,
      'urgent' => Colors.red,
      'critical' => Colors.red,
      _ => Colors.grey,
    };

String _taskStatusLabel(String s) => switch (s) {
      'todo' => tr('To do'),
      'to_do' => tr('To do'),
      'in_progress' => tr('In progress'),
      'done' => tr('Done'),
      'completed' => tr('Done'),
      _ => _human(s),
    };

Color _taskStatusColor(String s) {
  if (_taskDone.contains(s)) return Colors.green;
  if (s == 'in_progress') return Colors.blue;
  return Colors.grey;
}

DateTime? _date(dynamic v) {
  final text = '${v ?? ''}';
  if (text.isEmpty) return null;
  final d = DateTime.tryParse(text);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

List<Map<String, dynamic>> _rows(dynamic v) {
  if (v is! List) return [];
  return [for (final e in v) Map<String, dynamic>.from(e as Map)];
}

bool _milestoneReached(Map<String, dynamic> m) {
  return m['reached_at'] != null || _milestoneDone.contains('${m['status']}');
}

class ProjectDetailPage extends ConsumerWidget {
  const ProjectDetailPage({super.key, this.params = const {}});
  final Map<String, String> params;

  Future<void> _setStatus(BuildContext context, WidgetRef ref, int id, String status) async {
    try {
      await ref.read(apiClientProvider).patch('/project_detail/$id/status', data: {'status': status});
      ref.invalidate(projectDetailProvider(id));
      if (!context.mounted) return;
      showSnack(context, tr('Status updated'));
    } catch (e) {
      if (!context.mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref, int id, String route) async {
    final result = await context.push<bool>(route);
    if (result == true) ref.invalidate(projectDetailProvider(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(params['id'] ?? '');
    if (id == null) {
      return AppScaffold(
        title: tr('Project'),
        body: EmptyView(message: tr('Project not found.'), icon: AppIcons.folder),
      );
    }
    final async = ref.watch(projectDetailProvider(id));
    final auth = ref.watch(authProvider);
    final canEdit = auth.can('project_detail.edit');
    final project = async.valueOrNull;

    return AppScaffold(
      title: project != null ? '${project['name']}' : tr('Project'),
      actions: [
        if (project != null && canEdit)
          PopupMenuButton<String>(
            icon: Icon(AppIcons.flag),
            tooltip: tr('Change status'),
            onSelected: (s) => _setStatus(context, ref, id, s),
            itemBuilder: (ctx) => [
              for (final s in _statuses)
                CheckedPopupMenuItem<String>(
                  value: s,
                  checked: s == '${project['status']}',
                  child: Text(_statusLabel(s)),
                ),
            ],
          ),
        if (project != null && canEdit)
          IconButton(
            icon: Icon(AppIcons.edit),
            tooltip: tr('Edit'),
            onPressed: () => _open(context, ref, id, '/projects/$id/edit'),
          ),
      ],
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: errorMessage(e),
          onRetry: () => ref.invalidate(projectDetailProvider(id)),
        ),
        data: (p) => _buildBody(context, ref, id, p, canEdit),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, int id, Map<String, dynamic> p, bool canEdit) {
    final auth = ref.watch(authProvider);
    final stats = p['stats'] is Map ? Map<String, dynamic>.from(p['stats'] as Map) : <String, dynamic>{};
    final status = '${p['status'] ?? ''}';
    final priority = '${p['priority'] ?? ''}';
    final manager = p['manager'] is Map ? Map<String, dynamic>.from(p['manager'] as Map) : null;
    final tasks = _rows(p['tasks']);
    final milestones = _rows(p['milestones']);
    final teams = _rows(p['teams']);

    final taskTotal = int.tryParse('${stats['task_total'] ?? 0}') ?? 0;
    final tasksDone = int.tryParse('${stats['tasks_done'] ?? 0}') ?? 0;
    final tasksOverdue = int.tryParse('${stats['tasks_overdue'] ?? 0}') ?? 0;
    final milestoneTotal = int.tryParse('${stats['milestone_total'] ?? 0}') ?? 0;
    final teamTotal = int.tryParse('${stats['team_total'] ?? 0}') ?? 0;
    final progress = int.tryParse('${stats['progress'] ?? 0}') ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deadline = _date(p['deadline']);
    final completed = status == 'completed';

    final canOpenTasks = auth.can('tasks.view');
    final canOpenTask = auth.can('task_detail.view');
    final canOpenMilestones = auth.can('milestones.view');
    final canOpenTeam = auth.can('team_detail.view');
    final textTheme = Theme.of(context).textTheme;

    final detailStats = <DetailStat>[
      DetailStat(tr('Progress'), '$progress%'),
      DetailStat(
        tr('Tasks'),
        '$tasksDone/$taskTotal',
        onTap: canOpenTasks ? () => context.push('/tasks?project_id=$id') : null,
      ),
      DetailStat(tr('Overdue tasks'), '$tasksOverdue'),
      if (deadline != null && !completed)
        DetailStat(
          tr('Days left'),
          deadline.isBefore(today) ? tr('Overdue') : '${deadline.difference(today).inDays}',
        ),
    ];

    return DetailView(
      onRefresh: () async {
        ref.invalidate(projectDetailProvider(id));
        await ref.read(projectDetailProvider(id).future);
      },
      children: [
        DetailHeader(
          title: '${p['name']}',
          subtitle: manager != null ? tr('Managed by {name}', {'name': manager['name']}) : null,
          icon: AppIcons.folder,
          badge: StatusBadge(_statusLabel(status), color: _statusColor(status)),
          stats: detailStats,
          actions: [
            if (canEdit)
              FilledButton(
                onPressed: () => _open(context, ref, id, '/tasks/new?project_id=$id'),
                child: Text(tr('Add task')),
              ),
            if (canEdit)
              OutlinedButton(
                onPressed: () => _open(context, ref, id, '/milestones/new?project_id=$id'),
                child: Text(tr('Add milestone')),
              ),
          ],
        ),
        DetailSection(
          title: tr('Overview'),
          icon: AppIcons.info,
          fields: [
            DetailField(tr('Status'), _statusLabel(status), child: StatusBadge(_statusLabel(status), color: _statusColor(status))),
            DetailField(
              tr('Priority'),
              priority.isEmpty ? null : _priorityLabel(priority),
              child: priority.isEmpty ? null : StatusBadge(_priorityLabel(priority), color: _priorityColor(priority)),
            ),
            DetailField(tr('Manager'), manager?['name']),
            DetailField(tr('Progress'), tr('{done} of {total} tasks done', {'done': tasksDone, 'total': taskTotal})),
            DetailField(tr('Description'), p['description'], wide: true),
          ],
        ),
        DetailSection(
          title: tr('Dates'),
          icon: AppIcons.calendar,
          fields: [
            DetailField(tr('Start date'), p['start_date'] == null ? null : formatDate(p['start_date'])),
            DetailField(tr('Deadline'), p['deadline'] == null ? null : formatDate(p['deadline'])),
            DetailField(tr('Created'), p['created_at'] == null ? null : formatDateTime(p['created_at'])),
            DetailField(tr('Last updated'), p['updated_at'] == null ? null : formatDateTime(p['updated_at'])),
          ],
        ),
        DetailTabs(
          tabs: [
            DetailTab(
              label: tr('Tasks'),
              count: taskTotal,
              icon: AppIcons.task,
              builder: (ctx) {
                if (tasks.isEmpty) {
                  return EmptyView(message: tr('No tasks yet.'), icon: AppIcons.task);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in tasks)
                      ListTile(
                        title: Text('${t['title']}', style: textTheme.titleMedium),
                        subtitle: Text(_taskSubtitle(t)),
                        trailing: StatusBadge(
                          _taskStatusLabel('${t['status']}'),
                          color: _taskStatusColor('${t['status']}'),
                        ),
                        onTap: canOpenTask ? () => ctx.push('/tasks/${t['id']}') : null,
                      ),
                    if (taskTotal > tasks.length && canOpenTasks)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => ctx.push('/tasks?project_id=$id'),
                          child: Text(tr('View all')),
                        ),
                      ),
                  ],
                );
              },
            ),
            DetailTab(
              label: tr('Milestones'),
              count: milestoneTotal,
              icon: AppIcons.flag,
              builder: (ctx) {
                if (milestones.isEmpty) {
                  return EmptyView(message: tr('No milestones yet.'), icon: AppIcons.flag);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in milestones)
                      ListTile(
                        title: Text('${m['title']}', style: textTheme.titleMedium),
                        subtitle: Text(m['due_date'] == null ? tr('No due date') : tr('Due {date}', {'date': formatDate(m['due_date'])})),
                        trailing: _milestoneBadge(m, today),
                      ),
                    if (milestoneTotal > milestones.length && canOpenMilestones)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () => ctx.push('/milestones'),
                          child: Text(tr('View all')),
                        ),
                      ),
                  ],
                );
              },
            ),
            DetailTab(
              label: tr('Teams'),
              count: teamTotal,
              icon: AppIcons.group,
              builder: (ctx) {
                if (teams.isEmpty) {
                  return EmptyView(message: tr('No teams assigned yet.'), icon: AppIcons.group);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in teams)
                      ListTile(
                        leading: Icon(AppIcons.group),
                        title: Text('${t['name']}', style: textTheme.titleMedium),
                        subtitle: (t['description'] == null || '${t['description']}'.isEmpty)
                            ? null
                            : Text('${t['description']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: canOpenTeam ? () => ctx.push('/teams/${t['id']}') : null,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  String _taskSubtitle(Map<String, dynamic> t) {
    final assignee = t['assignee'] is Map ? (t['assignee'] as Map)['name'] : null;
    final parts = <String>[
      assignee != null ? '$assignee' : tr('Unassigned'),
      if (t['deadline'] != null) tr('Due {date}', {'date': formatDate(t['deadline'])}),
    ];
    return parts.join(' · ');
  }

  Widget _milestoneBadge(Map<String, dynamic> m, DateTime today) {
    if (_milestoneReached(m)) {
      return StatusBadge(tr('Reached'), color: Colors.green);
    }
    final due = _date(m['due_date']);
    if (due != null && due.isBefore(today)) {
      return StatusBadge(tr('Late'), color: Colors.red);
    }
    return StatusBadge(tr('Upcoming'), color: Colors.blue);
  }
}
