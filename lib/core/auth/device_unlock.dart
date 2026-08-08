import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// What this device can ask the learner for before releasing a saved sign-in.
///
/// [passcode] means there is a screen lock but no enrolled biometric — still a
/// perfectly good gate, and a common one on the hand-me-down and school devices
/// a student is likely to be using. [none] means there is no lock at all, and
/// the saved-sign-in feature is not offered: storing a password behind nothing
/// would be worse than making them type it.
enum DeviceLockKind { face, fingerprint, iris, passcode, none }

extension DeviceLockWording on DeviceLockKind {
  /// How to name this to a learner, mid-sentence.
  ///
  /// Apple requires its own marks for its own sensors, so iOS gets "Face ID"
  /// and "Touch ID" rather than a description of them.
  String get label {
    final bool isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return switch (this) {
      DeviceLockKind.face => isApple ? 'Face ID' : 'face unlock',
      DeviceLockKind.fingerprint => isApple ? 'Touch ID' : 'your fingerprint',
      DeviceLockKind.iris => 'iris unlock',
      DeviceLockKind.passcode => 'your device lock',
      DeviceLockKind.none => 'your device lock',
    };
  }
}

/// The device's own lock, used as the gate on a saved sign-in.
abstract interface class DeviceUnlock {
  /// What this device can offer right now. Re-read rather than cached: a
  /// learner can enrol a fingerprint, or remove their screen lock, at any time.
  Future<DeviceLockKind> lockKind();

  /// Raises the system prompt. True when the learner passed it, false when they
  /// dismissed it or it failed — a refusal is an ordinary outcome here, not an
  /// error to report.
  Future<bool> confirm(String reason);
}

class LocalAuthDeviceUnlock implements DeviceUnlock {
  const LocalAuthDeviceUnlock(this._auth);

  final LocalAuthentication _auth;

  @override
  Future<DeviceLockKind> lockKind() async {
    try {
      // Covers "has a screen lock", biometric or not — which is exactly the set
      // of devices [confirm] can prompt on.
      if (!await _auth.isDeviceSupported()) return DeviceLockKind.none;

      final List<BiometricType> enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.contains(BiometricType.face)) return DeviceLockKind.face;
      if (enrolled.contains(BiometricType.fingerprint)) {
        return DeviceLockKind.fingerprint;
      }
      if (enrolled.contains(BiometricType.iris)) return DeviceLockKind.iris;
      // Android reports `strong`/`weak` instead of naming the sensor on most
      // recent versions. Something is enrolled and we cannot tell what, so say
      // nothing specific rather than guessing wrong at the learner.
      return DeviceLockKind.passcode;
    } on Exception {
      // A platform that has no such thing at all (a desktop build, a test
      // harness). Not an error worth surfacing — the feature simply isn't on
      // offer.
      return DeviceLockKind.none;
    }
  }

  @override
  Future<bool> confirm(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Device PIN/pattern is accepted as well as a biometric. Insisting on a
        // fingerprint would shut out every learner whose phone has none, and it
        // is the screen lock that is actually being trusted here.
        biometricOnly: false,
        // Survives the app being backgrounded mid-prompt — switching away to
        // read a notification should not silently cancel the sign-in.
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      // Every failure is the same answer to the caller: not unlocked, so fall
      // back to the password form. Cancelling, no enrolled biometric and a
      // lockout are all ordinary here, and the OS has already told the learner
      // what happened — repeating it in the app would only say it worse.
      return false;
    }
  }
}
