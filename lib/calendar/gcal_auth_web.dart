import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../google_config.dart';

// ---- Google Identity Services (GIS) token-client interop ----
// The GIS library is loaded from index.html (accounts.google.com/gsi/client).
// We use the OAuth "token" model: request an access token in the browser and
// call the Calendar REST API directly with it. No client secret, no redirect.

@JS('google.accounts.oauth2.initTokenClient')
external _TokenClient _initTokenClient(_TokenConfig config);

extension type _TokenClient(JSObject _) implements JSObject {
  external void requestAccessToken([_OverrideConfig? override]);
}

extension type _TokenConfig._(JSObject _) implements JSObject {
  external factory _TokenConfig({
    String client_id,
    String scope,
    JSFunction callback,
    JSFunction? error_callback,
    String prompt,
  });
}

extension type _OverrideConfig._(JSObject _) implements JSObject {
  external factory _OverrideConfig({String prompt});
}

extension type _TokenResponse(JSObject _) implements JSObject {
  external String? get access_token;
  external String? get error;
  external int? get expires_in;
}

// ---- Code client (authorization-code flow) ----
// Unlike the token client this yields a one-time code that the gcal-token
// Supabase function exchanges for an access token AND a refresh token, so the
// app can renew access later with a plain request instead of a popup.

@JS('google.accounts.oauth2.initCodeClient')
external _CodeClient _initCodeClient(_CodeConfig config);

extension type _CodeClient(JSObject _) implements JSObject {
  external void requestCode();
}

extension type _CodeConfig._(JSObject _) implements JSObject {
  external factory _CodeConfig({
    String client_id,
    String scope,
    String ux_mode,
    JSFunction callback,
    JSFunction? error_callback,
  });
}

extension type _CodeResponse(JSObject _) implements JSObject {
  external String? get code;
  external String? get error;
}

bool get gcalAuthSupported => true;

/// On the web a "silent" token request is not silent — Google satisfies it by
/// opening its popup. Callers must never use it from an automatic path.
const bool silentTokenIsReallySilent = false;

/// Shows Google's consent popup and returns a one-time authorization code for
/// offline Calendar access, or null if the user cancelled. Must be called from
/// a user gesture (a tap), or the popup will be blocked.
Future<String?> getCalendarCode() async {
  if (!await _waitForGis()) return null;
  final completer = Completer<String?>();
  void done(String? c) {
    if (!completer.isCompleted) completer.complete(c);
  }

  try {
    _initCodeClient(_CodeConfig(
      client_id: googleClientId,
      scope: googleCalendarScope,
      ux_mode: 'popup',
      callback: ((_CodeResponse r) {
        final c = r.code;
        done((c != null && c.isNotEmpty) ? c : null);
      }).toJS,
      error_callback: ((JSObject _) => done(null)).toJS,
    )).requestCode();
  } catch (_) {
    done(null);
  }
  return completer.future.timeout(const Duration(minutes: 2), onTimeout: () => null);
}

/// True once the GIS script has finished loading and defined the oauth2 API.
bool _gisReady() {
  if (!globalContext.has('google')) return false;
  final google = globalContext.getProperty('google'.toJS) as JSObject;
  if (!google.has('accounts')) return false;
  final accounts = google.getProperty('accounts'.toJS) as JSObject;
  return accounts.has('oauth2');
}

Future<bool> _waitForGis() async {
  for (var i = 0; i < 60; i++) {
    if (_gisReady()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return _gisReady();
}

/// Requests an OAuth access token for the read-only Calendar scope.
///
/// [interactive] true shows Google's account/consent popup; false attempts a
/// silent refresh (works only if the user has already granted access this
/// browser session / recently). Returns (token, secondsUntilExpiry) or null.
Future<(String, int)?> getCalendarToken({required bool interactive}) async {
  if (!await _waitForGis()) return null;
  final completer = Completer<(String, int)?>();

  void done((String, int)? result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  final config = _TokenConfig(
    client_id: googleClientId,
    scope: googleCalendarScope,
    prompt: interactive ? 'consent' : '',
    callback: ((_TokenResponse resp) {
      final t = resp.access_token;
      done((t != null && t.isNotEmpty) ? (t, resp.expires_in ?? 3600) : null);
    }).toJS,
    error_callback: ((JSObject _) => done(null)).toJS,
  );

  try {
    final client = _initTokenClient(config);
    // For a silent attempt, override prompt to '' so no popup appears.
    client.requestAccessToken(
        interactive ? null : _OverrideConfig(prompt: ''));
  } catch (_) {
    done(null);
  }

  // Safety timeout: if the popup is closed without a callback, don't hang.
  return completer.future.timeout(const Duration(minutes: 2), onTimeout: () => null);
}
