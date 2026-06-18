import 'package:flutter/material.dart';

import '../../services/demo_vault_repository.dart';
import '../manage/manage_screen.dart';
import '../settings/settings_screen.dart';
import '../vault/vault_screen.dart';

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
      VaultScreen(repository: widget.repository),
      ManageScreen(repository: widget.repository),
      SettingsScreen(repository: widget.repository),
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
