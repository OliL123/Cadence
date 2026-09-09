import 'dart:html' as html;

/// Web: offer the bundled Android APK as a download. The href is relative, so
/// it resolves under the app's base href (…/Cadence/cadence.apk).
bool get canDownloadApk => true;

void downloadApk() {
  final a = html.AnchorElement(href: 'cadence.apk')
    ..setAttribute('download', 'cadence.apk')
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
}
