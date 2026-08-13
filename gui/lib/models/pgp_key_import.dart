/// Where PGP key material came from.
///
/// Deliberately independent of the key's kind: a file can hold a public key and pasted text can
/// hold a private one, so the source only decides which bridge call to make.
enum PgpImportSource { text, file }

extension PgpImportSourceLabel on PgpImportSource {
  String get label {
    switch (this) {
      case PgpImportSource.text:
        return 'Text';
      case PgpImportSource.file:
        return 'File';
    }
  }
}

enum PgpKeyKind { public, private }

extension PgpKeyKindLabel on PgpKeyKind {
  String get label {
    switch (this) {
      case PgpKeyKind.public:
        return 'Public key';
      case PgpKeyKind.private:
        return 'Private key';
    }
  }
}

/// What the bridge found in the supplied material. Never carries key bytes.
class PgpKeyInspection {
  const PgpKeyInspection({
    required this.kind,
    required this.fingerprint,
    required this.identity,
    required this.hasPrivateKey,
    required this.requiresPassphrase,
    required this.armored,
  });

  final PgpKeyKind kind;

  /// Canonical primary-key fingerprint, which every later step keys off.
  final String fingerprint;
  final String identity;
  final bool hasPrivateKey;

  /// True when the import needs a passphrase to complete.
  final bool requiresPassphrase;
  final bool armored;

  bool get isPrivate => kind == PgpKeyKind.private;

  @override
  bool operator ==(Object other) {
    return other is PgpKeyInspection &&
        other.kind == kind &&
        other.fingerprint == fingerprint &&
        other.identity == identity &&
        other.hasPrivateKey == hasPrivateKey &&
        other.requiresPassphrase == requiresPassphrase &&
        other.armored == armored;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    fingerprint,
    identity,
    hasPrivateKey,
    requiresPassphrase,
    armored,
  );
}

/// Why a PGP import failed.
///
/// The UI branches on this rather than on message text, so a wording change cannot turn a
/// "wrong passphrase" prompt into a generic error.
enum PgpImportFailureKind {
  unsupportedMaterial,
  kindMismatch,
  passphraseRequired,
  incorrectPassphrase,
  unsupportedProtection,
  reprotectionFailed,
  backendError,
  unknown,
}

/// A failed PGP import. The message is sanitized in Rust and holds no secret input.
class PgpImportException implements Exception {
  const PgpImportException(this.kind, this.message);

  final PgpImportFailureKind kind;
  final String message;

  bool get isPassphraseFailure =>
      kind == PgpImportFailureKind.passphraseRequired ||
      kind == PgpImportFailureKind.incorrectPassphrase;

  @override
  String toString() => message;
}
