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
    const maximumLength = 1200;
    if (value.length > maximumLength) {
      value = '${value.substring(0, maximumLength)}…';
    }
    return value;
  }
}
