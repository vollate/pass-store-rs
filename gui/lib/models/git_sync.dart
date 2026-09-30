enum GitIntegrationStrategy { rebase, merge }

enum GitOperationState { none, rebasing, merging, other }

class GitStatusSummary {
  const GitStatusSummary({
    required this.branch,
    required this.upstream,
    required this.ahead,
    required this.behind,
    required this.changed,
    required this.conflicted,
    required this.operation,
    required this.lastFetchedAt,
  });

  final String? branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final int changed;
  final int conflicted;
  final GitOperationState operation;
  final DateTime? lastFetchedAt;

  bool get inProgress =>
      operation != GitOperationState.none || conflicted > 0;

  /// Switching branch would drop or strand local work otherwise.
  bool get canSwitchBranch => changed == 0 && !inProgress && ahead == 0;
}

class GitSyncConflict {
  const GitSyncConflict({required this.backupBranch, required this.paths});

  /// Absent when the repository was already mid-rebase or mid-merge.
  final String? backupBranch;
  final List<String> paths;
}

class GitSyncOutcome {
  const GitSyncOutcome({
    required this.committed,
    required this.pulled,
    required this.pushed,
    required this.blockedByChanges,
    required this.conflict,
    required this.summary,
  });

  final bool committed;
  final int pulled;
  final bool pushed;
  final bool blockedByChanges;
  final GitSyncConflict? conflict;
  final GitStatusSummary summary;
}

class GitResetOutcome {
  const GitResetOutcome({
    required this.committed,
    required this.backupBranch,
    required this.summary,
  });

  final bool committed;
  final String? backupBranch;
  final GitStatusSummary summary;
}

class GitLogEntry {
  const GitLogEntry({
    required this.id,
    required this.summary,
    required this.author,
    required this.time,
  });

  final String id;
  final String summary;
  final String author;
  final DateTime time;
}

class GitIdentity {
  const GitIdentity({
    required this.name,
    required this.email,
    this.local = true,
  });

  final String name;
  final String email;
  final bool local;

  /// Parses a PGP user ID such as `Ada Lovelace <ada@example.com>`.
  static GitIdentity? fromUserId(String userId) {
    final match = RegExp(r'^\s*(.*?)\s*<([^<>\s]+@[^<>\s]+)>\s*$')
        .firstMatch(userId);
    if (match == null) return null;
    final name = match.group(1)!.trim();
    final email = match.group(2)!.trim();
    if (name.isEmpty) return null;
    return GitIdentity(name: name, email: email);
  }
}

class GitRemoteBranches {
  const GitRemoteBranches({
    required this.remote,
    required this.current,
    required this.branches,
  });

  final String? remote;
  final String? current;
  final List<String> branches;
}

class GitPreferences {
  const GitPreferences({
    this.commitEveryChange = true,
    this.checkRemoteOnLaunch = true,
    this.strategy = GitIntegrationStrategy.rebase,
  });

  final bool commitEveryChange;
  final bool checkRemoteOnLaunch;
  final GitIntegrationStrategy strategy;

  GitPreferences copyWith({
    bool? commitEveryChange,
    bool? checkRemoteOnLaunch,
    GitIntegrationStrategy? strategy,
  }) {
    return GitPreferences(
      commitEveryChange: commitEveryChange ?? this.commitEveryChange,
      checkRemoteOnLaunch: checkRemoteOnLaunch ?? this.checkRemoteOnLaunch,
      strategy: strategy ?? this.strategy,
    );
  }
}

class HttpsCredentials {
  const HttpsCredentials({required this.username, required this.token});

  final String username;
  final String token;
}

/// Git needs a name and email before it can commit.
class GitIdentityRequiredException implements Exception {
  const GitIdentityRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The remote asked for HTTPS credentials that were missing or rejected.
class GitAuthenticationRequiredException implements Exception {
  const GitAuthenticationRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The selected SSH key is encrypted and its passphrase was missing or wrong.
class GitSshPassphraseRequiredException implements Exception {
  const GitSshPassphraseRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}
