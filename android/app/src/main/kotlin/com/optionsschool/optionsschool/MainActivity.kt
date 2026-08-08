package com.optionsschool.optionsschool

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * FlutterFragmentActivity, not FlutterActivity.
 *
 * androidx.biometric's BiometricPrompt — which local_auth uses for the saved
 * sign-in — attaches to a FragmentActivity. Hosting Flutter in a plain
 * FlutterActivity compiles and runs perfectly well right up until the unlock
 * prompt is raised, which then fails at runtime with "requires
 * FragmentActivity". Nothing else in the app depends on this, so it looks
 * removable and is not.
 */
class MainActivity : FlutterFragmentActivity()
