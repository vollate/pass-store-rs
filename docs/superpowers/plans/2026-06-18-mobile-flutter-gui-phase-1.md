# Mobile Flutter GUI Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Flutter counter template with a mobile-first Pars password-manager UI that demonstrates onboarding, Vault, Manage, Settings, entry parsing, and safety-oriented controls using in-memory demo data.

**Architecture:** Build a self-contained Flutter UI slice under `gui/lib/` with small model, fixture, parsing, and screen files. This phase does not connect to Rust core, real PGP, real Git, biometrics, or platform KMS; it creates clear interfaces and visible UX states that later phases can wire to real services.

**Tech Stack:** Flutter Material 3, Dart 3.7, `flutter_test`, existing `flutter_lints`. No new package dependencies in phase 1.

---

## Scope

This plan implements phase 1 only:

- Mobile UI shell with `Vault`, `Manage`, and `Settings` bottom tabs.
- First-run onboarding mock flow with 9-dot gesture setup screens.
- Vault list/search/browse demo data.
- Entry detail bottom sheet with masked password, parsed fields, raw notes, and action buttons.
- Manage screen for generate/create/edit/delete/batch-regenerate entry workflows as UI flows.
- Settings screens for security, key management, password stores, Git, and advanced Git args.
- Best-effort pass metadata parser with unit tests.

Out of scope for this phase:

- Rust FFI bridge.
- Real PGP encryption/decryption.
- Real Git execution.
- Real biometric/KMS/Keychain integration.
- Real QR code rendering.
- Persisted state.

## File Structure

- `gui/lib/main.dart`
  - Minimal `main()` that runs `ParsGuiApp`.
- `gui/lib/app/pars_gui_app.dart`
  - Root `MaterialApp`, app theme, and initial onboarding/home switching state.
- `gui/lib/app/pars_theme.dart`
  - Mobile-focused Material theme constants.
- `gui/lib/models/password_entry.dart`
  - Entry, repo status, and parsed secret models.
- `gui/lib/models/key_record.dart`
  - PGP/SSH key display model used by Settings.
- `gui/lib/services/pass_entry_parser.dart`
  - First-line password plus best-effort metadata parser.
- `gui/lib/services/demo_vault_repository.dart`
  - Demo data for entries, keys, repo status, and onboarding state.
- `gui/lib/screens/onboarding/onboarding_screen.dart`
  - First-run setup mock flow.
- `gui/lib/screens/shell/mobile_shell.dart`
  - Bottom navigation and tab switching.
- `gui/lib/screens/vault/vault_screen.dart`
  - Daily Vault UI: repo status, search, recent entries, browse list, pull-to-sync.
- `gui/lib/screens/vault/entry_detail_sheet.dart`
  - Bottom sheet for entry actions and parsed fields.
- `gui/lib/screens/manage/manage_screen.dart`
  - Maintenance UI for generate/create/edit/delete/batch workflows.
- `gui/lib/screens/settings/settings_screen.dart`
  - Settings overview and drill-in sheets/sections.
- `gui/lib/widgets/app_section.dart`
  - Reusable section header/container primitives.
- `gui/lib/widgets/entry_tile.dart`
  - Password entry list tile with copy shortcut.
- `gui/test/pass_entry_parser_test.dart`
  - Parser unit tests.
- `gui/test/mobile_gui_smoke_test.dart`
  - Widget tests for onboarding, tabs, Vault detail sheet, Manage, and Settings.
- `gui/test/widget_test.dart`
  - Replace counter test with a small compatibility smoke test or delete if covered.

## Task 1: Add Domain Models, Parser, and Demo Data

**Files:**
- Create: `gui/lib/models/password_entry.dart`
- Create: `gui/lib/models/key_record.dart`
- Create: `gui/lib/services/pass_entry_parser.dart`
- Create: `gui/lib/services/demo_vault_repository.dart`
- Test: `gui/test/pass_entry_parser_test.dart`

- [ ] **Step 1: Write parser tests**

