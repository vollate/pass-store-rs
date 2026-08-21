import '../l10n/app_localizations.dart';

class UiProblem {
  const UiProblem({required this.summary, this.diagnostics});

  final String summary;
  final String? diagnostics;

  factory UiProblem.fromError(AppLocalizations localizations, Object error) {
    return UiProblem(
      summary: localizations.operationFailed,
      diagnostics: _sanitizeDiagnostics(error.toString()),
    );
  }

  static String? _sanitizeDiagnostics(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.contains('BEGIN PGP PRIVATE KEY') ||
        value.contains('BEGIN PRIVATE KEY')) {
      return null;
    }
    value = value.replaceAll(
      RegExp(r'(passphrase|password)\s*[:=]\s*[^\s,;]+', caseSensitive: false),
      r'$1=[redacted]',
    );
    value = value.splitMapJoin(
      RegExp(r'\s+'),
      onMatch: (match) => match.group(0)!,
      onNonMatch: _sanitizeDiagnosticToken,
    );
    const maximumLength = 1200;
    if (value.length > maximumLength) {
      value = '${value.substring(0, maximumLength)}…';
    }
    return value;
  }

  static String _sanitizeDiagnosticToken(String token) {
    final leading =
        RegExp(r'''^[\'"(\[{]+''').firstMatch(token)?.group(0) ?? '';
    final trailing =
        RegExp(r'''[\'"),\]};]+$''').firstMatch(token)?.group(0) ?? '';
    if (leading.length + trailing.length > token.length) return token;
    final core = token.substring(
      leading.length,
      token.length - trailing.length,
    );
    final sanitized =
        core.startsWith('content://') || core.startsWith('file://')
            ? '[uri]'
            : core.contains('://')
            ? _sanitizeRemoteUrl(core)
            : core.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(core)
            ? '[path]'
            : core;
    return '$leading$sanitized$trailing';
  }

  static String _sanitizeRemoteUrl(String raw) {
    var value = raw.split('?').first.split('#').first;
    final schemeEnd = value.indexOf('://');
    if (schemeEnd < 0) return value;
    final authorityStart = schemeEnd + 3;
    final slash = value.indexOf('/', authorityStart);
    final authorityEnd = slash < 0 ? value.length : slash;
    final at = value.substring(authorityStart, authorityEnd).lastIndexOf('@');
    if (at >= 0) {
      value = value.replaceRange(
        authorityStart,
        authorityStart + at + 1,
        '***@',
      );
    }
    return value;
  }
}
