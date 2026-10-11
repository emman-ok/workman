import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/uploads.dart';
import 'package:app/core/widgets.dart';
import '../../plugins/record_ownership/record_ownership.dart';

final taskDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/task_detail/$id');
  return Map<String, dynamic>.from(data as Map);
});

String _statusLabel(String status) => switch (status) {
      'todo' => tr('To do'),
      'in_progress' => tr('In progress'),
      'done' => tr('Done'),
      _ => status,
    };

Color _statusColor(String status) => switch (status) {
      'todo' => Colors.grey,
      'in_progress' => Colors.blue,
      'done' => Colors.green,
      _ => Colors.grey,
    };

String _priorityLabel(String priority) => switch (priority) {
      'low' => tr('Low'),
      'medium' => tr('Medium'),
      'high' => tr('High'),
      'urgent' => tr('Urgent'),
      'critical' => tr('Critical'),
      _ => priority,
    };

Color _priorityColor(String priority) => switch (priority) {
      'low' => Colors.grey,
      'medium' => Colors.blue,
      'high' => Colors.orange,
      'urgent' => Colors.red,
      'critical' => Colors.red,
      _ => Colors.grey,
    };

class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  final _comment = TextEditingController();
  bool _sending = false;
  bool _changing = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _setStatus(int id, String status) async {
    setState(() => _changing = true);
    try {
      await ref.read(apiClientProvider).patch('/task_detail/$id/status', data: {'status': status});
      ref.invalidate(taskDetailProvider('$id'));
      if (!mounted) return;
      showSnack(context, tr('Status updated'));
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _sendComment(int id) async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).post('/task_detail/$id/comments', data: {'body': text});
      _comment.clear();
      ref.invalidate(taskDetailProvider('$id'));
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(int id, int commentId) async {
    final ok = await showConfirmDialog(context, title: tr('Delete comment?'), message: tr('This cannot be undone.'));
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).delete('/task_detail/$id/comments/$commentId');
      ref.invalidate(taskDetailProvider('$id'));
      if (!mounted) return;
      showSnack(context, tr('Comment deleted'));
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(widget.params['id'] ?? '');
    if (id == null) {
      return AppScaffold(title: tr('Task Details'), body: ErrorView(message: tr('Task not found.')));
    }
    final provider = taskDetailProvider('$id');
    final async = ref.watch(provider);
    final auth = ref.watch(authProvider);
    final canEdit = auth.can('task_detail.edit');
    final isManager = canEdit && seesEveryone(auth, 'task_detail', 'tasks');

    return AppScaffold(
      title: tr('Task Details'),
      actions: [
        if (isManager)
          IconButton(
            icon: Icon(AppIcons.edit),
            tooltip: tr('Edit'),
            onPressed: () async {
              final result = await context.push<bool>('/tasks/$id/edit');
              if (result == true && mounted) ref.invalidate(provider);
            },
          ),
      ],
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: errorMessage(e), onRetry: () => ref.invalidate(provider)),
        data: (task) => _buildBody(context, id, task, auth, canEdit),
      ),
    );
  }

  Widget _buildBody(BuildContext context, int id, Map<String, dynamic> task, AuthState auth, bool canEdit) {
    final theme = Theme.of(context);
    final provider = taskDetailProvider('$id');
    final status = '${task['status'] ?? ''}';
    final priority = '${task['priority'] ?? ''}';
    final project = task['project'] as Map?;
    final milestone = task['milestone'] as Map?;
    final assignee = task['assignee'] as Map?;
    final creator = task['createdByRef'] as Map?;
    final comments = [
      for (final c in (task['comments'] as List? ?? const [])) Map<String, dynamic>.from(c as Map),
    ];

    final projectName = project == null ? null : '${project['name'] ?? ''}';
    final milestoneTitle = milestone == null ? null : '${milestone['title'] ?? ''}';
    final assigneeName = assignee == null ? null : '${assignee['name'] ?? ''}';
    final creatorName = creator == null ? null : '${creator['name'] ?? ''}';

    final deadlineRaw = task['deadline'];
    final deadline = deadlineRaw == null ? null : DateTime.tryParse('$deadlineRaw');
    int? daysLeft;
    if (deadline != null) {
      final now = DateTime.now();
      daysLeft = DateTime(deadline.year, deadline.month, deadline.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
    }
    final open = status != 'done';

    final stats = <DetailStat>[
      DetailStat(tr('Comments'), '${comments.length}', icon: AppIcons.comment),
      if (daysLeft != null && open && daysLeft >= 0) DetailStat(tr('Days left'), '$daysLeft', icon: AppIcons.schedule),
      if (daysLeft != null && open && daysLeft < 0) DetailStat(tr('Days overdue'), '${-daysLeft}', icon: AppIcons.warning),
    ];

    final canViewProject = auth.can('project_detail.view');
    final canDeleteComment = auth.can('task_detail.delete');

    return DetailView(
      onRefresh: () async {
        ref.invalidate(provider);
        await ref.read(provider.future);
      },
      children: [
        DetailHeader(
          title: '${task['title'] ?? ''}',
          subtitle: projectName,
          icon: AppIcons.task,
          badge: StatusBadge(_statusLabel(status), color: _statusColor(status)),
          stats: stats,
        ),
        if (canEdit)
          AppSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Status'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: [
                      ButtonSegment(value: 'todo', label: Text(tr('To do'))),
                      ButtonSegment(value: 'in_progress', label: Text(tr('In progress'))),
                      ButtonSegment(value: 'done', label: Text(tr('Done'))),
                    ],
                    selected: {
                      if (status == 'todo' || status == 'in_progress' || status == 'done') status,
                    },
                    onSelectionChanged: _changing
                        ? null
                        : (selection) {
                            if (selection.isEmpty) return;
                            final next = selection.first;
                            if (next != status) _setStatus(id, next);
                          },
                  ),
                ),
              ],
            ),
          ),
        DetailSection(
          title: tr('Overview'),
          icon: AppIcons.info,
          fields: [
            DetailField(tr('Description'), task['description'], wide: true),
            DetailField(
              tr('Project'),
              projectName,
              onTap: (canViewProject && project != null) ? () => context.push('/projects/${project['id']}') : null,
            ),
            DetailField(tr('Milestone'), milestoneTitle),
          ],
        ),
        DetailSection(
          title: tr('Planning'),
          icon: AppIcons.calendar,
          fields: [
            DetailField(
              tr('Priority'),
              priority.isEmpty ? null : _priorityLabel(priority),
              child: priority.isEmpty ? null : StatusBadge(_priorityLabel(priority), color: _priorityColor(priority)),
            ),
            DetailField(tr('Deadline'), deadlineRaw == null ? null : formatDate(deadlineRaw)),
            DetailField(tr('Assignee'), assigneeName),
            DetailField(tr('Created by'), creatorName),
            DetailField(tr('Created'), task['created_at'] == null ? null : formatDateTime(task['created_at'])),
            DetailField(tr('Completed'), task['completed_at'] == null ? null : formatDateTime(task['completed_at'])),
          ],
        ),
        AppSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Comments'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (comments.isEmpty)
                EmptyView(message: tr('No comments yet. Start the conversation.'), icon: AppIcons.chat)
              else
                for (final c in comments) _commentTile(context, id, c, canDeleteComment),
              if (canEdit) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comment,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(hintText: tr('Write a comment')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: tr('Send'),
                      icon: Icon(AppIcons.send),
                      onPressed: _sending ? null : () => _sendComment(id),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _commentTile(BuildContext context, int taskId, Map<String, dynamic> c, bool canDelete) {
    final theme = Theme.of(context);
    final user = c['user'] as Map?;
    final name = user == null ? tr('Unknown user') : '${user['name'] ?? ''}';
    final commentId = int.tryParse('${c['id']}');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AppImage(user?['photo'], width: 40, height: 40, circle: true, preview: false),
      title: Text(name, style: theme.textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c['body'] ?? ''}', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(
            c['created_at'] == null ? '' : formatDateTime(c['created_at']),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: (canDelete && commentId != null)
          ? IconButton(
              tooltip: tr('Delete'),
              icon: Icon(AppIcons.delete),
              onPressed: () => _deleteComment(taskId, commentId),
            )
          : null,
    );
  }
}
