// The screens the router needs around the pages. Owned by AppWand; the
// sign-in screens are the app's own, in features/auth/.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api_client.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_options.dart';
import 'format.dart';
import 'plugins.g.dart' show appPlugins;
import 'theme.dart' show AccountLayout, accountLayout, themeSwitch;
import 'uploads.dart';
import 'widgets.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(tr('No pages yet. Generate them in AppWand.'))));
  }
}

/// Where the router sends a signed-in user whose role cannot open a page.
class ForbiddenPage extends ConsumerWidget {
  const ForbiddenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(AppIcons.lock, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(tr('Your account cannot open this page.'), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              if (GoRouter.of(context).canPop()) OutlinedButton(onPressed: () => context.pop(), child: Text(tr('Go back'))),
              FilledButton(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                child: Text(tr('Sign in as someone else')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The signed-in account: its details, links to Edit profile (/account/edit)
/// and Change password (/account/password), the plugins' settings, the app's
/// settings and Sign out, laid out as theme.dart's accountLayout says.
/// Opened from the account menu at /account (unless a page of the app owns
/// that route).
class AppAccountPage extends ConsumerWidget {
  const AppAccountPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user ?? const <String, dynamic>{};
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final name = '${user['name'] ?? ''}'.trim();
    final email = '${user['email'] ?? ''}'.trim();
    final role = auth.role ?? '';
    final username = '${user['username'] ?? ''}'.trim();
    final phone = '${user['phone'] ?? ''}'.trim();
    final photo = fileUrl(user['photo']);
    final shown = name.isNotEmpty ? name : email;
    final details = _details(user, shown: {name, email, role, auth.roleLabel, username, phone, '${user['photo'] ?? ''}'});
    // Side by side, Edit profile is a button of the card, not a row under Security.
    final split = accountLayout == AccountLayout.split;

    Widget picture(double size) => photo == null
        ? CircleAvatar(
            radius: size / 2,
            child: Text(
              shown.isEmpty ? '?' : shown[0].toUpperCase(),
              style: size > 64 ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge,
            ),
          )
        : AppImage(photo, width: size, height: size, circle: true, title: shown);

    Widget names({bool centered = false}) {
      final align = centered ? TextAlign.center : TextAlign.start;
      return Column(
        crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(shown, style: centered ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge, textAlign: align),
          if (name.isNotEmpty && email.isNotEmpty) Text(email, style: muted, textAlign: align),
          if (auth.roleLabel.isNotEmpty) ...[const SizedBox(height: 8), Chip(label: Text(auth.roleLabel))],
        ],
      );
    }

    List<Widget> section(String title, Widget card) => [
          const SizedBox(height: 24),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          card,
        ];

    final profile = AppSurface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _DetailRow(label: tr('Name'), value: name.isEmpty ? '—' : name),
        _DetailRow(label: tr('Email'), value: email.isEmpty ? '—' : email),
        if (authHasUsername) _DetailRow(label: tr('Username'), value: username.isEmpty ? '—' : username),
        if (authHasPhone) _DetailRow(label: tr('Phone number'), value: phone.isEmpty ? '—' : phone),
        if (auth.roleLabel.isNotEmpty) _DetailRow(label: tr('Role'), value: auth.roleLabel),
        for (final entry in details.entries) _DetailRow(label: entry.key, value: entry.value),
      ]),
    );
    final hasSecurity = !split || authChangePassword;
    final security = AppSurface(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        if (!split)
          ListTile(
            leading: const Icon(AppIcons.edit),
            title: Text(tr('Edit profile')),
            subtitle: Text(authHasPhoto ? tr('Change your photo, name and email.') : tr('Change your name and email.')),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => context.push('/account/edit'),
          ),
        if (authChangePassword)
          ListTile(
            leading: const Icon(AppIcons.key),
            title: Text(tr('Change password')),
            subtitle: Text(tr('Pick a new password for signing in.')),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => context.push('/account/password'),
          ),
      ]),
    );
    final Widget? appearance = themeSwitch || appLanguages.length > 1
        ? AppSurface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (themeSwitch) ...[
                Text(tr('Theme'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(tr('Light, dark, or the same as this device.'), style: muted),
                const SizedBox(height: 12),
                const Align(alignment: AlignmentDirectional.centerStart, child: ThemeModeSetting()),
              ],
              if (themeSwitch && appLanguages.length > 1) const SizedBox(height: 24),
              if (appLanguages.length > 1) ...[
                Text(tr('Language'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(tr('The language the app is shown in.'), style: muted),
                const SizedBox(height: 12),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: const LanguageSetting()),
              ],
            ]),
          )
        : null;
    final hasPluginSettings = appPlugins.any((plugin) => plugin.accountSection != null);
    final signOut = OutlinedButton.icon(
      onPressed: () => ref.read(authProvider.notifier).logout(),
      icon: const Icon(AppIcons.logout),
      label: Text(tr('Sign out')),
    );
    // Everything under the account's name, each part with 24px above it.
    final rest = <Widget>[
      ...section(tr('Profile'), profile),
      if (hasSecurity) ...section(tr('Security'), security),
      const PluginSettings(),
      if (appearance != null) ...section(tr('Appearance'), appearance),
    ];

    final Widget body = switch (accountLayout) {
      AccountLayout.sections => ListView(padding: const EdgeInsets.all(20), children: [
          _accountWidth(
            640,
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSurface(
                child: Row(children: [picture(56), const SizedBox(width: 16), Expanded(child: names())]),
              ),
              ...rest,
              const SizedBox(height: 24),
              Align(alignment: AlignmentDirectional.centerStart, child: signOut),
            ]),
          ),
        ]),
      // A banner in the brand colour, the photo over its foot.
      AccountLayout.cover => ListView(padding: EdgeInsets.zero, children: [
          Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
            Container(
              width: double.infinity,
              height: 132,
              margin: const EdgeInsets.only(bottom: 52),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.6)!],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, shape: BoxShape.circle),
              child: picture(96),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: _accountWidth(
              640,
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                names(centered: true),
                ...rest,
                const SizedBox(height: 24),
                Center(child: signOut),
              ]),
            ),
          ),
        ]),
      // The account's card beside the details from 900 wide, over them below that.
      AccountLayout.split => LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final card = AppSurface(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              picture(96),
              const SizedBox(height: 16),
              names(centered: true),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => context.push('/account/edit'),
                  icon: const Icon(AppIcons.edit),
                  label: Text(tr('Edit profile')),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: signOut),
            ]),
          );
          return ListView(padding: const EdgeInsets.all(20), children: [
            _accountWidth(
              wide ? 1040 : 640,
              wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 320, child: card),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          // Without the space above the first part: it starts level with the card.
                          children: rest.skip(1).toList(),
                        ),
                      ),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [card, ...rest]),
            ),
          ]);
        }),
      AccountLayout.tabs => ListView(padding: const EdgeInsets.all(20), children: [
          _accountWidth(
            720,
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [picture(64), const SizedBox(width: 16), Expanded(child: names())]),
              const SizedBox(height: 16),
              _AccountTabs(tabs: [
                (tr('Profile'), profile),
                (tr('Security'), security),
                if (appearance != null || hasPluginSettings)
                  (
                    tr('Settings'),
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (appearance != null) appearance,
                      const PluginSettings(),
                    ]),
                  ),
              ]),
              const SizedBox(height: 24),
              Align(alignment: AlignmentDirectional.centerStart, child: signOut),
            ]),
          ),
        ]),
    };

    return AppScaffold(title: tr('Account'), body: body);
  }

  /// The account's other columns as label → text: secrets, empty values and
  /// the values already [shown] (name, email, role, username, phone, photo)
  /// are left out.
  static Map<String, String> _details(Map<String, dynamic> user, {required Set<String> shown}) {
    final hidden = RegExp(r'password|token|secret|hash|salt|otp', caseSensitive: false);
    final visible = {...shown}..remove('');
    final id = '${user['id'] ?? ''}';
    final out = <String, String>{};
    for (final entry in user.entries) {
      final key = entry.key;
      final value = entry.value;
      if (const {'id', 'name', 'email', 'role', 'role_name', 'username', 'phone', 'photo'}.contains(key) || hidden.hasMatch(key)) continue;
      if (value == null || value is Map || value is List) continue;
      final text = '$value'.trim();
      if (text.isEmpty || visible.contains(text)) continue;
      // The id column under its own name (user_id, userId).
      if (text == id && key.toLowerCase().endsWith('id')) continue;
      out[_label(key)] = _text(key, value);
    }
    return out;
  }

  static String _label(String key) {
    final words = key
        .replaceAll(RegExp(r'_id$'), '')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll(RegExp(r'[_.]+'), ' ')
        .trim()
        .toLowerCase();
    return words.isEmpty ? key : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  static String _text(String key, dynamic value) {
    if (value is bool) return value ? tr('Yes') : tr('No');
    final text = '$value';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(text)) return formatDateTime(text);
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return formatDate(text);
    return text;
  }
}

