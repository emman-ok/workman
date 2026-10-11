import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/widgets.dart';
import 'package:app/core/auth/auth_controller.dart';

final accountEditProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/account_edit/$id');
  return Map<String, dynamic>.from(data as Map);
});

class AccountEditPage extends ConsumerWidget {
  const AccountEditPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = int.tryParse(params['id'] ?? '');
    if (id == null) {
      return AppScaffold(
        title: tr('Edit Account'),
        body: ErrorView(message: tr('Account not found.')),
      );
    }
    final async = ref.watch(accountEditProvider(id));
    return AppScaffold(
      title: tr('Edit Account'),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: errorMessage(e),
          onRetry: () => ref.invalidate(accountEditProvider(id)),
        ),
        data: (record) => _AccountForm(id: id, record: record),
      ),
    );
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm({required this.id, required this.record});
  final int id;
  final Map<String, dynamic> record;

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late String _role;
  late bool _active;
  bool _saving = false;
  Map<String, String> _fieldErrors = {};

  static const _roles = ['admin', 'project_manager', 'team_member'];

  String _roleLabel(String role) => switch (role) {
        'admin' => tr('Admin'),
        'project_manager' => tr('Project manager'),
        'team_member' => tr('Team member'),
        _ => role,
      };

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _name = TextEditingController(text: '${r['name'] ?? ''}');
    _email = TextEditingController(text: '${r['email'] ?? ''}');
    _role = '${r['role'] ?? 'team_member'}';
    _active = r['is_active'] == true;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      await ref.read(apiClientProvider).put('/account_edit/${widget.id}', data: {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'role': _role,
        'is_active': _active,
      });
      if (!mounted) return;
      showSnack(context, tr('Saved'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/accounts');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e is ApiException) _fieldErrors = Map<String, String>.from(e.fieldErrors);
      });
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(authProvider).can('account_edit.edit');
    final roleOptions = [..._roles, if (!_roles.contains(_role)) _role];
    final textTheme = Theme.of(context).textTheme;

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
                TextFormField(
                  controller: _name,
                  enabled: canEdit && !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tr('Name'),
                    errorText: _fieldErrors['name'],
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return tr('Name is required.');
                    if (t.length > 150) return tr('Name is too long.');
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  enabled: canEdit && !_saving,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: tr('Email'),
                    errorText: _fieldErrors['email'],
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return tr('Email is required.');
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                      return tr('Enter a valid email address.');
                    }
                    if (t.length > 255) return tr('Email is too long.');
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: InputDecoration(
                    labelText: tr('Role'),
                    errorText: _fieldErrors['role'],
                  ),
                  items: [
                    for (final r in roleOptions)
                      DropdownMenuItem<String>(value: r, child: Text(_roleLabel(r))),
                  ],
                  onChanged: (canEdit && !_saving)
                      ? (v) {
                          if (v != null) setState(() => _role = v);
                        }
                      : null,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Active'), style: textTheme.titleMedium),
                  subtitle: Text(tr('Inactive accounts cannot sign in.')),
                  value: _active,
                  onChanged: (canEdit && !_saving) ? (v) => setState(() => _active = v) : null,
                ),
                if (_fieldErrors['is_active'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _fieldErrors['is_active']!,
                      style: textTheme.bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (canEdit && !_saving) ? _save : null,
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
