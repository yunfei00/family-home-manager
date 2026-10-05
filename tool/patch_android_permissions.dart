import 'dart:io';

void main() {
  final file = File('android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) {
    stderr.writeln('AndroidManifest.xml not found. Run flutter create first.');
    exitCode = 1;
    return;
  }

  var content = file.readAsStringSync();
  const manifestMarker =
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">';
  const applicationMarker = '    <application';

  const permissions = [
    '    <uses-permission android:name="android.permission.INTERNET" />',
    '    <uses-permission android:name="android.permission.CAMERA" />',
  ];

  if (!content.contains(manifestMarker) || !content.contains(applicationMarker)) {
    stderr.writeln('Unexpected AndroidManifest.xml format.');
    exitCode = 1;
    return;
  }

  final missingPermissions =
      permissions.where((line) => !content.contains(line)).toList();
  if (missingPermissions.isNotEmpty) {
    content = content.replaceFirst(
      manifestMarker,
      '$manifestMarker\n${missingPermissions.join('\n')}',
    );
  }

  if (!content.contains('android:usesCleartextTraffic=')) {
    content = content.replaceFirst(
      applicationMarker,
      '$applicationMarker\n        android:usesCleartextTraffic="true"',
    );
  }

  file.writeAsStringSync(content);
}
