import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/pars_design_tokens.dart';
import '../../app/pars_theme.dart';
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
import '../shell/shell_view_state.dart';
import 'entry_detail_sheet.dart';
import 'operations/vault_operations.dart';

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
  GitOperationsRepository? get _gitOperations =>
      widget.gitRepository is GitOperationsRepository
          ? widget.gitRepository as GitOperationsRepository
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
    final theme = Theme.of(context);
    final entries = widget.vaultRepository.search(_query);
    final searchResults = entries
        .where((entry) => !entry.isDirectory)
        .toList(growable: false);
    final browseEntries =
        _query.isEmpty ? _visibleBrowseEntries() : const <PasswordEntry>[];

    // The repository name is useful context but is the first thing to drop
    // when the user scales text up, so the toolbar never has to clip it.
    final textScaler = MediaQuery.textScalerOf(context);
    final showRepoName = textScaler.scale(12) <= 18;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton:
          _manageRepository == null || _viewState.selectionMode
              ? null
              : FloatingActionButton(
                onPressed: _showCreateMenu,
                tooltip: localizations.createPassword,
                child: const Icon(Icons.add),
              ),
      body: RefreshIndicator(
        onRefresh: _syncVault,
        child: CustomScrollView(
          controller: _viewState.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              toolbarHeight: ParsSizes.tallToolbar,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    localizations.vaultTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (showRepoName)
                    Text(
                      widget.vaultRepository.currentRepoName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ParsTheme.mono(
                        theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ) ??
                            const TextStyle(),
                      ),
                    ),
                ],
              ),
              actions: <Widget>[
                if (_manageRepository != null && !_viewState.selectionMode)
                  IconButton(
                    tooltip: localizations.select,
                    onPressed: () => setState(_viewState.enterSelection),
                    icon: const Icon(Icons.checklist),
                  ),
                if (widget.onLock != null)
                  IconButton(
                    tooltip: localizations.lockNow,
                    onPressed: widget.onLock,
                    icon: const Icon(Icons.lock_outline),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: ParsSpacing.sm),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ParsSizes.statusBadge,
                    ),
                    child: ParsStatusBadge(
                      label: _gitStatusLabel(context),
                      kind: _gitStatusKind,
                      onPressed: _handleGitStatus,
                    ),
                  ),
                ),
              ],
            ),
            // Search is the primary way into a password store, so it stays
            // reachable instead of scrolling away with the content.
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedSearchHeader(
                extent: _searchHeaderExtent(textScaler),
                background: theme.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ParsSpacing.md,
                    0,
                    ParsSpacing.md,
                    ParsSpacing.xs,
                  ),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: localizations.searchVaultHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged:
                        (value) => setState(() => _viewState.setQuery(value)),
                  ),
                ),
              ),
            ),
            if (_viewState.selectionMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ParsSpacing.md,
                    ParsSpacing.sm,
                    ParsSpacing.md,
                    0,
                  ),
                  child: _buildVaultActions(context),
                ),
              ),
            if (_isLoading)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (_loadError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ParsSpacing.md,
                    ParsSpacing.sm,
                    ParsSpacing.md,
                    0,
                  ),
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
            if (_query.isNotEmpty)
              AppSection(
                title: localizations.searchResultsSection,
                emptyLabel: localizations.noSearchResults,
                children:
                    searchResults
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
                  if (_directoryPath != null) _buildUpOneLevelRow(context),
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
            // Clears the floating action button so the last row stays tappable.
            const SliverToBoxAdapter(
              child: SizedBox(height: ParsSizes.floatingActionClearance),
            ),
          ],
        ),
      ),
    );
  }

  // The pinned header has a fixed extent, so it is measured against the
  // current text scale rather than hard-coded, otherwise the field is clipped
  // once the user scales text up.
  double _searchHeaderExtent(TextScaler textScaler) {
    const verticalPadding = ParsSpacing.sm * 2;
    const borders = 4.0;
    const outerPadding = ParsSpacing.xs;
    return (textScaler.scale(16) * 1.3) +
        verticalPadding +
        borders +
        outerPadding;
  }

  List<PasswordEntry> _visibleBrowseEntries() {
    final browsed = widget.vaultRepository.browseEntries(_directoryPath);
    if (browsed.isNotEmpty || _directoryPath != null) {
      return browsed;
    }
    return widget.vaultRepository.entries
        .where((entry) => !entry.isDirectory)
        .toList(growable: false);
  }

  // Reads as another row in the same grouped list rather than a separate card.
  Widget _buildUpOneLevelRow(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ParsSectionRow(
      leading: const ParsSectionRowIcon(icon: Icons.arrow_upward),
      title: context.l10n.upOneLevel,
      subtitle: _directoryPath!,
      subtitleStyle: ParsTheme.mono(
        theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ) ??
            const TextStyle(),
      ),
      onTap: _openParentDirectory,
    );
  }

  Widget _buildVaultActions(BuildContext context) {
    final localizations = context.l10n;
    final selectedCount = _selectedEntries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                localizations.selectedCount(selectedCount),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => setState(_viewState.clearSelection),
              child: Text(localizations.cancel),
            ),
          ],
        ),
        if (selectedCount > 0)
          ParsActionGroup(
            actions: <ParsActionItem>[
              ParsActionItem(
                label: localizations.move,
                icon: Icons.drive_file_move_outlined,
                onPressed: _showBatchMove,
              ),
              ParsActionItem(
                label: localizations.rename,
                icon: Icons.drive_file_rename_outline,
                onPressed: _showBatchRename,
              ),
              ParsActionItem(
                label: localizations.regenerate,
                icon: Icons.refresh,
                onPressed: _showBatchRegenerate,
              ),
              ParsActionItem(
                label: localizations.delete,
                icon: Icons.delete_outline,
                kind: ParsActionKind.destructive,
                onPressed: _showBatchDelete,
              ),
            ],
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

  Future<void> _refreshVault() => _runVaultLoad(widget.vaultRepository.refresh);

  /// Pull-to-refresh syncs with the remote first; the Git operations refresh
  /// the entry list themselves once the remote state has landed.
  Future<void> _syncVault() {
    final git = _gitOperations;
    if (git == null) return _refreshVault();
    return _runVaultLoad(git.syncWithRemote);
  }

  Future<void> _runVaultLoad(Future<void> Function() operation) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      await operation();
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

// Keeps the search field docked below the app bar. The extent is supplied by
// the caller because it depends on the active text scale.
class _PinnedSearchHeader extends SliverPersistentHeaderDelegate {
  const _PinnedSearchHeader({
    required this.child,
    required this.extent,
    required this.background,
  });

  final Widget child;
  final double extent;
  final Color background;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: background,
      alignment: Alignment.topCenter,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSearchHeader oldDelegate) {
    return oldDelegate.extent != extent ||
        oldDelegate.background != background ||
        oldDelegate.child != child;
  }
}
