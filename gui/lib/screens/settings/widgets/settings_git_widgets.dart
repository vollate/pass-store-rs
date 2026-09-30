part of '../settings_screen.dart';

extension _SettingsScreenGitSheets on SettingsScreen {
  void _showGitSync(BuildContext context) {
    final git = _gitOperations;
    if (git == null) {
      _showUnavailableSheet(context, context.l10n.gitSyncTitle);
      return;
    }

    showParsAdaptiveDetail<void>(
      context: context,
      builder:
          (context) => _GitSyncSheetBody(
            git: git,
            gitMode: settingsRepository.store?.gitMode ?? StoreGitMode.disabled,
            onManageSshKeys: () => _showSshKeys(context),
            configPath: settingsRepository.lifecycle.configPath,
            sshKeys: keyRepository.keys
                .where(
                  (key) => key.type == KeyRecordType.ssh && key.hasPrivateKey,
                )
                .toList(growable: false),
          ),
    );
  }

  void _showGitArgs(BuildContext context) {
    showParsAdaptiveDetail<void>(
      context: context,
      builder: (context) => _GitArgsSheetBody(git: _gitOperations),
    );
  }
}

class _GitSyncSheetBody extends StatefulWidget {
  const _GitSyncSheetBody({
    required this.git,
    required this.gitMode,
    required this.onManageSshKeys,
    required this.configPath,
    required this.sshKeys,
  });

  final GitOperationsRepository git;
  final StoreGitMode gitMode;
  final VoidCallback onManageSshKeys;
  final String configPath;
  final List<KeyRecord> sshKeys;

  @override
  State<_GitSyncSheetBody> createState() => _GitSyncSheetBodyState();
}

class _GitSyncSheetBodyState extends State<_GitSyncSheetBody> {
  var _running = false;
  List<GitRemote> _remotes = const <GitRemote>[];
  GitIdentity? _identity;
  bool _hasHttpsCredentials = false;
  UiProblem? _error;
  String? _selectedSshKey;
  late StoreGitMode _gitMode = widget.gitMode;

  GitOperationsRepository get _git => widget.git;
  bool get _hasGit =>
      _gitMode == StoreGitMode.local || _gitMode == StoreGitMode.remote;
  bool get _hasRemote => _gitMode == StoreGitMode.remote;

  @override
  void initState() {
    super.initState();
    if (_hasGit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSelectedSshKey());
  }

  Future<void> _reload() async {
    try {
      final remotes = await _git.listRemotes();
      final identity = await _git.identity();
      final hasHttps = await _git.hasHttpsCredentials();
      if (!mounted) return;
      setState(() {
        _gitMode = _git.gitMode;
        _remotes = remotes;
        _identity = identity;
        _hasHttpsCredentials = hasHttps;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = UiProblem.fromError(context.l10n, error));
      }
    }
  }

  Future<void> _loadSelectedSshKey() async {
    final saved = await loadSelectedSshKey(widget.configPath);
    if (!mounted) return;
    final names = widget.sshKeys.map((key) => key.name).toSet();
    setState(() {
      if (saved != null && names.contains(saved)) {
        _selectedSshKey = saved;
      } else if (widget.sshKeys.length == 1) {
        _selectedSshKey = widget.sshKeys.single.name;
      }
    });
  }

  Future<void> _selectSshKey(String name) async {
    await saveSelectedSshKey(widget.configPath, name);
    if (!mounted) return;
    setState(() => _selectedSshKey = name);
  }

