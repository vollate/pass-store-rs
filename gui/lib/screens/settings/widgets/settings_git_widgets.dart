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
            gitRepository: gitRepository,
            gitMode: settingsRepository.store?.gitMode ?? StoreGitMode.disabled,
            combineGitOutput: _combineGitOutput,
            onManageSshKeys: () => _showSshKeys(context),
          ),
    );
  }

  void _showGitArgs(BuildContext context) {
    showParsAdaptiveDetail<void>(
      context: context,
      builder:
          (context) => _GitArgsSheetBody(
            git: _gitOperations,
            parseGitArgs: _parseGitArgs,
          ),
    );
  }
}

class _GitSyncSheetBody extends StatefulWidget {
  const _GitSyncSheetBody({
    required this.git,
    required this.gitRepository,
    required this.gitMode,
    required this.combineGitOutput,
    required this.onManageSshKeys,
  });

  final GitOperationsRepository git;
  final GitRepository gitRepository;
  final StoreGitMode gitMode;
  final GitOperationResult Function(GitOperationResult, GitOperationResult)
  combineGitOutput;
  final VoidCallback onManageSshKeys;

  @override
  State<_GitSyncSheetBody> createState() => _GitSyncSheetBodyState();
}

class _GitSyncSheetBodyState extends State<_GitSyncSheetBody> {
  var _message = '';
  var _messageInitialized = false;
  var _remoteName = 'origin';
  var _remoteUrl = '';
  var _pushAfterCommit = false;
  var _running = false;
  GitOperationResult? _output;
  List<GitRemote> _remotes = const <GitRemote>[];
  String? _errorText;

  @override
  void initState() {
    super.initState();
    if (widget.gitMode == StoreGitMode.local ||
        widget.gitMode == StoreGitMode.remote) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRemotes());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_messageInitialized) {
      _message = context.l10n.updatePasswordStore;
      _messageInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGit =
        widget.gitMode == StoreGitMode.local ||
        widget.gitMode == StoreGitMode.remote;
    final hasRemote = widget.gitMode == StoreGitMode.remote;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.gitSyncTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: context.l10n.gitSyncTitle,
                value: _gitModeLabel(context),
                child: Chip(label: Text(_gitModeLabel(context))),
              ),
              if (widget.gitMode == StoreGitMode.invalid) ...<Widget>[
                const SizedBox(height: 8),
                Text(context.l10n.invalidGitMetadataMessage),
              ],
              if (widget.gitRepository.gitStatus ==
                  RepoGitStatus.disabled) ...<Widget>[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      _running
                          ? null
                          : () => _run(widget.git.initializeRepository),
                  icon: const Icon(Icons.account_tree_outlined),
                  label: Text(context.l10n.initializeGit),
                ),
              ],
              if (hasGit) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed:
                          _running || !hasGit
                              ? null
                              : () => _run(widget.git.refreshGitStatus),
                      icon: const Icon(Icons.info_outline),
                      label: Text(context.l10n.status),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _running || !hasRemote
                              ? null
                              : () => _run(widget.git.pull),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(context.l10n.pull),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _running || !hasRemote
                              ? null
                              : () => _run(widget.git.push),
                      icon: const Icon(Icons.upload_outlined),
                      label: Text(context.l10n.push),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _running || !hasRemote
                              ? null
                              : () => _run(widget.git.recoverByPull),
                      icon: const Icon(Icons.healing_outlined),
                      label: Text(context.l10n.recoverPull),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: context.l10n.commitMessageField,
                  ),
                  onChanged: (value) => _message = value,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _pushAfterCommit,
                  onChanged:
                      _running || !hasRemote
                          ? null
                          : (value) =>
                              setState(() => _pushAfterCommit = value ?? false),
                  title: Text(context.l10n.pushAfterCommit),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed:
                      _running || !hasGit
                          ? null
                          : () => _run(() async {
                            final commit = await widget.git.commit(_message);
                            if (!_pushAfterCommit) {
                              return commit;
                            }
                            final push = await widget.git.push();
                            return widget.combineGitOutput(commit, push);
                          }),
                  icon: const Icon(Icons.add_task_outlined),
                  label: Text(context.l10n.commit),
                ),
                const Divider(height: 28),
                _RemoteList(remotes: _remotes),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _running ? null : _refreshRemotes,
                      icon: const Icon(Icons.list_alt_outlined),
                      label: Text(context.l10n.listRemotes),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    labelText: context.l10n.remoteNameField,
                  ),
                  onChanged: (value) => _remoteName = value,
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: context.l10n.remoteUrlField,
                  ),
                  onChanged: (value) => setState(() => _remoteUrl = value),
                ),
                if (_usesSshRemote) ...<Widget>[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.vpn_key_outlined),
                    title: Text(context.l10n.sshKeyRequiredForRemote),
                    subtitle: Text(context.l10n.sshKeysGitOnlyDescription),
                    trailing: TextButton(
                      onPressed: widget.onManageSshKeys,
                      child: Text(context.l10n.sshKeysTitle),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton(
                      onPressed:
                          _running || !hasGit
                              ? null
                              : () => _run(
                                () => widget.git.addRemote(
                                  name: _remoteName,
                                  url: _remoteUrl,
                                ),
                              ),
                      child: Text(context.l10n.addRemote),
                    ),
                    OutlinedButton(
                      onPressed:
                          _running || !_hasNamedRemote
                              ? null
                              : () => _run(
                                () => widget.git.editRemote(
                                  name: _remoteName,
                                  url: _remoteUrl,
                                ),
                              ),
                      child: Text(context.l10n.updateRemote),
                    ),
                    OutlinedButton(
                      onPressed:
                          _running || !_hasNamedRemote
                              ? null
                              : () => _run(
                                () => widget.git.removeRemote(_remoteName),
                              ),
                      child: Text(context.l10n.removeRemote),
                    ),
                  ],
                ),
              ],
              const Divider(height: 28),
              if (_running) ...const <Widget>[
                SizedBox(height: 12),
                LinearProgressIndicator(),
              ],
              if (_errorText != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_output != null) ...<Widget>[
                const SizedBox(height: 12),
                _GitOutputPanel(output: _output!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasNamedRemote =>
      _remotes.any((remote) => remote.name == _remoteName.trim());

  bool get _usesSshRemote =>
      remoteUrlUsesSsh(_remoteUrl) ||
      _remotes.any(
        (remote) =>
            remoteUrlUsesSsh(remote.fetchUrl) ||
            remoteUrlUsesSsh(remote.pushUrl),
      );

  String _gitModeLabel(BuildContext context) => switch (widget.gitMode) {
    StoreGitMode.disabled => context.l10n.gitDisabledState,
    StoreGitMode.local => context.l10n.gitLocalState,
    StoreGitMode.remote => context.l10n.gitRemoteState,
    StoreGitMode.invalid => context.l10n.invalidGitMetadataTitle,
  };

  Future<void> _refreshRemotes() async {
    try {
      final loaded = await widget.git.listRemotes();
      if (mounted) {
        setState(() => _remotes = loaded);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorText = UiProblem.fromError(context.l10n, error).summary,
        );
      }
    }
  }

  Future<void> _run(Future<GitOperationResult> Function() action) async {
    setState(() {
      _running = true;
      _errorText = null;
    });
    try {
      final result = await action();
      if (mounted) {
        setState(() {
          _output = result;
          _running = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = UiProblem.fromError(context.l10n, error).summary;
          _running = false;
        });
      }
    }
  }
}