/// The Account page's content centred at [width] on wide screens.
Widget _accountWidth(double width, Widget child) =>
    Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));

/// The Account page's parts as tabs (the Tabs layout): a tab bar, and under
/// it the chosen tab's content at its own height, since the page scrolls as
/// one.
class _AccountTabs extends StatefulWidget {
  const _AccountTabs({required this.tabs});
  final List<(String, Widget)> tabs;

  @override
  State<_AccountTabs> createState() => _AccountTabsState();
}

class _AccountTabsState extends State<_AccountTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final index = _index.clamp(0, tabs.length - 1);
    return DefaultTabController(
      length: tabs.length,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final tab in tabs) Tab(text: tab.$1)],
          onTap: (value) => setState(() => _index = value),
        ),
        const SizedBox(height: 16),
        tabs[index].$2,
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(spacing: 16, runSpacing: 4, children: [
        SizedBox(
          width: 160,
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Text(value, style: theme.textTheme.bodyLarge),
      ]),
    );
  }
}

/// Leaves a form page: back where it came from, or to the Account page.
void _leave(BuildContext context) {
  if (GoRouter.of(context).canPop()) {
    context.pop();
  } else {
    context.go('/account');
  }
}

/// /account/edit: the signed-in account's name and email
/// (PATCH /api/auth/me, which answers a new session).
class AppEditProfilePage extends ConsumerStatefulWidget {
  const AppEditProfilePage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<AppEditProfilePage> createState() => _AppEditProfilePageState();
}

