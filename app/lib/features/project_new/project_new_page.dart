import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/widgets.dart';

class ProjectNewPage extends ConsumerStatefulWidget {
  const ProjectNewPage({super.key, this.params = const {}});

  final Map<String, String> params;

  @override
  ConsumerState<ProjectNewPage> createState() => _ProjectNewPageState();
}

class _ProjectNewPageState extends ConsumerState<ProjectNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();

  String _status = 'planning';
  String _priority = 'medium';
  DateTime? _startDate;
  DateTime? _deadline;
  Object? _managerId;
  Map<String, dynamic>? _manager;

  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  static const _statuses = ['planning', 'active', 'on_hold', 'completed', 'cancelled'];
  static const _priorities = ['low', 'medium', 'high', 'critical'];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  String _statusLabel(String s) => switch (s) {
        'planning' => tr('Planning'),
        'active' => tr('Active'),
        'on_hold' => tr('On hold'),
        'completed' => tr('Completed'),
        'cancelled' => tr('Cancelled'),
        _ => s,
      };

  String _priorityLabel(String s) => switch (s) {
        'low' => tr('Low'),
        'medium' => tr('Medium'),
        'high' => tr('High'),
        'critical' => tr('Critical'),
        _ => s,
      };

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _fieldErrors = {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      await ref.read(apiClientProvider).post('/project_new', data: {
        'name': _name.text.trim(),
        'description': description.isEmpty ? null : description,
        'status': _status,
        'priority': _priority,
        'start_date': apiDate(_startDate),
        'deadline': apiDate(_deadline),
        'manager_id': _managerId,
      });
      if (!mounted) return;
      showSnack(context, tr('Project created'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/projects');
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
    return AppScaffold(
      title: tr('New Project'),
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
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr('Name'),
                      errorText: _fieldErrors['name'],
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? tr('Name is required.') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    enabled: !_saving,
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
                    value: _status,
                    decoration: InputDecoration(
                      labelText: tr('Status'),
                      errorText: _fieldErrors['status'],
                    ),
                    items: [
                      for (final s in _statuses)
                        DropdownMenuItem(value: s, child: Text(_statusLabel(s))),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: InputDecoration(
                      labelText: tr('Priority'),
                      errorText: _fieldErrors['priority'],
                    ),
                    items: [
                      for (final p in _priorities)
                        DropdownMenuItem(value: p, child: Text(_priorityLabel(p))),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _priority = v ?? _priority),
                  ),
                  const SizedBox(height: 16),
                  DateField(
                    label: tr('Start date'),
                    value: _startDate,
                    enabled: !_saving,
                    errorText: _fieldErrors['start_date'],
                    onChanged: (d) => setState(() => _startDate = d),
                  ),
                  const SizedBox(height: 16),
                  DateField(
                    label: tr('Deadline'),
                    value: _deadline,
                    enabled: !_saving,
                    errorText: _fieldErrors['deadline'],
                    validator: (d) => (d != null && _startDate != null && d.isBefore(_startDate!))
                        ? tr('The deadline cannot be before the start date.')
                        : null,
                    onChanged: (d) => setState(() => _deadline = d),
                  ),
                  const SizedBox(height: 16),
                  RelationField(
                    label: tr('Manager'),
                    path: '/project_new/options/managers',
                    value: _managerId,
                    selected: _manager,
                    enabled: !_saving,
                    errorText: _fieldErrors['manager_id'],
                    subtitle: (row) => row['email']?.toString(),
                    onChanged: (id, row) => setState(() {
                      _managerId = id;
                      _manager = row;
                    }),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(AppIcons.save),
                    label: Text(_saving ? tr('Saving...') : tr('Create project')),
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
