import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/ui_problem.dart';

class FailureNotice extends StatelessWidget {
  const FailureNotice({super.key, required this.problem});

  final UiProblem problem;

  @override
  Widget build(BuildContext context) {
    final diagnostics = problem.diagnostics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          problem.summary,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (diagnostics != null)
          // The vault page keeps a PageStorageKey so the list can restore
          // its scroll offset, which is a double. ExpansionTile reads that
          // same slot as bool?. A nested PageStorage stops the walk, so the
          // tile and the text selection inside it no longer share the list's
          // slot.
          _SeparatePageStorage(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.l10n.details),
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(diagnostics),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SeparatePageStorage extends StatefulWidget {
  const _SeparatePageStorage({required this.child});

  final Widget child;

  @override
  State<_SeparatePageStorage> createState() => _SeparatePageStorageState();
}

class _SeparatePageStorageState extends State<_SeparatePageStorage> {
  final PageStorageBucket _bucket = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    return PageStorage(bucket: _bucket, child: widget.child);
  }
}
