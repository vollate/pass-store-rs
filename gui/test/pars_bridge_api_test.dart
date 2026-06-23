import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/bridge/pars_bridge_api.dart';

void main() {
  test('mock bridge exposes async entry list calls', () async {
    final bridge = _MockParsBridgeApi();

    final entries = await bridge.listEntries(<String, Object?>{
      'root': '/tmp/password-store',
      'recursive': true,
    });

    expect(entries['count'], 2);
    expect(bridge.calledMethods, contains('list_entries'));
  });

  test('bridge failures preserve typed Rust error fields', () {
    final failure = BridgeFailure.fromJson(<String, Object?>{
      'category': 'Conflict',
      'message': 'entry already exists: github',
      'conflict_kind': 'EntryAlreadyExists',
      'path': 'github',
    });

    expect(failure.category, BridgeFailureCategory.conflict);
    expect(failure.conflictKind, 'EntryAlreadyExists');
    expect(failure.path, 'github');
    expect(failure.toString(), contains('entry already exists'));
  });
}

class _MockParsBridgeApi implements ParsBridgeApi {
  final List<String> calledMethods = <String>[];

  @override
  Future<Map<String, Object?>> loadConfig(Map<String, Object?> request) =>
      _record('load_config');

  @override
  Future<Map<String, Object?>> saveConfig(Map<String, Object?> request) =>
      _record('save_config');

  @override
  Future<Map<String, Object?>> listStores(Map<String, Object?> request) =>
      _record('list_stores');

  @override
  Future<Map<String, Object?>> listEntries(Map<String, Object?> request) =>
      _record('list_entries', <String, Object?>{'count': 2});

  @override
  Future<Map<String, Object?>> readEntry(Map<String, Object?> request) =>
      _record('read_entry');

  @override
  Future<Map<String, Object?>> copyEntryPassword(
    Map<String, Object?> request,
  ) => _record('copy_entry_password');

  @override
  Future<Map<String, Object?>> insertEntry(Map<String, Object?> request) =>
      _record('insert_entry');

  @override
  Future<Map<String, Object?>> generateEntry(Map<String, Object?> request) =>
      _record('generate_entry');

  @override
  Future<Map<String, Object?>> editEntry(Map<String, Object?> request) =>
      _record('edit_entry');

  @override
  Future<Map<String, Object?>> moveEntry(Map<String, Object?> request) =>
      _record('move_entry');

  @override
  Future<Map<String, Object?>> deleteEntry(Map<String, Object?> request) =>
      _record('delete_entry');

  @override
  Future<Map<String, Object?>> gitStatus(Map<String, Object?> request) =>
      _record('git_status');

  @override
  Future<Map<String, Object?>> gitPull(Map<String, Object?> request) =>
      _record('git_pull');

  @override
  Future<Map<String, Object?>> gitPush(Map<String, Object?> request) =>
      _record('git_push');

  @override
  Future<Map<String, Object?>> gitCommit(Map<String, Object?> request) =>
      _record('git_commit');

  @override
  Future<Map<String, Object?>> runGitArgs(Map<String, Object?> request) =>
      _record('run_git_args');

  Future<Map<String, Object?>> _record(
    String method, [
    Map<String, Object?> response = const <String, Object?>{},
  ]) async {
    calledMethods.add(method);
    return response;
  }
}
