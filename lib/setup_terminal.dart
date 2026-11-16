// setup_terminal.dart -- the interactive terminal shown while the system is
// first installed, with copy / paste so errors can be selected and shared.
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'package:da_ripped_tiny_computer/setup_session.dart';

class SetupTerminal extends StatelessWidget {
  const SetupTerminal({super.key, required this.session});

  final SetupSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(4),
            child: TerminalView(
              session.terminal,
              controller: session.controller,
              keyboardType: TextInputType.multiline,
              textStyle: const TerminalStyle(fontSize: 11),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text("Copy selection"),
              onPressed: () => _copy(context, session.copySelection,
                  "Long-press the terminal and drag to select text first"),
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy_all, size: 16),
              label: const Text("Copy all"),
              onPressed: () => _copy(context, session.copyAll, null),
            ),
            TextButton.icon(
              icon: const Icon(Icons.paste, size: 16),
              label: const Text("Paste"),
              onPressed: session.paste,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(
    BuildContext context,
    Future<void> Function() copy,
    String? emptyHint,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (emptyHint != null && (session.selectedText ?? "").isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(emptyHint)));
      return;
    }
    await copy();
    messenger.showSnackBar(const SnackBar(content: Text("Copied")));
  }
}