  /// Runs one action with credential prompts, then reloads the sheet.
  Future<void> _run(
    Future<Object?> Function() action, {
    String? Function(Object? result)? success,
  }) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await runGitWithPrompts(context, _git, action);
      if (!mounted) return;
      if (result is GitOperationResult && !result.success) {
        setState(() => _error = _gitResultProblem(context, result));
      } else if (result != null) {
        final message = success?.call(result);
        if (message != null) {
          AppNotification.show(
            context,
            message,
            severity: AppNotificationSeverity.success,
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = UiProblem.fromError(context.l10n, error));
      }
    }
    await _reload();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _sync() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await runGitSyncFlow(context, _git);
    } catch (error) {
      if (mounted) {
        setState(() => _error = UiProblem.fromError(context.l10n, error));
      }
    }
    await _reload();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _updatePreferences(GitPreferences preferences) async {
    await _git.updatePreferences(preferences);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          ParsSpacing.lg,
          ParsSpacing.lg,
          ParsSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + ParsSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.gitSyncTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: ParsSpacing.xs),
            Text(_gitModeLabel(context)),
            if (_gitMode == StoreGitMode.invalid) ...<Widget>[
              const SizedBox(height: ParsSpacing.xs),
              Text(l10n.invalidGitMetadataMessage),
            ],
            if (_gitMode == StoreGitMode.disabled) ...<Widget>[
              const SizedBox(height: ParsSpacing.md),
              FilledButton.icon(
                onPressed:
                    _running
                        ? null
                        : () => _run(() async {
                          final result = await _git.initializeRepository();
                          _gitMode = _git.gitMode;
                          return result;
                        }),
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(l10n.initializeGit),
              ),
            ],
            if (_hasGit) ..._gitSections(context),
            if (_running) ...const <Widget>[
              SizedBox(height: ParsSpacing.sm),
              LinearProgressIndicator(),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: ParsSpacing.sm),
              FailureNotice(problem: _error!),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _gitSections(BuildContext context) {
    final l10n = context.l10n;
    final preferences = _git.preferences;
    final summary = _git.statusSummary;
    final branch = summary?.branch;
    final upstream = summary?.upstream;
    return <Widget>[
      const SizedBox(height: ParsSpacing.md),
      AppSectionBox(
        title: l10n.gitSyncSection,
        padding: EdgeInsets.zero,
        children: <Widget>[
          ParsSectionRow(
            leading: const ParsSectionRowIcon(icon: Icons.sync),
            title: gitStatusLabel(l10n, _git.gitStatus),
            subtitle: _statusSubtitle(context, branch, upstream, summary),
            trailing: IconButton(
              tooltip: l10n.status,
              onPressed: _running ? null : () => _run(_git.refreshGitStatus),
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (_hasRemote)
            ParsSectionRow(
              leading: const ParsSectionRowIcon(
                icon: Icons.cloud_sync_outlined,
              ),
              title: l10n.checkRemoteOnLaunch,
              subtitle:
                  preferences.checkRemoteOnLaunch
                      ? l10n.checkRemoteOnLaunchOn
                      : l10n.checkRemoteOnLaunchOff,
              onTap:
                  () => _updatePreferences(
                    preferences.copyWith(
                      checkRemoteOnLaunch: !preferences.checkRemoteOnLaunch,
                    ),
                  ),
              trailing: Switch(
                value: preferences.checkRemoteOnLaunch,
                onChanged:
                    (value) => _updatePreferences(
                      preferences.copyWith(checkRemoteOnLaunch: value),
                    ),
              ),
            ),
          if (_hasRemote)
            ParsSectionRow(
              leading: const ParsSectionRowIcon(icon: Icons.call_merge),
              title: l10n.integrationStrategy,
              subtitle: _strategyLabel(l10n, preferences.strategy),
              trailing: PopupMenuButton<GitIntegrationStrategy>(
                tooltip: l10n.integrationStrategy,
                initialValue: preferences.strategy,
                onSelected:
                    (strategy) => _updatePreferences(
                      preferences.copyWith(strategy: strategy),
                    ),
                itemBuilder:
                    (context) => <PopupMenuEntry<GitIntegrationStrategy>>[
                      for (final strategy in GitIntegrationStrategy.values)
                        PopupMenuItem<GitIntegrationStrategy>(
                          value: strategy,
                          child: Text(_strategyLabel(l10n, strategy)),
                        ),
                    ],
                icon: const Icon(Icons.expand_more),
              ),
            ),
        ],
      ),
      if (_hasRemote) ...<Widget>[
        const SizedBox(height: ParsSpacing.sm),
        ParsButtonGrid(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _running ? null : () => _run(_git.pull),
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.pull),
            ),
            OutlinedButton.icon(
              onPressed: _running ? null : () => _run(_git.push),
              icon: const Icon(Icons.upload_outlined),
              label: Text(l10n.push),
            ),
            FilledButton.icon(
              onPressed: _running ? null : _sync,
              icon: const Icon(Icons.sync),
              label: Text(l10n.syncNow),
            ),
          ],
        ),
      ],
      const SizedBox(height: ParsSpacing.lg),
      AppSectionBox(
        title: l10n.gitCommitsSection,
        padding: EdgeInsets.zero,
        children: <Widget>[
          ParsSectionRow(
            leading: const ParsSectionRowIcon(icon: Icons.badge_outlined),
            title: l10n.gitIdentityTitle,
            subtitle:
                _identity == null
                    ? l10n.gitIdentityNotSet
                    : '${_identity!.name} <${_identity!.email}>',
            onTap:
                _running
                    ? null
                    : () async {
                      await showGitIdentitySheet(context, _git);
                      await _reload();
                    },
            trailing: const Icon(Icons.chevron_right),
          ),
          ParsSectionRow(
            leading: const ParsSectionRowIcon(icon: Icons.task_alt_outlined),
            title: l10n.commitEveryChange,
            subtitle:
                preferences.commitEveryChange
                    ? l10n.commitEveryChangeOn
                    : l10n.commitEveryChangeOff,
            onTap:
                () => _updatePreferences(
                  preferences.copyWith(
                    commitEveryChange: !preferences.commitEveryChange,
                  ),
                ),
            trailing: Switch(
              value: preferences.commitEveryChange,
              onChanged:
                  (value) => _updatePreferences(
                    preferences.copyWith(commitEveryChange: value),
                  ),
            ),
          ),
          ParsSectionRow(
            leading: const ParsSectionRowIcon(icon: Icons.add_task_outlined),
            title: l10n.commitNow,
            subtitle: l10n.commitMessageField,
            onTap: _running ? null : _commitNow,
            trailing: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      const SizedBox(height: ParsSpacing.lg),
      AppSectionBox(
        title: l10n.gitRemotesSection,
        padding: EdgeInsets.zero,
        emptyLabel: l10n.gitNoUpstream,
        children: <Widget>[
          for (final remote in _remotes)
            ParsSectionRow(
              leading: const ParsSectionRowIcon(
                icon: Icons.cloud_queue_outlined,
              ),
              title: remote.name,
              subtitle: remote.fetchUrl,
              trailing: PopupMenuButton<String>(
                tooltip: l10n.remoteLabel,
                enabled: !_running,
                onSelected: (action) {
                  if (action == 'edit') {
                    _editRemote(remote);
                  } else {
                    _run(() => _git.removeRemote(remote.name));
                  }
                },
                itemBuilder:
                    (context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text(l10n.editRemote),
                      ),
                      PopupMenuItem<String>(
                        value: 'remove',
                        child: Text(l10n.removeRemote),
                      ),
                    ],
              ),
            ),
          if (_usesSshRemote)
            ParsSectionRow(
              leading: const ParsSectionRowIcon(icon: Icons.vpn_key_outlined),
              title: l10n.sshKeysTitle,
              subtitle: _sshKeySubtitle(l10n),
              onTap: widget.onManageSshKeys,
              trailing:
                  widget.sshKeys.isEmpty
                      ? const Icon(Icons.chevron_right)
                      : PopupMenuButton<String>(
                        tooltip: l10n.sshKeysTitle,
                        initialValue: _selectedSshKey,
                        enabled: !_running,
                        onSelected: _selectSshKey,
                        itemBuilder:
                            (context) => <PopupMenuEntry<String>>[
                              for (final key in widget.sshKeys)
                                PopupMenuItem<String>(
                                  value: key.name,
                                  child: Text(key.name),
                                ),
                            ],
                        icon: const Icon(Icons.expand_more),
                      ),
            ),
          if (_usesHttpsRemote && (Platform.isAndroid || Platform.isIOS))
            ParsSectionRow(
              leading: const ParsSectionRowIcon(icon: Icons.password_outlined),
              title: l10n.httpsCredentials,
              subtitle:
                  _hasHttpsCredentials
                      ? l10n.httpsCredentialsSaved
                      : l10n.httpsCredentialsNone,
              trailing:
                  _hasHttpsCredentials
                      ? TextButton(
                        onPressed: _running ? null : _forgetHttps,
                        child: Text(l10n.forget),
                      )
                      : null,
            ),
        ],
      ),
      const SizedBox(height: ParsSpacing.sm),
      ParsButtonGrid(
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: _running ? null : () => _editRemote(null),
            icon: const Icon(Icons.add_link),
            label: Text(l10n.addRemote),
          ),
        ],
      ),
      const SizedBox(height: ParsSpacing.lg),
      AppSectionBox(
        title: l10n.gitMaintenanceSection,
        padding: EdgeInsets.zero,
        children: <Widget>[
          ParsSectionRow(
            leading: const ParsSectionRowIcon(icon: Icons.history),
            title: l10n.gitHistory,
            subtitle: branch ?? l10n.gitHistoryEmpty,
            onTap: _running ? null : _showHistory,
            trailing: const Icon(Icons.chevron_right),
          ),
          if (_hasRemote)
            ParsSectionRow(
              leading: const ParsSectionRowIcon(icon: Icons.alt_route),
              title: l10n.switchBranch,
              subtitle: branch ?? l10n.gitNoUpstream,
              onTap: _running ? null : _switchBranch,
              trailing: const Icon(Icons.chevron_right),
            ),
          if (_hasRemote)
            ParsSectionRow(
              leading: ParsSectionRowIcon(
                icon: Icons.restore,
                color: Theme.of(context).colorScheme.error,
              ),
              title: l10n.resetToRemote,
              subtitle: upstream ?? l10n.gitNoUpstream,
              onTap:
                  _running
                      ? null
                      : () async {
                        await runGitResetFlow(context, _git);
                        await _reload();
                      },
            ),
        ],
      ),
    ];
  }

  String _statusSubtitle(
    BuildContext context,
    String? branch,
    String? upstream,
    GitStatusSummary? summary,
  ) {
    final l10n = context.l10n;
    if (_hasRemote && _git.lastRemoteCheckFailed) {
      return l10n.gitRemoteCheckFailed;
    }
    final fetched = summary?.lastFetchedAt;
    if (_hasRemote && fetched != null) {
      return l10n.gitLastChecked(_formatTime(fetched));
    }
    if (branch == null) return l10n.gitHistoryEmpty;
    return l10n.gitBranchSummary(branch, upstream ?? l10n.gitNoUpstream);
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _strategyLabel(AppLocalizations l10n, GitIntegrationStrategy value) =>
      switch (value) {
        GitIntegrationStrategy.rebase => l10n.strategyRebase,
        GitIntegrationStrategy.merge => l10n.strategyMerge,
      };

  String _sshKeySubtitle(AppLocalizations l10n) {
    final selected = _selectedSshKey;
    if (selected == null) return l10n.sshKeyRequiredForRemote;
    final encrypted = widget.sshKeys.any(
      (key) => key.name == selected && key.encrypted,
    );
    return encrypted ? '$selected · ${l10n.sshKeyEncrypted}' : selected;
  }

  bool get _usesSshRemote => _remotes.any(
    (remote) =>
        remoteUrlUsesSsh(remote.fetchUrl) || remoteUrlUsesSsh(remote.pushUrl),
  );

  bool get _usesHttpsRemote => _remotes.any(
    (remote) => remote.fetchUrl.toLowerCase().startsWith('http'),
  );

  String _gitModeLabel(BuildContext context) => switch (_gitMode) {
    StoreGitMode.disabled => context.l10n.gitDisabledState,
    StoreGitMode.local => context.l10n.gitLocalState,
    StoreGitMode.remote => context.l10n.gitRemoteState,
    StoreGitMode.invalid => context.l10n.invalidGitMetadataTitle,
  };

  Future<void> _commitNow() async {
    final message = await showParsAdaptiveSurface<String>(
      context: context,
      title: context.l10n.commitNow,
      builder:
          (surfaceContext) => _SingleFieldForm(
            label: surfaceContext.l10n.commitMessageField,
            initialValue: surfaceContext.l10n.gitCommitMessageDefault,
            submitLabel: surfaceContext.l10n.commit,
          ),
    );
    if (message == null || !mounted) return;
    await _run(() => _git.commit(message));
  }

  Future<void> _editRemote(GitRemote? remote) async {
    final result = await showParsAdaptiveSurface<({String name, String url})>(
      context: context,
      title: remote == null ? context.l10n.addRemote : context.l10n.editRemote,
      builder: (surfaceContext) => _RemoteForm(remote: remote),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      final output =
          remote == null
              ? await _git.addRemote(name: result.name, url: result.url)
              : await _git.editRemote(name: result.name, url: result.url);
      _gitMode = _git.gitMode;
      return output;
    });
  }

  Future<void> _forgetHttps() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = dialogContext.l10n;
        return ParsDialog(
          title: l10n.httpsCredentials,
          content: Text(l10n.forgetHttpsQuestion),
          destructive: true,
          secondary: ParsDialogAction(
            label: l10n.cancel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          primary: ParsDialogAction(
            label: l10n.forget,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        );
      },
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      await _git.forgetHttpsCredentials();
      return null;
    });
  }

  Future<void> _showHistory() async {
    await showParsAdaptiveDetail<void>(
      context: context,
      builder: (context) => _GitHistorySheet(git: _git),
    );
  }

  Future<void> _switchBranch() async {
    final summary = _git.statusSummary;
    if (summary != null && !summary.canSwitchBranch) {
      AppNotification.show(
        context,
        context.l10n.switchBranchSyncFirst,
        severity: AppNotificationSeverity.warning,
      );
      return;
    }
    GitRemoteBranches? branches;
    await _run(() async {
      branches = await _git.remoteBranches();
      return branches;
    });
    final loaded = branches;
    if (loaded == null || !mounted) return;
    final choice = await showParsAdaptiveSurface<String>(
      context: context,
      title: context.l10n.switchBranch,
      builder:
          (surfaceContext) => AppSectionBox(
            title: loaded.remote ?? surfaceContext.l10n.remoteLabel,
            padding: EdgeInsets.zero,
            emptyLabel: surfaceContext.l10n.gitNoUpstream,
            children: <Widget>[
              for (final name in loaded.branches)
                ParsSectionRow(
                  leading: ParsSectionRowIcon(
                    icon:
                        name == loaded.current ? Icons.check : Icons.alt_route,
                  ),
                  title: name,
                  subtitle: '${loaded.remote ?? ''}/$name',
                  selected: name == loaded.current,
                  onTap:
                      name == loaded.current
                          ? null
                          : () => Navigator.of(surfaceContext).pop(name),
                ),
            ],
          ),
    );
    if (choice == null || !mounted) return;
    await _run(() async {
      await _git.switchBranch(choice);
      return choice;
    }, success: (_) => context.l10n.switchedBranch(choice));
  }
}

