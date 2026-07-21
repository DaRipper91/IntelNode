// container_setup_page.dart -- distro + desktop environment picker wizard
// for building a new container on-device. Reads Distros.all and
// DesktopEnvironments.all so adding a manifest entry is enough to make it
// selectable here; no page logic needs to change.
import 'package:flutter/material.dart';

import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/l10n/app_localizations.dart';

class ContainerSetupPage extends StatefulWidget {
  const ContainerSetupPage({super.key});

  @override
  State<ContainerSetupPage> createState() => _ContainerSetupPageState();
}

class _ContainerSetupPageState extends State<ContainerSetupPage> {
  late DistroSpec _selectedDistro = Distros.all.first;
  late DesktopEnvironmentSpec _selectedDesktop = DesktopEnvironments.all.first;
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _containerName => _nameController.text.trim().isEmpty
      ? "${_selectedDistro.displayName} + ${_selectedDesktop.displayName}"
      : _nameController.text.trim();

  InstallPlan get _plan => ContainerInstaller.plan(
    distro: _selectedDistro,
    desktop: _selectedDesktop,
    containerName: _containerName,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final plan = _plan;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.newContainerPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l10n.containerNameLabel,
              hintText: _containerName,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(l10n.chooseBaseDistro, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          // Config-driven: iterates Distros.all, no hardcoded count/list.
          ...Distros.all.map(
            (distro) => RadioListTile<DistroSpec>(
              value: distro,
              groupValue: _selectedDistro,
              onChanged: (v) => setState(() => _selectedDistro = v!),
              title: Text(distro.displayName),
              subtitle: Text(
                distro.rootfs.verified
                    ? distro.description
                    : "${distro.description} (${l10n.unverifiedSourceWarning})",
              ),
            ),
          ),
          const Divider(height: 24),
          Text(
            l10n.chooseDesktopEnvironment,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.tierStable,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          // Config-driven: iterates DesktopEnvironments.forTier(stable).
          ...DesktopEnvironments.forTier(DesktopTier.stable).map(
            (de) => RadioListTile<DesktopEnvironmentSpec>(
              value: de,
              groupValue: _selectedDesktop,
              onChanged: (v) => setState(() => _selectedDesktop = v!),
              title: Text(de.displayName),
              subtitle: Text(de.description),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tierExperimental,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              l10n.experimentalWarning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          // Config-driven: iterates DesktopEnvironments.forTier(experimental).
          ...DesktopEnvironments.forTier(DesktopTier.experimental).map(
            (de) => RadioListTile<DesktopEnvironmentSpec>(
              value: de,
              groupValue: _selectedDesktop,
              onChanged: (v) => setState(() => _selectedDesktop = v!),
              title: Text(de.displayName),
              subtitle: Text(de.description),
            ),
          ),
          const SizedBox(height: 24),
          if (plan.blocked)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  plan.blockedReason!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _showPlanPreview(context, plan),
                child: Text(l10n.previewInstall),
              ),
              FilledButton(
                onPressed: plan.blocked ? null : () => _runInstall(context, plan),
                child: Text(l10n.installNow),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPlanPreview(BuildContext context, InstallPlan plan) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.installPlanTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (plan.blocked) ...[
                  Text(
                    "${l10n.installBlockedTitle}: ${plan.blockedReason}",
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final step in plan.steps) ...[
                  Text("• ${step.description}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (step.command.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 8),
                      child: Text(
                        step.command,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _runInstall(BuildContext context, InstallPlan plan) async {
    final l10n = AppLocalizations.of(context)!;
    final ValueNotifier<List<String>> progress = ValueNotifier([]);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.installProgressTitle),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: ValueListenableBuilder<List<String>>(
            valueListenable: progress,
            builder: (context, lines, child) =>
                ListView(children: lines.map((l) => Text(l)).toList()),
          ),
        ),
      ),
    );

    Object? error;
    try {
      await ContainerInstaller.execute(
        plan,
        onProgress: (line) => progress.value = [...progress.value, line],
      );
    } catch (e) {
      error = e;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress dialog

    final bool succeeded = error == null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          succeeded ? l10n.installCompleteTitle : l10n.installFailedTitle,
        ),
        content: Text(succeeded ? plan.containerName : error.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );

    if (succeeded && context.mounted) {
      Navigator.of(context).pop(); // leave the setup page, back to Settings
    }
  }
}
