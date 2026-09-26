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
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(context.l10n.details),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(diagnostics),
              ),
            ],
          ),
      ],
    );
  }
}
