import 'package:flutter/material.dart';

class VaultDestinationState extends ChangeNotifier {
  VaultDestinationState({String query = '', String? directoryPath})
    : _query = query,
      _directoryPath = directoryPath;

  final ScrollController scrollController = ScrollController();
  String _query;
  String? _directoryPath;

  String get query => _query;
  String? get directoryPath => _directoryPath;

  /// The folder Up returns to. Null means the next step is the store root.
  String? get parentDirectory {
    final path = _directoryPath;
    if (path == null) return null;
    final index = path.lastIndexOf('/');
    return index == -1 ? null : path.substring(0, index);
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    if (value.isNotEmpty) _directoryPath = null;
    notifyListeners();
  }

  void setDirectory(String? value) {
    if (_directoryPath == value) return;
    _directoryPath = value;
    notifyListeners();
  }

  /// Moves to the parent folder. Returns false when Vault is already at the
  /// store root, so system back can leave the app.
  bool popDirectory() {
    if (_directoryPath == null) return false;
    _directoryPath = parentDirectory;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}

class SettingsDestinationState {
  final ScrollController scrollController = ScrollController();

  void dispose() => scrollController.dispose();
}