Create `gui/test/pass_entry_parser_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/pass_entry_parser.dart';

void main() {
  group('PassEntryParser', () {
    test('uses the first line as password', () {
      final content = PassEntryParser.parse('hunter2');

      expect(content.password, 'hunter2');
      expect(content.fields, isEmpty);
      expect(content.rawNotes, isEmpty);
    });

    test('parses common metadata fields after first line', () {
      final content = PassEntryParser.parse('hunter2\nusername: alice\nurl: https://github.com\nemail: alice@example.com');

      expect(content.password, 'hunter2');
      expect(content.fieldValue('username'), 'alice');
      expect(content.fieldValue('url'), 'https://github.com');
      expect(content.fieldValue('email'), 'alice@example.com');
      expect(content.rawNotes, isEmpty);
    });

    test('preserves unknown metadata as raw notes', () {
      final content = PassEntryParser.parse('hunter2\nsecurity question answer\nproject=demo');

      expect(content.password, 'hunter2');
      expect(content.fields, isEmpty);
      expect(content.rawNotes, 'security question answer\nproject=demo');
    });

    test('keeps mixed known and unknown lines', () {
      final content = PassEntryParser.parse('hunter2\nlogin: alice\ncreated by hand\nwebsite: https://example.com');

      expect(content.fieldValue('login'), 'alice');
      expect(content.fieldValue('website'), 'https://example.com');
      expect(content.rawNotes, 'created by hand');
    });
  });
}
```

- [ ] **Step 2: Run parser tests and verify they fail**

Run:

```powershell
flutter test test/pass_entry_parser_test.dart
```

Working directory: `gui`

Expected: FAIL because `PassEntryParser` does not exist.

- [ ] **Step 3: Create password entry models**

Create `gui/lib/models/password_entry.dart`:

```dart
enum RepoGitStatus {
  clean,
  needPull,
  uncommitted,
  syncFailed,
}

extension RepoGitStatusLabel on RepoGitStatus {
  String get label {
    switch (this) {
      case RepoGitStatus.clean:
        return 'Clean';
      case RepoGitStatus.needPull:
        return 'Need pull';
      case RepoGitStatus.uncommitted:
        return 'Uncommitted';
      case RepoGitStatus.syncFailed:
        return 'Sync failed';
    }
  }
}

class PasswordEntry {
  const PasswordEntry({
    required this.path,
    required this.displayName,
    required this.repoName,
    required this.encryptedContent,
    this.isDirectory = false,
    this.childCount = 0,
    this.isFavorite = false,
    this.lastUsedLabel,
  });

  final String path;
  final String displayName;
  final String repoName;
  final String encryptedContent;
  final bool isDirectory;
  final int childCount;
  final bool isFavorite;
  final String? lastUsedLabel;

  String get parentPath {
    final index = path.lastIndexOf('/');
    if (index == -1) {
      return repoName;
    }
    return path.substring(0, index);
  }

  String get initials {
    if (displayName.isEmpty) {
      return '?';
    }
    return displayName.characters.first.toUpperCase();
  }
}

class ParsedSecretField {
  const ParsedSecretField({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final String value;
}

class SecretContent {
  const SecretContent({
    required this.password,
    required this.fields,
    required this.rawNotes,
  });

  final String password;
  final List<ParsedSecretField> fields;
  final String rawNotes;

  String? fieldValue(String key) {
    for (final field in fields) {
      if (field.key == key) {
        return field.value;
      }
    }
    return null;
  }
}
```

- [ ] **Step 4: Create key record model**

Create `gui/lib/models/key_record.dart`:

```dart
enum KeyRecordType {
  pgp,
  ssh,
}

class KeyRecord {
  const KeyRecord({
    required this.type,
    required this.name,
    required this.fingerprint,
    required this.source,
    required this.hasPrivateKey,
  });

  final KeyRecordType type;
  final String name;
  final String fingerprint;
  final String source;
  final bool hasPrivateKey;

  String get typeLabel {
    switch (type) {
      case KeyRecordType.pgp:
        return 'PGP';
      case KeyRecordType.ssh:
        return 'SSH';
    }
  }
}
```

