import '../models/key_record.dart';
import '../models/password_entry.dart';

class DemoVaultRepository {
  const DemoVaultRepository();

  String get currentRepoName => '~/.password-store';

  RepoGitStatus get gitStatus => RepoGitStatus.clean;

  List<PasswordEntry> get entries => const <PasswordEntry>[
    PasswordEntry(
      path: 'work/dev/github',
      displayName: 'GitHub',
      repoName: '~/.password-store',
      encryptedContent:
          's3cret-github\nusername: Vollate\nurl: https://github.com\ncreated on desktop',
      isFavorite: true,
      lastUsedLabel: 'Today',
    ),
    PasswordEntry(
      path: 'finance/stripe',
      displayName: 'Stripe',
      repoName: '~/.password-store',
      encryptedContent:
          'stripe-passphrase\nlogin: billing@example.com\nwebsite: https://dashboard.stripe.com',
      lastUsedLabel: 'Yesterday',
    ),
    PasswordEntry(
      path: 'infra/prod/root',
      displayName: 'Root server',
      repoName: '~/.password-store',
      encryptedContent: 'root-server-password\nssh jump host\nrotate manually',
    ),
    PasswordEntry(
      path: 'work',
      displayName: 'work',
      repoName: '~/.password-store',
      encryptedContent: '',
      isDirectory: true,
      childCount: 8,
    ),
    PasswordEntry(
      path: 'finance',
      displayName: 'finance',
      repoName: '~/.password-store',
      encryptedContent: '',
      isDirectory: true,
      childCount: 5,
    ),
  ];

  List<KeyRecord> get keys => const <KeyRecord>[
    KeyRecord(
      type: KeyRecordType.pgp,
      name: 'Vollate <me@example.com>',
      fingerprint: '3A8E 9C12 77FA 22D1 90BD 48AA A991 D3B4 A702 91EF',
      source: 'Generated on device',
      hasPrivateKey: true,
    ),
    KeyRecord(
      type: KeyRecordType.ssh,
      name: 'github-mobile-ed25519',
      fingerprint: 'SHA256:4m0ckedGitHubSshKeyFingerprint',
      source: 'Imported from text',
      hasPrivateKey: true,
    ),
  ];

  List<PasswordEntry> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return entries;
    }
    return entries
        .where(
          (entry) =>
              entry.displayName.toLowerCase().contains(normalized) ||
              entry.path.toLowerCase().contains(normalized),
        )
        .toList();
  }
}
