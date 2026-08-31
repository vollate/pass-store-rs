part of '../vault_operations.dart';

typedef _GenerateEntrySubmit =
    Future<EntryOperationResult> Function(
      String path,
      bool noSymbols,
      bool overwrite,
      bool commit,
    );

typedef _SaveExistingEntrySubmit =
    Future<EntryOperationResult> Function(
      String path,
      String password,
      String notes,
      bool overwrite,
      bool commit,
    );

typedef _MoveOrRenameEntrySubmit =
    Future<EntryOperationResult> Function(
      PasswordEntry entry,
      String target,
      bool overwrite,
      bool commit,
    );

typedef _DeleteEntrySubmit =
    Future<EntryOperationResult> Function(PasswordEntry entry, bool commit);

typedef _ReadEntryForEdit = Future<SecretContent> Function(PasswordEntry entry);

typedef _SaveEditedEntrySubmit =
    Future<EntryOperationResult> Function(
      PasswordEntry entry,
      String password,
      List<ParsedSecretField> fields,
      String notes,
      bool commit,
    );

typedef _ReplaceEntryPasswordSubmit =
    Future<EntryOperationResult> Function(
      PasswordEntry entry,
      String password,
      bool commit,
    );

typedef _BatchMoveSubmit =
    Future<BatchOperationResult> Function(
      String destination,
      bool overwrite,
      bool commit,
    );

typedef _BatchRenameSubmit =
    Future<BatchOperationResult> Function(
      String prefix,
      String suffix,
      bool overwrite,
      bool commit,
    );

typedef _BatchDeleteSubmit = Future<BatchOperationResult> Function(bool commit);

typedef _BatchRegenerateSubmit =
    Future<BatchOperationResult> Function(bool noSymbols, bool commit);
