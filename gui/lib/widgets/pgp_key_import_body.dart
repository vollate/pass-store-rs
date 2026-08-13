import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/pgp_key_import.dart';
import '../services/key_repository.dart';
import '../services/path_picker_service.dart';
import '../services/pgp_import_service.dart';
import '../services/security_repository.dart';
import 'path_picker_row.dart';

/// Reusable PGP import body shared by Settings and Onboarding.
///
/// Owns the whole flow: source choice, inspection, the native file picker, the passphrase step for
/// protected private keys, the opt-in Keychain/KMS control, submission, and inline errors. Hosts
/// supply only [onCompleted], so Settings navigation stays out of Onboarding's step history.
///
/// Source (Text or File) is independent of key kind: inspection decides whether the material is
/// public or private, so a public key imports fine from a file.
class PgpKeyImportBody extends StatefulWidget {
  const PgpKeyImportBody({
    super.key,
    required this.keyRepository,
    required this.securityRepository,
    required this.pathPickerService,
    required this.onCompleted,
    this.initialDirectory,
    this.onCancel,
  });

  final KeyRepository keyRepository;
  final SecurityRepository securityRepository;
  final PathPickerService pathPickerService;

  /// Called after the key is imported and passphrase policy has been applied.
  final Future<void> Function(PgpImportCompletion completion) onCompleted;

  final String? initialDirectory;
  final VoidCallback? onCancel;

  @override
  State<PgpKeyImportBody> createState() => _PgpKeyImportBodyState();
}

class _PgpKeyImportBodyState extends State<PgpKeyImportBody> {
  final TextEditingController _keyText = TextEditingController();
  final TextEditingController _passphrase = TextEditingController();

  PgpImportSource _source = PgpImportSource.text;
  String? _selectedPath;
  PgpKeyInspection? _inspection;
  bool _isInspecting = false;
  bool _isSubmitting = false;
  bool _remember = false;
  String? _error;

