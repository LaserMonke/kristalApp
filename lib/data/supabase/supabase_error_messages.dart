/// Turns backend failures into one honest sentence a learner can act on.
///
/// Kept as pure functions (no client, no state) so every branch is unit-tested.
/// Two rules shape the wording:
///   * Never leak which half of a credential pair was wrong — that hands an
///     attacker a username oracle.
///   * Never blame the learner for our outage. "Can't reach the server" is the
///     truth when the network is down; "wrong password" is not.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const String _offline =
    'Can’t reach the server. Check your connection and try again.';

const String _genericSignIn = 'Incorrect username or password.';

/// Message for a failure during sign-in.
String signInErrorMessage(Object error) {
  if (isOfflineError(error)) return _offline;

  if (error is sb.AuthApiException) {
    switch (error.code) {
      case 'invalid_credentials':
      case 'user_not_found':
      case 'validation_failed':
        return _genericSignIn;
      case 'email_not_confirmed':
        // Can only happen if the project turned email confirmation on after
        // accounts existed; there is no mailbox to confirm (see DEPLOY.md §1a).
        return 'This account can’t be verified by email. Contact support.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Too many attempts. Wait a minute and try again.';
      case 'user_banned':
        return 'This account is locked. Contact support.';
    }
    if (error.statusCode == '400') return _genericSignIn;
  }

  return 'Couldn’t sign in right now. Please try again.';
}

/// Message for a failure during sign-up.
String signUpErrorMessage(Object error) {
  if (isOfflineError(error)) return _offline;

  if (error is sb.AuthApiException) {
    switch (error.code) {
      case 'user_already_exists':
      case 'email_exists':
        return 'That username is already taken.';
      case 'weak_password':
        return 'Please choose a stronger password.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Too many attempts. Wait a minute and try again.';
      case 'signup_disabled':
        return 'New accounts are closed at the moment.';
      case 'email_address_invalid':
      case 'email_address_not_authorized':
        // Our synthetic address was rejected by the project's email rules.
        // A learner cannot fix this; see account_identity.dart.
        return 'Sign-up isn’t available right now. Please try again later.';
    }
  }

  return 'Couldn’t create the account right now. Please try again.';
}

/// Message for a failure while deleting an account.
///
/// The wording has to be unambiguous that NOTHING was deleted. A learner who
/// reads a vague failure and assumes it half-worked has no way to check: we
/// hold no email, so we cannot write to them, and a still-live account looks
/// identical to one that failed to delete.
String deleteAccountErrorMessage(Object error) {
  if (isOfflineError(error)) {
    return 'Can’t reach the server, so your account was NOT deleted. '
        'Check your connection and try again.';
  }

  if (error is sb.AuthApiException || error is sb.PostgrestException) {
    final String? code = error is sb.AuthApiException
        ? error.code
        : (error as sb.PostgrestException).code;
    if (code == 'over_request_rate_limit') {
      return 'Too many attempts. Your account was NOT deleted — wait a minute '
          'and try again.';
    }
    if (code == '28000') {
      // The server refused because the JWT carried no user. Re-authenticating
      // is the only fix.
      return 'Your session has expired, so your account was NOT deleted. '
          'Sign in again and retry.';
    }
  }

  return 'Couldn’t delete the account right now. Nothing was deleted — '
      'please try again.';
}

/// True for the failures that mean "no usable network", as opposed to a real
/// rejection by the server. Drives the offline fallback in the repositories.
bool isOfflineError(Object error) {
  if (error is SocketException) return true;
  if (error is http.ClientException) return true;
  if (error is TimeoutException) return true;
  if (error is sb.AuthRetryableFetchException) return true;
  if (error is sb.PostgrestException) {
    // A gateway/timeout status means the request never reached Postgres. A real
    // rejection (RLS, constraint violation) carries an SQLSTATE instead, and
    // must NOT be mistaken for being offline — that would hide a bug behind a
    // "check your connection" message.
    return const <String>{'502', '503', '504', '408'}.contains(error.code);
  }
  return false;
}
