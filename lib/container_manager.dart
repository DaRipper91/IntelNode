// container_manager.dart -- lists installed containers and deletes the ones the
// user picks. A container is identified by its position in `containersInfo`, and
// its files live in containers/<position>, so removing one renumbers the rest.
import 'dart:convert';

import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/workflow.dart';

class ContainerEntry {
  const ContainerEntry({
    required this.index,
    required this.name,
    this.blockedReason,
  });

  final int index;
  final String name;

  /// Why this container cannot be deleted, or null when it can.
  final String? blockedReason;
}

class DeletePlan {
  const DeletePlan({
    required this.remove,
    required this.survivors,
    required this.moves,
    required this.newDefault,
    required this.newCurrent,
  });

  final List<int> remove;

  /// Old indexes that stay, in order; a survivor's new index is its position here.
  final List<int> survivors;

  /// old index -> new index, only for survivors that change.
  final Map<int, int> moves;
  final int newDefault;
  final int newCurrent;
}

class ContainerManager {
  static const String runningReason = "In use (running now)";
  static const String defaultReason = "Default container";
  static const String olderReason = "Older than the running container";

  static String? blockedReason(
    int index, {
    required int current,
    required int defaultContainer,
  }) {
    if (index == current) return runningReason;
    if (index == defaultContainer) return defaultReason;
    // Renumbering below the running container would move its folder under it.
    if (index < current) return olderReason;
    return null;
  }

  /// What tapping [index] in the Containers tab does. `G.currentContainer` is the
  /// container that is running (its terminal, its folder, the delete guard and the
  /// renumbering all key on it), so a tap never moves it: it only chooses which
  /// container the next launch starts.
  static ({bool setDefault, String message}) tapOutcome(
    int index, {
    required String name,
    required int running,
    required int defaultContainer,
  }) {
    if (index == running) {
      return (setDefault: false, message: "$name is running now.");
    }
    if (index == defaultContainer) {
      return (
        setDefault: false,
        message: "$name already starts on the next launch.",
      );
    }
    return (
      setDefault: true,
      message: "$name will start on the next launch. Restart the app to switch.",
    );
  }

  static List<ContainerEntry> entries(
    List<String> infos, {
    required int current,
    required int defaultContainer,
  }) {
    return [
      for (var i = 0; i < infos.length; i++)
        ContainerEntry(
          index: i,
          name: _nameOf(infos[i]) ?? "Container $i",
          blockedReason: blockedReason(
            i,
            current: current,
            defaultContainer: defaultContainer,
          ),
        ),
    ];
  }

  static String? _nameOf(String json) {
    try {
      final name = (jsonDecode(json) as Map<String, dynamic>)["name"];
      return name is String && name.isNotEmpty ? name : null;
    } catch (_) {
      return null;
    }
  }

  static DeletePlan plan({
    required int count,
    required Set<int> remove,
    required int current,
    required int defaultContainer,
  }) {
    if (remove.isEmpty) throw StateError("Nothing selected to delete");
    for (final i in remove) {
      if (i < 0 || i >= count) {
        throw StateError("Container $i does not exist");
      }
      final reason = blockedReason(
        i,
        current: current,
        defaultContainer: defaultContainer,
      );
      if (reason != null) throw StateError("Container $i cannot be deleted: $reason");
    }
    final survivors = [
      for (var i = 0; i < count; i++)
        if (!remove.contains(i)) i,
    ];
    final moves = <int, int>{
      for (var n = 0; n < survivors.length; n++)
        if (survivors[n] != n) survivors[n]: n,
    };
    return DeletePlan(
      remove: remove.toList()..sort(),
      survivors: survivors,
      moves: moves,
      newDefault: survivors.indexOf(defaultContainer),
      newCurrent: survivors.indexOf(current),
    );
  }

  /// Shell script that removes the chosen container folders (and any leftover
  /// staging folder) and renumbers the survivors. Moves run in ascending order so
  /// a folder is never moved onto one that still exists.
  static String script(String dataPath, DeletePlan plan) {
    String dir(Object name) =>
        Util.escapeShellArgument("$dataPath/containers/$name");
    final b = StringBuffer("set -e\n");
    for (final i in plan.remove) {
      b.writeln(ContainerInstaller.rmrf("$dataPath/containers/$i"));
      b.writeln(ContainerInstaller.rmrf("$dataPath/containers/${i}_staging"));
    }
    final olds = plan.moves.keys.toList()..sort();
    for (final old in olds) {
      b.writeln("mv ${dir(old)} ${dir(plan.moves[old]!)}");
    }
    return b.toString();
  }

  /// Deletes [remove], then saves the renumbered list. Files go first: if the
  /// script fails, the saved list still matches what is left on disk as closely
  /// as it can.
  static Future<void> delete(
    Set<int> remove, {
    required Future<int> Function(String script) run,
  }) async {
    final infos = List<String>.from(
      Util.getGlobal("containersInfo") ?? <String>[],
    );
    final p = plan(
      count: infos.length,
      remove: remove,
      current: G.currentContainer,
      defaultContainer: G.settings.defaultContainer,
    );
    final code = await run(script(G.dataPath, p));
    if (code != 0) {
      throw Exception("Deleting containers failed (exit code $code)");
    }
    await G.prefs.setStringList("containersInfo", [
      for (final old in p.survivors) infos[old],
    ]);
    G.settings.defaultContainer = p.newDefault;
    G.currentContainer = p.newCurrent;
  }
}
