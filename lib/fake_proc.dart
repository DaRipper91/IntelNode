import 'dart:io';

/// Placeholder /proc entries that proot bind-mounts over files Android denies
/// to app processes (SELinux), so guest tools read plausible data instead of
/// failing with EACCES. The upstream Tiny Computer rootfs ships the same set
/// under usr/local/etc/tmoe-linux/proot_proc; the Arch rootfs does not, so the
/// app generates them under $DATA_DIR/fakeproc and mounts them from there.
class FakeProc {
  static const String dirName = "fakeproc";

  /// Mounted over /proc/sys/kernel/cap_last_cap so libcap-style readers get an
  /// empty file (and fall back to probing) rather than an access error.
  static const String capLastCapSource = "/dev/null";
  static const String capLastCapTarget = "/proc/sys/kernel/cap_last_cap";

  /// Entries that are directories in /proc.
  static const List<String> directories = ["bus"];

  /// Entries with content. Everything else in [names] is created empty.
  static final Map<String, String> contents = {
    "loadavg": "0.12 0.07 0.02 2/165 765\n",
    "uptime": "284684.56 513853.46\n",
    "version":
        "Linux version 6.2.1 (proot@termux) (gcc (GCC) 12.2.1 20230201, GNU ld (GNU Binutils) 2.40) #1 SMP PREEMPT_DYNAMIC Wed, 01 Mar 2023 00:00:00 +0000\n",
    "stat": _stat(),
    "vmstat": _vmstat(),
    "filesystems":
        "nodev\tsysfs\nnodev\trootfs\nnodev\ttmpfs\nnodev\tproc\nnodev\tdevpts\n\text4\n\tvfat\n",
    "cgroups": "#subsys_name\thierarchy\tnum_cgroups\tenabled\n",
    "partitions": "major minor  #blocks  name\n",
  };

  /// Every /proc entry mounted from [dirName], in mount order.
  static const List<String> names = [
    "bus",
    "buddyinfo",
    "cgroups",
    "consoles",
    "crypto",
    "devices",
    "diskstats",
    "execdomains",
    "fb",
    "filesystems",
    "interrupts",
    "iomem",
    "ioports",
    "kallsyms",
    "keys",
    "key-users",
    "kpageflags",
    "loadavg",
    "locks",
    "misc",
    "modules",
    "pagetypeinfo",
    "partitions",
    "sched_debug",
    "softirqs",
    "stat",
    "timer_list",
    "uptime",
    "version",
    "vmallocinfo",
    "vmstat",
    "zoneinfo",
  ];

  /// Idempotently creates every entry under [dataPath]/[dirName]. Existing
  /// files are rewritten so a changed template reaches already-installed apps.
  static void writeTo(String dataPath) {
    final root = Directory("$dataPath/$dirName")..createSync(recursive: true);
    for (final name in names) {
      final path = "${root.path}/$name";
      if (directories.contains(name)) {
        Directory(path).createSync(recursive: true);
      } else {
        File(path).writeAsStringSync(contents[name] ?? "");
      }
    }
  }

  static String _stat() {
    final b = StringBuffer("cpu  1050008 127632 898432 43828767 37203 63 99244 0 0 0\n");
    for (var i = 0; i < 8; i++) {
      b.write("cpu$i 131251 15954 112304 5478595 4650 8 12405 0 0 0\n");
    }
    b.write("intr 0\nctxt 56829411\nbtime 1700000000\nprocesses 120031\n"
        "procs_running 1\nprocs_blocked 0\nsoftirq 0 0 0 0 0 0 0 0 0 0 0\n");
    return b.toString();
  }

  static String _vmstat() => [
        "nr_free_pages 1578303",
        "nr_zone_inactive_anon 579",
        "nr_zone_active_anon 21140",
        "nr_zone_inactive_file 253113",
        "nr_zone_active_file 105424",
        "nr_zone_unevictable 11",
        "nr_dirty 40",
        "nr_writeback 0",
        "pgpgin 4301927",
        "pgpgout 2012382",
        "pswpin 0",
        "pswpout 0",
      ].join("\n") +
      "\n";
}