class _AppEditProfilePageState extends ConsumerState<AppEditProfilePage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _username;
  late final TextEditingController _phone;
  late final bool _nameIsEmail;
  String? _photo;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user ?? const <String, dynamic>{};
    final name = '${user['name'] ?? ''}';
    final email = '${user['email'] ?? ''}';
    _nameIsEmail = name.isNotEmpty && name == email;
    _name = TextEditingController(text: name);
    _email = TextEditingController(text: email);
    _username = TextEditingController(text: '${user['username'] ?? ''}');
    _phone = TextEditingController(text: '${user['phone'] ?? ''}');
    final photo = '${user['photo'] ?? ''}';
    _photo = photo.isEmpty ? null : photo;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _username.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final result = await ref.read(apiClientProvider).patch('/auth/me', data: {
        if (!_nameIsEmail) 'name': _name.text.trim(),
        'email': _email.text.trim(),
        if (authHasUsername) 'username': _username.text.trim(),
        if (authHasPhone) 'phone': _phone.text.trim(),
        if (authHasPhoto) 'photo': _photo,
      });
      await ref.read(authProvider.notifier).signedIn(result);
      // The new session makes the router read its pages again. Until the next
      // frame has drawn them, a pop is undone and this page comes back.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      showSnack(context, tr('Profile saved'));
      _leave(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(e);
        _fieldErrors = e is ApiException ? e.fieldErrors : const {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: tr('Edit profile'),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppSurface(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (authHasPhoto) ...[
                    FileField(
                      label: tr('Photo'),
                      imagesOnly: true,
                      value: _photo,
                      onChanged: (path) => setState(() => _photo = path),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!_nameIsEmail) ...[
                    TextFormField(
                      controller: _name,
                      decoration: InputDecoration(labelText: tr('Name'), errorText: _fieldErrors['name']),
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter your name.') : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: InputDecoration(labelText: tr('Email'), errorText: _fieldErrors['email']),
                    keyboardType: TextInputType.emailAddress,
                    onFieldSubmitted: (_) => _save(),
                    validator: (v) => (v ?? '').trim().contains('@') ? null : tr('Enter a valid email address.'),
                  ),
                  if (authHasUsername) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _username,
                      decoration: InputDecoration(labelText: tr('Username'), errorText: _fieldErrors['username']),
                      onFieldSubmitted: (_) => _save(),
                      validator: (v) => authLoginWith.contains('username') && (v ?? '').trim().length < 3
                          ? tr('A username needs at least 3 characters.')
                          : null,
                    ),
                  ],
                  if (authHasPhone) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      decoration: InputDecoration(labelText: tr('Phone number'), errorText: _fieldErrors['phone']),
                      keyboardType: TextInputType.phone,
                      onFieldSubmitted: (_) => _save(),
                      validator: (v) => authLoginWith.contains('phone') && (v ?? '').trim().isEmpty ? tr('Enter your phone number.') : null,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 12, children: [
                    TextButton(onPressed: _saving ? null : () => _leave(context), child: Text(tr('Cancel'))),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr('Save')),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// /account/password: a new password, after the current one
/// (POST /api/auth/me/password).
class AppChangePasswordPage extends ConsumerStatefulWidget {
  const AppChangePasswordPage({super.key, this.params = const {}});
  final Map<String, String> params;

  @override
  ConsumerState<AppChangePasswordPage> createState() => _AppChangePasswordPageState();
}

class _AppChangePasswordPageState extends ConsumerState<AppChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  Map<String, String> _fieldErrors = const {};
  String? _error;
  bool _saving = false;
  bool _show = false;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref.read(apiClientProvider).post('/auth/me/password', data: {
        'current_password': _current.text,
        'password': _password.text,
      });
      if (!mounted) return;
      showSnack(context, tr('Password changed'));
      _leave(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(e);
        _fieldErrors = e is ApiException ? e.fieldErrors : const {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      tooltip: _show ? tr('Hide passwords') : tr('Show passwords'),
      icon: Icon(_show ? AppIcons.visibilityOff : AppIcons.visibility),
      onPressed: () => setState(() => _show = !_show),
    );
    return AppScaffold(
      title: tr('Change password'),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppSurface(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    controller: _current,
                    obscureText: !_show,
                    decoration: InputDecoration(
                      labelText: tr('Current password'),
                      errorText: _fieldErrors['current_password'],
                      suffixIcon: toggle,
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v ?? '').isEmpty ? tr('Enter your current password.') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: !_show,
                    decoration: InputDecoration(labelText: tr('New password'), errorText: _fieldErrors['password']),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v ?? '').length < 6 ? tr('The new password must be at least 6 characters.') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    obscureText: !_show,
                    decoration: InputDecoration(labelText: tr('Confirm the new password')),
                    onFieldSubmitted: (_) => _save(),
                    validator: (v) => v == _password.text ? null : tr('The passwords do not match.'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 12, children: [
                    TextButton(onPressed: _saving ? null : () => _leave(context), child: Text(tr('Cancel'))),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr('Change password')),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Page not found')),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => context.go('/'), child: Text(tr('Go home'))),
        ]),
      ),
    );
  }
}
