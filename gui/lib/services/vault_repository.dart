import '../models/password_entry.dart';

abstract interface class VaultRepository {
  String get currentRepoName;

  List<PasswordEntry> get entries;

  Future<void> refresh();

  List<PasswordEntry> search(String query);

  List<PasswordEntry> browseEntries(String? directoryPath);

  Future<SecretContent> readEntry(PasswordEntry entry);

  Future<String> copyEntryPassword(PasswordEntry entry);

  Future<void> toggleFavorite(PasswordEntry entry);

  Future<EntryOperationResult> generateEntry({
    required String path,
    required int length,
    required bool noSymbols,
    required bool overwrite,
  });

  Future<EntryOperationResult> saveEntry({
    required String path,
    required String content,
    required bool overwrite,
  });
}

abstract interface class ManageRepository implements VaultRepository {
  Future<EntryOperationResult> editEntry({
    required String path,
    required String content,
  });

  Future<EntryOperationResult> replaceEntryPassword({
    required PasswordEntry entry,
    required String password,
  });

  Future<EntryOperationResult> moveEntry({
    required String fromPath,
    required String toPath,
    required bool overwrite,
  });

  Future<EntryOperationResult> deleteEntry({
    required String path,
    required bool recursive,
  });

  Future<BatchOperationResult> batchMoveEntries({
    required List<PasswordEntry> entries,
    required String destinationDirectory,
    required bool overwrite,
  });

  Future<BatchOperationResult> batchRenameEntries({
    required List<PasswordEntry> entries,
    required String prefix,
    required String suffix,
    required bool overwrite,
  });

  Future<BatchOperationResult> batchDeleteEntries({
    required List<PasswordEntry> entries,
  });

  Future<BatchOperationResult> batchRegenerateEntries({
    required List<PasswordEntry> entries,
    required int length,
    required bool noSymbols,
  });

  Future<GitOperationResult> commitChanges(String message);
}
