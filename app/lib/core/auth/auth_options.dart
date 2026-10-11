// Written by AppWand from the project's authentication options: change them
// in AppWand (Authentication options), not here.

import '../i18n.dart';

/// What people sign in with, besides a password: 'email', 'username', 'phone'.
const List<String> authLoginWith = ["email"];

/// What registration asks for, besides a name and a password.
const List<String> authRegisterWith = ["email"];

/// "Forgot password?": a code by email or SMS, then a new password
/// (POST /auth/forgot, then POST /auth/reset).
const bool authForgotPassword = false;

/// Signing in with a one-time code by email or SMS, no password
/// (POST /auth/code, then POST /auth/code/verify).
const bool authOtpLogin = false;

/// Whether the Account page offers Change password.
const bool authChangePassword = true;

/// The account fields the accounts table has besides the name and email;
/// Edit profile offers them.
const bool authHasUsername = false;
const bool authHasPhone = false;
const bool authHasPhoto = true;

/// A label for [key] ('email', 'username', 'phone'): "Email", "Phone number".
String authFieldLabel(String key) => switch (key) {
      'email' => tr('Email'),
      'username' => tr('Username'),
      'phone' => tr('Phone number'),
      _ => key,
    };

/// The sign-in field's label: "Email", "Email or username", "Email, username or phone number".
String get authLoginLabel => tr('Email');