- [ ] **Step 5: Create parser implementation**

Create `gui/lib/services/pass_entry_parser.dart`:

```dart
import '../models/password_entry.dart';

class PassEntryParser {
  static const Map<String, String> _knownLabels = <String, String>{
    'username': 'Username',
    'user': 'User',
    'login': 'Login',
    'email': 'Email',
    'url': 'URL',
    'website': 'Website',
    'totp': 'TOTP',
    'otp': 'OTP',
    'note': 'Note',
  };

  static SecretContent parse(String plainText) {
    final normalized = plainText.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final password = lines.isEmpty ? '' : lines.first;
    final fields = <ParsedSecretField>[];
    final rawNotes = <String>[];

    for (final line in lines.skip(1)) {
      final parsed = _parseField(line);
      if (parsed == null) {
        if (line.isNotEmpty) {
          rawNotes.add(line);
        }
      } else {
        fields.add(parsed);
      }
    }

    return SecretContent(
      password: password,
      fields: fields,
      rawNotes: rawNotes.join('\n'),
    );
  }

  static ParsedSecretField? _parseField(String line) {
    final separatorIndex = line.indexOf(':');
    if (separatorIndex <= 0) {
      return null;
    }

    final rawKey = line.substring(0, separatorIndex).trim();
    final key = rawKey.toLowerCase();
    final label = _knownLabels[key];
    if (label == null) {
      return null;
    }

    final value = line.substring(separatorIndex + 1).trim();
    if (value.isEmpty) {
      return null;
    }

    return ParsedSecretField(key: key, label: label, value: value);
  }
}
```

- [ ] **Step 6: Create demo repository**

Create `gui/lib/services/demo_vault_repository.dart`:

```dart
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
          encryptedContent: 's3cret-github\nusername: Vollate\nurl: https://github.com\ncreated on desktop',
          isFavorite: true,
          lastUsedLabel: 'Today',
        ),
        PasswordEntry(
          path: 'finance/stripe',
          displayName: 'Stripe',
          repoName: '~/.password-store',
          encryptedContent: 'stripe-passphrase\nlogin: billing@example.com\nwebsite: https://dashboard.stripe.com',
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
```

- [ ] **Step 7: Run parser tests and analyze**

Run:

```powershell
flutter test test/pass_entry_parser_test.dart
flutter analyze
```

Working directory: `gui`

Expected: parser tests PASS. Analyze may still report failures from the template app until later tasks remove it.

- [ ] **Step 8: Commit task 1**

```powershell
git add gui/lib/models/password_entry.dart gui/lib/models/key_record.dart gui/lib/services/pass_entry_parser.dart gui/lib/services/demo_vault_repository.dart gui/test/pass_entry_parser_test.dart
git commit -m "feat(gui): add mobile vault demo models"
```

## Task 2: Replace Counter Template with App Shell

**Files:**
- Modify: `gui/lib/main.dart`
- Create: `gui/lib/app/pars_gui_app.dart`
- Create: `gui/lib/app/pars_theme.dart`
- Create: `gui/lib/screens/shell/mobile_shell.dart`
- Create: `gui/lib/widgets/app_section.dart`
- Test: `gui/test/mobile_gui_smoke_test.dart`
- Modify: `gui/test/widget_test.dart`

- [ ] **Step 1: Write app shell widget test**

Create `gui/test/mobile_gui_smoke_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/main.dart';

void main() {
  testWidgets('shows onboarding before entering the vault', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());

    expect(find.text('Set gesture lock'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('enters the mobile shell after onboarding', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart
```

Working directory: `gui`

Expected: FAIL because `ParsGuiApp` and onboarding shell do not exist.

- [ ] **Step 3: Replace `main.dart`**

Modify `gui/lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'app/pars_gui_app.dart';

void main() {
  runApp(const ParsGuiApp());
}
```

- [ ] **Step 4: Add app theme**