class _GitArgsSheetBody extends StatefulWidget {
  const _GitArgsSheetBody({required this.git, required this.parseGitArgs});

  final GitOperationsRepository? git;
  final List<String> Function(String) parseGitArgs;

  @override
  State<_GitArgsSheetBody> createState() => _GitArgsSheetBodyState();
}

class _GitArgsSheetBodyState extends State<_GitArgsSheetBody> {
  var _argsText = '';
  var _running = false;
  GitOperationResult? _output;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
              const SizedBox(height: 8),
              Text(context.l10n.gitArgsOnlyDescription),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text(
                    'git',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _argsText,
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
              const SizedBox(height: 8),
              SelectableText('git ${_argsText.trim()}'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _running ? null : _run,
                child: SizedBox(
                  width: double.infinity,
                  child: Center(child: Text(context.l10n.runSelectedCommand)),
                ),
              ),
              if (_running) ...const <Widget>[
                SizedBox(height: 12),
                LinearProgressIndicator(),
              ],
              if (_errorText != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_output != null) ...<Widget>[
                const SizedBox(height: 12),
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
      setState(() => _errorText = context.l10n.gitOperationsUnavailable);
      return;
    }
    if (_argsText.trim().isEmpty) {
      setState(() => _errorText = context.l10n.gitArgumentRequired);
      return;
    }
    setState(() {
      _running = true;
      _errorText = null;
    });
    try {
      final result = await git.runArgs(widget.parseGitArgs(_argsText));
      if (mounted) {
        setState(() {
          _output = result;
          _running = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = UiProblem.fromError(context.l10n, error).summary;
          _running = false;
        });
      }
    }
  }
}

class _RemoteList extends StatelessWidget {
  const _RemoteList({required this.remotes});

  final List<GitRemote> remotes;

  @override
  Widget build(BuildContext context) {
    if (remotes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: remotes
          .map(
            (remote) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_queue_outlined),
              title: Text(remote.name),
              subtitle: Text('${remote.fetchUrl}\n${remote.pushUrl}'),
              isThreeLine: true,
            ),
          )
          .toList(growable: false),
    );
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SelectableText(
              output.command,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.exitCodeValue(
                output.exitCode?.toString() ?? 'signal',
              ),
            ),
            Text(output.success ? context.l10n.success : context.l10n.failed),
            if (output.stdout.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                context.l10n.standardOutput,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              SelectableText(output.stdout),
            ],
            if (output.stderr.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
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
