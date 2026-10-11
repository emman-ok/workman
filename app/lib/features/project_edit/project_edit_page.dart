import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/widgets.dart';

final _projectProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/project_edit/$id');
  return Map<String, dynamic>.from(data as Map);
});

class ProjectEditPage extends ConsumerWidget {
  const ProjectEditPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(params['id'] ?? '');
    if (id == null) {
      return AppScaffold(
        title: tr('Edit Project'),
        body: ErrorView(message: tr('Project not found.')),
      );
    }
    final async = ref.watch(_projectProvider(id));
    return async.when(
      loading: () => AppScaffold(title: tr('Edit Project'), body: const LoadingView()),
      error: (e, _) => AppScaffold(
        title: tr('Edit Project'),
        body: ErrorView(
          message: errorMessage(e),
          onRetry: () => ref.invalidate(_projectProvider(id)),
        ),
      ),
      data: (record) => _ProjectEditForm(id: id, record: record),
    );
  }
}

class _ProjectEditForm extends ConsumerStatefulWidget {
  const _ProjectEditForm({required this.id, required this.record});
  final int id;
  final Map<String, dynamic> record;

  @override
  ConsumerState<_ProjectEditForm> createState() => _ProjectEditFormState();
}

class _ProjectEditFormState extends ConsumerState<_ProjectEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late String _status;
  late String _priority;
  DateTime? _start;
  DateTime? _deadline;
  Object? _managerId;
  Map<String, dynamic>? _manager;
  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  static const _statuses = ['planning', 'active', 'on_hold', 'completed', 'cancelled'];
  static const _priorities = ['low', 'medium', 'high', 'critical'];

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _name = TextEditingController(text: '${r['name'] ?? ''}');
    _description = TextEditingController(text: '${r['description'] ?? ''}');
    _status = (r['status'] ?? 'planning').toString();
    _priority = (r['priority'] ?? 'medium').toString();
    _start = toDate(r['start_date']);
    _deadline = toDate(r['deadline']);
    _managerId = r['manager_id'];
    final m = r['manager'];
    _manager = m is Map ? Map<String, dynamic>.from(m) : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  String _statusLabel(String v) => switch (v) {
        'planning' => tr('Planning'),
        'active' => tr('Active'),
        'on_hold' => tr('On hold'),
        'completed' => tr('Completed'),
        'cancelled' => tr('Cancelled'),
        _ => v,
      };

  String _priorityLabel(String v) => switch (v) {
        'low' => tr('Low'),
        'medium' => tr('Medium'),
        'high' => tr('High'),
        'critical' => tr('Critical'),
        _ => v,
      };

  List<String> _withCurrent(List<String> base, String current) =>
      base.contains(current) ? base : [...base, current];

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      final description = _description.text.trim();
      await ref.read(apiClientProvider).put('/project_edit/${widget.id}', data: {
        'name': _name.text.trim(),
        'description': description.isEmpty ? null : description,
        'status': _status,
        'priority': _priority,
        'start_date': apiDate(_start),
        'deadline': apiDate(_deadline),
        'manager_id': _managerId,
      });
      if (!mounted) return;
      ref.invalidate(_projectProvider(widget.id));
      showSnack(context, tr('Saved'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/projects/${widget.id}');
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
      title: tr('Edit Project'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
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
                    value: _status,
                    decoration: InputDecoration(
                      labelText: tr('Status'),
                      errorText: _fieldErrors['status'],
                    ),
                    items: [
                      for (final s in _withCurrent(_statuses, _status))
                        DropdownMenuItem(value: s, child: Text(_statusLabel(s))),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _status = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: InputDecoration(
                      labelText: tr('Priority'),
                      errorText: _fieldErrors['priority'],
                    ),
                    items: [
                      for (final p in _withCurrent(_priorities, _priority))
                        DropdownMenuItem(value: p, child: Text(_priorityLabel(p))),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _priority = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  DateField(
                    label: tr('Start date'),
                    value: _start,
                    errorText: _fieldErrors['start_date'],
                    onChanged: (d) => setState(() => _start = d),
                  ),
                  const SizedBox(height: 16),
                  DateField(
                    label: tr('Deadline'),
                    value: _deadline,
                    errorText: _fieldErrors['deadline'],
                    validator: (d) {
                      final s = _start;
                      if (d != null && s != null && d.isBefore(s)) {
                        return tr('The deadline cannot be before the start date.');
                      }
                      return null;
                    },
                    onChanged: (d) => setState(() => _deadline = d),
                  ),
                  const SizedBox(height: 16),
                  RelationField(
                    label: tr('Manager'),
                    path: '/project_edit/options/users',
                    value: _managerId,
                    selected: _manager,
                    errorText: _fieldErrors['manager_id'],
                    onChanged: (id, row) => setState(() {
                      _managerId = id;
                      _manager = row;
                    }),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
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
