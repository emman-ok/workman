import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/auth/auth_controller.dart';
import 'package:app/core/auth/auth_options.dart';
import 'package:app/core/widgets.dart';

final List<GoRoute> authRoutes = [
  GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
];

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  TextInputType get _keyboard {
    if (authLoginWith.length == 1 && authLoginWith.contains('phone')) {
      return TextInputType.phone;
    }
    return TextInputType.emailAddress;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      final result = await ref.read(apiClientProvider).post('/auth/login', data: {
        'login': _login.text.trim(),
        'password': _password.text,
      });
      await ref.read(authProvider.notifier).signedIn(Map<String, dynamic>.from(result as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(e);
        if (e is ApiException) {
          _fieldErrors = e.fieldErrors;
        }
      });
      return;
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Widget _formContent(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('Sign in'),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Sign in with your email and password to see your projects, tasks and deadlines.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _login,
              keyboardType: _keyboard,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: authLoginLabel,
                prefixIcon: Icon(AppIcons.mail),
                errorText: _fieldErrors['login'],
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return tr('Please enter your login.');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              enabled: !_busy,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr('Password'),
                prefixIcon: Icon(AppIcons.lock),
                errorText: _fieldErrors['password'],
                suffixIcon: IconButton(
                  tooltip: _obscure ? tr('Show password') : tr('Hide password'),
                  icon: Icon(_obscure ? AppIcons.visibility : AppIcons.visibilityOff),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return tr('Please enter your password.');
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Sign in')),
            ),
            const PluginSignInButtons(),
          ],
        ),
      ),
    );
  }

  BoxDecoration _gradient(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [scheme.primary, scheme.tertiary],
      ),
    );
  }

  Widget _widePanel(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimary;
    final highlights = [
      (AppIcons.chart, tr('See project status and deadlines at a glance')),
      (AppIcons.checkCircle, tr('Work on your assigned tasks and update progress')),
      (AppIcons.comment, tr('Talk about the work in task comments')),
    ];
    return Container(
      decoration: _gradient(context),
      padding: const EdgeInsets.all(48),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppLogo(size: 48),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      appTitle,
                      style: theme.textTheme.titleLarge?.copyWith(color: on, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Text(
                tr('Keep every project on track'),
                style: theme.textTheme.displaySmall?.copyWith(color: on, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                tr('Sign in with your email and password to see your projects, tasks and deadlines.'),
                style: theme.textTheme.titleMedium?.copyWith(color: on),
              ),
              const SizedBox(height: 32),
              for (final h in highlights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Icon(h.$1, color: on),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(h.$2, style: theme.textTheme.bodyLarge?.copyWith(color: on)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _band(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimary;
    return Container(
      height: 200,
      width: double.infinity,
      decoration: _gradient(context),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppLogo(size: 36),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(color: on, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tr('Keep every project on track'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(color: on, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                Expanded(child: _widePanel(context)),
                Expanded(
                  child: SafeArea(
                    child: Column(
                      children: [
                        const Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: LanguageButton(),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: _formContent(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _band(context),
                const Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: LanguageButton(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Center(child: _formContent(context)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
