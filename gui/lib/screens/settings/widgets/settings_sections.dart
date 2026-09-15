part of '../settings_screen.dart';

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ParsSectionRow(
      leading: ParsSectionRowIcon(
        icon: icon,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Padding(
        padding: const EdgeInsets.only(right: ParsSpacing.sm),
        child: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
