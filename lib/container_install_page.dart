// container_install_page.dart -- installs a new container in the same visible
// terminal the first run uses, so every step and any error can be read, scrolled
// and copied. Pops true once the container is registered.
import 'package:flutter/material.dart';

import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/l10n/app_localizations.dart';
import 'package:da_ripped_tiny_computer/setup_session.dart';
import 'package:da_ripped_tiny_computer/setup_terminal.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

enum _InstallState { running, failed, done }

class ContainerInstallPage extends StatefulWidget {
  const ContainerInstallPage({super.key, required this.plan});

  final InstallPlan plan;

  @override
  State<ContainerInstallPage> createState() => _ContainerInstallPageState();
}

class _ContainerInstallPageState extends State<ContainerInstallPage> {
  late SetupSession _session;
  _InstallState _state = _InstallState.running;

  @override
  void initState() {
    super.initState();
    _session = SetupSession(G.dataPath);
    _run();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final session = _session;
    try {
      await ContainerInstaller.install(
        widget.plan,
        run: session.run,
        log: session.log,
        onProgress: (m) => session.terminal.write(
          m.startsWith("Connection lost") ? "\r\n$m\r\n" : "\x1b[2K\r$m",
        ),
      );
      session.log("\r\n== ${widget.plan.containerName} is ready");
      _finish(_InstallState.done);
    } catch (e) {
      session.log("\r\n== Install failed: $e");
      _finish(_InstallState.failed);
    }
  }

  void _finish(_InstallState state) {
    if (mounted) setState(() => _state = state);
  }

  void _retry() {
    final old = _session;
    setState(() {
      _session = SetupSession(G.dataPath);
      _state = _InstallState.running;
    });
    old.dispose();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final running = _state == _InstallState.running;
    return PopScope(
      canPop: !running,
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_state) {
            _InstallState.running => l10n.installProgressTitle,
            _InstallState.failed => l10n.installFailedTitle,
            _InstallState.done => l10n.installCompleteTitle,
          }),
          automaticallyImplyLeading: !running,
        ),
        body: Column(
          children: [
            if (running) const LinearProgressIndicator(),
            Expanded(child: SetupTerminal(session: _session)),
            if (!running)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_state == _InstallState.failed)
                      TextButton(onPressed: _retry, child: const Text("Retry")),
                    FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pop(_state == _InstallState.done),
                      child: Text(l10n.close),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