class _GitHistorySheet extends StatefulWidget {
  const _GitHistorySheet({required this.git});

  final GitOperationsRepository git;

  @override
  State<_GitHistorySheet> createState() => _GitHistorySheetState();
}

class _GitHistorySheetState extends State<_GitHistorySheet> {
  late final Future<List<GitLogEntry>> _entries = widget.git.history();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(ParsSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.gitHistory,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: ParsSpacing.md),
            Flexible(
              child: FutureBuilder<List<GitLogEntry>>(
                future: _entries,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return FailureNotice(
                      problem: UiProblem.fromError(l10n, snapshot.error!),
                    );
                  }
                  final entries = snapshot.data;
                  if (entries == null) {
                    return const LinearProgressIndicator();
                  }
                  return AppSectionBox(
                    title: widget.git.statusSummary?.branch ?? l10n.gitHistory,
                    padding: EdgeInsets.zero,
                    scrollable: true,
                    emptyLabel: l10n.gitHistoryEmpty,
                    children: <Widget>[
                      for (final entry in entries)
                        ParsSectionRow(
                          leading: const ParsSectionRowIcon(icon: Icons.commit),
                          title: entry.summary,
                          subtitle:
                              '${entry.id} · ${entry.author} · '
                              '${_historyTime(entry.time)}',
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _historyTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

class _SingleFieldForm extends StatefulWidget {
  const _SingleFieldForm({
    required this.label,
    required this.initialValue,
    required this.submitLabel,
  });

  final String label;
  final String initialValue;
  final String submitLabel;

  @override
  State<_SingleFieldForm> createState() => _SingleFieldFormState();
}

class _SingleFieldFormState extends State<_SingleFieldForm> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _controller,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: widget.label),
        ),
        const SizedBox(height: ParsSpacing.sm),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}

class _RemoteForm extends StatefulWidget {
  const _RemoteForm({required this.remote});

  final GitRemote? remote;

  @override
  State<_RemoteForm> createState() => _RemoteFormState();
}

class _RemoteFormState extends State<_RemoteForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.remote?.name ?? 'origin',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.remote?.fetchUrl ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    Navigator.of(context).pop((name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _name,
          enabled: widget.remote == null,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l10n.remoteNameField),
        ),
        const SizedBox(height: ParsSpacing.sm),
        TextField(
          controller: _url,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: l10n.remoteUrlField),
        ),
        const SizedBox(height: ParsSpacing.sm),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.remote == null ? l10n.addRemote : l10n.updateRemote,
          ),
        ),
      ],
    );
  }
}

