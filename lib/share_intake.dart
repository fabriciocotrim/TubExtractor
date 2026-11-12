/// Receives text shared from other apps (e.g. "Compartilhar" in the YouTube
/// app). The Android side lives in MainActivity.kt.
library;

import 'package:flutter/services.dart';

class ShareIntake {
  static const _channel = MethodChannel('subshaul/share');

  /// Text that launched the app, if any. Consumed once.
  Future<String?> initialText() async {
    try {
      return await _channel.invokeMethod<String>('initialText');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Called when text is shared while the app is already open.
  void listen(void Function(String text) onText) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) onText(call.arguments as String);
    });
  }

  /// Stops [listen], so a closed screen is not called.
  void stop() => _channel.setMethodCallHandler(null);
}
