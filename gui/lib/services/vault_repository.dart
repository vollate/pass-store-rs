import '../models/password_entry.dart';

abstract interface class VaultRepository {
  String get currentRepoName;

  List<PasswordEntry> get entries;

  Future<void> refresh();

  List<PasswordEntry> search(String query);
}
