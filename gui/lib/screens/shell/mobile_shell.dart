import 'package:flutter/material.dart';

import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/security_repository.dart';
import '../../services/settings_repository.dart';
import '../../services/vault_repository.dart';
import '../manage/manage_screen.dart';
import '../settings/settings_screen.dart';
import '../vault/vault_screen.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.vaultRepository,
    required this.settingsRepository,
    required this.keyRepository,
    required this.gitRepository,
    required this.securityRepository,
    this.onSecuritySettingsChanged,
  });

  final VaultRepository vaultRepository;
  final SettingsRepository settingsRepository;
  final KeyRepository keyRepository;
  final GitRepository gitRepository;
  final SecurityRepository securityRepository;
  final VoidCallback? onSecuritySettingsChanged;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      VaultScreen(
        vaultRepository: widget.vaultRepository,
        gitRepository: widget.gitRepository,
      ),
      ManageScreen(repository: widget.vaultRepository),
      SettingsScreen(
        settingsRepository: widget.settingsRepository,
        keyRepository: widget.keyRepository,
        gitRepository: widget.gitRepository,
        securityRepository: widget.securityRepository,
        onSecuritySettingsChanged: widget.onSecuritySettingsChanged,
      ),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (value) => setState(() => _index = value),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.lock_outline),
            label: 'Vault',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Manage'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
