// desktop_picker.dart -- second stage of first run: once the bare base system
// is installed and verified, the user picks what to put on top of it. Entries
// come from the DesktopEnvironments manifest, grouped by kind.
import 'package:flutter/material.dart';

import 'package:da_ripped_tiny_computer/desktop_environments.dart';

class DesktopPickerBody extends StatelessWidget {
  const DesktopPickerBody({super.key, required this.onSelected});

  final ValueChanged<DesktopEnvironmentSpec> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            "The base system is installed and working. Pick what to install "
            "on top of it. You can add more later with pacman.",
          ),
        ),
        _section(context, "Desktop Environments", DesktopKind.environment),
        _section(context, "Window Managers", DesktopKind.windowManager),
      ],
    );
  }

  Widget _section(BuildContext context, String title, DesktopKind kind) {
    final items =
        DesktopEnvironments.all.where((d) => d.kind == kind).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final d in items) _tile(context, d),
      ],
    );
  }

  Widget _tile(BuildContext context, DesktopEnvironmentSpec d) {
    final preview = d.tier == DesktopTier.experimental;
    return Card(
      child: ListTile(
        key: ValueKey("desktop-${d.id}"),
        enabled: !preview,
        title: Text(d.displayName),
        subtitle: Text(preview ? "Preview, not installable yet. ${d.description}" : d.description),
        trailing: preview ? null : const Icon(Icons.chevron_right),
        onTap: preview ? null : () => onSelected(d),
      ),
    );
  }
}

/// Shows the picker as a non-dismissible dialog and returns the user's choice.
Future<DesktopEnvironmentSpec> showDesktopPicker(BuildContext context) async {
  final choice = await showDialog<DesktopEnvironmentSpec>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Choose your desktop"),
      content: SizedBox(
        width: double.maxFinite,
        child: DesktopPickerBody(
          onSelected: (d) => Navigator.of(dialogContext).pop(d),
        ),
      ),
    ),
  );
  return choice!;
}
