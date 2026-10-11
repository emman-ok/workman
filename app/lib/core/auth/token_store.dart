// Owned by AppWand.
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in user's API token, cached in memory and persisted.
class TokenStore {
  TokenStore._();

  static const String _key = 'auth_token';
  static String? token;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_key);
  }

  static Future<void> save(String? value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, value);
    }
  }
}
