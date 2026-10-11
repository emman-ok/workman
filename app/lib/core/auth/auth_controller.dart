// Owned by AppWand.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import 'token_store.dart';

class AuthState {
  const AuthState({this.user, this.restoring = false});

  final Map<String, dynamic>? user;

  /// True while a saved token is being checked at start-up.
  final bool restoring;

  bool get isSignedIn => user != null;

  /// The signed-in account's role; null when signed out or the app has no roles.
  String? get role => user?['role']?.toString();

  /// True when [roles] is empty or holds the signed-in account's role.
  bool hasRole(List<String> roles) => roles.isEmpty || (role != null && roles.contains(role));

  /// The role as people read it: the name it was given in the app (the Roles
  /// & permissions plugin), or else its value in words ('hr_manager' → 'Hr
  /// manager'). Empty when the account has no role.
  String get roleLabel {
    final name = '${user?['role_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    final words = (role ?? '').replaceAll(RegExp(r'[_\-\s]+'), ' ').trim();
    return words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1);
  }

  /// What the account's role may do, as 'page id.action' (view, create,
  /// edit, delete, export, import); null unless the app has the Roles &
  /// permissions plugin, where they are set in the app itself.
  Set<String>? get permissions {
    final list = user?['permissions'];
    return list is List ? {for (final item in list) '$item'} : null;
  }

  /// Whether the account may do [permission], e.g. can('orders.create').
  /// Always true without the Roles & permissions plugin. The API checks it
  /// too: this only hides what would be refused.
  bool can(String permission) => permissions?.contains(permission) ?? true;

  /// [can] with the plugin, else [hasRole]: what the shell asks for a menu
  /// entry or a route that the page plan gave roles.
  bool allows(String? permission, List<String> roles) =>
      permission == null || permissions == null ? hasRole(roles) : can(permission);
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState(restoring: true);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> _restore() async {
    await TokenStore.load();
    if (TokenStore.token == null) {
      state = const AuthState();
      return;
    }
    try {
      final me = await _api.get('/auth/me');
      state = AuthState(user: Map<String, dynamic>.from(me as Map));
    } catch (_) {
      await TokenStore.save(null);
      state = const AuthState();
    }
  }

  /// Signs in with the { token, user } answer of the app's sign-in API
  /// (api/src/routes/auth.js). The router then moves on by itself.
  Future<void> signedIn(dynamic result) async {
    final map = Map<String, dynamic>.from(result as Map);
    await TokenStore.save(map['token'] as String?);
    state = AuthState(user: Map<String, dynamic>.from(map['user'] as Map));
  }

  /// Reads the account again (GET /auth/me), e.g. after its role or its
  /// role's permissions changed. Keeps what it has when the API can't be reached.
  Future<void> refresh() async {
    if (!state.isSignedIn) return;
    try {
      final me = await _api.get('/auth/me');
      if (state.isSignedIn) state = AuthState(user: Map<String, dynamic>.from(me as Map));
    } catch (_) {
      // Offline, or signed out meanwhile (a 401 already ended the session).
    }
  }

  Future<void> logout() async {
    await TokenStore.save(null);
    state = const AuthState();
  }

  /// Called when the API rejects the token.
  void expire() {
    if (!state.isSignedIn) return;
    TokenStore.save(null);
    state = const AuthState();
  }
}
