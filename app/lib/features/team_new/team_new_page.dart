import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/widgets.dart';

class TeamNewPage extends ConsumerStatefulWidget {
  const TeamNewPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<TeamNewPage> createState() => _TeamNewPageState();
}

class _TeamNewPageState extends ConsumerState<TeamNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  Map<String, String> _fieldErrors = {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _fieldErrors = {});
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      await ref.read(apiClientProvider).post('/team_new', data: {
        'name': _name.text.trim(),
        'description': description.isEmpty ? null : description,
      });
      if (!mounted) return;
      showSnack(context, tr('Team created'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/teams');
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
    return AppScaffold(
      title: tr('New Team'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: AlignmentDirectional.topCenter,
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
