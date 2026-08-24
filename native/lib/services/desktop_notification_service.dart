import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

class DesktopNotificationService {
  bool _initialized = false;

  Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.windows || _initialized) return;
    await localNotifier.setup(
      appName: 'JHE Billing Hub',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    _initialized = true;
  }

  Future<void> show({
    required String id,
    required String title,
    required String body,
    VoidCallback? onClick,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    if (!_initialized) await initialize();
    if (!_initialized) return;
    final notification = LocalNotification(
      identifier: id,
      title: title,
      body: body,
    );
    notification.onClick = onClick;
    await notification.show();
  }
}
