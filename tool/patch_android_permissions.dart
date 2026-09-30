import 'dart:io';

void main() {
  final file = File('android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) {
    stderr.writeln('AndroidManifest.xml not found. Run flutter create first.');
    exitCode = 1;
    return;
  }

  var content = file.readAsStringSync();
  const marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">';
  const permissions = [
    '    <uses-permission android:name="android.permission.RECORD_AUDIO" />',
    '    <uses-permission android:name="android.permission.CAMERA" />',
  ];

  if (!content.contains(marker)) {
    stderr.writeln('Unexpected AndroidManifest.xml format.');
    exitCode = 1;
    return;
  }

  final missing = permissions.where((line) => !content.contains(line)).toList();
  if (missing.isEmpty) return;

  content = content.replaceFirst(
    marker,
    '$marker\n${missing.join('\n')}',
  );
  file.writeAsStringSync(content);
}