UiProblem _gitResultProblem(BuildContext context, GitOperationResult result) {
  final detail = [
    result.stderr.trim(),
    result.stdout.trim(),
  ].where((part) => part.isNotEmpty).join('\n');
  if (detail.isEmpty) {
    return UiProblem(summary: context.l10n.operationFailed);
  }
  return UiProblem(
    summary: context.l10n.operationFailed,
    diagnostics:
        UiProblem.fromError(context.l10n, StateError(detail)).diagnostics,
  );
}

class _GitArgsSheetBody extends StatefulWidget {
  const _GitArgsSheetBody({required this.git});

  final GitOperationsRepository? git;

  @override
  State<_GitArgsSheetBody> createState() => _GitArgsSheetBodyState();
}

class _GitArgsSheetBodyState extends State<_GitArgsSheetBody> {
  var _argsText = '';
  var _running = false;
  GitOperationResult? _output;
  UiProblem? _error;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: ParsSpacing.lg,
            right: ParsSpacing.lg,
            top: ParsSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + ParsSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.advancedGitArgsTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: ParsSpacing.xs),
              Text(context.l10n.gitArgsOnlyDescription),
              const SizedBox(height: ParsSpacing.sm),
              Row(
                children: <Widget>[
                  const Text(
                    'git',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: ParsSpacing.xs),
                  Expanded(
                    child: TextFormField(
                      initialValue: _argsText,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'status, log',
                      ),
                      onChanged: (value) {
                        _argsText = value;
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ParsSpacing.xs),
              SelectableText('git ${_argsText.trim()}'),
              const SizedBox(height: ParsSpacing.sm),
              FilledButton(
                onPressed: _running ? null : _run,
                child: SizedBox(
                  width: double.infinity,
                  child: Center(child: Text(context.l10n.runSelectedCommand)),
                ),
              ),
              if (_running) ...const <Widget>[
                SizedBox(height: ParsSpacing.sm),
                LinearProgressIndicator(),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: ParsSpacing.sm),
                FailureNotice(problem: _error!),
              ],
              if (_output != null) ...<Widget>[
                const SizedBox(height: ParsSpacing.sm),
                _GitOutputPanel(output: _output!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run() async {
    final git = widget.git;
    if (git == null) {
      setState(
        () =>
            _error = UiProblem(summary: context.l10n.gitOperationsUnavailable),
      );
      return;
    }
    if (_argsText.trim().isEmpty) {
      setState(
        () => _error = UiProblem(summary: context.l10n.gitArgumentRequired),
      );
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await git.runCommandLine(_argsText);
      if (mounted) {
        setState(() {
          _output = result;
          _running = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = UiProblem.fromError(context.l10n, error);
          _running = false;
        });
      }
    }
  }
}

class _GitOutputPanel extends StatelessWidget {
  const _GitOutputPanel({required this.output});

  final GitOperationResult output;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(ParsRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ParsSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(
              output.command,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: ParsSpacing.xs),
            Text(
              context.l10n.exitCodeValue(
                output.exitCode?.toString() ?? 'signal',
              ),
            ),
            Text(output.success ? context.l10n.success : context.l10n.failed),
            if (output.stdout.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: ParsSpacing.xs),
              Text(
                context.l10n.standardOutput,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(output.stdout),
            ],
            if (output.stderr.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: ParsSpacing.xs),
              Text(
                context.l10n.standardError,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(output.stderr),
            ],
          ],
        ),
      ),
    );
  }
}
