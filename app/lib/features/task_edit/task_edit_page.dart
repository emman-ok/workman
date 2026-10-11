import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/widgets.dart';

class TaskEditPage extends ConsumerStatefulWidget {
  const TaskEditPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends ConsumerState<TaskEditPage> {
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
  String _status = 'todo';
  DateTime? _deadline;

  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  int? get _id => int.tryParse(widget.params['id'] ?? '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _id;
    if (id == null) {
      setState(() {
        _loading = false;
        _loadError = tr('Task not found.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await ref.read(apiClientProvider).get('/task_edit/$id');
      final row = Map<String, dynamic>.from(data as Map);
      if (!mounted) return;
      setState(() {
        _title.text = '${row['title'] ?? ''}';
        _description.text = '${row['description'] ?? ''}';
        _projectId = row['project_id'];
        _project = row['project'] is Map ? Map<String, dynamic>.from(row['project'] as Map) : null;
        _milestoneId = row['milestone_id'];
        _milestone = row['milestone'] is Map ? Map<String, dynamic>.from(row['milestone'] as Map) : null;
        _assigneeId = row['assignee_id'];
        _assignee = row['assignee'] is Map ? Map<String, dynamic>.from(row['assignee'] as Map) : null;
        _priority = '${row['priority'] ?? 'medium'}';
        _status = '${row['status'] ?? 'todo'}';
        _deadline = toDate(row['deadline']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = errorMessage(e);
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final id = _id;
    if (id == null) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      await ref.read(apiClientProvider).put('/task_edit/$id', data: {
        'project_id': _projectId,
        'milestone_id': _milestoneId,
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'priority': _priority,
        'status': _status,
        'deadline': apiDate(_deadline),
        'assignee_id': _assigneeId,
      });
      if (!mounted) return;
      showSnack(context, tr('Task saved'));
      if (context.canPop()) context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiException) _fieldErrors = e.fieldErrors;
      });
      showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<DropdownMenuItem<String>> _items(Map<String, String> labels, String current) {
    final all = Map<String, String>.from(labels);
    if (!all.containsKey(current)) all[current] = current;
    return [
      for (final e in all.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final title = tr('Edit Task');
    if (_loading) {
      return AppScaffold(title: title, body: const LoadingView());
    }
    if (_loadError != null) {
      return AppScaffold(
        title: title,
        body: ErrorView(message: _loadError!, onRetry: _load),
      );
    }

    final priorities = <String, String>{
      'low': tr('Low'),
      'medium': tr('Medium'),
      'high': tr('High'),
      'urgent': tr('Urgent'),
    };
    final statuses = <String, String>{
      'todo': tr('To do'),
      'in_progress': tr('In progress'),
      'done': tr('Done'),
    };

    return AppScaffold(
      title: title,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RelationField(
                    label: tr('Project'),
                    path: '/task_edit/options/projects',
                    value: _projectId,
                    selected: _project,
                    required: true,
                    errorText: _fieldErrors['project_id'],
                    onChanged: (id, row) => setState(() {
                      if (id != _projectId) {
                        _milestoneId = null;
                        _milestone = null;
                      }
                      _projectId = id;
                      _project = row;
                    }),
                  ),
                  const SizedBox(height: 16),
                  RelationField(
                    key: ValueKey('milestone-$_projectId'),
                    label: tr('Milestone'),
                    path: '/task_edit/options/milestones',
                    value: _milestoneId,
                    selected: _milestone,
                    query: {'project_id': '$_projectId'},
                    display: (row) => '${row['title'] ?? ''}',
                    enabled: _projectId != null,
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
                    decoration: InputDecoration(
                      labelText: tr('Title'),
                      errorText: _fieldErrors['title'],
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? tr('Title is required.') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: tr('Description'),
                      alignLabelWithHint: true,
                      errorText: _fieldErrors['description'],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _priority,
                    items: _items(priorities, _priority),
                    decoration: InputDecoration(
                      labelText: tr('Priority'),
                      errorText: _fieldErrors['priority'],
                    ),
                    onChanged: (v) => setState(() => _priority = v ?? _priority),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _status,
                    items: _items(statuses, _status),
                    decoration: InputDecoration(
                      labelText: tr('Status'),
                      errorText: _fieldErrors['status'],
                    ),
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 16),
                  DateField(
                    label: tr('Deadline'),
                    value: _deadline,
                    errorText: _fieldErrors['deadline'],
                    onChanged: (d) => setState(() => _deadline = d),
                  ),
                  const SizedBox(height: 16),
                  RelationField(
                    label: tr('Assignee'),
                    path: '/task_edit/options/users',
                    value: _assigneeId,
                    selected: _assignee,
                    subtitle: (row) => row['email']?.toString(),
                    errorText: _fieldErrors['assignee_id'],
                    onChanged: (id, row) => setState(() {
                      _assigneeId = id;
                      _assignee = row;
                    }),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
