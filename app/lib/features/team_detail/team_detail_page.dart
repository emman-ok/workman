import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/uploads.dart';
import 'package:app/core/widgets.dart';

final teamDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/team_detail/$id');
  return Map<String, dynamic>.from(data as Map);
});

String _roleLabel(String role) {
  switch (role) {
    case 'admin':
      return tr('Admin');
    case 'project_manager':
      return tr('Project manager');
    case 'team_member':
      return tr('Team member');
    default:
      return role;
  }
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
    case 'archived':
      return tr('Archived');
    default:
      return status;
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

class TeamDetailPage extends ConsumerWidget {
  const TeamDetailPage({super.key, this.params = const {}});
  final Map<String, String> params;

  Future<void> _add(BuildContext context, WidgetRef ref, int teamId, bool member) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _PickDialog(
        title: member ? tr('Add member') : tr('Add project'),
        label: member ? tr('Person') : tr('Project'),
        path: member ? '/team_detail/options/users' : '/team_detail/options/projects',
        query: {'team_id': '$teamId'},
        showEmail: member,
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(apiClientProvider).post(
            member ? '/team_detail/$teamId/members' : '/team_detail/$teamId/projects',
            data: member ? {'user_id': picked} : {'project_id': picked},
          );
      ref.invalidate(teamDetailProvider(teamId));
      if (!context.mounted) return;
      showSnack(context, member ? tr('Member added') : tr('Project added'));
    } catch (e) {
      if (!context.mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, int teamId, bool member, int otherId, String name) async {
    final ok = await showConfirmDialog(
      context,
      title: member ? tr('Remove member?') : tr('Remove project?'),
      message: member
          ? tr('{name} will be removed from this team.', {'name': name})
          : tr('{name} will no longer be assigned to this team.', {'name': name}),
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).delete(
            member ? '/team_detail/$teamId/members/$otherId' : '/team_detail/$teamId/projects/$otherId',
          );
      ref.invalidate(teamDetailProvider(teamId));
      if (!context.mounted) return;
      showSnack(context, member ? tr('Member removed') : tr('Project removed'));
    } catch (e) {
      if (!context.mounted) return;
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(params['id'] ?? '');
    if (id == null) {
      return AppScaffold(
        title: tr('Team Details'),
        body: ErrorView(message: tr('Team not found.')),
      );
    }
    final auth = ref.watch(authProvider);
    final canEdit = auth.can('team_detail.edit');
    final canDelete = auth.can('team_detail.delete');
    final async = ref.watch(teamDetailProvider(id));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppScaffold(
      title: tr('Team Details'),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: errorMessage(e),
          onRetry: () => ref.invalidate(teamDetailProvider(id)),
        ),
        data: (team) {
          final members = List<Map<String, dynamic>>.from(
              ((team['teamMembers'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
          final projects = List<Map<String, dynamic>>.from(
              ((team['projectTeams'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
          final creator = team['createdByRef'] is Map ? (team['createdByRef'] as Map)['name']?.toString() : null;
          final description = team['description']?.toString();

          Widget membersTab(BuildContext ctx) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canEdit)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _add(ctx, ref, id, true),
                      icon: Icon(AppIcons.personAdd),
                      label: Text(tr('Add member')),
                    ),
                  ),
                if (members.isEmpty)
                  EmptyView(message: tr('This team has no members yet.'), icon: AppIcons.people)
                else
                  for (final m in members)
                    Builder(builder: (_) {
                      final user = m['user'] is Map ? Map<String, dynamic>.from(m['user'] as Map) : <String, dynamic>{};
                      final name = user['name']?.toString() ?? '';
                      final role = user['role']?.toString() ?? '';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AppImage(user['photo'], width: 40, height: 40, circle: true, preview: false),
                        title: Text(name, style: textTheme.titleMedium),
                        subtitle: Text(
                          user['email']?.toString() ?? '',
                          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (role.isNotEmpty) StatusBadge(_roleLabel(role)),
                            if (canDelete)
                              IconButton(
                                tooltip: tr('Remove member'),
                                icon: Icon(AppIcons.close),
                                onPressed: () => _remove(ctx, ref, id, true, (m['user_id'] as num).toInt(), name),
                              ),
                          ],
                        ),
                      );
                    }),
              ],
            );
          }

          Widget projectsTab(BuildContext ctx) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canEdit)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _add(ctx, ref, id, false),
                      icon: Icon(AppIcons.addCircle),
                      label: Text(tr('Add project')),
                    ),
                  ),
                if (projects.isEmpty)
                  EmptyView(message: tr('This team has no projects yet.'), icon: AppIcons.folder)
                else
                  for (final p in projects)
                    Builder(builder: (_) {
                      final project = p['project'] is Map ? Map<String, dynamic>.from(p['project'] as Map) : <String, dynamic>{};
                      final name = project['name']?.toString() ?? '';
                      final status = project['status']?.toString() ?? '';
                      final deadline = project['deadline'];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(AppIcons.folder, color: scheme.onSurfaceVariant),
                        title: Text(name, style: textTheme.titleMedium),
                        subtitle: deadline == null
                            ? null
                            : Text(
                                tr('Deadline {date}', {'date': formatDate(deadline)}),
                                style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status.isNotEmpty) StatusBadge(_statusLabel(status), color: _statusColor(status)),
                            if (canDelete)
                              IconButton(
                                tooltip: tr('Remove project'),
                                icon: Icon(AppIcons.close),
                                onPressed: () => _remove(ctx, ref, id, false, (p['project_id'] as num).toInt(), name),
                              ),
                          ],
                        ),
                      );
                    }),
              ],
            );
          }

          return DetailView(
            onRefresh: () => ref.refresh(teamDetailProvider(id).future),
            children: [
              DetailHeader(
                title: team['name']?.toString() ?? '',
                subtitle: creator == null ? null : tr('Created by {name}', {'name': creator}),
                icon: AppIcons.group,
                stats: [
                  DetailStat(tr('Members'), formatNumber(members.length), icon: AppIcons.people),
                  DetailStat(tr('Projects'), formatNumber(projects.length), icon: AppIcons.folder),
                ],
              ),
              DetailSection(
                title: tr('About'),
                hideEmpty: true,
                fields: [
                  DetailField(tr('Description'), description, wide: true),
                  DetailField(tr('Created'), formatDate(team['created_at'])),
                ],
              ),
              DetailTabs(
                tabs: [
                  DetailTab(
                    label: tr('Members'),
                    count: members.length,
                    icon: AppIcons.people,
                    builder: membersTab,
                  ),
                  DetailTab(
                    label: tr('Projects'),
                    count: projects.length,
                    icon: AppIcons.folder,
                    builder: projectsTab,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PickDialog extends StatefulWidget {
  const _PickDialog({
    required this.title,
    required this.label,
    required this.path,
    required this.query,
    required this.showEmail,
  });
  final String title;
  final String label;
  final String path;
  final Map<String, dynamic> query;
  final bool showEmail;

  @override
  State<_PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<_PickDialog> {
  final _formKey = GlobalKey<FormState>();
  Object? _id;
  Map<String, dynamic>? _row;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: RelationField(
            label: widget.label,
            path: widget.path,
            query: widget.query,
            value: _id,
            selected: _row,
            required: true,
            subtitle: widget.showEmail ? (row) => row['email']?.toString() : null,
            onChanged: (id, row) => setState(() {
              _id = id;
              _row = row;
            }),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final id = _id;
            final value = id is int ? id : int.tryParse('$id');
            if (value == null) return;
            Navigator.of(context).pop(value);
          },
          child: Text(tr('Add')),
        ),
      ],
    );
  }
}