  @override
  void dispose() {
    // Secrets must not outlive the form.
    _keyText.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  /// True once the protected-private passphrase step is showing.
  bool get _needsPassphrase => _inspection?.requiresPassphrase ?? false;

  bool get _hasMaterial => switch (_source) {
    PgpImportSource.text => _keyText.text.trim().isNotEmpty,
    PgpImportSource.file => _selectedPath != null,
  };

  bool get _canSubmit {
    if (_isSubmitting || _isInspecting || !_hasMaterial) {
      return false;
    }
    if (_needsPassphrase) {
      return _passphrase.text.isNotEmpty;
    }
    return true;
  }

  String get _initialDirectory =>
      widget.initialDirectory ?? defaultUserDirectory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedButton<PgpImportSource>(
          segments: <ButtonSegment<PgpImportSource>>[
            for (final source in PgpImportSource.values)
              ButtonSegment<PgpImportSource>(
                value: source,
                label: Text(source.label),
              ),
          ],
          selected: <PgpImportSource>{_source},
          onSelectionChanged: _isSubmitting ? null : _changeSource,
        ),
        const SizedBox(height: 12),
        if (_source == PgpImportSource.text)
          TextField(
            controller: _keyText,
            minLines: 4,
            maxLines: 8,
            enabled: !_isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Key text',
              helperText: 'Paste a PGP public or private key.',
            ),
            onChanged: (_) => _resetInspection(),
          )
        else
          PathPickerRow(
            title: 'Key file',
            path: _selectedPath ?? _initialDirectory,
            isSelected: _selectedPath != null,
            onPressed: _isSubmitting ? null : _chooseFile,
          ),
        if (_inspection != null) ...<Widget>[
          const SizedBox(height: 12),
          _InspectionSummary(inspection: _inspection!),
        ],
        if (_needsPassphrase) ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            controller: _passphrase,
            obscureText: true,
            enabled: !_isSubmitting,
            decoration: const InputDecoration(
              labelText: 'PGP passphrase',
              helperText: 'Required to unlock this private key.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _remember,
            onChanged:
                _isSubmitting
                    ? null
                    : (value) => setState(() => _remember = value),
            title: const Text('Remember in Keychain/KMS'),
            subtitle: const Text(
              'Off by default. The passphrase stays in memory for this session '
              'unless you enable this.',
            ),
          ),
        ],
        if (_isInspecting) ...<Widget>[
          const SizedBox(height: 12),
          const Row(
            children: <Widget>[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Inspecting key material...'),
            ],
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (widget.onCancel != null)
              TextButton(
                onPressed: _isSubmitting ? null : _cancel,
                child: const Text('Cancel'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: Text(
                _isSubmitting && _needsPassphrase
                    ? localizations.pgpPreparationInProgress
                    : _needsPassphrase
                    ? 'Unlock and import'
                    : 'Import',
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _changeSource(Set<PgpImportSource> selection) {
    final source = selection.first;
    if (source == _source) {
      return;
    }
    setState(() {
      _source = source;
      // Material from the previous source no longer applies.
      _keyText.clear();
      _selectedPath = null;
      _clearTransientState();
    });
  }

  /// Drops inspection state whenever the material changes, so a stale
  /// "protected" verdict cannot be applied to different bytes.
  void _resetInspection() {
    if (_inspection == null && _error == null && _passphrase.text.isEmpty) {
      setState(() {});
      return;
    }
    setState(_clearTransientState);
  }

  void _clearTransientState() {
    _inspection = null;
    _error = null;
    _remember = false;
    _passphrase.clear();
  }

  Future<void> _chooseFile() async {
    try {
      final path = await widget.pathPickerService.pickFile(
        initialDirectory: _initialDirectory,
      );
      if (path == null) {
        // Cancelling the picker leaves any earlier selection untouched.
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedPath = path;
        _clearTransientState();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _submit() async {
    // Inspect first so a protected key gets its passphrase step instead of a failed import.
    if (_inspection == null) {
      final inspection = await _inspect();
      if (inspection == null || !mounted) {
        return;
      }
      if (inspection.requiresPassphrase) {
        // Wait for the passphrase before importing.
        return;
      }
    }
    await _import();
  }

  Future<PgpKeyInspection?> _inspect() async {
    setState(() {
      _isInspecting = true;
      _error = null;
    });
    try {
      final inspection = switch (_source) {
        PgpImportSource.text => await widget.keyRepository.inspectPgpKeyText(
          _keyText.text,
        ),
        PgpImportSource.file => await widget.keyRepository.inspectPgpKeyFile(
          _selectedPath!,
        ),
      };
      if (!mounted) return null;
      setState(() {
        _inspection = inspection;
        _isInspecting = false;
      });
      return inspection;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _isInspecting = false;
        _error = _messageFor(error);
      });
      return null;
    }
  }

  Future<void> _import() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final completion = await importPgpKeyWithSecurity(
        keyRepository: widget.keyRepository,
        securityRepository: widget.securityRepository,
        source: _source,
        value: _source == PgpImportSource.text ? _keyText.text : _selectedPath!,
        passphrase: _needsPassphrase ? _passphrase.text : null,
        remember: _remember,
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        // Clear every secret before handing control back to the host.
        _keyText.clear();
        _passphrase.clear();
        _selectedPath = null;
        _inspection = null;
        _remember = false;
      });
      await widget.onCompleted(completion);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _messageFor(error);
        // Keep the passphrase step visible so the user can retry, but never keep the value.
        _passphrase.clear();
      });
    }
  }

  void _cancel() {
    setState(() {
      _keyText.clear();
      _selectedPath = null;
      _clearTransientState();
    });
    widget.onCancel?.call();
  }

  /// Import errors are already sanitized in Rust; this only reshapes the wording.
  String _messageFor(Object error) {
    if (error is PgpImportException) {
      final localizations = AppLocalizations.of(context);
      switch (error.kind) {
        case PgpImportFailureKind.passphraseRequired:
          return localizations.pgpPassphraseRequired;
        case PgpImportFailureKind.incorrectPassphrase:
          return localizations.pgpPassphraseIncorrect;
        case PgpImportFailureKind.unsupportedProtection:
          return localizations.pgpUnsupportedProtection;
        case PgpImportFailureKind.reprotectionFailed:
          return localizations.pgpReprotectionFailed;
        case PgpImportFailureKind.unsupportedMaterial:
        case PgpImportFailureKind.kindMismatch:
        case PgpImportFailureKind.backendError:
        case PgpImportFailureKind.unknown:
          return error.message;
      }
    }
    return error.toString();
  }
}

class _InspectionSummary extends StatelessWidget {
  const _InspectionSummary({required this.inspection});

  final PgpKeyInspection inspection;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          inspection.isPrivate ? Icons.key : Icons.vpn_key_outlined,
        ),
        title: Text(inspection.identity),
        subtitle: Text('${inspection.kind.label}\n${inspection.fingerprint}'),
        isThreeLine: true,
      ),
    );
  }
}
