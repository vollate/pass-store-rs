import 'package:flutter/material.dart';

import '../../services/security_repository.dart';
import '../../widgets/gesture_lock_input.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.securityRepository,
    required this.onUnlocked,
  });

  final SecurityRepository securityRepository;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 24),
              Text(
                'Unlock Pars',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Draw your gesture to open the local app session.'),
              const Spacer(),
              Center(
                child: GestureLockInput(
                  onCompleted: (pattern) => _unlock(context, pattern),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlock(BuildContext context, List<int> pattern) async {
    final isValid = await widget.securityRepository.verifyGesture(pattern);
    if (!context.mounted) {
      return;
    }
    if (!isValid) {
      setState(() => _error = 'Gesture did not match');
      return;
    }
    await widget.securityRepository.markUnlocked(DateTime.now());
    if (context.mounted) {
      widget.onUnlocked();
    }
  }
}
