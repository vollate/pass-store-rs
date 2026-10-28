import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';
import '../l10n/l10n.dart';
import '../services/security_repository.dart';
import '../services/ui_problem.dart';

class PasswordSetupPanel extends StatefulWidget {
  const PasswordSetupPanel({
    super.key,
    required this.securityRepository,
    required this.onSaved,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onSaved;

  @override
  State<PasswordSetupPanel> createState() => _PasswordSetupPanelState();
}

class _PasswordSetupPanelState extends State<PasswordSetupPanel> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  final FocusNode _confirmationFocus = FocusNode();
  String? _passwordError;
  String? _confirmationError;
  bool _isSaving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const Key('app-password-field'),
          controller: _password,
          autofocus: true,
          enabled: !_isSaving,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.password,
            helperText: l10n.passwordMinimumLength(
              PasswordVerifier.minimumLength,
            ),
            errorText: _passwordError,
          ),
          onSubmitted: (_) => _confirmationFocus.requestFocus(),
        ),
        const SizedBox(height: ParsSpacing.sm),
        TextField(
          key: const Key('app-password-confirmation-field'),
          controller: _confirmation,
          focusNode: _confirmationFocus,
          enabled: !_isSaving,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.confirmPassword,
            errorText: _confirmationError,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: ParsSpacing.md),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(l10n.savePassword, textAlign: TextAlign.center),
        ),
        if (_isSaving) ...<Widget>[
          const SizedBox(height: ParsSpacing.xs),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final l10n = context.l10n;
    final password = _password.text;
    if (password.runes.length < PasswordVerifier.minimumLength) {
      setState(() {
        _passwordError = l10n.passwordMinimumLength(
          PasswordVerifier.minimumLength,
        );
        _confirmationError = null;
      });
      return;
    }
    if (password != _confirmation.text) {
      _confirmation.clear();
      setState(() {
        _passwordError = null;
        _confirmationError = l10n.passwordsDidNotMatch;
      });
      _confirmationFocus.requestFocus();
      return;
    }
    setState(() {
      _isSaving = true;
      _passwordError = null;
      _confirmationError = null;
    });
    try {
      await widget.securityRepository.savePassword(password);
      await widget.securityRepository.markUnlocked(DateTime.now());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _passwordError = UiProblem.fromError(l10n, error).summary;
      });
      return;
    }
    _password.clear();
    _confirmation.clear();
    if (mounted) widget.onSaved();
  }
}
