import 'package:flutter/material.dart';

import '../app/pars_design_tokens.dart';

class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.children,
    this.emptyLabel,
  });

  final String title;
  final List<Widget> children;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (children.isEmpty && emptyLabel != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: Text(emptyLabel!),
                ),
              )
            else
              for (var index = 0; index < children.length; index++) ...<Widget>[
                children[index],
                if (index != children.length - 1)
                  const SizedBox(height: ParsSpacing.xs),
              ],
          ],
        ),
      ),
    );
  }
}
