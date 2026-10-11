import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/widgets.dart';

class MilestoneNewPage extends ConsumerStatefulWidget {
  const MilestoneNewPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<MilestoneNewPage> createState() => _MilestoneNewPageState();
}

class _MilestoneNewPageState extends ConsumerState<MilestoneNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();

  Object? _projectId;
  Map<String, dynamic>? _project;
  DateTime? _dueDate;
  String _status = 'pending';
  bool _loading = false;
  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final preset = int.tryParse(widget.params['project_id'] ?? '');
    if (preset != null) {
      _projectId = preset;
      _loading = true;
      _loadProject(preset);
    }
  }

  Future<void> _loadProject(int id) async {
    try {
      final data = await ref.read(apiClientProvider).get('/milestone_new/options/projects/$id');
      if (data is Map) {
        _project = Map<String, dynamic>.from(data);
      } else {
        _projectId = null;
      }
    } catch (e) {
      _projectId = null;
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    return switch (status) {
      'pending' => tr('Upcoming'),
      'reached' => tr('Reached'),
      'late' => tr('Late'),
      _ => status,
    };
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      final description = _description.text.trim();
      await ref.read(apiClientProvider).post('/milestone_new', data: {
        'project_id': _projectId,
        'title': _title.text.trim(),
        'description': description.isEmpty ? null : description,
        'due_date': apiDate(_dueDate),
        'status': _status,
      });
      if (!mounted) return;
      showSnack(context, tr('Milestone created'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/milestones');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e is ApiException) _fieldErrors = e.fieldErrors;
      });
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppScaffold(title: tr('New Milestone'), body: const LoadingView());
    }
    return AppScaffold(
      title: tr('New Milestone'),
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
                    path: '/milestone_new/options/projects',
                    value: _projectId,
                    selected: _project,
                    required: true,
                    enabled: !_saving,
                    errorText: _fieldErrors['project_id'],
                    onChanged: (id, row) => setState(() {
                      _projectId = id;
                      _project = row;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _title,
                    enabled: !_saving,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: tr('Title'),
                      errorText: _fieldErrors['title'],
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return tr('Title is required.');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    enabled: !_saving,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: tr('Description'),
                      alignLabelWithHint: true,
                      errorText: _fieldErrors['description'],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DateField(
                    label: tr('Due date'),
                    value: _dueDate,
                    required: true,
                    enabled: !_saving,
                    errorText: _fieldErrors['due_date'],
                    onChanged: (date) => setState(() => _dueDate = date),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: InputDecoration(
                      labelText: tr('Status'),
                      errorText: _fieldErrors['status'],
                    ),
                    items: [
                      for (final s in const ['pending', 'reached', 'late'])
                        DropdownMenuItem(value: s, child: Text(_statusLabel(s))),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _status = value);
                          },
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
