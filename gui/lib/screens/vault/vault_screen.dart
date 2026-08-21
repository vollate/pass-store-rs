import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../l10n/operation_localizations.dart';
import '../../models/key_record.dart';
import '../../models/password_entry.dart';
import '../../services/git_repository.dart';
import '../../services/key_repository.dart';
import '../../services/security_repository.dart';
import '../../services/sensitive_clipboard_service.dart';
import '../../services/store_lifecycle.dart';
import '../../services/vault_repository.dart';
import '../../widgets/app_notification.dart';
import '../../widgets/app_section.dart';
import '../../widgets/entry_tile.dart';
import '../../widgets/pars_action_group.dart';
import '../../widgets/pars_adaptive_surface.dart';
import '../../widgets/pars_status_badge.dart';
import '../manage/manage_screen.dart';
import '../shell/shell_view_state.dart';
import 'entry_detail_sheet.dart';

enum _EntryDetailAction { edit, move, rename, regenerate, delete }

enum _CreateEntryAction { generate, existing }

class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    required this.vaultRepository,
    required this.gitRepository,
    this.keyRepository,
    this.securityRepository,
    this.keys = const <KeyRecord>[],
    this.viewState,
    this.clipboardService,
    this.privacyEvents,
    this.onLock,
  });

  final VaultRepository vaultRepository;
  final GitRepository gitRepository;
  final KeyRepository? keyRepository;
  final SecurityRepository? securityRepository;
  final List<KeyRecord> keys;
  final VaultDestinationState? viewState;
  final SensitiveClipboardService? clipboardService;
  final ValueListenable<int>? privacyEvents;
  final VoidCallback? onLock;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  static const int _favoritesLimit = 6;
  static const int _recentLimit = 10;

  late final VaultDestinationState _viewState;
  late final bool _ownsViewState;
  late final TextEditingController _searchController;
  late final SensitiveClipboardService _clipboardService;
  late final bool _ownsClipboardService;
  bool _isLoading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _ownsViewState = widget.viewState == null;
    _viewState = widget.viewState ?? VaultDestinationState();
    _searchController = TextEditingController(text: _viewState.query);
    _ownsClipboardService = widget.clipboardService == null;
    _clipboardService = widget.clipboardService ?? SensitiveClipboardService();
    _refreshVault();
  }

  @override
  void didUpdateWidget(covariant VaultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vaultRepository != widget.vaultRepository) {
      _refreshVault();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_ownsViewState) _viewState.dispose();
    if (_ownsClipboardService) _clipboardService.dispose();
    super.dispose();
  }

  String get _query => _viewState.query;
  String? get _directoryPath => _viewState.directoryPath;
  ManageRepository? get _manageRepository =>
      widget.vaultRepository is ManageRepository
          ? widget.vaultRepository as ManageRepository
          : null;
  List<PasswordEntry> get _selectedEntries => widget.vaultRepository.entries
      .where(
        (entry) =>
            !entry.isDirectory && _viewState.selectedPaths.contains(entry.path),
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final localizations = context.l10n;
    final entries = widget.vaultRepository.search(_query);
    final favorites =
        _query.isEmpty
            ? widget.vaultRepository.entries
                .where((entry) => !entry.isDirectory && entry.isFavorite)
                .take(_favoritesLimit)
                .toList(growable: false)
            : const <PasswordEntry>[];
    final favoritePaths = favorites.map((entry) => entry.path).toSet();
    final recent =
        _query.isEmpty
            ? widget.vaultRepository
                .recentEntries()
                .where((entry) => !favoritePaths.contains(entry.path))
                .take(_recentLimit)
                .toList(growable: false)
            : entries
                .where((entry) => !entry.isDirectory)
                .toList(growable: false);
    final browseEntries =
        _query.isEmpty
            ? widget.vaultRepository.browseEntries(_directoryPath)
            : const <PasswordEntry>[];

    return RefreshIndicator(
      onRefresh: _refreshVault,
      child: CustomScrollView(
        controller: _viewState.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  localizations.vaultTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.vaultRepository.currentRepoName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: <Widget>[
              if (widget.onLock != null)
                IconButton(
                  tooltip: localizations.lockNow,
                  onPressed: widget.onLock,
                  icon: const Icon(Icons.lock_outline),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 152),
                  child: ParsStatusBadge(
                    label: _gitStatusLabel(context),
                    kind: _gitStatusKind,
                    onPressed: _handleGitStatus,
                  ),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: localizations.searchVaultHint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged:
                    (value) => setState(() => _viewState.setQuery(value)),
              ),
            ),
          ),
          if (_manageRepository != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildVaultActions(context),
              ),
            ),
          if (_isLoading)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          if (_loadError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(_loadError!),
                    trailing: TextButton(
                      onPressed: _refreshVault,
                      child: Text(localizations.retry),
                    ),
                  ),
                ),
              ),
            ),
          if (_query.isEmpty)
            AppSection(
              title: localizations.favoritesSection,
              emptyLabel: localizations.noFavoriteEntries,
              children:
                  favorites
                      .map(
                        (entry) => _buildEntryTile(
                          entry,
                          onTap: () => _showEntry(entry),
                        ),
                      )
                      .toList(),
            ),
          AppSection(
            title:
                _query.isEmpty
                    ? localizations.recentSection
                    : localizations.searchResultsSection,
            emptyLabel:
                _query.isEmpty
                    ? localizations.noRecentEntries
                    : localizations.noSearchResults,
            children:
                recent
                    .map(
                      (entry) => _buildEntryTile(
                        entry,
                        onTap: () => _showEntry(entry),
                      ),
                    )
                    .toList(),
          ),
          if (_query.isEmpty)
            AppSection(
              title:
                  _directoryPath == null
                      ? localizations.browseSection
                      : localizations.browsePathSection(_directoryPath!),
              emptyLabel:
                  _directoryPath == null
                      ? localizations.noStoreEntries
                      : localizations.noFolderEntries,
              children: <Widget>[
                if (_directoryPath != null)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: _openParentDirectory,
                      leading: const Icon(Icons.arrow_upward),
                      title: Text(localizations.upOneLevel),
                      subtitle: Text(_directoryPath!),
                    ),
                  ),
                ...browseEntries.map(
                  (entry) => _buildEntryTile(
                    entry,
                    onTap:
                        entry.isDirectory
                            ? () => _openDirectory(entry)
                            : () => _showEntry(entry),
                  ),
                ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildVaultActions(BuildContext context) {
    final localizations = context.l10n;
    if (_viewState.selectionMode) {
      final selectedCount = _viewState.selectedPaths.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  localizations.selectedCount(selectedCount),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(_viewState.clearSelection),
                child: Text(localizations.cancel),
              ),
            ],
          ),
          ParsActionGroup(
            actions: <ParsActionItem>[
              ParsActionItem(
                label: localizations.move,
                icon: Icons.drive_file_move_outlined,
                onPressed: selectedCount == 0 ? null : _showBatchMove,
              ),
              ParsActionItem(
                label: localizations.rename,
                icon: Icons.drive_file_rename_outline,
                onPressed: selectedCount == 0 ? null : _showBatchRename,
              ),
              ParsActionItem(
                label: localizations.regenerate,
                icon: Icons.refresh,
                onPressed: selectedCount == 0 ? null : _showBatchRegenerate,
              ),
              ParsActionItem(
                label: localizations.delete,
                icon: Icons.delete_outline,
                kind: ParsActionKind.destructive,
                onPressed: selectedCount == 0 ? null : _showBatchDelete,
              ),
            ],
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: _showCreateMenu,
            icon: const Icon(Icons.add),
            label: Text(localizations.createPassword),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => setState(_viewState.enterSelection),
          icon: const Icon(Icons.checklist),
          label: Text(localizations.select),
        ),
      ],
    );
  }

  Widget _buildEntryTile(PasswordEntry entry, {required VoidCallback onTap}) {
    final selected = _viewState.selectedPaths.contains(entry.path);
    return EntryTile(
      entry: entry,
      onTap: onTap,
      onCopy: entry.isDirectory ? null : () => _copyPassword(entry),
      onFavorite: entry.isDirectory ? null : () => _toggleFavorite(entry),
      onLongPress:
          entry.isDirectory
              ? null
              : () => setState(() => _viewState.enterSelection(entry.path)),
      selectionMode: _viewState.selectionMode,
      selected: selected,
      onSelectedChanged:
          entry.isDirectory
              ? null
              : (value) => setState(
                () => _viewState.setSelected(entry.path, selected: value),
              ),
    );
  }

  Future<void> _showCreateMenu() async {
    final repository = _manageRepository;
    if (repository == null) {
      AppNotification.show(context, context.l10n.manageUnavailable);
      return;
    }
    final action = await showParsAdaptiveSurface<_CreateEntryAction>(
      context: context,
      title: context.l10n.createPassword,
      builder:
          (surfaceContext) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.auto_fix_high),
                title: Text(context.l10n.generateAndSave),
                subtitle: Text(context.l10n.generateAndSaveDescription),
                onTap:
                    () => Navigator.of(
                      surfaceContext,
                    ).pop(_CreateEntryAction.generate),
              ),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: Text(context.l10n.saveExistingPassword),
                subtitle: Text(context.l10n.saveExistingPasswordDescription),
                onTap:
                    () => Navigator.of(
                      surfaceContext,
                    ).pop(_CreateEntryAction.existing),
              ),
            ],
          ),
    );
    if (!mounted || action == null) return;
    final operation =
        action == _CreateEntryAction.generate
            ? showCreateGeneratedEntrySurface(
              context: context,
              repository: repository,
            )
            : showSaveExistingEntrySurface(
              context: context,
              repository: repository,
            );
    final result = await operation;
    _showEntryOperationResult(result);
  }

  Future<void> _showBatchMove() async {
    final result = await showBatchMoveEntriesSurface(
      context: context,
      entries: _selectedEntries,
      repository: _manageRepository!,
    );
    _finishBatchAction(result);
  }

  Future<void> _showBatchRename() async {
    final result = await showBatchRenameEntriesSurface(
      context: context,
      entries: _selectedEntries,
      repository: _manageRepository!,
    );
    _finishBatchAction(result);
  }

  Future<void> _showBatchRegenerate() async {
    final result = await showBatchRegenerateEntriesSurface(
      context: context,
      entries: _selectedEntries,
      repository: _manageRepository!,
    );
    _finishBatchAction(result);
  }

  Future<void> _showBatchDelete() async {
    final result = await showBatchDeleteEntriesSurface(
      context: context,
      entries: _selectedEntries,
      repository: _manageRepository!,
    );
    _finishBatchAction(result);
  }

  void _finishBatchAction(BatchOperationResult? result) {
    if (result == null || !mounted) return;
    setState(_viewState.clearSelection);
    _showBatchOperationResult(result);
  }

  Future<void> _refreshVault() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      await widget.vaultRepository.refresh();
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = context.l10n.couldNotLoadVault;
      });
    }
  }

  Future<void> _showEntry(PasswordEntry entry) async {
    if (entry.isDirectory) {
      return;
    }
    final manageRepository = _manageRepository;
    final action = await showParsAdaptiveDetail<_EntryDetailAction>(
      context: context,
      builder:
          (sheetContext) => EntryDetailSheet(
            entry: entry,
            repository: widget.vaultRepository,
            keyRepository: widget.keyRepository,
            securityRepository: widget.securityRepository,
            clipboardService: _clipboardService,
            privacyEvents: widget.privacyEvents,
            keys: widget.keys,
            onFavoriteChanged: () => setState(() {}),
            onEdit:
                manageRepository == null
                    ? null
                    : () =>
                        Navigator.of(sheetContext).pop(_EntryDetailAction.edit),
            onMove:
                manageRepository == null
                    ? null
                    : () =>
                        Navigator.of(sheetContext).pop(_EntryDetailAction.move),
            onRename:
                manageRepository == null
                    ? null
                    : () => Navigator.of(
                      sheetContext,
                    ).pop(_EntryDetailAction.rename),
            onRegenerate:
                manageRepository == null
                    ? null
                    : () => Navigator.of(
                      sheetContext,
                    ).pop(_EntryDetailAction.regenerate),
            onDelete:
                manageRepository == null
                    ? null
                    : () => Navigator.of(
                      sheetContext,
                    ).pop(_EntryDetailAction.delete),
          ),
    );
    if (!mounted || action == null || manageRepository == null) {
      return;
    }

    switch (action) {
      case _EntryDetailAction.edit:
        final result = await showFocusedEditEntrySheet(
          context: context,
          entry: entry,
          repository: manageRepository,
        );
        _showEntryOperationResult(result);
        break;
      case _EntryDetailAction.move:
        final result = await showFocusedMoveOrRenameEntrySurface(
          context: context,
          entry: entry,
          repository: manageRepository,
          rename: false,
        );
        _showEntryOperationResult(result);
        break;
      case _EntryDetailAction.rename:
        final result = await showFocusedMoveOrRenameEntrySurface(
          context: context,
          entry: entry,
          repository: manageRepository,
          rename: true,
        );
        _showEntryOperationResult(result);
        break;
      case _EntryDetailAction.regenerate:
        final result = await showFocusedRegenerateEntrySheet(
          context: context,
          entry: entry,
          repository: manageRepository,
        );
        _showBatchOperationResult(result);
        break;
      case _EntryDetailAction.delete:
        final result = await showFocusedDeleteEntrySheet(
          context: context,
          entry: entry,
          repository: manageRepository,
        );
        _showEntryOperationResult(result);
        break;
    }
  }

  void _showEntryOperationResult(EntryOperationResult? result) {
    if (!mounted || result == null) {
      return;
    }
    setState(() {});
    AppNotification.show(
      context,
      localizedEntryOperationSummary(context.l10n, result),
      severity: AppNotificationSeverity.success,
    );
  }

  void _showBatchOperationResult(BatchOperationResult? result) {
    if (!mounted || result == null) {
      return;
    }
    setState(() {});
    AppNotification.show(
      context,
      localizedBatchOperationSummary(context.l10n, result),
      severity:
          result.failures.isEmpty
              ? AppNotificationSeverity.success
              : AppNotificationSeverity.warning,
      duration: result.failures.isEmpty ? null : Duration.zero,
    );
  }

  StoreGitMode get _storeGitMode {
    final repository = widget.gitRepository;
    if (repository is GitModeRepository) {
      return (repository as GitModeRepository).gitMode;
    }
    return repository.gitStatus == RepoGitStatus.disabled
        ? StoreGitMode.disabled
        : StoreGitMode.remote;
  }

  String _gitStatusLabel(BuildContext context) {
    if (_isLoading) return context.l10n.storeActionInProgress;
    final operational = switch (widget.gitRepository.gitStatus) {
      RepoGitStatus.disabled => context.l10n.gitDisabledState,
      RepoGitStatus.clean => context.l10n.gitClean,
      RepoGitStatus.needPull => context.l10n.gitNeedPull,
      RepoGitStatus.uncommitted => context.l10n.gitUncommitted,
      RepoGitStatus.invalid => context.l10n.invalidGitMetadataTitle,
      RepoGitStatus.syncFailed => context.l10n.gitSyncFailed,
    };
    return switch (_storeGitMode) {
      StoreGitMode.disabled => context.l10n.gitDisabledState,
      StoreGitMode.invalid => context.l10n.invalidGitMetadataTitle,
      StoreGitMode.local =>
        widget.gitRepository.gitStatus == RepoGitStatus.clean
            ? context.l10n.gitLocalState
            : '${context.l10n.gitLocalState} · $operational',
      StoreGitMode.remote =>
        widget.gitRepository.gitStatus == RepoGitStatus.clean
            ? '${context.l10n.gitRemoteState} · ${context.l10n.gitClean}'
            : operational,
    };
  }

  ParsStatusKind get _gitStatusKind {
    if (_isLoading) return ParsStatusKind.busy;
    if (_storeGitMode == StoreGitMode.disabled) return ParsStatusKind.neutral;
    if (_storeGitMode == StoreGitMode.invalid) return ParsStatusKind.error;
    return switch (widget.gitRepository.gitStatus) {
      RepoGitStatus.disabled => ParsStatusKind.neutral,
      RepoGitStatus.clean => ParsStatusKind.success,
      RepoGitStatus.needPull => ParsStatusKind.warning,
      RepoGitStatus.uncommitted => ParsStatusKind.warning,
      RepoGitStatus.invalid => ParsStatusKind.error,
      RepoGitStatus.syncFailed => ParsStatusKind.error,
    };
  }

  void _handleGitStatus() {
    AppNotification.show(context, _gitStatusLabel(context));
  }

  Future<void> _toggleFavorite(PasswordEntry entry) async {
    try {
      await widget.vaultRepository.toggleFavorite(entry);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        AppNotification.show(
          context,
          context.l10n.favoriteUpdateFailed,
          severity: AppNotificationSeverity.error,
        );
      }
    }
  }

  void _openDirectory(PasswordEntry entry) {
    setState(() => _viewState.setDirectory(entry.path));
  }

  void _openParentDirectory() {
    final path = _directoryPath;
    if (path == null) {
      return;
    }
    final index = path.lastIndexOf('/');
    setState(() {
      _viewState.setDirectory(index == -1 ? null : path.substring(0, index));
    });
  }

  Future<void> _copyPassword(PasswordEntry entry) async {
    try {
      final password = await widget.vaultRepository.copyEntryPassword(entry);
      await _clipboardService.copySecret(password);
      if (!mounted) {
        return;
      }
      AppNotification.show(
        context,
        context.l10n.copiedEntryPassword(entry.displayName),
        severity: AppNotificationSeverity.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppNotification.show(
        context,
        context.l10n.couldNotCopyPassword,
        severity: AppNotificationSeverity.error,
      );
    }
  }
}
