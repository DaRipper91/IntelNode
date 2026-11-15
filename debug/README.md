# Debugging IntelNode

Everything needed to diagnose a failed boot on a real phone. Run `capture.sh`, reproduce, and read the output
against the stage table below.

## Capture

```bash
adb connect 192.168.1.68:5555        # wireless debugging, or use USB
debug/capture.sh 192.168.1.68:5555   # writes debug/logs/<timestamp>/
```

`debug/logs/` is git-ignored. Raw logcat contains other apps' package names; trim it before sharing.
Use the **debug APK** from CI or a pre-release: `run-as` only works on debuggable builds.

## Where it can fail

| Stage | Healthy sign | Failure symptom |
|---|---|---|
| Install / chunk copy | `files/applib` link, 14 chunks copied | applib error screen |
| Extract | `containers/0_staging` grows for about 12 min, then `containers/0/etc` exists | "Installation Complete" with a thin rootfs |
| Boot | `proot` process, `start-arch.sh` runs | frozen on "Installation Complete" |
| X server | TCP 7897 open (`1ED9` in `/proc/net/tcp`) and `tmp/.X11-unix` | "X server did not start within 60 seconds" |
| Desktop | `xfce4-session` process | black or empty X window |

## Known facts

- Android 17 DP11 on the Pixel 10 Pro: the app writes almost nothing to logcat. Use `-b all` and `run-as`.
- Android may freeze the app when it is backgrounded during extraction. The `tar` child kept running in a captured session; keep the app open anyway.
- Arch ships `usr/share/X11/xkb` as an absolute symlink (`/usr/share/xkeyboard-config-2`) that dangles outside proot. Fixed in `3e661ca`.
- Arch's stock user `alarm` is uid 1000, so `tiny` is remapped to 1000 at extraction.

Full history of findings is in [`../AGENT_REPORT.md`](../AGENT_REPORT.md).
