import 'package:flutter/foundation.dart';

/// Десктопная раскладка: Windows, Linux, macOS.
///
/// Web и мобильные платформы (Android, iOS) используют мобильную раскладку.
bool isDesktopLayout() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };
}
