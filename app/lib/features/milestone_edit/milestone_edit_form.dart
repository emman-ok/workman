import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/widgets.dart';

const _knownStatuses = ['pending', 'in_progress', 'reached', 'missed'];

String _statusLabel(String status) {
  switch (status) {
    case 'pending':
      return tr('Pending');
    case 'in_progress':
      return tr('In progress');
    case 'reached':
      return tr('Reached');
    case 'missed':
      return tr('Missed');
    default:
      return status;
  }
}

class MilestoneEditForm extends ConsumerStatefulWidget {
  const MilestoneEditForm({super.key, required this.id, required this.record});
  final int id;
  final Map<String, dynamic> record;

  @override
  ConsumerState<MilestoneEditForm> createState() => _MilestoneEditFormState();
}

class _MilestoneEditFormState extends ConsumerState<MilestoneEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  DateTime? _dueDate;
  late String _status;
  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _title = TextEditingController(text: '${r['title'] ?? ''}');
    _description = TextEditingController(text: '${r['description'] ?? ''}');
    _dueDate = toDate(r['due_date']);
    final status = '${r['status'] ?? ''}';
    _status = status.isEmpty ? 'pending' : status;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      final description = _description.text.trim();
      await ref.read(apiClientProvider).put('/milestone_edit/${widget.id}', data: {
        'title': _title.text.trim(),
        'description': description.isEmpty ? null : description,
        'due_date': apiDate(_dueDate),
        'status': _status,
      });
      if (!mounted) return;
      showSnack(context, tr('Saved'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/milestones');
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
    final canEdit = ref.watch(authProvider).can('milestone_edit.edit');
    final project = widget.record['project'];
    final projectName = project is Map ? '${project['name'] ?? ''}' : '';
    final statuses = [..._knownStatuses];
    if (!statuses.contains(_status)) statuses.add(_status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (projectName.isNotEmpty) ...[
                  TextFormField(
                    initialValue: projectName,
                    enabled: false,
                    decoration: InputDecoration(labelText: tr('Project')),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _title,
                  enabled: canEdit && !_saving,
                  maxLength: 200,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tr('Title'),
                    errorText: _fieldErrors['title'],
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? tr('Title is required.') : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  enabled: canEdit && !_saving,
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
                  required: true,
                  value: _dueDate,
                  enabled: canEdit && !_saving,
                  errorText: _fieldErrors['due_date'],
                  onChanged: (d) => setState(() => _dueDate = d),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: InputDecoration(
                    labelText: tr('Status'),
                    errorText: _fieldErrors['status'],
                  ),
                  items: [
                    for (final s in statuses)
                      DropdownMenuItem<String>(value: s, child: Text(_statusLabel(s))),
                  ],
                  onChanged: (canEdit && !_saving)
                      ? (v) {
                          if (v != null) setState(() => _status = v);
                        }
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: (canEdit && !_saving) ? _save : null,
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
    );
  }
}
