import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optionsschool/data/supabase/account_identity.dart';
import 'package:optionsschool/data/supabase/supabase_error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// What a learner is told when the backend says no.
void main() {
  group('sign-in', () {
    test('bad credentials never reveal which half was wrong', () {
      const sb.AuthApiException wrongPassword = sb.AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );
      const sb.AuthApiException noSuchUser = sb.AuthApiException(
        'User not found',
        statusCode: '400',
        code: 'user_not_found',
      );

      expect(
        signInErrorMessage(wrongPassword),
        signInErrorMessage(noSuchUser),
        reason: 'differing messages would confirm which usernames exist',
      );
      expect(signInErrorMessage(wrongPassword), 'Incorrect username or password.');
    });

    test('rate limiting says to wait, not that the password is wrong', () {
      const sb.AuthApiException limited = sb.AuthApiException(
        'Too many requests',
        statusCode: '429',
        code: 'over_request_rate_limit',
      );
      expect(signInErrorMessage(limited), contains('Wait a minute'));
    });

    test('an outage is not blamed on the learner', () {
      final Object offline = const SocketException('no route to host');
      expect(signInErrorMessage(offline), contains('Check your connection'));
      expect(signInErrorMessage(offline), isNot(contains('password')));
    });

    test('an unrecognised failure still gets a usable sentence', () {
      expect(signInErrorMessage(StateError('?')), contains('try again'));
    });
  });

  group('sign-up', () {
    test('a taken username is named as such', () {
      const sb.AuthApiException exists = sb.AuthApiException(
        'User already registered',
        statusCode: '422',
        code: 'user_already_exists',
      );
      expect(signUpErrorMessage(exists), 'That username is already taken.');
    });

    test('a weak password is answered with the rule, not with "stronger"', () {
      const sb.AuthApiException weak = sb.AuthApiException(
        'Password is too weak',
        statusCode: '422',
        code: 'weak_password',
      );
      // "Choose a stronger password" leaves the learner guessing at which of
      // length, letters or digits it wanted. State the requirement instead.
      expect(signUpErrorMessage(weak), PasswordRule.describe);
      expect(signUpErrorMessage(weak), contains('number'));
    });

    test('a rejected synthetic address does not blame the learner', () {
      // They never typed an address, so "invalid email" would be nonsense.
      const sb.AuthApiException badEmail = sb.AuthApiException(
        'Email address is invalid',
        statusCode: '400',
        code: 'email_address_invalid',
      );
      expect(signUpErrorMessage(badEmail), isNot(contains('email')));
      expect(signUpErrorMessage(badEmail), contains('try again later'));
    });
  });

  group('offline detection', () {
    test('transport failures count as offline', () {
      expect(isOfflineError(const SocketException('down')), isTrue);
      expect(isOfflineError(http.ClientException('failed')), isTrue);
      expect(isOfflineError(TimeoutException('slow')), isTrue);
      expect(isOfflineError(sb.AuthRetryableFetchException()), isTrue);
      expect(
        isOfflineError(
          sb.PostgrestException(message: 'bad gateway', code: '502'),
        ),
        isTrue,
      );
    });

    test('a real rejection is NOT treated as offline', () {
      // 42501 = insufficient_privilege, i.e. an RLS policy did its job. Hiding
      // that behind "check your connection" would bury a genuine bug.
      expect(
        isOfflineError(
          sb.PostgrestException(message: 'permission denied', code: '42501'),
        ),
        isFalse,
      );
      // 23505 = unique violation (a taken username).
      expect(
        isOfflineError(
          sb.PostgrestException(message: 'duplicate key', code: '23505'),
        ),
        isFalse,
      );
      expect(isOfflineError(StateError('nope')), isFalse);
    });
  });
}