Create `gui/lib/app/pars_theme.dart`:

```dart
import 'package:flutter/material.dart';

class ParsTheme {
  static const Color primary = Color(0xFF0F766E);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color mutedSurface = Color(0xFFE2E8F0);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: surface,
        foregroundColor: Color(0xFF0F172A),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF64748B),
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mutedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Add reusable section widget**

Create `gui/lib/widgets/app_section.dart`:

```dart
import 'package:flutter/material.dart';

class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Add app root**

Create `gui/lib/app/pars_gui_app.dart`:

```dart
import 'package:flutter/material.dart';

import '../screens/onboarding/onboarding_screen.dart';
import '../screens/shell/mobile_shell.dart';
import '../services/demo_vault_repository.dart';
import 'pars_theme.dart';

class ParsGuiApp extends StatefulWidget {
  const ParsGuiApp({super.key});

  @override
  State<ParsGuiApp> createState() => _ParsGuiAppState();
}

class _ParsGuiAppState extends State<ParsGuiApp> {
  bool _isOnboardingComplete = false;
  final DemoVaultRepository _repository = const DemoVaultRepository();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pars',
      debugShowCheckedModeBanner: false,
      theme: ParsTheme.light(),
      home: _isOnboardingComplete
          ? MobileShell(repository: _repository)
          : OnboardingScreen(
              onComplete: () {
                setState(() => _isOnboardingComplete = true);
              },
            ),
    );
  }
}
```

- [ ] **Step 7: Add temporary mobile shell**

Create `gui/lib/screens/shell/mobile_shell.dart`:

