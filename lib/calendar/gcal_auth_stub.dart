/// Non-web fallback. Google sign-in on Android needs a separate native OAuth
/// client (added later), so on mobile this returns null for now.
Future<String?> getCalendarToken({required bool interactive}) async => null;

/// Whether the sign-in library is available on this platform.
bool get gcalAuthSupported => false;
