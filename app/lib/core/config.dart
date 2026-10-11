// Owned by AppWand. Override with --dart-define=API_URL=https://host/api
import 'package:flutter/foundation.dart';

const String _apiUrl = String.fromEnvironment('API_URL');

/// Base URL of the Express API, ending in /api.
String get apiBaseUrl {
  if (_apiUrl.isNotEmpty) return _apiUrl;
  // The Android emulator reaches the host machine through 10.0.2.2.
  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
  return 'http://$host:8842/api';
}
