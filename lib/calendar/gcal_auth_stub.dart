import 'dart:io' show Platform;
import 'package:google_sign_in/google_sign_in.dart';

import '../google_config.dart';

// Native (mobile) Google sign-in. Web uses gcal_auth_web.dart via conditional
// import instead. Android matches the OAuth client by package name + SHA-1, so
// no client id is needed here — only the scopes.
final GoogleSignIn _gsi = GoogleSignIn(scopes: const [googleCalendarScope]);

/// Calendar sign-in is wired up on phones/tablets; on desktop it isn't (no
/// google_sign_in platform implementation), so hide the button there.
bool get gcalAuthSupported => Platform.isAndroid || Platform.isIOS;

/// Returns (access token, secondsUntilExpiry) for the read-only Calendar scope,
/// or null. [interactive] true shows the account picker; false is silent.
/// google_sign_in refreshes its own token, so the expiry here is just a hint.
Future<(String, int)?> getCalendarToken({required bool interactive}) async {
  try {
    GoogleSignInAccount? account =
        interactive ? await _gsi.signIn() : await _gsi.signInSilently();
    if (account == null) return null;
    final tokens = await account.authentication;
    final t = tokens.accessToken;
    return t == null ? null : (t, 3000);
  } catch (_) {
    return null;
  }
}
