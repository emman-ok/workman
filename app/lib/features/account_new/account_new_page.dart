import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/widgets.dart';

class AccountNewPage extends ConsumerStatefulWidget {
  const AccountNewPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<AccountNewPage> createState() => _AccountNewPageState();
}

class _AccountNewPageState extends ConsumerState<AccountNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'team_member';
  bool _active = true;
  bool _saving = false;
  bool _showPassword = false;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _fieldErrors = {};
    });
    try {
      await ref.read(apiClientProvider).post('/account_new', data: {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        'role': _role,
        'is_active': _active,
      });
      if (!mounted) return;
      showSnack(context, tr('Account created'));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/accounts');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e is ApiException) {
          _fieldErrors = e.fieldErrors;
        }
      });
      showSnack(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(authProvider).can('account_new.create');
    if (!canCreate) {
      return AppScaffold(
        title: tr('New Account'),
        body: EmptyView(message: tr('You do not have permission to create accounts.'), icon: AppIcons.lock),
      );
    }
    return AppScaffold(
      title: tr('New Account'),
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
                    textInputAction: TextInputAction.next,
                    maxLength: 150,
                    decoration: InputDecoration(
                      labelText: tr('Name'),
                      errorText: _fieldErrors['name'],
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? tr('Name is required.') : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: tr('Email'),
                      errorText: _fieldErrors['email'],
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return tr('Email is required.');
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                        return tr('Enter a valid email address.');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: tr('Initial password'),
                      helperText: tr('At least 6 characters.'),
                      errorText: _fieldErrors['password'],
                      suffixIcon: IconButton(
                        icon: Icon(_showPassword ? AppIcons.visibilityOff : AppIcons.visibility),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return tr('Password is required.');
                      if (v.length < 6) return tr('Password must be at least 6 characters.');
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
                      for (final r in const ['admin', 'project_manager', 'team_member'])
                        DropdownMenuItem<String>(value: r, child: Text(_roleLabel(r))),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _role = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Active')),
                    subtitle: Text(tr('Inactive accounts cannot sign in.')),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
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
                        : Text(tr('Create account')),
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
