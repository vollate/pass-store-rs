import 'dart:async';

import 'package:flutter/services.dart';

abstract interface class SensitiveClipboardPlatform {
  Future<void> write(
    String text, {
    required bool sensitive,
    required String ownerToken,
    Duration? expiresAfter,
  });

  Future<void> clearIfMatches(
    String expectedText, {
    required String ownerToken,
  });
}

class CallbackSensitiveClipboardPlatform implements SensitiveClipboardPlatform {
  const CallbackSensitiveClipboardPlatform(this.writer);

  final Future<void> Function(String text) writer;

  @override
  Future<void> write(
    String text, {
    required bool sensitive,
    required String ownerToken,
    Duration? expiresAfter,
  }) {
    return writer(text);
  }

  @override
  Future<void> clearIfMatches(
    String expectedText, {
    required String ownerToken,
  }) => writer('');
}

class SystemSensitiveClipboardPlatform implements SensitiveClipboardPlatform {
  const SystemSensitiveClipboardPlatform();

  static const MethodChannel _channel = MethodChannel(
    'top.vollate.pars_gui/sensitive_clipboard',
  );

  @override
  Future<void> write(
    String text, {
    required bool sensitive,
    required String ownerToken,
    Duration? expiresAfter,
  }) async {
    try {
      await _channel.invokeMethod<void>('setClipboard', <String, Object?>{
        'text': text,
        'sensitive': sensitive,
        'ownerToken': ownerToken,
        'expiresAfterSeconds': expiresAfter?.inSeconds,
      });
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Future<void> clearIfMatches(
    String expectedText, {
    required String ownerToken,
  }) async {
    try {
      await _channel.invokeMethod<void>('clearIfMatches', <String, Object?>{
        'expectedText': expectedText,
        'ownerToken': ownerToken,
      });
    } on MissingPluginException {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == expectedText) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    }
  }
}

class SensitiveClipboardService {
  SensitiveClipboardService({
    SensitiveClipboardPlatform platform =
        const SystemSensitiveClipboardPlatform(),
    this.clearDelay = const Duration(seconds: 45),
  }) : _platform = platform;

  final SensitiveClipboardPlatform _platform;
  final Duration clearDelay;
  Timer? _clearTimer;
  int _writeGeneration = 0;
  String? _lastSecret;
  String? _lastOwnerToken;

  Future<void> copySecret(String text) async {
    _writeGeneration += 1;
    final generation = _writeGeneration;
    final ownerToken = '${DateTime.now().microsecondsSinceEpoch}:$generation';
    _clearTimer?.cancel();
    _lastSecret = text;
    _lastOwnerToken = ownerToken;
    await _platform.write(
      text,
      sensitive: true,
      ownerToken: ownerToken,
      expiresAfter: clearDelay > Duration.zero ? clearDelay : null,
    );
    if (clearDelay <= Duration.zero) return;
    _clearTimer = Timer(clearDelay, () async {
      if (generation != _writeGeneration) return;
      await _platform.clearIfMatches(text, ownerToken: ownerToken);
      if (generation == _writeGeneration) {
        _lastSecret = null;
        _lastOwnerToken = null;
      }
    });
  }

  Future<void> clearNow() async {
    final expected = _lastSecret;
    final ownerToken = _lastOwnerToken;
    _writeGeneration += 1;
    _clearTimer?.cancel();
    _lastSecret = null;
    _lastOwnerToken = null;
    if (expected != null && ownerToken != null) {
      await _platform.clearIfMatches(expected, ownerToken: ownerToken);
    }
  }

  void dispose() {
    final expected = _lastSecret;
    final ownerToken = _lastOwnerToken;
    _writeGeneration += 1;
    _clearTimer?.cancel();
    _lastSecret = null;
    _lastOwnerToken = null;
    if (expected != null && ownerToken != null) {
      unawaited(_platform.clearIfMatches(expected, ownerToken: ownerToken));
    }
  }
}
