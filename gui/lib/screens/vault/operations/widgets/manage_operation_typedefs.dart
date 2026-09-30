part of '../vault_operations.dart';

typedef _GenerateEntrySubmit =
    Future<EntryOperationResult> Function(
      String path,
      bool noSymbols,
      bool overwrite,
    );

typedef _SaveExistingEntrySubmit =
    Future<EntryOperationResult> Function(
      String path,
      String password,
      String notes,
      bool overwrite,
    );

typedef _MoveOrRenameEntrySubmit =
    Future<EntryOperationResult> Function(
      PasswordEntry entry,
      String target,
      bool overwrite,
    );

typedef _DeleteEntrySubmit =
    Future<EntryOperationResult> Function(PasswordEntry entry);

typedef _ReadEntryForEdit = Future<SecretContent> Function(PasswordEntry entry);

typedef _SaveEditedEntrySubmit =
    Future<EntryOperationResult> Function(
      PasswordEntry entry,
      String password,
      List<ParsedSecretField> fields,
      String notes,
    );

typedef _ReplaceEntryPasswordSubmit =
    Future<EntryOperationResult> Function(PasswordEntry entry, String password);

typedef _BatchMoveSubmit =
    Future<BatchOperationResult> Function(String destination, bool overwrite);

typedef _BatchRenameSubmit =
    Future<BatchOperationResult> Function(
      String prefix,
      String suffix,
      bool overwrite,
    );

typedef _BatchDeleteSubmit = Future<BatchOperationResult> Function();

typedef _BatchRegenerateSubmit =
    Future<BatchOperationResult> Function(bool noSymbols);
