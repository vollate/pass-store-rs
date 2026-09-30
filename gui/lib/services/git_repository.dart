import '../models/git_sync.dart';
import '../models/password_entry.dart';
import 'store_lifecycle.dart';

abstract interface class GitRepository {
  RepoGitStatus get gitStatus;
}

/// Picks the one state the Vault badge shows, most urgent first.
RepoGitStatus classifyGitStatus(
  GitStatusSummary summary, {
  required StoreGitMode mode,
  GitSyncConflict? conflict,
  bool syncFailed = false,
}) {
  if (conflict != null || summary.inProgress) return RepoGitStatus.conflicted;
  if (syncFailed) return RepoGitStatus.syncFailed;
  if (summary.changed > 0) return RepoGitStatus.uncommitted;
  if (summary.ahead > 0 && summary.behind > 0) return RepoGitStatus.diverged;
  if (summary.behind > 0) return RepoGitStatus.needPull;
  if (summary.ahead > 0) return RepoGitStatus.needPush;
  if (mode == StoreGitMode.remote &&
      summary.branch != null &&
      summary.upstream == null) {
    return RepoGitStatus.needPush;
  }
  return RepoGitStatus.clean;
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

abstract interface class GitModeRepository {
  StoreGitMode get gitMode;
}

abstract interface class GitOperationsRepository
    implements GitRepository, GitModeRepository {
  /// The last typed status, or `null` before the first refresh or when Git is
  /// disabled.
  GitStatusSummary? get statusSummary;

  /// The conflict from the last sync, kept until a later sync, reset, or
  /// backup push resolves it.
  GitSyncConflict? get lastConflict;

  /// True when the last background remote check could not reach the remote.
  bool get lastRemoteCheckFailed;

  GitPreferences get preferences;

  Future<void> updatePreferences(GitPreferences preferences);

  Future<GitOperationResult> initializeRepository();

  Future<GitOperationResult> refreshGitStatus();

  /// Fetches once per app launch when the setting allows it. Failures are
  /// recorded instead of thrown so the badge keeps the local state.
  Future<void> checkRemoteOnLaunch();

  Future<GitOperationResult> pull();

  Future<GitOperationResult> push();

  Future<GitOperationResult> commit(String message);

  Future<GitSyncOutcome> sync({
    required bool commitPending,
    String message = 'Sync password store',
  });

  Future<GitResetOutcome> resetToUpstream();

  Future<GitOperationResult> pushBackupBranch(String branch);

  Future<List<GitLogEntry>> history({int limit = 50});

  Future<GitRemoteBranches> remoteBranches();

  Future<void> switchBranch(String branch);

  Future<GitIdentity?> identity();

  /// A name and email taken from the store's PGP key, for prefilling.
  GitIdentity? suggestedIdentity();

  Future<void> setIdentity({required String name, required String email});

  Future<bool> hasHttpsCredentials();

  Future<void> rememberHttpsCredentials(HttpsCredentials credentials);

  Future<void> forgetHttpsCredentials();

  Future<void> rememberSshPassphrase(String passphrase, {required bool persist});

  /// Desktop only. The text is tokenized by the bridge, not split here.
  Future<GitOperationResult> runCommandLine(String commandLine);

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
}
