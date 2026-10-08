import 'dart:html' as html;

/// The Android APK lives on a GitHub release (tag `apk`, uploaded by
/// tool/release_apk.sh), not in the repo: committing it every deploy had
/// grown the repo past 250 MiB. GitHub serves it as an attachment, so the
/// link downloads even though it's cross-origin.
const apkUrl = 'https://github.com/OliL123/Cadence/releases/download/apk/cadence.apk';

bool get canDownloadApk => true;

void downloadApk() {
  final a = html.AnchorElement(href: apkUrl)
    ..setAttribute('download', 'cadence.apk')
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
}
