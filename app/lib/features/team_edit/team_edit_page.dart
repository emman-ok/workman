import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/widgets.dart';

final teamEditProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/team_edit/$id');
  return Map<String, dynamic>.from(data as Map);
});

class TeamEditPage extends ConsumerWidget {
  const TeamEditPage({super.key, this.params = const {}});

  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(params['id'] ?? '');
    if (id == null) {
      return AppScaffold(
        title: tr('Edit Team'),
        body: ErrorView(message: tr('Team not found.')),
      );
    }
    final team = ref.watch(teamEditProvider(id));
    return AppScaffold(
      title: tr('Edit Team'),
      body: team.when(
        data: (data) => _TeamForm(id: id, team: data),
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: errorMessage(e),
          onRetry: () => ref.invalidate(teamEditProvider(id)),
        ),
      ),
    );
  }
}

class _TeamForm extends ConsumerStatefulWidget {
  const _TeamForm({required this.id, required this.team});

  final int id;
  final Map<String, dynamic> team;

  @override
  ConsumerState<_TeamForm> createState() => _TeamFormState();
}

class _TeamFormState extends ConsumerState<_TeamForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: '${widget.team['name'] ?? ''}');
    _description = TextEditingController(text: '${widget.team['description'] ?? ''}');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    final description = _description.text.trim();
    try {
      await ref.read(apiClientProvider).put('/team_edit/${widget.id}', data: {
        'name': _name.text.trim(),
        'description': description.isEmpty ? null : description,
      });
      if (!mounted) return;
      ref.invalidate(teamEditProvider(widget.id));
      showSnack(context, tr('Saved'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/teams/${widget.id}');
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
    final canEdit = ref.watch(authProvider).can('team_edit.edit');
    return SingleChildScrollView(
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
                  enabled: canEdit && !_saving,
                  maxLength: 150,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tr('Name'),
                    errorText: _fieldErrors['name'],
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return tr('Name is required.');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  enabled: canEdit && !_saving,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: tr('Description'),
                    alignLabelWithHint: true,
                    errorText: _fieldErrors['description'],
                  ),
                ),
                const SizedBox(height: 24),
                if (canEdit)
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
    );
  }
}