```dart
import 'package:flutter/material.dart';

import '../../services/demo_vault_repository.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.repository});

  final DemoVaultRepository repository;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const Center(child: Text('Vault')),
      const Center(child: Text('Manage')),
      const Center(child: Text('Settings')),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.lock_outline), label: 'Vault'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Manage'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: Add onboarding screen**

Create `gui/lib/screens/onboarding/onboarding_screen.dart`:

```dart
import 'package:flutter/material.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 24),
              Text('Set gesture lock', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Use a 9-dot gesture as the local Pars unlock method. Biometrics can be enabled after setup.'),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 190,
                    height: 190,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 24,
                      children: List<Widget>.generate(
                        9,
                        (index) => DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              FilledButton(
                onPressed: onComplete,
                child: const SizedBox(width: double.infinity, child: Center(child: Text('Continue'))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: Replace template widget test**

Modify `gui/test/widget_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/main.dart';

void main() {
  testWidgets('Pars app starts at gesture onboarding', (tester) async {
    await tester.pumpWidget(const ParsGuiApp());

    expect(find.text('Set gesture lock'), findsOneWidget);
  });
}
```

- [ ] **Step 10: Run app shell tests**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart test/widget_test.dart
flutter analyze
```

Working directory: `gui`

Expected: PASS.

- [ ] **Step 11: Commit task 2**

```powershell
git add gui/lib/main.dart gui/lib/app/pars_gui_app.dart gui/lib/app/pars_theme.dart gui/lib/screens/onboarding/onboarding_screen.dart gui/lib/screens/shell/mobile_shell.dart gui/lib/widgets/app_section.dart gui/test/mobile_gui_smoke_test.dart gui/test/widget_test.dart
git commit -m "feat(gui): add mobile app shell"
```

## Task 3: Implement Vault and Entry Detail Bottom Sheet

**Files:**
- Create: `gui/lib/widgets/entry_tile.dart`
- Create: `gui/lib/screens/vault/vault_screen.dart`
- Create: `gui/lib/screens/vault/entry_detail_sheet.dart`
- Modify: `gui/lib/screens/shell/mobile_shell.dart`
- Test: `gui/test/mobile_gui_smoke_test.dart`

- [ ] **Step 1: Extend widget tests for Vault**

Append to `gui/test/mobile_gui_smoke_test.dart`:

```dart
testWidgets('vault searches entries and opens detail sheet', (tester) async {
  await tester.pumpWidget(const ParsGuiApp());
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();

  expect(find.text('GitHub'), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'stripe');
  await tester.pumpAndSettle();

  expect(find.text('Stripe'), findsOneWidget);
  expect(find.text('GitHub'), findsNothing);

  await tester.tap(find.text('Stripe'));
  await tester.pumpAndSettle();

  expect(find.text('Copy password'), findsOneWidget);
  expect(find.text('Reveal'), findsOneWidget);
  expect(find.text('Raw notes'), findsNothing);
});
```

- [ ] **Step 2: Run Vault test and verify it fails**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart
```

Working directory: `gui`

Expected: FAIL because Vault screen is still a temporary stub.

- [ ] **Step 3: Create entry tile**

Create `gui/lib/widgets/entry_tile.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/password_entry.dart';

class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onCopy,
  });

  final PasswordEntry entry;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          child: Text(entry.initials),
        ),
        title: Text(entry.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          entry.isDirectory ? '${entry.childCount} entries' : entry.parentPath,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: entry.isDirectory
            ? const Icon(Icons.chevron_right)
            : TextButton(
                onPressed: onCopy,
                child: const Text('Copy'),
              ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create detail sheet**

Create `gui/lib/screens/vault/entry_detail_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../models/password_entry.dart';
import '../../services/pass_entry_parser.dart';

class EntryDetailSheet extends StatefulWidget {
  const EntryDetailSheet({super.key, required this.entry});

  final PasswordEntry entry;

  @override
  State<EntryDetailSheet> createState() => _EntryDetailSheetState();
}

class _EntryDetailSheetState extends State<EntryDetailSheet> {
  bool _isRevealed = false;

  @override
  Widget build(BuildContext context) {
    final content = PassEntryParser.parse(widget.entry.encryptedContent);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: Text(widget.entry.initials),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.entry.displayName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(widget.entry.path, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _isRevealed ? content.password : '••••••••••••••',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: _isRevealed ? 0 : 2),
                      ),
                    ),
                    IconButton(
                      tooltip: _isRevealed ? 'Hide' : 'Reveal',
                      onPressed: () => setState(() => _isRevealed = !_isRevealed),
                      icon: Icon(_isRevealed ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.copy), label: const Text('Copy password')),
                OutlinedButton.icon(onPressed: () => setState(() => _isRevealed = !_isRevealed), icon: const Icon(Icons.visibility_outlined), label: const Text('Reveal')),
                OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
                OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.qr_code_2), label: const Text('QR code')),
                OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.refresh), label: const Text('Regenerate')),
                OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
              ],
            ),
            if (content.fields.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Fields', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final field in content.fields)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(field.label),
                  subtitle: Text(field.value),
                  trailing: TextButton(onPressed: () {}, child: const Text('Copy')),
                ),
            ],
            if (content.rawNotes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('Raw notes', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(content.rawNotes),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Create Vault screen**

Create `gui/lib/screens/vault/vault_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../models/password_entry.dart';
import '../../services/demo_vault_repository.dart';
import '../../widgets/app_section.dart';
import '../../widgets/entry_tile.dart';
import 'entry_detail_sheet.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.repository});

  final DemoVaultRepository repository;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.repository.search(_query);
    final recent = entries.where((entry) => !entry.isDirectory).toList();
    final directories = entries.where((entry) => entry.isDirectory).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      child: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Vault', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(widget.repository.currentRepoName, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  label: Text(widget.repository.gitStatus.label),
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by name or path',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
          AppSection(
            title: _query.isEmpty ? 'Recent' : 'Search results',
            children: recent
                .map(
                  (entry) => EntryTile(
                    entry: entry,
                    onTap: () => _showEntry(entry),
                    onCopy: () => _showCopied(entry),
                  ),
                )
                .toList(),
          ),
          if (_query.isEmpty)
            AppSection(
              title: 'Browse',
              children: directories
                  .map(
                    (entry) => EntryTile(
                      entry: entry,
                      onTap: () {},
                      onCopy: () {},
                    ),
                  )
                  .toList(),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  void _showEntry(PasswordEntry entry) {
    if (entry.isDirectory) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => EntryDetailSheet(entry: entry),
    );
  }

  void _showCopied(PasswordEntry entry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${entry.displayName} password')),
    );
  }
}
```

- [ ] **Step 6: Wire Vault into shell**

Modify `gui/lib/screens/shell/mobile_shell.dart` so page 0 is `VaultScreen(repository: widget.repository)`.

Required imports:

```dart
import '../vault/vault_screen.dart';
```

Replace the first page in `pages`:

```dart
VaultScreen(repository: widget.repository),
```

- [ ] **Step 7: Run Vault tests**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart
flutter analyze
```

Working directory: `gui`

Expected: PASS.

- [ ] **Step 8: Commit task 3**

```powershell
git add gui/lib/widgets/entry_tile.dart gui/lib/screens/vault/vault_screen.dart gui/lib/screens/vault/entry_detail_sheet.dart gui/lib/screens/shell/mobile_shell.dart gui/test/mobile_gui_smoke_test.dart
git commit -m "feat(gui): build mobile vault screen"
```

## Task 4: Implement Manage Screen

**Files:**
- Create: `gui/lib/screens/manage/manage_screen.dart`
- Modify: `gui/lib/screens/shell/mobile_shell.dart`
- Test: `gui/test/mobile_gui_smoke_test.dart`

- [ ] **Step 1: Add Manage widget test**

Append to `gui/test/mobile_gui_smoke_test.dart`:

```dart
testWidgets('manage tab exposes batch management workflows', (tester) async {
  await tester.pumpWidget(const ParsGuiApp());
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Manage'));
  await tester.pumpAndSettle();

  expect(find.text('Generate and save'), findsOneWidget);
  expect(find.text('Save existing password'), findsOneWidget);
  expect(find.text('Batch delete'), findsOneWidget);
  expect(find.text('Regenerate selected'), findsOneWidget);
});
```

- [ ] **Step 2: Run Manage test and verify it fails**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart
```

Working directory: `gui`

Expected: FAIL because Manage tab is still a temporary stub.

- [ ] **Step 3: Create Manage screen**

Create `gui/lib/screens/manage/manage_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../services/demo_vault_repository.dart';

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key, required this.repository});

  final DemoVaultRepository repository;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text('Manage', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: <Widget>[
              Text('Maintain passwords in batches or one at a time.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              _ManageActionCard(
                title: 'Generate and save',
                subtitle: 'Create one or many entries with generated passwords.',
                icon: Icons.auto_fix_high,
                onTap: () => _showPreview(context, 'Generate and save'),
              ),
              _ManageActionCard(
                title: 'Save existing password',
                subtitle: 'Manual entry for credentials you already have.',
                icon: Icons.add_circle_outline,
                onTap: () => _showPreview(context, 'Save existing password'),
              ),
              _ManageActionCard(
                title: 'Edit entries',
                subtitle: 'Rename paths, move folders, replace password lines, and edit raw notes.',
                icon: Icons.edit_outlined,
                onTap: () => _showPreview(context, 'Edit entries'),
              ),
              _ManageActionCard(
                title: 'Batch delete',
                subtitle: 'Preview full paths before removing selected entries.',
                icon: Icons.delete_outline,
                isDanger: true,
                onTap: () => _showPreview(context, 'Batch delete'),
              ),
              _ManageActionCard(
                title: 'Regenerate selected',
                subtitle: 'Replace password lines while preserving parsed fields and raw notes.',
                icon: Icons.refresh,
                onTap: () => _showPreview(context, 'Regenerate selected'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPreview(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text('Preview affected paths before execution. Real password-store operations will be connected in a later phase.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const SizedBox(width: double.infinity, child: Center(child: Text('Close preview'))),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ManageActionCard extends StatelessWidget {
  const _ManageActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDanger = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire Manage into shell**

Modify `gui/lib/screens/shell/mobile_shell.dart`:

Add import:

```dart
import '../manage/manage_screen.dart';
```

Replace second page:

```dart
ManageScreen(repository: widget.repository),
```

- [ ] **Step 5: Run Manage tests**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart
flutter analyze
```

Working directory: `gui`

Expected: PASS.

- [ ] **Step 6: Commit task 4**

```powershell
git add gui/lib/screens/manage/manage_screen.dart gui/lib/screens/shell/mobile_shell.dart gui/test/mobile_gui_smoke_test.dart
git commit -m "feat(gui): add mobile manage workflows"
```

## Task 5: Implement Settings Screen and Key Management Surfaces

**Files:**
- Create: `gui/lib/screens/settings/settings_screen.dart`
- Modify: `gui/lib/screens/shell/mobile_shell.dart`
- Test: `gui/test/mobile_gui_smoke_test.dart`

- [ ] **Step 1: Add Settings widget test**

Append to `gui/test/mobile_gui_smoke_test.dart`:

```dart
testWidgets('settings tab exposes security keys stores and git sections', (tester) async {
  await tester.pumpWidget(const ParsGuiApp());
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();

  expect(find.text('Gesture lock and biometrics'), findsOneWidget);
  expect(find.text('PGP keys'), findsOneWidget);
  expect(find.text('SSH keys'), findsOneWidget);
  expect(find.text('Advanced git args'), findsOneWidget);

  await tester.tap(find.text('Advanced git args'));
  await tester.pumpAndSettle();
  expect(find.text('git'), findsOneWidget);
  expect(find.text('Run selected command'), findsOneWidget);
});
```

- [ ] **Step 2: Run Settings test and verify it fails**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart
```

Working directory: `gui`

Expected: FAIL because Settings tab is still a temporary stub.

- [ ] **Step 3: Create Settings screen**

Create `gui/lib/screens/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../models/key_record.dart';
import '../../services/demo_vault_repository.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.repository});

  final DemoVaultRepository repository;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          pinned: true,
          title: Text('Settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: <Widget>[
              _SettingsSection(
                title: 'Security',
                children: <Widget>[
                  _SettingsTile(title: 'Gesture lock and biometrics', subtitle: 'Gesture fallback, biometric quick unlock', icon: Icons.pattern, onTap: () => _showTextSheet(context, 'Gesture lock and biometrics')),
                  _SettingsTile(title: 'PGP session timeout', subtitle: '15 min', icon: Icons.timer_outlined, onTap: () => _showTextSheet(context, 'PGP session timeout')),
                  _SettingsTile(title: 'KMS / Keychain passphrase', subtitle: 'Optional one-step unlock', icon: Icons.key_outlined, onTap: () => _showTextSheet(context, 'KMS / Keychain passphrase')),
                ],
              ),
              _SettingsSection(
                title: 'Key management',
                children: <Widget>[
                  _SettingsTile(title: 'PGP keys', subtitle: 'Create, import, export, delete', icon: Icons.enhanced_encryption_outlined, onTap: () => _showKeys(context, KeyRecordType.pgp)),
                  _SettingsTile(title: 'SSH keys', subtitle: 'GitHub access keys', icon: Icons.vpn_key_outlined, onTap: () => _showKeys(context, KeyRecordType.ssh)),
                ],
              ),
              _SettingsSection(
                title: 'Password stores and Git',
                children: <Widget>[
                  _SettingsTile(title: 'Password stores', subtitle: repository.currentRepoName, icon: Icons.folder_outlined, onTap: () => _showTextSheet(context, 'Password stores')),
                  _SettingsTile(title: 'Git sync and remotes', subtitle: 'Pull, push, status, remotes', icon: Icons.sync, onTap: () => _showTextSheet(context, 'Git sync and remotes')),
                  _SettingsTile(title: 'Advanced git args', subtitle: 'Arguments after git only', icon: Icons.terminal, onTap: () => _showGitArgs(context)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTextSheet(BuildContext context, String title) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text('This configuration surface is mocked in phase 1 and will be wired to platform services later.'),
            ],
          ),
        ),
      ),
    );
  }

  void _showKeys(BuildContext context, KeyRecordType type) {
    final keys = repository.keys.where((key) => key.type == type).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(type == KeyRecordType.pgp ? 'PGP keys' : 'SSH keys', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              for (final key in keys)
                Card(
                  child: ListTile(
                    title: Text(key.name),
                    subtitle: Text('${key.fingerprint}\n${key.source}'),
                    isThreeLine: true,
                    trailing: Text(key.hasPrivateKey ? 'Private' : 'Public'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  FilledButton(onPressed: () {}, child: const Text('Create')),
                  OutlinedButton(onPressed: () {}, child: const Text('Import')),
                  OutlinedButton(onPressed: () {}, child: const Text('Export public')),
                  OutlinedButton(onPressed: () {}, child: const Text('Export private')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGitArgs(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Advanced git args', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Only enter arguments after git. Shell syntax is not accepted.'),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text('git', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'status'),
                      controller: TextEditingController(text: 'status'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {},
                child: const SizedBox(width: double.infinity, child: Center(child: Text('Run selected command'))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire Settings into shell**

Modify `gui/lib/screens/shell/mobile_shell.dart`:

Add import:

```dart
import '../settings/settings_screen.dart';
```

Replace third page:

```dart
SettingsScreen(repository: widget.repository),
```

- [ ] **Step 5: Run Settings tests**

Run:

```powershell
flutter test test/mobile_gui_smoke_test.dart
flutter analyze
```

Working directory: `gui`

Expected: PASS.

- [ ] **Step 6: Commit task 5**

```powershell
git add gui/lib/screens/settings/settings_screen.dart gui/lib/screens/shell/mobile_shell.dart gui/test/mobile_gui_smoke_test.dart
git commit -m "feat(gui): add mobile settings surfaces"
```

## Task 6: Final Verification and Polish

**Files:**
- Modify as needed: all files touched by previous tasks.

- [ ] **Step 1: Run all Flutter tests**

Run:

```powershell
flutter test
```

Working directory: `gui`

Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run:

```powershell
flutter analyze
```

Working directory: `gui`

Expected: no issues.

- [ ] **Step 3: Inspect app at mobile size**

Run:

```powershell
flutter run -d windows
```

Working directory: `gui`

Expected:

- App starts at gesture onboarding.
- Continue opens shell.
- Bottom tabs switch between Vault, Manage, Settings.
- Vault search filters entries.
- Entry tap opens bottom sheet.
- Manage cards open preview sheets.
- Settings opens key and Git args sheets.

Stop the dev run after inspection.

- [ ] **Step 4: Commit any polish**

If step 1 or 2 required fixes:

```powershell
git add gui
git commit -m "fix(gui): polish mobile mock UX"
```

If no fixes were needed, do not create an empty commit.

## Self-Review

Spec coverage:

- Three-tab navigation is covered by Tasks 2 through 5.
- Gesture onboarding is covered by Task 2.
- Vault search/browse/copy/detail bottom sheet is covered by Task 3.
- Best-effort parser and raw notes preservation are covered by Task 1.
- Manage generation/edit/delete/batch surfaces are covered by Task 4.
- Settings security/key/store/Git surfaces are covered by Task 5.
- Git args is represented as arguments-after-git only in Task 5.
- Real PGP/Git/KMS/biometrics are intentionally out of scope for phase 1 and remain future implementation work.

Placeholder scan:

- This plan avoids red-flag markers and unspecified work.
- Mocked phase-1 surfaces are explicit scope choices, not unspecified work.

Type consistency:

- `PasswordEntry`, `SecretContent`, `ParsedSecretField`, `KeyRecord`, `DemoVaultRepository`, and `PassEntryParser` are introduced before use.
- `MobileShell` consistently receives `DemoVaultRepository`.
- Tests import `ParsGuiApp` from `main.dart`, which re-exports the app root by importing it.
