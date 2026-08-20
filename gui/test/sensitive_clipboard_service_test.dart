import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/sensitive_clipboard_service.dart';

void main() {
  testWidgets('sensitive clipboard clears after the configured delay', (
    tester,
  ) async {
    final platform = _RecordingClipboardPlatform();
    final service = SensitiveClipboardService(
      platform: platform,
      clearDelay: const Duration(seconds: 2),
    );
    addTearDown(service.dispose);

    await service.copySecret('secret');
    expect(platform.writes.single.text, 'secret');
    expect(platform.writes.single.sensitive, isTrue);
    expect(platform.writes.single.expiresAfter, const Duration(seconds: 2));

    await tester.pump(const Duration(seconds: 2));
    expect(platform.writes.last.text, isEmpty);
    expect(platform.writes.last.sensitive, isTrue);
  });

  testWidgets('new copy supersedes the previous clear timer', (tester) async {
    final platform = _RecordingClipboardPlatform();
    final service = SensitiveClipboardService(
      platform: platform,
      clearDelay: const Duration(seconds: 2),
    );
    addTearDown(service.dispose);

    await service.copySecret('first');
    await tester.pump(const Duration(seconds: 1));
    await service.copySecret('second');
    await tester.pump(const Duration(seconds: 1));
    expect(platform.writes.map((write) => write.text), <String>[
      'first',
      'second',
    ]);

    await tester.pump(const Duration(seconds: 1));
    expect(platform.writes.last.text, isEmpty);
  });

  testWidgets('scheduled clear preserves newer clipboard content', (
    tester,
  ) async {
    final platform = _OwnershipClipboardPlatform();
    final service = SensitiveClipboardService(
      platform: platform,
      clearDelay: const Duration(seconds: 2),
    );
    addTearDown(service.dispose);

    await service.copySecret('pars-secret');
    platform.replaceExternally('copied by another app');
    await tester.pump(const Duration(seconds: 2));

    expect(platform.currentText, 'copied by another app');
  });

  testWidgets('zero clear delay writes once without a timer', (tester) async {
    final platform = _RecordingClipboardPlatform();
    final service = SensitiveClipboardService(
      platform: platform,
      clearDelay: Duration.zero,
    );
    addTearDown(service.dispose);

    await service.copySecret('session-only');
    await tester.pump(const Duration(minutes: 1));

    expect(platform.writes, hasLength(1));
    expect(platform.writes.single.expiresAfter, isNull);
  });
}

class _RecordingClipboardPlatform implements SensitiveClipboardPlatform {
  final List<_ClipboardWrite> writes = <_ClipboardWrite>[];

  @override
  Future<void> clearIfMatches(
    String expectedText, {
    required String ownerToken,
  }) async {
    writes.add(
      const _ClipboardWrite(text: '', sensitive: true, expiresAfter: null),
    );
  }

  @override
  Future<void> write(
    String text, {
    required bool sensitive,
    required String ownerToken,
    Duration? expiresAfter,
  }) async {
    writes.add(
      _ClipboardWrite(
        text: text,
        sensitive: sensitive,
        expiresAfter: expiresAfter,
      ),
    );
  }
}

class _OwnershipClipboardPlatform implements SensitiveClipboardPlatform {
  String? currentText;
  String? currentOwnerToken;

  void replaceExternally(String text) {
    currentText = text;
    currentOwnerToken = 'external';
  }

  @override
  Future<void> write(
    String text, {
    required bool sensitive,
    required String ownerToken,
    Duration? expiresAfter,
  }) async {
    currentText = text;
    currentOwnerToken = ownerToken;
  }

  @override
  Future<void> clearIfMatches(
    String expectedText, {
    required String ownerToken,
  }) async {
    if (currentText == expectedText && currentOwnerToken == ownerToken) {
      currentText = null;
      currentOwnerToken = null;
    }
  }
}

class _ClipboardWrite {
  const _ClipboardWrite({
    required this.text,
    required this.sensitive,
    required this.expiresAfter,
  });

  final String text;
  final bool sensitive;
  final Duration? expiresAfter;
}
