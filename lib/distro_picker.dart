// distro_picker.dart -- first stage of first run: before downloading any base
// image, let the user pick which distribution IntelNode should download and install.
import 'package:flutter/material.dart';

import 'package:da_ripped_tiny_computer/distros.dart';

class DistroPickerBody extends StatelessWidget {
  const DistroPickerBody({super.key, required this.onSelected});

  final ValueChanged<DistroSpec> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            "Select the Linux distribution to download and install for your container.",
          ),
        ),
        for (final d in Distros.all) _tile(context, d),
      ],
    );
  }

  Widget _tile(BuildContext context, DistroSpec d) {
    final verified = d.rootfs.verified;
    return Card(
      child: ListTile(
        key: ValueKey("distro-${d.id}"),
        enabled: verified,
        title: Text(d.displayName),
        subtitle: Text(
          verified
              ? d.description
              : "Preview, unverified source. ${d.description}",
        ),
        trailing: verified ? const Icon(Icons.chevron_right) : null,
        onTap: verified ? () => onSelected(d) : null,
      ),
    );
  }
}

/// Shows the distro picker as a non-dismissible dialog and returns the user's choice.
Future<DistroSpec> showDistroPicker(BuildContext context) async {
  final choice = await showDialog<DistroSpec>(
    context: context,
    barrierDismissible: false,
    // barrierDismissible does not stop the Android back button; without
    // PopScope it pops null and `choice!` throws after the base is installed.
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text("Choose Linux Distribution"),
        content: SizedBox(
          width: double.maxFinite,
          child: DistroPickerBody(
            onSelected: (d) => Navigator.of(dialogContext).pop(d),
          ),
        ),
      ),
    ),
  );
  return choice!;
}
