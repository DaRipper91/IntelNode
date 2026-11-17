// container_delete_dialog.dart -- pick installed containers from a checkbox list,
// confirm, and delete them.
import 'package:flutter/material.dart';

import 'package:da_ripped_tiny_computer/container_manager.dart';
import 'package:da_ripped_tiny_computer/l10n/app_localizations.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

Future<void> showDeleteContainersDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final entries = ContainerManager.entries(
    List<String>.from(Util.getGlobal("containersInfo") ?? <String>[]),
    current: G.currentContainer,
    defaultContainer: G.settings.defaultContainer,
  );

  final selected = await showDialog<Set<int>>(
    context: context,
    builder: (_) => PickContainersDialog(entries: entries),
  );
  if (selected == null || selected.isEmpty || !context.mounted) return;

  final names = entries
      .where((e) => selected.contains(e.index))
      .map((e) => e.name)
      .join(", ");
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.deleteContainers),
      content: Text("$names\n\n${l10n.deleteContainersConfirm}"),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(content: LinearProgressIndicator()),
    ),
  );
  Object? error;
  try {
    await ContainerManager.delete(selected, run: Util.execute);
  } catch (e) {
    error = e;
  }
  if (!context.mounted) return;
  Navigator.of(context).pop(); // dismiss the progress dialog
  messenger.showSnackBar(
    SnackBar(
      content: Text(error == null ? "${l10n.delete}: $names" : "$error"),
    ),
  );
}

@visibleForTesting
class PickContainersDialog extends StatefulWidget {
  const PickContainersDialog({super.key, required this.entries});

  final List<ContainerEntry> entries;

  @override
  State<PickContainersDialog> createState() => _PickContainersDialogState();
}

class _PickContainersDialogState extends State<PickContainersDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.deleteContainersTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.entries.isEmpty
            ? Text(l10n.deleteContainersNone)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final e in widget.entries)
                    CheckboxListTile(
                      value: _selected.contains(e.index),
                      onChanged: e.blockedReason == null
                          ? (on) => setState(() {
                                on == true
                                    ? _selected.add(e.index)
                                    : _selected.remove(e.index);
                              })
                          : null,
                      title: Text(e.name),
                      subtitle: Text(e.blockedReason ?? "Container ${e.index}"),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(Set<int>.of(_selected)),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}
