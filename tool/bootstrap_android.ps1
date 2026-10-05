$ErrorActionPreference = "Stop"

flutter --version
flutter create --platforms=android --project-name family_home_manager --org com.yunfei.family .
dart run tool/patch_android_permissions.dart
dart run tool/patch_android_reminders.dart
flutter pub get

Write-Host ""
Write-Host "Android platform files are ready."
Write-Host "Run: flutter run"
