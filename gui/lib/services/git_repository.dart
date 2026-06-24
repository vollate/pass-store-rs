import '../models/password_entry.dart';

abstract interface class GitRepository {
  RepoGitStatus get gitStatus;
}

class GitRemote {
  const GitRemote({
    required this.name,
    required this.fetchUrl,
    required this.pushUrl,
  });

  final String name;
  final String fetchUrl;
  final String pushUrl;
}

abstract interface class GitOperationsRepository implements GitRepository {
  Future<GitOperationResult> refreshGitStatus();

  Future<GitOperationResult> pull();

  Future<GitOperationResult> push();

  Future<GitOperationResult> commit(String message);

  Future<GitOperationResult> runArgs(List<String> args);

  Future<List<GitRemote>> listRemotes();

  Future<GitOperationResult> addRemote({
    required String name,
    required String url,
  });

  Future<GitOperationResult> editRemote({
    required String name,
    required String url,
  });

  Future<GitOperationResult> removeRemote(String name);

  Future<GitOperationResult> autoPullOnOpen();

  Future<GitOperationResult> recoverByPull();

  Future<GitOperationResult> deleteLocalRepo({required String confirmation});
}
