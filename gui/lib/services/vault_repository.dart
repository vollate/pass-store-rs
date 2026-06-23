import '../models/password_entry.dart';

abstract interface class VaultRepository {
  String get currentRepoName;

  List<PasswordEntry> get entries;

  List<PasswordEntry> search(String query);
}
