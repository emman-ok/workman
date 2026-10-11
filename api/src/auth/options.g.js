// Written by AppWand from the project's authentication options: change them
// in AppWand (Authentication options), not here.

/** The app's name, used in the messages that carry one-time codes. */
export const APP_NAME = "WorkMan";

export const AUTH_OPTIONS = Object.freeze({
  /** What people sign in with, besides a password: 'email', 'username', 'phone'. */
  loginWith: Object.freeze(["email"]),
  /** What registration asks for, besides a name and a password. */
  registerWith: Object.freeze(["email"]),
  /** "Forgot password?": a code by email or SMS, then a new password. */
  forgotPassword: false,
  /** Signing in with a one-time code by email or SMS, no password. */
  otpLogin: false,
  /** Change password on the Account page (POST /api/auth/me/password). */
  changePassword: true,
});
