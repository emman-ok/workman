import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/format.dart';
import 'package:app/core/widgets.dart';
import '../../plugins/record_ownership/record_ownership.dart';

class TaskNewPage extends ConsumerStatefulWidget {
  const TaskNewPage({super.key, this.params = const {}});

  final Map<String, String> params;

  @override
  ConsumerState<TaskNewPage> createState() => _TaskNewPageState();
}

class _TaskNewPageState extends ConsumerState<TaskNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  Object? _projectId;
  Map<String, dynamic>? _project;
  Object? _milestoneId;
  Map<String, dynamic>? _milestone;
  Object? _assigneeId;
  Map<String, dynamic>? _assignee;
  String _priority = 'medium';
  DateTime? _deadline;

  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final preset = int.tryParse(widget.params['project_id'] ?? '');
    if (preset != null) {
      _projectId = preset;
      _loadPreset(preset);
    }
  }

  Future<void> _loadPreset(int id) async {
    try {
      final data = await ref.read(apiClientProvider).get('/task_new/options/projects', query: {'id': id});
      final items = (data is Map ? data['items'] : null) as List?;
      if (!mounted || items == null || items.isEmpty) return;
      setState(() => _project = Map<String, dynamic>.from(items.first as Map));
    } catch (_) {
      // The project stays selected by its id; its name is simply not shown.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String _priorityLabel(String value) {
    switch (value) {
      case 'low':
        return tr('Low');
      case 'medium':
        return tr('Medium');
      case 'high':
        return tr('High');
      case 'urgent':
        return tr('Urgent');
      default:
        return value;
    }
  }

  Future<void> _save(bool canAssign) async {
    if (_saving) return;
    setState(() => _fieldErrors = {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      final result = await ref.read(apiClientProvider).post('/task_new', data: {
        'project_id': _projectId,
        'milestone_id': _milestoneId,
        'title': _title.text.trim(),
        'description': description.isEmpty ? null : description,
        'priority': _priority,
        'deadline': apiDate(_deadline),
        if (canAssign) 'assignee_id': _assigneeId,
      });
      if (!mounted) return;
      showSnack(context, tr('Task created'));
      final auth = ref.read(authProvider);
      final id = result is Map ? result['id'] : null;
      if (context.canPop()) {
        context.pop(true);
      } else if (id != null && !ApiClient.isQueued(result) && auth.can('tasks.view')) {
        context.go('/tasks/$id');
      } else if (auth.can('tasks.view')) {
        context.go('/tasks');
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException) {
        setState(() => _fieldErrors = e.fieldErrors);
      }
      showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    if (!auth.can('task_new.create')) {
      return AppScaffold(
        title: tr('New Task'),
        body: EmptyView(message: tr('You are not allowed to create tasks.'), icon: AppIcons.lock),
      );
    }
    final canAssign = seesEveryone(auth, 'task_new', 'tasks');
    final hasProject = _projectId != null;

    return AppScaffold(
      title: tr('New Task'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RelationField(
                    label: tr('Project'),
                    path: '/task_new/options/projects',
                    value: _projectId,
                    selected: _project,
                    required: true,
                    errorText: _fieldErrors['project_id'],
                    onChanged: (id, row) => setState(() {
                      if (id != _projectId) {
                        _milestoneId = null;
                        _milestone = null;
                        _assigneeId = null;
                        _assignee = null;
                      }
                      _projectId = id;
                      _project = row;
                    }),
                  ),
                  const SizedBox(height: 16),
                  RelationField(
                    key: ValueKey('milestone_$_projectId'),
                    label: tr('Milestone (optional)'),
                    path: '/task_new/options/milestones',
                    value: _milestoneId,
                    selected: _milestone,
                    enabled: hasProject,
                    query: {'project_id': '$_projectId'},
                    subtitle: (row) => formatDate(row['due_date']),
                    helperText: hasProject ? null : tr('Pick a project first.'),
                    errorText: _fieldErrors['milestone_id'],
                    onChanged: (id, row) => setState(() {
                      _milestoneId = id;
                      _milestone = row;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _title,
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: tr('Title'), errorText: _fieldErrors['title']),
                    validator: (v) => (v == null || v.trim().isEmpty) ? tr('Title is required.') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: tr('Description'),
                      alignLabelWithHint: true,
                      errorText: _fieldErrors['description'],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: InputDecoration(labelText: tr('Priority'), errorText: _fieldErrors['priority']),
                    items: [
                      for (final p in const ['low', 'medium', 'high', 'urgent'])
                        DropdownMenuItem(value: p, child: Text(_priorityLabel(p))),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? 'medium'),
                  ),
                  const SizedBox(height: 16),
                  DateField(
                    label: tr('Deadline'),
                    value: _deadline,
                    errorText: _fieldErrors['deadline'],
                    onChanged: (d) => setState(() => _deadline = d),
                  ),
                  if (canAssign) ...[
                    const SizedBox(height: 16),
                    RelationField(
                      key: ValueKey('assignee_$_projectId'),
                      label: tr('Assignee (optional)'),
                      path: '/task_new/options/assignees',
                      value: _assigneeId,
                      selected: _assignee,
                      enabled: hasProject,
                      query: {'project_id': '$_projectId'},
                      subtitle: (row) => row['email']?.toString(),
                      helperText: hasProject
                          ? tr('Members of the teams working on this project.')
                          : tr('Pick a project first.'),
                      errorText: _fieldErrors['assignee_id'],
                      onChanged: (id, row) => setState(() {
                        _assigneeId = id;
                        _assignee = row;
                      }),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(canAssign),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('Save')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
