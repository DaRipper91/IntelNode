// guest_shims.dart -- small replacements for programs that cannot work under proot.
//
// bubblewrap (bwrap) needs Linux namespaces, which proot cannot provide. glycin, the image
// decoder behind gdk-pixbuf2 >= 2.44, runs every loader inside bwrap, so without a stand-in no
// PNG or SVG can be decoded at all. libwnck then cannot load its default icon, asserts, and
// aborts the whole XFCE session ("Wnck:ERROR ... default_icon_at_size: assertion failed:
// (base)", proot "vpid 1: terminated with signal 6"). GLYCIN_DISABLE_SANDBOX is ignored by
// the glycin in Arch's packages (checked on a device), so the shim has to be in place.
import 'dart:io';

class GuestShims {
  static const String dirName = "guestshims";

  /// Mounted at /usr/local/bin/bwrap, which comes first on the guest's PATH.
  static const String bwrapMountTarget = "/usr/local/bin/bwrap";

  static String bwrapPath(String dataPath) => "$dataPath/$dirName/bwrap";

  static const String bwrapScript = r'''
#!/bin/bash
# bwrap stand-in for proot: bubblewrap needs Linux namespaces, which proot cannot provide, and
# glycin (the image decoder behind gdk-pixbuf2 >= 2.44) runs every loader inside it. This
# applies the options that matter (environment, working directory), ignores the sandbox
# setup (binds, namespaces, seccomp) and runs the command directly.
while [ $# -gt 0 ]; do
  case "$1" in
    --clearenv) for v in $(compgen -e); do unset "$v" 2>/dev/null; done; shift ;;
    --setenv) export "$2=$3"; shift 3 ;;
    --unsetenv) unset "$2"; shift 2 ;;
    --chdir) cd "$2" 2>/dev/null || true; shift 2 ;;
    --ro-bind|--ro-bind-try|--bind|--bind-try|--dev-bind|--dev-bind-try|--symlink|--file|--bind-data|--ro-bind-data|--chmod|--overlay-src)
      shift 3 ;;
    --overlay|--tmp-overlay|--ro-overlay) shift 4 ;;
    --seccomp|--add-seccomp-fd|--block-fd|--userns-block-fd|--info-fd|--json-status-fd|--sync-fd|--lock-file|--exec-label|--file-label|--hostname|--uid|--gid|--userns|--userns2|--pidns|--cap-add|--cap-drop|--args|--dir|--proc|--dev|--tmpfs|--mqueue|--remount-ro|--perms|--size)
      shift 2 ;;
    --) shift; break ;;
    --*) shift ;;
    *) break ;;
  esac
done
exec "$@"
''';

  /// Rewritten on every launch so containers installed by an older build gain it.
  static void writeTo(String dataPath) {
    final file = File(bwrapPath(dataPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(bwrapScript);
    Process.runSync("chmod", ["755", file.path]);
  }
}
