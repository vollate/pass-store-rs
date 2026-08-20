import 'package:flutter/material.dart';

class VaultDestinationState extends ChangeNotifier {
  VaultDestinationState({
    String query = '',
    String? directoryPath,
    Set<String> selectedPaths = const <String>{},
  }) : _query = query,
       _directoryPath = directoryPath,
       _selectedPaths = <String>{...selectedPaths};

  final ScrollController scrollController = ScrollController();
  String _query;
  String? _directoryPath;
  final Set<String> _selectedPaths;
  bool _selectionMode = false;

  String get query => _query;
  String? get directoryPath => _directoryPath;
  Set<String> get selectedPaths => Set<String>.unmodifiable(_selectedPaths);
  bool get selectionMode => _selectionMode;

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

  void enterSelection([String? path]) {
    final modeChanged = !_selectionMode;
    _selectionMode = true;
    final selectionChanged = path == null ? false : _selectedPaths.add(path);
    if (modeChanged || selectionChanged) notifyListeners();
  }

  void setSelected(String path, {required bool selected}) {
    final changed =
        selected ? _selectedPaths.add(path) : _selectedPaths.remove(path);
    if (changed) notifyListeners();
  }

  void clearSelection() {
    final changed = _selectionMode || _selectedPaths.isNotEmpty;
    _selectionMode = false;
    _selectedPaths.clear();
    if (changed) notifyListeners();
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
