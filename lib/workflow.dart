// workflow.dart  --  This file is part of tiny_computer.

// Copyright (C) 2023 Caten Hu

// Tiny Computer is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License,
// or any later version.

// Tiny Computer is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/.

// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:da_ripped_tiny_computer/theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:xterm/xterm.dart';
import 'package:flutter_pty/flutter_pty.dart';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:da_ripped_tiny_computer/boot_log.dart';
import 'package:da_ripped_tiny_computer/container_installer.dart';
import 'package:da_ripped_tiny_computer/desktop_environments.dart';
import 'package:da_ripped_tiny_computer/desktop_picker.dart';
import 'package:da_ripped_tiny_computer/distro_picker.dart';
import 'package:da_ripped_tiny_computer/distros.dart';
import 'package:da_ripped_tiny_computer/fake_proc.dart';
import 'package:da_ripped_tiny_computer/guest_shims.dart';
import 'package:da_ripped_tiny_computer/pty_shell.dart';
import 'package:da_ripped_tiny_computer/setup_session.dart';
import 'package:da_ripped_tiny_computer/l10n/app_localizations.dart';

import 'package:avnc_flutter/avnc_flutter.dart';
import 'package:x11_flutter/x11_flutter.dart';

import 'models.dart';
import 'settings.dart';

class DownloadHttpException implements Exception {
  final int status;
  final String url;
  DownloadHttpException(this.status, this.url);
  @override
  String toString() => "Download failed: HTTP $status for $url";
}

class Util {
  static Future<void> copyAsset(String src, String dst) async {
    await File(
      dst,
    ).writeAsBytes((await rootBundle.load(src)).buffer.asUint8List());
  }

  // rootBundle.load reads a whole asset into memory. The rootfs ships as ~14 chunks of
  // ~98 MiB, so copying them concurrently needs >1 GiB at once and gets the app killed
  // with no error. One at a time keeps the peak at a single chunk.
  static Future<void> copyAssetsSequentially(
    List<String> names,
    Future<void> Function(String name) copy,
  ) async {
    for (final String name in (List<String>.of(names)..sort())) {
      await copy(name);
    }
  }

  static Future<void> copyAsset2(String src, String dst) async {
    ByteData data = await rootBundle.load(src);
    await File(dst).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  static void createDirFromString(String dir) {
    Directory.fromRawPath(
      const Utf8Encoder().convert(dir),
    ).createSync(recursive: true);
  }

  static Future<int> execute(String str) async {
    Pty pty;
    try {
      pty = startShell();
    } catch (e) {
      debugPrint("Failed to start shell: $e");
      return -1;
    }

    pty.write(const Utf8Encoder().convert("$str\nexit \$?\n"));
    StreamSubscription<Uint8List>? sub;
    sub = pty.output.listen((data) {
      final text = const Utf8Decoder(allowMalformed: true).convert(data);
      if (text.isEmpty) return;

      // Always log to debug console for developers
      debugPrint("PTY Output: $text");

      if (G.showAdvancedLogs.value) {
        final newLines = text.split('\n').where((l) => l.isNotEmpty).toList();
        if (newLines.isEmpty) return;
        final updated = [...G.logLines.value, ...newLines];
        // Limit to 500 lines to avoid unbounded memory growth
        G.logLines.value = updated.length > 500
            ? updated.sublist(updated.length - 500)
            : updated;
      }
    });
    try {
      final code = await pty.exitCode;
      BootLog.event('shell finished with exit code $code');
      return code;
    } catch (e) {
      debugPrint("Error waiting for shell exit: $e");
      return -1;
    } finally {
      await sub.cancel();
    }
  }

  // Like execute(), but also returns the command's own stdout/stderr text so
  // callers can surface the real OS-level error instead of just an exit code.
  static Future<(int, String)> executeCapture(String str) async {
    Pty pty;
    try {
      pty = startShell();
    } catch (e) {
      return (-1, "Failed to start shell: $e");
    }

    final output = StringBuffer();
    pty.write(const Utf8Encoder().convert("$str\nexit \$?\n"));
    StreamSubscription<Uint8List>? sub;
    sub = pty.output.listen((data) {
      final text = const Utf8Decoder(allowMalformed: true).convert(data);
      if (text.isEmpty) return;
      debugPrint("PTY Output: $text");
      output.write(text);
    });
    try {
      final exitCode = await pty.exitCode;
      BootLog.event('shell finished with exit code $exitCode');
      return (exitCode, output.toString().trim());
    } catch (e) {
      return (-1, "Error waiting for shell exit: $e");
    } finally {
      await sub.cancel();
    }
  }

  // POSIX single-quote escape — safe to embed in any sh -c string.
  // Mirrors ShizukuHelper._escapeArg.
  static String escapeShellArgument(String arg) =>
      "'${arg.replaceAll("'", "'\\''")}'";

  // -n is required: on every launch after the first, applib already exists as a
  // symlink to the (read-only) APK lib dir, and plain `ln -sf` would follow it and
  // try to create a link inside that dir, failing with exit 1. -n also re-points the
  // link after a reinstall changes the /data/app/~~.../lib path.
  static String nativeLibLinkCommand(String libPath, String dataPath) =>
      "/system/bin/ln -sfn ${escapeShellArgument(libPath)} ${escapeShellArgument(dataPath)}/applib";

  // Arch Linux ARM ships a stock `alarm` user as uid/gid 1000, so useradd gave `tiny`
  // 1001, but the boot command runs as 1000 (proot --change-id=1000:1000). That made
  // the session the wrong user, and `su - tiny` then prompted for a password forever.
  // Swap the two so uid 1000 is `tiny`, matching the upstream rootfs.
  static String swapAlarmTinyIdsCommand(String rootDir) {
    final String q = escapeShellArgument(rootDir);
    return "sed -i -e 's/^alarm:\\([^:]*\\):1000:1000:/alarm:\\1:1001:1001:/' "
        "-e 's/^tiny:\\([^:]*\\):1001:1001:/tiny:\\1:1000:1000:/' $q/etc/passwd\n"
        "sed -i -e 's/^alarm:\\([^:]*\\):1000:/alarm:\\1:1001:/' "
        "-e 's/^tiny:\\([^:]*\\):1001:/tiny:\\1:1000:/' $q/etc/group";
  }

  // GNU tar has no built-in XZ decoder: `tar -J` forks an external `xz`, resolved
  // through PATH to the bin/xz -> busybox symlink. Upstream does exactly that and it
  // works, but decompressing with busybox's unxz and feeding plain tar avoids the
  // fork and the PATH dependency, and behaves the same on a ~1.3 GB stream.
  static String rootfsExtractCommand({String stagingDir = "containers/0_staging"}) =>
      "cat xa* | \$DATA_DIR/bin/busybox unxz | \$DATA_DIR/bin/tar x --delay-directory-restore --preserve-permissions -v -C $stagingDir";

  static final List<Process> _backgroundProcesses = [];

  // Fire-and-forget background process (for long-running daemons like
  // virgl_test_server and getifaddrs_bridge_server). Drains stdout and stderr
  // so background daemons never deadlock on a full pipe buffer.
  static void executeBackground(String str) {
    Process.start("/system/bin/sh", ["-c", str]).then((process) {
      _backgroundProcesses.add(process);
      process.stdout.drain<void>().catchError((_) {});
      process.stderr.drain<void>().catchError((_) {});
      process.exitCode.then((_) => _backgroundProcesses.remove(process));
    });
  }

  static void killAllProcesses() {
    for (var p in _backgroundProcesses) {
      p.kill();
    }
    _backgroundProcesses.clear();
    G.audioPty?.kill();
    Workflow.stopContainerForegroundService();
  }

  static void termWrite(String str) {
    G.termPtys[G.currentContainer]!.pty.write(
      const Utf8Encoder().convert("$str\n"),
    );
  }

  //所有key
  //int defaultContainer = 0: 默认启动第0个容器
  //int defaultAudioPort = 4718: 默认pulseaudio端口(为了避免和其它软件冲突改成4718了，原默认4713)
  //bool autoLaunchVnc = true: 是否自动启动图形界面并跳转 以前只支持VNC就这么起名了
  //String lastDate: 上次启动软件的日期，yyyy-MM-dd
  //bool isTerminalWriteEnabled = false
  //bool isTerminalCommandsEnabled = false
  //int termMaxLines = 4095 终端最大行数
  //double termFontScale = 1 终端字体大小
  //bool isStickyKey = true 终端ctrl, shift, alt键是否粘滞
  //String defaultFFmpegCommand 默认推流命令
  //String defaultVirglCommand 默认virgl参数
  //String defaultVirglOpt 默认virgl环境变量
  //bool reinstallBootstrap = false 下次启动是否重装引导包
  //bool getifaddrsBridge = false 下次启动是否桥接getifaddrs
  //bool virgl = false 下次启动是否启用virgl
  //bool wakelock = false 屏幕常亮
  //bool isHidpiEnabled = false 是否开启高分辨率
  //bool isJpEnabled = false 是否切换系统到日语
  //bool useAvnc = false 是否默认使用AVNC
  //bool avncResizeDesktop = true 是否默认AVNC按当前屏幕大小调整分辨率
  //double avncScaleFactor = -0.5 AVNC：在当前屏幕大小的基础上调整缩放的比例。范围-1~1，对应比例4^-1~4^1
  //String defaultHidpiOpt 默认HiDPI环境变量
  //? int bootstrapVersion: 启动包版本
  //String[] containersInfo: 所有容器信息(json)
  //{name, boot:"\$DATA_DIR/bin/proot ...", vnc:"startnovnc", vncUrl:"...", commands:[{name:"更新和升级", command:"pacman -Syu --noconfirm"},
  // bind:[{name:"U盘", src:"/storage/xxxx", dst:"/media/meow"}]...]}
  static dynamic getGlobal(String key) {
    try {
      return G.settings.getGlobal(key);
    } catch (e) {
      return null;
    }
  }

  static dynamic getCurrentProp(String key) {
    try {
      dynamic infoJson = getGlobal("containersInfo");
      if (infoJson == null || infoJson is! List || infoJson.isEmpty) {
        return _getDefaultProp(key);
      }
      String containerJsonStr = infoJson[G.currentContainer];
      Map<String, dynamic> jsonMap = jsonDecode(containerJsonStr);
      ContainerInfo info = ContainerInfo.fromJson(jsonMap);

      // Migrate legacy hardcoded VNC password for existing users
      if ((key == "vncUrl" || key == "vncUri" || key == "vncPassword") &&
              !info.hasProp("vncPassword") ||
          (info.hasProp("vncPassword") &&
              info.getProp("vncPassword").toString().isEmpty)) {
        // No stored password yet — generate one and persist it
        String newPass = generateRandomPassword();
        addCurrentProp("vncPassword", newPass);
        info.vncPassword = newPass;
        // Also migrate any existing URLs that have the old password
        if (info.hasProp("vncUrl") &&
            info.getProp("vncUrl").toString().isNotEmpty) {
          String updatedUrl = info.vncUrl.replaceAll(
            "password=12345678",
            "password=$newPass",
          );
          addCurrentProp("vncUrl", updatedUrl);
          info.vncUrl = updatedUrl;
        }
        if (info.hasProp("vncUri") &&
            info.getProp("vncUri").toString().isNotEmpty) {
          String updatedUri = info.vncUri.replaceAll(
            "VncPassword=12345678",
            "VncPassword=$newPass",
          );
          addCurrentProp("vncUri", updatedUri);
          info.vncUri = updatedUri;
        }
      }

      if (info.hasProp(key)) {
        dynamic val = info.getProp(key);
        if (val != null &&
            (val is! String || val.isNotEmpty) &&
            (val is! List || val.isNotEmpty)) {
          return val;
        }
      }

      return _getDefaultProp(key);
    } catch (_) {
      return _getDefaultProp(key);
    }
  }

  static dynamic _getDefaultProp(String key) {
    switch (key) {
      case "name":
        return "Arch Linux";
      case "boot":
        return Workflow.getBootCommand();
      case "vnc":
        return "start-desktop &";
      case "vncUrl":
        return "http://localhost:36082/vnc.html";
      case "vncUri":
        return "vnc://127.0.0.1:5904";
      case "commands":
        return [];
      default:
        return null;
    }
  }
  //用来设置name, boot, vnc, vncUrl等
  static Future<void> setCurrentProp(String key, dynamic value) async {
    List<String> containersInfo = List<String>.from(
      getGlobal("containersInfo"),
    );
    ContainerInfo info = ContainerInfo.fromJson(
      jsonDecode(containersInfo[G.currentContainer]),
    );

    info.setProp(key, value);

    containersInfo[G.currentContainer] = jsonEncode(info.toJson());
    await G.prefs.setStringList("containersInfo", containersInfo);
  }

  //用来添加不存在的key等
  static Future<void> addCurrentProp(String key, dynamic value) async {
    List<String> containersInfo = List<String>.from(
      getGlobal("containersInfo"),
    );
    ContainerInfo info = ContainerInfo.fromJson(
      jsonDecode(containersInfo[G.currentContainer]),
    );

    info.setProp(key, value);

    containersInfo[G.currentContainer] = jsonEncode(info.toJson());
    await G.prefs.setStringList("containersInfo", containersInfo);
  }

  //限定字符串在min和max之间, 给文本框的validator
  static String? validateBetween(
    String? value,
    int min,
    int max,
    Function opr,
  ) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(G.homePageStateContext)!.enterNumber;
    }
    int? parsedValue = int.tryParse(value);
    if (parsedValue == null) {
      return AppLocalizations.of(G.homePageStateContext)!.enterValidNumber;
    }
    if (parsedValue < min || parsedValue > max) {
      return AppLocalizations.of(
        G.homePageStateContext,
      )!
          .enterNumberBetween(min, max);
    }
    opr();
    return null;
  }

  static Future<bool> isXServerReady(
    String host,
    int port, {
    int timeoutSeconds = 5,
    Future<Socket> Function(dynamic host, int port, {Duration? timeout})?
        connectSocket,
  }) async {
    final connect = connectSocket ?? Socket.connect;
    try {
      final socket = await connect(
        host,
        port,
        timeout: Duration(seconds: timeoutSeconds),
      );
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  static String? xServerLaunchError;

  static Future<void> waitForXServer({
    int timeoutSeconds = 60,
    Future<bool> Function(String host, int port) isReadyCheck = isXServerReady,
  }) async {
    const host = '127.0.0.1';
    const port = 7897;
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    final waited = Stopwatch()..start();
    BootLog.event('waiting for X server on $host:$port (timeout ${timeoutSeconds}s)');

    while (DateTime.now().isBefore(deadline)) {
      if (await isReadyCheck(host, port)) {
        BootLog.event('X server ready after ${waited.elapsed.inSeconds}s');
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    BootLog.event(
      'X server not ready after ${timeoutSeconds}s'
      '${xServerLaunchError == null ? '' : ' (launch failed: $xServerLaunchError)'}',
    );
    throw TimeoutException(
      'X server did not start within $timeoutSeconds seconds'
      '${xServerLaunchError == null ? '' : ' (launch failed: $xServerLaunchError)'}',
    );
  }

  static String getl10nText(String key, BuildContext context) {
    switch (key) {
      case 'projectUrl':
        return AppLocalizations.of(context)!.projectUrl;
      case 'issueUrl':
        return AppLocalizations.of(context)!.issueUrl;
      case 'faqUrl':
        return AppLocalizations.of(context)!.faqUrl;
      case 'solutionUrl':
        return AppLocalizations.of(context)!.solutionUrl;
      case 'discussionUrl':
        return AppLocalizations.of(context)!.discussionUrl;
      default:
        return AppLocalizations.of(context)!.projectUrl;
    }
  }

  static String generateRandomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  // Streams [url] to [destPath], reporting whole-percent progress through
  // onProgress when the response declares a content length. Used by
  // ContainerInstaller to fetch on-device distro rootfs tarballs.
  /// Downloads [url] to [destPath], surviving dropped connections: a failed or
  /// truncated attempt is retried with backoff and continues from the bytes
  /// already on disk using an HTTP Range request (restarting from zero when the
  /// server ignores Range). 4xx responses are not retried.
  static Future<void> downloadFile(
    String url,
    String destPath, {
    required void Function(String) onProgress,
    http.Client? client,
    int maxAttempts = 8,
    Duration retryDelay = const Duration(seconds: 2),
    Duration stallTimeout = const Duration(seconds: 30),
  }) async {
    final c = client ?? http.Client();
    final file = File(destPath);
    int? total;
    int lastPct = -1;
    try {
      for (int attempt = 1;; attempt++) {
        final have = file.existsSync() ? file.lengthSync() : 0;
        try {
          final req = http.Request('GET', Uri.parse(url));
          if (have > 0) req.headers['Range'] = 'bytes=$have-';
          final resp = await c.send(req).timeout(stallTimeout);
          if (resp.statusCode == 416 && have > 0) {
            // Range Not Satisfiable: the file on disk is already complete (a
            // retry after a failure past the download) or longer than the
            // server's copy (stale). Content-Range: bytes */TOTAL says which.
            final m = RegExp(r'bytes \*/(\d+)')
                .firstMatch(resp.headers['content-range'] ?? '');
            final serverTotal = m == null ? null : int.parse(m.group(1)!);
            if (serverTotal == null || serverTotal == have) {
              return; // complete; the checksum step catches a bad file
            }
            file.deleteSync();
            continue;
          }
          if (resp.statusCode != 200 && resp.statusCode != 206) {
            throw DownloadHttpException(resp.statusCode, url);
          }
          final resumed = resp.statusCode == 206 && have > 0;
          final base = resumed ? have : 0;
          final len = resp.contentLength;
          if (len != null) total = base + len;
          final sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
          int received = base;
          try {
            await for (final chunk in resp.stream.timeout(stallTimeout)) {
              sink.add(chunk);
              received += chunk.length;
              if (total != null && total > 0) {
                final pct = (received / total * 100).floor();
                if (pct != lastPct) {
                  lastPct = pct;
                  onProgress(
                    "Downloading... $pct% (${received ~/ 1048576}/${total ~/ 1048576} MB)",
                  );
                }
              }
            }
          } finally {
            await sink.close();
          }
          if (total != null && received < total) {
            throw HttpException("connection closed at $received of $total bytes");
          }
          return;
        } catch (e) {
          final fatal = e is DownloadHttpException && e.status >= 400 && e.status < 500;
          if (fatal || attempt >= maxAttempts) rethrow;
          onProgress("Connection lost ($e); retrying in ${(retryDelay * attempt).inSeconds}s (attempt $attempt/$maxAttempts)...");
          await Future.delayed(retryDelay * attempt);
        }
      }
    } finally {
      if (client == null) c.close();
    }
  }
}

//来自xterms关于操作ctrl, shift, alt键的示例
//这个类应该只能有一个实例G.keyboard
class VirtualKeyboard extends TerminalInputHandler with ChangeNotifier {
  final TerminalInputHandler _inputHandler;

  VirtualKeyboard(this._inputHandler);

  bool _ctrl = false;

  bool get ctrl => _ctrl;

  set ctrl(bool value) {
    if (_ctrl != value) {
      _ctrl = value;
      notifyListeners();
    }
  }

  bool _shift = false;

  bool get shift => _shift;

  set shift(bool value) {
    if (_shift != value) {
      _shift = value;
      notifyListeners();
    }
  }

  bool _alt = false;

  bool get alt => _alt;

  set alt(bool value) {
    if (_alt != value) {
      _alt = value;
      notifyListeners();
    }
  }

  @override
  String? call(TerminalKeyboardEvent event) {
    final ret = _inputHandler.call(
      event.copyWith(
        ctrl: event.ctrl || _ctrl,
        shift: event.shift || _shift,
        alt: event.alt || _alt,
      ),
    );
    G.maybeCtrlJ = event.key.name == "keyJ"; //这个是为了稍后区分按键到底是Enter还是Ctrl+J
    if (!(Util.getGlobal("isStickyKey") as bool)) {
      G.keyboard.ctrl = false;
      G.keyboard.shift = false;
      G.keyboard.alt = false;
    }
    return ret;
  }
}

//一个结合terminal和pty的类
class TermPty {
  late final Terminal terminal;
  late final Pty pty;

  TermPty() {
    terminal = Terminal(
      inputHandler: G.keyboard,
      maxLines: Util.getGlobal("termMaxLines") as int,
    );
    pty = startShell(
      workingDirectory: G.dataPath,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );
    pty.output.cast<List<int>>().transform(const Utf8Decoder()).listen((text) {
      terminal.write(text);
      BootLog.feed('term', text);
    });
    pty.exitCode.then((code) {
      BootLog.flush('term');
      BootLog.event('terminal pty exited with exit code $code');
      terminal.write('the process exited with exit code $code');
      if (code == 0) {
        SystemChannels.platform.invokeMethod("SystemNavigator.pop");
      }
      //Signal 9 hint
      if (code == -9) {
        D.androidChannel.invokeMethod("launchSignal9Page", {});
      }
    });
    terminal.onOutput = (data) {
      if (!(Util.getGlobal("isTerminalWriteEnabled") as bool)) {
        return;
      }
      //由于对回车的处理似乎存在问题，所以拿出来单独处理
      data.split("").forEach((element) {
        if (element == "\n" && !G.maybeCtrlJ) {
          terminal.keyInput(TerminalKey.enter);
          return;
        }
        G.maybeCtrlJ = false;
        pty.write(const Utf8Encoder().convert(element));
      });
    };
    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };
  }
}

//default values
class D {
  //常用链接
  static const links = [
    {
      "name": "projectUrl",
      "value": "https://github.com/Cateners/tiny_computer",
    },
    {
      "name": "issueUrl",
      "value": "https://github.com/Cateners/tiny_computer/issues",
    },
    {
      "name": "faqUrl",
      "value": "https://gitee.com/caten/tc-hints/blob/master/pool/faq.md",
    },
    {
      "name": "solutionUrl",
      "value": "https://gitee.com/caten/tc-hints/blob/master/pool/solution.md",
    },
    {
      "name": "discussionUrl",
      "value": "https://github.com/Cateners/tiny_computer/discussions",
    },
  ];

  static String _debInstall(String urlExpr, String tmp, {String after = ""}) =>
      "wget $urlExpr -O /tmp/$tmp.deb && bsdtar -xOf /tmp/$tmp.deb 'data.tar*' | sudo bsdtar -xf - -C /$after; rm /tmp/$tmp.deb";

  //默认快捷指令
  static final commands = [
    {
      "name": "检查更新并升级",
      "command": "sudo pacman -Syu --noconfirm && sudo pacman -Sc --noconfirm",
    },
    {"name": "查看系统信息", "command": "neofetch -L && neofetch --off"},
    {"name": "清屏", "command": "clear"},
    {"name": "中断任务", "command": "\x03"},
    {"name": "安装图形处理软件Krita", "command": "sudo pacman -S --noconfirm krita"},
    {"name": "卸载Krita", "command": "sudo pacman -Rns --noconfirm krita"},
    {
      "name": "安装视频剪辑软件Kdenlive",
      "command": "sudo pacman -S --noconfirm kdenlive",
    },
    {"name": "卸载Kdenlive", "command": "sudo pacman -Rns --noconfirm kdenlive"},
    {"name": "安装科学计算软件Octave", "command": "sudo pacman -S --noconfirm octave"},
    {"name": "卸载Octave", "command": "sudo pacman -Rns --noconfirm octave"},
    {
      "name": "安装WPS",
      "command": _debInstall(
        "https://github.com/tiny-computer/third-party-archives/releases/download/archives/wps-office_11.1.0.11720_arm64.deb",
        "wps",
      ),
    },
    {
      "name": "卸载WPS",
      "command": "sudo rm -rf /opt/kingsoft/wps-office",
    },
    {
      "name": "安装CAJViewer",
      "command": _debInstall(
        "https://download.cnki.net/cajPackage/tongxinUOS/signed_cajviewer_9.5.0-25268_arm64.deb",
        "caj",
      ),
    },
    {
      "name": "卸载CAJViewer",
      "command": "sudo rm -rf /opt/apps/cajviewer",
    },
    {
      "name": "安装亿图图示",
      "command": _debInstall(
        "https://cc-download.wondershare.cc/business/prd/edrawmax_13.1.0-1_arm64_binner.deb",
        "edraw",
        after: """ && bash /home/tiny/.local/share/tiny/edraw/postinst""",
      ),
    },
    {
      "name": "卸载亿图图示",
      "command":
          "sudo rm -rf /opt/apps/edrawmax /home/tiny/.local/share/tiny/edraw",
    },
    {
      "name": "安装QQ",
      "command": _debInstall(
        """\$(curl -s https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js | grep -oP '"armDownloadUrl":{[^}]*"deb":"\\K[^"]+')""",
        "qq",
        after:
            """ && sudo sed -i 's#Exec=/opt/QQ/qq %U#Exec=/opt/QQ/qq --no-sandbox %U#g' /usr/share/applications/qq.desktop""",
      ),
    },
    {
      "name": "卸载QQ",
      "command": "sudo rm -rf /opt/QQ /usr/share/applications/qq.desktop",
    },
    {
      "name": "安装微信",
      "command": _debInstall(
        "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_arm64.deb",
        "wechat",
        after:
            """ && echo '安装完成。如果你使用微信只是为了传输文件，那么可以考虑使用支持SAF的文件管理器（如：质感文件），直接访问小小电脑所有文件。'""",
      ),
    },
    {
      "name": "卸载微信",
      "command":
          "sudo rm -rf /opt/wechat /usr/share/applications/wechat.desktop /usr/share/applications/com.tencent.wechatappex.desktop /usr/share/doc/wechat /usr/share/icons/hicolor/*/apps/wechat*.png",
    },
    {
      "name": "安装钉钉",
      "command": "sudo pacman -S --noconfirm --needed freeglut glu && " +
          _debInstall(
            "\$(curl -sw %{redirect_url} https://www.dingtalk.com/win/d/qd=linux_arm64)",
            "dingtalk",
            after:
                """ && sudo sed -i 's#\\./com.alibabainc.dingtalk#\\./com.alibabainc.dingtalk --no-sandbox#g' /opt/apps/com.alibabainc.dingtalk/files/Elevator.sh""",
          ),
    },
    {
      "name": "卸载钉钉",
      "command": "sudo rm -rf /opt/apps/com.alibabainc.dingtalk",
    },
    {
      "name": "启用回收站",
      "command": "sudo pacman -S --noconfirm gvfs && echo '安装完成, 重启软件即可使用回收站。'",
    },
    {"name": "清理包管理器缓存", "command": "sudo pacman -Scc --noconfirm"},
    {"name": "关机", "command": "stopvnc\nexit\nexit"},
    {"name": "???", "command": "timeout 8 cmatrix"},
  ];

  //默认快捷指令，英文版本
  static final commands4En = [
    {
      "name": "Update Packages",
      "command": "sudo pacman -Syu --noconfirm && sudo pacman -Sc --noconfirm",
    },
    {"name": "System Info", "command": "neofetch -L && neofetch --off"},
    {"name": "Clear", "command": "clear"},
    {"name": "Interrupt", "command": "\x03"},
    {
      "name": "Install Painting Program Krita",
      "command": "sudo pacman -S --noconfirm krita",
    },
    {
      "name": "Uninstall Krita",
      "command": "sudo pacman -Rns --noconfirm krita",
    },
    {
      "name": "Install KDE Non-Linear Video Editor",
      "command": "sudo pacman -S --noconfirm kdenlive",
    },
    {
      "name": "Uninstall Kdenlive",
      "command": "sudo pacman -Rns --noconfirm kdenlive",
    },
    {
      "name": "Install LibreOffice",
      "command": "sudo pacman -S --noconfirm libreoffice",
    },
    {
      "name": "Uninstall LibreOffice",
      "command": "sudo pacman -Rns --noconfirm libreoffice",
    },
    {
      "name": "Install WPS",
      "command": _debInstall(
        "https://github.com/tiny-computer/third-party-archives/releases/download/archives/wps-office_11.1.0.11720_arm64.deb",
        "wps",
      ),
    },
    {
      "name": "Uninstall WPS",
      "command": "sudo rm -rf /opt/kingsoft/wps-office",
    },
    {
      "name": "Install EdrawMax",
      "command": _debInstall(
        "https://cc-download.wondershare.cc/business/prd/edrawmax_13.1.0-1_arm64_binner.deb",
        "edraw",
        after:
            """ && bash /home/tiny/.local/share/tiny/edraw/postinst && sudo sed -i 's/<Language V="cn"\\/>/<Language V="en"\\/>/g' /opt/apps/edrawmax/config/settings.xml""",
      ),
    },
    {
      "name": "Uninstall EdrawMax",
      "command":
          "sudo rm -rf /opt/apps/edrawmax /home/tiny/.local/share/tiny/edraw",
    },
    {
      "name": "Enable Recycle Bin",
      "command":
          "sudo pacman -S --noconfirm gvfs && echo 'Restart the app to use Recycle Bin.'",
    },
    {"name": "Clean Package Cache", "command": "sudo pacman -Scc --noconfirm"},
    {"name": "Power Off", "command": "stopvnc\nexit\nexit"},
    {"name": "???", "command": "timeout 8 cmatrix"},
  ];

  //以下为不同包管理器的快捷指令集合
  /// Get commands appropriate for the given package manager
  static List<Map<String, dynamic>> getCommandsForPackageManager(
    String packageManager, {
    bool english = false,
  }) {
    final lowerPM = packageManager.toLowerCase();
    if (lowerPM.contains('pacman')) {
      return english ? commands4En : _commands4Pacman;
    } else if (lowerPM.contains('apt') ||
        lowerPM.contains('debian') ||
        lowerPM.contains('ubuntu') ||
        lowerPM.contains('trixie') ||
        lowerPM.contains('kali')) {
      return _commandsForApt;
    } else if (lowerPM.contains('dnf') || lowerPM.contains('fedora')) {
      return _commandsForDnf;
    } else if (lowerPM.contains('zypper') ||
        lowerPM.contains('opensuse') ||
        lowerPM.contains('leap') ||
        lowerPM.contains('tumbleweed')) {
      return _commandsForZypper;
    } else if (lowerPM.contains('apk') || lowerPM.contains('alpine')) {
      return _commandsForApk;
    } else if (lowerPM.contains('xbps') || lowerPM.contains('void')) {
      return _commandsForXbps;
    }
    // Default to pacman (Arch Linux)
    return _commands4Pacman;
  }

  /// Pacman-based commands (Arch Linux)
  static final List<Map<String, dynamic>> _commands4Pacman = [
    {
      "name": "更新和升级",
      "command": "pacman -Syu --noconfirm",
    },
    {"name": "查看系统信息", "command": "neofetch -L && neofetch --off"},
    {"name": "清屏", "command": "clear"},
    {"name": "中断任务", "command": "\x03"},
    {"name": "安装图形处理软件Krita", "command": "sudo pacman -S --noconfirm krita"},
    {"name": "卸载Krita", "command": "sudo pacman -Rns --noconfirm krita"},
    {
      "name": "安装视频剪辑软件Kdenlive",
      "command": "sudo pacman -S --noconfirm kdenlive",
    },
    {"name": "卸载Kdenlive", "command": "sudo pacman -Rns --noconfirm kdenlive"},
    {"name": "安装科学计算软件Octave", "command": "sudo pacman -S --noconfirm octave"},
    {"name": "卸载Octave", "command": "sudo pacman -Rns --noconfirm octave"},
    {
      "name": "安装WPS",
      "command": _debInstall(
        "https://github.com/tiny-computer/third-party-archives/releases/download/archives/wps-office_11.1.0.11720_arm64.deb",
        "wps",
      ),
    },
    {
      "name": "卸载WPS",
      "command": "sudo rm -rf /opt/kingsoft/wps-office",
    },
    {
      "name": "安装亿图图示",
      "command": _debInstall(
        "https://cc-download.wondershare.cc/business/prd/edrawmax_13.1.0-1_arm64_binner.deb",
        "edraw",
        after: """ && bash /home/tiny/.local/share/tiny/edraw/postinst""",
      ),
    },
    {
      "name": "卸载亿图图示",
      "command":
          "sudo rm -rf /opt/apps/edrawmax /home/tiny/.local/share/tiny/edraw",
    },
    {
      "name": "安装QQ",
      "command": _debInstall(
        """\$(curl -s https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js | grep -oP '"armDownloadUrl":{[^}]*"deb":"\\K[^"]+')""",
        "qq",
        after:
            """ && sudo sed -i 's#Exec=/opt/QQ/qq %U#Exec=/opt/QQ/qq --no-sandbox %U#g' /usr/share/applications/qq.desktop""",
      ),
    },
    {
      "name": "卸载QQ",
      "command": "sudo rm -rf /opt/QQ /usr/share/applications/qq.desktop",
    },
    {
      "name": "安装微信",
      "command": _debInstall(
        "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_arm64.deb",
        "wechat",
        after:
            """ && echo '安装完成。如果你使用微信只是为了传输文件，那么可以考虑使用支持SAF的文件管理器（如：质感文件），直接访问小小电脑所有文件。'""",
      ),
    },
    {
      "name": "卸载微信",
      "command":
          "sudo rm -rf /opt/wechat /usr/share/applications/wechat.desktop /usr/share/applications/com.tencent.wechatappex.desktop /usr/share/doc/wechat /usr/share/icons/hicolor/*/apps/wechat*.png",
    },
    {
      "name": "安装钉钉",
      "command": "sudo pacman -S --noconfirm --needed freeglut glu && " +
          _debInstall(
            "\$(curl -sw %{redirect_url} https://www.dingtalk.com/win/d/qd=linux_arm64)",
            "dingtalk",
            after:
                """ && sudo sed -i 's#\\./com.alibabainc.dingtalk#\\./com.alibabainc.dingtalk --no-sandbox#g' /opt/apps/com.alibabainc.dingtalk/files/Elevator.sh""",
          ),
    },
    {
      "name": "卸载钉钉",
      "command": "sudo rm -rf /opt/apps/com.alibabainc.dingtalk",
    },
    {"name": "安装gvfs", "command": "sudo pacman -S --noconfirm gvfs"},
    {"name": "清理包管理器缓存", "command": "sudo pacman -Scc --noconfirm"},
  ];

  /// APT-based commands (Debian/Ubuntu)
  static final List<Map<String, dynamic>> _commandsForApt = [
    {
      "name": "更新和升级",
      "command": "apt update -y && apt upgrade -y",
    },
    {"name": "查看系统信息", "command": "neofetch -L && neofetch --off"},
    {"name": "清屏", "command": "clear"},
    {"name": "中断任务", "command": "\x03"},
    {"name": "安装图形处理软件Krita", "command": "sudo apt install -y krita"},
    {"name": "卸载Krita", "command": "sudo apt remove -y krita"},
    {
      "name": "安装视频剪辑软件Kdenlive",
      "command": "sudo apt install -y kdenlive",
    },
    {"name": "卸载Kdenlive", "command": "sudo apt remove -y kdenlive"},
    {"name": "安装科学计算软件Octave", "command": "sudo apt install -y octave"},
    {"name": "卸载Octave", "command": "sudo apt remove -y octave"},
    {
      "name": "安装WPS",
      "command": r"""cat << 'EOF' | sh && sudo apt-get install -y /tmp/wps.deb
wget https://github.com/tiny-computer/third-party-archives/releases/download/archives/wps-office_11.1.0.11720_arm64.deb -O /tmp/wps.deb
EOF
rm /tmp/wps.deb""",
    },
    {"name": "卸载WPS", "command": "sudo apt remove -y wps-office"},
    {
      "name": "安装亿图图示",
      "command":
          "wget https://cc-download.wondershare.cc/business/prd/edrawmax_13.1.0-1_arm64_binner.deb -O /tmp/edraw.deb && sudo apt -y install /tmp/edraw.deb; rm /tmp/edraw.deb",
    },
    {"name": "卸载亿图图示", "command": "sudo apt -y remove --autoremove edrawmax"},
    {
      "name": "安装QQ",
      "command":
          """wget \$(curl -s https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js | grep -oP '"armDownloadUrl":{[^}]*"deb":"\\K[^"]+') -O /tmp/qq.deb && sudo apt -y install /tmp/qq.deb; rm /tmp/qq.deb""",
    },
    {
      "name": "卸载QQ",
      "command": "sudo apt -y remove -y linuxqq",
    },
    {
      "name": "安装微信",
      "command":
          """wget \$(curl -s https://cdn-go.cn/weixin.qq.com/wiki/image/zh_cn/logo_900_2.png) -O /tmp/wechat.deb && sudo apt -y install /tmp/wechat.deb; rm /tmp/wechat.deb""",
    },
    {
      "name": "卸载微信",
      "command": "sudo apt -y remove -y wechat",
    },
    {
      "name": "安装钉钉",
      "command":
          """wget \$(curl -sw %{redirect_url} https://www.dingtalk.com/win/d/qd=linux_arm64) -O /tmp/dingtalk.deb && sudo apt -y install /tmp/dingtalk.deb libglut3.12 libglu1-mesa; rm /tmp/dingtalk.deb""",
    },
    {
      "name": "卸载钉钉",
      "command": "sudo apt -y remove -y com.alibabainc.dingtalk",
    },
    {"name": "安装gvfs", "command": "sudo apt install -y gvfs"},
    {"name": "清理包管理器缓存", "command": "sudo apt -y clean"},
  ];

  /// DNF-based commands (Fedora)
  static final List<Map<String, dynamic>> _commandsForDnf = [
    {
      "name": "更新和升级",
      "command": "sudo dnf -y update",
    },
    {"name": "查看系统信息", "command": "neofetch -L && neofetch --off"},
    {"name": "清屏", "command": "clear"},
    {"name": "中断任务", "command": "\x03"},
    {"name": "安装图形处理软件Krita", "command": "sudo dnf -y install krita"},
    {"name": "卸载Krita", "command": "sudo dnf -y remove krita"},
    {
      "name": "安装视频剪辑软件Kdenlive",
      "command": "sudo dnf -y install kdenlive",
    },
    {"name": "卸载Kdenlive", "command": "sudo dnf -y remove kdenlive"},
    {"name": "安装科学计算软件Octave", "command": "sudo dnf -y install octave"},
    {"name": "卸载Octave", "command": "sudo dnf -y remove octave"},
    {
      "name": "安装WPS",
      "command": "sudo dnf -y install bsdtar && " +
          _debInstall(
            "https://github.com/tiny-computer/third-party-archives/releases/download/archives/wps-office_11.1.0.11720_arm64.deb",
            "wps",
          ),
    },
    {
      "name": "卸载WPS",
      "command": "sudo rm -rf /opt/kingsoft/wps-office",
    },
    {
      "name": "安装亿图图示",
      "command": "sudo dnf -y install bsdtar && " +
          _debInstall(
            "https://cc-download.wondershare.cc/business/prd/edrawmax_13.1.0-1_arm64_binner.deb",
            "edraw",
            after: """ && bash /home/tiny/.local/share/tiny/edraw/postinst""",
          ),
    },
    {
      "name": "卸载亿图图示",
      "command":
          "sudo rm -rf /opt/apps/edrawmax /home/tiny/.local/share/tiny/edraw",
    },
    {
      "name": "安装QQ",
      "command":
          """wget \$(curl -s https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js | grep -oP '"armDownloadUrl":{[^}]*"rpm":"\\K[^"]+') -O /tmp/qq.rpm && sudo dnf -y --nogpgcheck install /tmp/qq.rpm && sudo sed -i 's#Exec=/opt/QQ/qq %U#Exec=/opt/QQ/qq --no-sandbox %U#g' /usr/share/applications/qq.desktop; rm /tmp/qq.rpm""",
    },
    {
      "name": "卸载QQ",
      "command": "sudo dnf -y remove linuxqq",
    },
    {
      "name": "安装微信",
      "command": "sudo dnf -y install bsdtar && " +
          _debInstall(
            "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_arm64.deb",
            "wechat",
          ),
    },
    {
      "name": "卸载微信",
      "command":
          "sudo rm -rf /opt/wechat /usr/share/applications/wechat.desktop /usr/share/applications/com.tencent.wechatappex.desktop /usr/share/doc/wechat /usr/share/icons/hicolor/*/apps/wechat*.png",
    },
    {
      "name": "安装钉钉",
      "command":
          "sudo dnf -y install bsdtar && sudo dnf -y install freeglut mesa-libGLU && " +
              _debInstall(
                "\$(curl -sw %{redirect_url} https://www.dingtalk.com/win/d/qd=linux_arm64)",
                "dingtalk",
                after:
                    """ && sudo sed -i 's#\\./com.alibabainc.dingtalk#\\./com.alibabainc.dingtalk --no-sandbox#g' /opt/apps/com.alibabainc.dingtalk/files/Elevator.sh""",
              ),
    },
    {
      "name": "卸载钉钉",
      "command": "sudo rm -rf /opt/apps/com.alibabainc.dingtalk",
    },
    {"name": "安装gvfs", "command": "sudo dnf -y install gvfs"},
    {"name": "清理包管理器缓存", "command": "sudo dnf -y clean all"},
  ];

  /// Zypper-based commands (OpenSUSE)
  static final List<Map<String, dynamic>> _commandsForZypper = [
    {
      "name": "更新和升级",
      "command":
          "sudo zypper --non-interactive refresh && sudo zypper --non-interactive update",
    },
    {"name": "查看系统信息", "command": "neofetch -L && neofetch --off"},
    {"name": "清屏", "command": "clear"},
    {"name": "中断任务", "command": "\x03"},
    {
      "name": "安装图形处理软件Krita",
      "command": "sudo zypper --non-interactive install krita"
    },
    {
      "name": "卸载Krita",
      "command": "sudo zypper --non-interactive remove krita"
    },
    {
      "name": "安装视频剪辑软件Kdenlive",
      "command": "sudo zypper --non-interactive install kdenlive",
    },
    {
      "name": "卸载Kdenlive",
      "command": "sudo zypper --non-interactive remove kdenlive"
    },
    {
      "name": "安装科学计算软件Octave",
      "command": "sudo zypper --non-interactive install octave"
    },
    {
      "name": "卸载Octave",
      "command": "sudo zypper --non-interactive remove octave"
    },
    {
      "name": "安装WPS",
      "command": "sudo zypper --non-interactive install bsdtar && " +
          _debInstall(
            "https://github.com/tiny-computer/third-party-archives/releases/download/archives/wps-office_11.1.0.11720_arm64.deb",
            "wps",
          ),
    },
    {
      "name": "卸载WPS",
      "command": "sudo rm -rf /opt/kingsoft/wps-office",
    },
    {
      "name": "安装亿图图示",
      "command": "sudo zypper --non-interactive install bsdtar && " +
          _debInstall(
            "https://cc-download.wondershare.cc/business/prd/edrawmax_13.1.0-1_arm64_binner.deb",
            "edraw",
            after: """ && bash /home/tiny/.local/share/tiny/edraw/postinst""",
          ),
    },
    {
      "name": "卸载亿图图示",
      "command":
          "sudo rm -rf /opt/apps/edrawmax /home/tiny/.local/share/tiny/edraw",
    },
    {
      "name": "安装QQ",
      "command":
          """wget \$(curl -s https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js | grep -oP '"armDownloadUrl":{[^}]*"rpm":"\\K[^"]+') -O /tmp/qq.rpm && sudo zypper --non-interactive --no-gpg-checks install /tmp/qq.rpm && sudo sed -i 's#Exec=/opt/QQ/qq %U#Exec=/opt/QQ/qq --no-sandbox %U#g' /usr/share/applications/qq.desktop; rm /tmp/qq.rpm""",
    },
    {
      "name": "卸载QQ",
      "command": "sudo zypper --non-interactive remove linuxqq",
    },
    {
      "name": "安装微信",
      "command": "sudo zypper --non-interactive install bsdtar && " +
          _debInstall(
            "https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_arm64.deb",
            "wechat",
          ),
    },
    {
      "name": "卸载微信",
      "command":
          "sudo rm -rf /opt/wechat /usr/share/applications/wechat.desktop /usr/share/applications/com.tencent.wechatappex.desktop /usr/share/doc/wechat /usr/share/icons/hicolor/*/apps/wechat*.png",
    },
    {
      "name": "安装钉钉",
      "command":
          "sudo zypper --non-interactive install bsdtar && sudo zypper --non-interactive install freeglut libGLU1 && " +
              _debInstall(
                "\$(curl -sw %{redirect_url} https://www.dingtalk.com/win/d/qd=linux_arm64)",
                "dingtalk",
                after:
                    """ && sudo sed -i 's#\\./com.alibabainc.dingtalk#\\./com.alibabainc.dingtalk --no-sandbox#g' /opt/apps/com.alibabainc.dingtalk/files/Elevator.sh""",
              ),
    },
    {
      "name": "卸载钉钉",
      "command": "sudo rm -rf /opt/apps/com.alibabainc.dingtalk",
    },
    {"name": "安装gvfs", "command": "sudo zypper --non-interactive install gvfs"},
    {"name": "清理包管理器缓存", "command": "sudo zypper clean -a"},
  ];

  /// APK-based commands (Alpine Linux)
  static final List<Map<String, dynamic>> _commandsForApk = [
    {
      "name": "更新和升级",
      "command": "sudo apk update && sudo apk upgrade",
    },
    {"name": "查看系统信息", "command": "uname -a"},
    {"name": "清屏", "command": "clear"},
    {"name": "中断任务", "command": "\x03"},
    {
      "name": "安装Neofetch",
      "command": "sudo apk add --no-cache neofetch",
    },
    {
      "name": "清理缓存",
      "command": "sudo rm -rf /var/cache/apk/*",
    },
  ];

  /// XBPS-based commands (Void Linux)
  static final List<Map<String, dynamic>> _commandsForXbps = [
    {
      "name": "更新和升级",
      "command": "sudo xbps-install -Syu",
    },
    {"name": "查看系统信息", "command": "uname -a"},
    {"name": "清屏", "command": "clear"},
    {"name": "中断任务", "command": "\x03"},
    {
      "name": "安装Neofetch",
      "command": "sudo xbps-install -y neofetch",
    },
    {
      "name": "清理缓存",
      "command": "sudo xbps-remove -O && sudo xbps-remove -o",
    },
  ];

  static const wineCommands = [
    {"name": "Wine配置", "command": "winecfg"},
    {
      "name": "修复方块字",
      "command":
          "regedit Z:\\\\home\\\\tiny\\\\.local\\\\share\\\\tiny\\\\extra\\\\chn_fonts.reg && wine reg delete \"HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes\" /va /f",
    },
    {
      "name": "开始菜单文件夹",
      "command":
          "wine explorer \"C:\\\\ProgramData\\\\Microsoft\\\\Windows\\\\Start Menu\\\\Programs\"",
    },
    {
      "name": "开启DXVK",
      "command":
          """WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d8 /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d9 /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d10core /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d11 /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v dxgi /d native /f >/dev/null 2>&1""",
    },
    {
      "name": "关闭DXVK",
      "command":
          """WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d8 /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d9 /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d10core /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d11 /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v dxgi /d builtin /f >/dev/null 2>&1""",
    },
    {"name": "我的电脑", "command": "wine explorer"},
    {"name": "记事本", "command": "notepad"},
    {"name": "扫雷", "command": "winemine"},
    {"name": "注册表", "command": "regedit"},
    {"name": "控制面板", "command": "wine control"},
    {"name": "文件管理器", "command": "winefile"},
    {"name": "任务管理器", "command": "wine taskmgr"},
    {"name": "IE浏览器", "command": "wine iexplore"},
    {"name": "强制关闭Wine", "command": "wineserver -k"},
  ];

  //默认wine快捷指令，英文版本
  static const wineCommands4En = [
    {"name": "Wine Configuration", "command": "winecfg"},
    {
      "name": "Fix CJK Characters",
      "command":
          "regedit Z:\\\\home\\\\tiny\\\\.local\\\\share\\\\tiny\\\\extra\\\\chn_fonts.reg && wine reg delete \"HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes\" /va /f",
    },
    {
      "name": "Start Menu Dir",
      "command":
          "wine explorer \"C:\\\\ProgramData\\\\Microsoft\\\\Windows\\\\Start Menu\\\\Programs\"",
    },
    {
      "name": "Enable DXVK",
      "command":
          """WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d8 /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d9 /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d10core /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d11 /d native /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=n,d3d9=n,d3d10core=n,d3d11=n,dxgi=n" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v dxgi /d native /f >/dev/null 2>&1""",
    },
    {
      "name": "Disable DXVK",
      "command":
          """WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d8 /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d9 /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d10core /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v d3d11 /d builtin /f >/dev/null 2>&1
WINEDLLOVERRIDES="d3d8=b,d3d9=b,d3d10core=b,d3d11=b,dxgi=b" wine reg add 'HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides' /v dxgi /d builtin /f >/dev/null 2>&1""",
    },
    {"name": "Explorer", "command": "wine explorer"},
    {"name": "Notepad", "command": "notepad"},
    {"name": "Minesweeper", "command": "winemine"},
    {"name": "Regedit", "command": "regedit"},
    {"name": "Control Panel", "command": "wine control"},
    {"name": "File Manager", "command": "winefile"},
    {"name": "Task Manager", "command": "wine taskmgr"},
    {"name": "Internet Explorer", "command": "wine iexplore"},
    {"name": "Kill Wine Process", "command": "wineserver -k"},
  ];

  //默认小键盘
  static const termCommands = [
    {"name": "Esc", "key": TerminalKey.escape},
    {"name": "Tab", "key": TerminalKey.tab},
    {"name": "↑", "key": TerminalKey.arrowUp},
    {"name": "↓", "key": TerminalKey.arrowDown},
    {"name": "←", "key": TerminalKey.arrowLeft},
    {"name": "→", "key": TerminalKey.arrowRight},
    {"name": "Del", "key": TerminalKey.delete},
    {"name": "PgUp", "key": TerminalKey.pageUp},
    {"name": "PgDn", "key": TerminalKey.pageDown},
    {"name": "Home", "key": TerminalKey.home},
    {"name": "End", "key": TerminalKey.end},
    {"name": "F1", "key": TerminalKey.f1},
    {"name": "F2", "key": TerminalKey.f2},
    {"name": "F3", "key": TerminalKey.f3},
    {"name": "F4", "key": TerminalKey.f4},
    {"name": "F5", "key": TerminalKey.f5},
    {"name": "F6", "key": TerminalKey.f6},
    {"name": "F7", "key": TerminalKey.f7},
    {"name": "F8", "key": TerminalKey.f8},
    {"name": "F9", "key": TerminalKey.f9},
    {"name": "F10", "key": TerminalKey.f10},
    {"name": "F11", "key": TerminalKey.f11},
    {"name": "F12", "key": TerminalKey.f12},
  ];

  static ButtonStyle get commandButtonStyle => AppTheme.commandButtonStyle;
  static ButtonStyle get controlButtonStyle => AppTheme.controlButtonStyle;

  static const MethodChannel androidChannel = MethodChannel("android");
}

// Global variables
class G {
  // Not `late final`: initData() runs again when the Retry button restarts startup, and a
  // second assignment to a late final field throws LateInitializationError.
  static String dataPath = "";
  static Pty? audioPty;
  static late WebViewController controller;
  static late BuildContext homePageStateContext;
  static late int currentContainer; //目前运行第几个容器
  static late Map<int, TermPty> termPtys; //为容器<int>存放TermPty数据
  static late VirtualKeyboard keyboard; //存储ctrl, shift, alt状态
  static bool maybeCtrlJ = false; //为了区分按下的ctrl+J和enter而准备的变量
  static ValueNotifier<double> termFontScale = ValueNotifier(
    1,
  ); //终端字体大小，存储为G.prefs的termFontScale
  static bool isStreaming = false;
  //static int? virglPid;
  static ValueNotifier<int> pageIndex = ValueNotifier(0); //主界面索引
  static ValueNotifier<bool> terminalPageChange = ValueNotifier(
    true,
  ); //更改值，用于刷新小键盘
  static ValueNotifier<bool> bootTextChange = ValueNotifier(
    true,
  ); //更改值，用于刷新启动命令
  static ValueNotifier<String> updateText = ValueNotifier("IntelNode"); // Loading screen caption
  static ValueNotifier<bool> showAdvancedLogs =
      ValueNotifier(false); // Whether to show the log console
  static ValueNotifier<List<String>> logLines =
      ValueNotifier([]); // Captured PTY output lines
  // Visible install terminal; non-null from the start of first-run setup until it completes.
  static ValueNotifier<SetupSession?> setupSession = ValueNotifier(null);
  // Set when startup fails; the loading screen then offers a Retry button.
  static ValueNotifier<bool> startupFailed = ValueNotifier(false);
  static Future<void> Function()? retryStartup;

  static bool wasAvncEnabled = false;
  static bool wasX11Enabled = false;

  static late SharedPreferences prefs;
  static late GlobalSettings settings;
}

class Workflow {
  static String getBootCommand({String extraMount = "", String extraOpt = ""}) {
    final builder = ProotCommandBuilder();
    // No PROOT_NO_SECCOMP=1: with it proot ptrace-traces every syscall, and on a
    // real Android 17 phone every chdir/getcwd inside the container then failed with
    // ENOSYS ("cd: /: Function not implemented"), so dbus-daemon and the desktop could
    // not start. The provisioning proot runs never set it and worked on the same device.
    builder.addFlag("-H");
    builder.addFlag("--change-id=1000:1000");
    builder.setPwd("/home/tiny");
    builder.setRootfs("\$CONTAINER_DIR");

    // System mounts
    builder.addMount("/system");
    builder.addMount("/apex");
    builder.addMount("/sys");
    builder.addMount("/data");
    builder.addMount("/storage");
    builder.addMount("/proc");
    builder.addMount("/dev");
    // /tmp stays the container's own tmp: the in-app X server (launchXServer)
    // creates its socket in containers/N/tmp, so binding another directory over
    // /tmp (e.g. Termux's) would hide it and reintroduce a Termux dependency.
    builder.addMount("\$CONTAINER_DIR/tmp", target: "/dev/shm");
    builder.addMount("/dev/urandom", target: "/dev/random");

    // Device node simulation
    builder.addMount("/proc/self/fd", target: "/dev/fd");
    builder.addMount("/proc/self/fd/0", target: "/dev/stdin");
    builder.addMount("/proc/self/fd/1", target: "/dev/stdout");
    builder.addMount("/proc/self/fd/2", target: "/dev/stderr");
    builder.addMount("/dev/null", target: "/dev/tty0");

    // Android denies apps several /proc files; mirror upstream's placeholders.
    // bubblewrap cannot run under proot; see lib/guest_shims.dart.
    builder.addMount("\$DATA_DIR/${GuestShims.dirName}/bwrap",
        target: GuestShims.bwrapMountTarget);
    builder.addMount(FakeProc.capLastCapSource, target: FakeProc.capLastCapTarget);
    for (final name in FakeProc.names) {
      builder.addMount("\$DATA_DIR/${FakeProc.dirName}/$name", target: "/proc/$name");
    }

    // Storage mounts
    builder.addMount("/storage/self/primary", target: "/media/sd");
    builder.addMount("\$DATA_DIR/share", target: "/home/tiny/Public");
    builder.addMount("\$DATA_DIR/tiny", target: "/home/tiny/.local/share/tiny");

    // Font mounts
    builder.addMount("/storage/self/primary/Fonts",
        target: "/usr/share/fonts/wpsm");
    builder.addMount("/storage/self/primary/AppFiles/Fonts",
        target: "/usr/share/fonts/yozom");
    builder.addMount("/system/fonts", target: "/usr/share/fonts/androidm");

    // User directory mounts
    builder.addMount("/storage/self/primary/Pictures",
        target: "/home/tiny/Pictures");
    builder.addMount("/storage/self/primary/Music", target: "/home/tiny/Music");
    builder.addMount("/storage/self/primary/Movies",
        target: "/home/tiny/Videos");
    builder.addMount("/storage/self/primary/Download",
        target: "/home/tiny/Downloads");
    builder.addMount("/storage/self/primary/DCIM", target: "/home/tiny/Photos");
    builder.addMount("/storage/self/primary/Documents",
        target: "/home/tiny/Documents");

    builder.addFlag("--kill-on-exit");
    builder.addFlag("--sysvipc");
    builder.addFlag("-L");
    builder.addFlag("--link2symlink");

    // Append the extraMount string (already formatted as flags)
    String cmd = builder.build();
    if (extraMount.isNotEmpty) cmd += " $extraMount";

    cmd +=
        " /usr/bin/env -i HOME=/home/tiny USER=tiny LANG=en_US.UTF-8 TERM=xterm-256color PATH=/home/tiny/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin PULSE_SERVER=tcp:127.0.0.1:4718 DISPLAY=:4 $extraOpt /bin/bash /usr/local/bin/start-arch.sh";

    return cmd;
  }

  static Future<bool> grantPermissions() async {
    // Permission.storage (READ/WRITE_EXTERNAL_STORAGE) is a no-op on Android
    // 13+ for apps targeting API 33+ (this app targets 36) — scoped storage
    // replaced it with MANAGE_EXTERNAL_STORAGE ("All files access"), which is
    // the permission that actually gates real filesystem access here. Check
    // both and accept whichever one is actually meaningful on this OS version,
    // since Permission.storage is still the real mechanism on older devices.
    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted || storageStatus.isLimited) return true;
    final manageStatus = await Permission.manageExternalStorage.request();
    return manageStatus.isGranted;
  }

  static Future<void> setupBootstrap() async {
    // Shared data directory
    Util.createDirFromString("${G.dataPath}/share");
    // Binary directory
    Util.createDirFromString("${G.dataPath}/bin");
    // Library directory
    Util.createDirFromString("${G.dataPath}/lib");
    // Shm mount directory
    Util.createDirFromString("${G.dataPath}/tmp");
    // PRoot temporary directory
    Util.createDirFromString("${G.dataPath}/proot_tmp");
    // PulseAudio temporary directory
    Util.createDirFromString("${G.dataPath}/pulseaudio_tmp");

    await Util.copyAsset("assets/assets.zip", "${G.dataPath}/assets.zip");
    // patch.tar.gz contains the 'tiny' folder with customization scripts
    await Util.copyAsset("assets/patch.tar.gz", "${G.dataPath}/patch.tar.gz");

    // Ensure the scripts directory exists
    Util.createDirFromString("${G.dataPath}/tiny/extra");
    await Util.copyAsset(
      "assets/scripts/start-arch.sh",
      "${G.dataPath}/tiny/extra/start-arch.sh",
    );
    await Util.copyAsset(
      "assets/scripts/start-desktop",
      "${G.dataPath}/tiny/extra/start-desktop",
    );
    await Util.copyAsset(
      "assets/scripts/to_vault",
      "${G.dataPath}/tiny/extra/to_vault",
    );

    final List<String> binSymlinks = [
      'busybox',
      'sh',
      'cat',
      'xz',
      'gzip',
      'proot',
      'tar',
      'virgl_test_server',
      'getifaddrs_bridge_server',
      'pulseaudio'
    ];
    final List<String> libSymlinks = [
      'libacl.so',
      'libandroid-selinux.so',
      'libattr.so',
      'libbusybox.so.1.37.0',
      'libiconv.so',
      'libpcre2-8.so',
      'libtalloc.so.2',
      'libvirglrenderer.so',
      'libepoxy.so',
      'loader32',
      'loader'
    ];

    StringBuffer script = StringBuffer();
    script.writeln("set -e");
    script.writeln("export DATA_DIR=${G.dataPath}");
    script.writeln("export LD_LIBRARY_PATH=\$DATA_DIR/lib");
    script.writeln("cd \$DATA_DIR");

    for (var bin in binSymlinks) {
      script.writeln("""
if [ -f applib/libexec_$bin.so ]; then
    /system/bin/ln -sf ../applib/libexec_$bin.so \$DATA_DIR/bin/$bin
elif [ -f applib/lib$bin.so ]; then
    /system/bin/ln -sf ../applib/lib$bin.so \$DATA_DIR/bin/$bin
elif [ "$bin" = "sh" ] || [ "$bin" = "cat" ] || [ "$bin" = "xz" ] || [ "$bin" = "gzip" ] || [ "$bin" = "tar" ]; then
    /system/bin/ln -sf busybox \$DATA_DIR/bin/$bin
else
    echo "Error: Binary $bin not found in applib (tried libexec_$bin.so and lib$bin.so)" >&2
    exit 127
fi""");
    }
    for (var lib in libSymlinks) {
      if (lib == 'loader32') {
        script.writeln(
          "if [ -f applib/libproot-loader32.so ]; then /system/bin/ln -sf ../applib/libproot-loader32.so \$DATA_DIR/lib/loader32; fi",
        );
      } else if (lib == 'loader') {
        script.writeln(
          "if [ -f applib/libproot-loader.so ]; then /system/bin/ln -sf ../applib/libproot-loader.so \$DATA_DIR/lib/loader; fi",
        );
      } else if (lib == 'libtalloc.so.2') {
        // libexec_proot.so declares NEEDED libtalloc.so.2, but Android's
        // packager ships the file as libtalloc.so (SONAME libtalloc.so.2).
        // Stage it under the NEEDED name or proot cannot load at all.
        script.writeln(
          "if [ -f applib/libtalloc.so.2 ]; then /system/bin/ln -sf ../applib/libtalloc.so.2 \$DATA_DIR/lib/libtalloc.so.2; elif [ -f applib/libtalloc.so ]; then /system/bin/ln -sf ../applib/libtalloc.so \$DATA_DIR/lib/libtalloc.so.2; fi",
        );
      } else if (lib == 'libbusybox.so.1.37.0') {
        // The shipped file is named libbusybox.so (no version suffix), but
        // libexec_busybox.so's ELF NEEDED entry hardcodes the versioned name
        // — stage it under that exact name so the dynamic linker resolves it
        // via LD_LIBRARY_PATH instead of the broken Termux-only RUNPATH.
        script.writeln(
          "if [ -f applib/libbusybox.so.1.37.0 ]; then /system/bin/ln -sf ../applib/libbusybox.so.1.37.0 \$DATA_DIR/lib/libbusybox.so.1.37.0; elif [ -f applib/libbusybox.so ]; then /system/bin/ln -sf ../applib/libbusybox.so \$DATA_DIR/lib/libbusybox.so.1.37.0; fi",
        );
      } else {
        script.writeln(
          "if [ -f applib/$lib ]; then /system/bin/ln -sf ../applib/$lib \$DATA_DIR/lib/$lib; fi",
        );
      }
    }

    script.writeln("""
# Verify busybox exists before using it
if [ ! -x \$DATA_DIR/bin/busybox ]; then
    echo "Error: busybox binary is missing or not executable" >&2
    exit 127
fi

\$DATA_DIR/bin/busybox unzip -o assets.zip

# Verify tar exists before using it
if [ ! -x \$DATA_DIR/bin/tar ]; then
    echo "Error: tar binary is missing or not executable" >&2
    exit 127
fi

\$DATA_DIR/bin/tar zxf patch.tar.gz

/system/bin/chmod -R +x bin/* || true
/system/bin/chmod -R +x libexec/proot/* 2>/dev/null || true
/system/bin/chmod 1777 tmp

\$DATA_DIR/bin/busybox rm -rf assets.zip patch.tar.gz
""");

    final int exitCode = await Util.execute(script.toString());
    if (exitCode != 0) {
      throw Exception("Bootstrap setup failed with exit code $exitCode");
    }
  }

  // Actions to perform on first launch
  static Future<void> initForFirstTime({
    DistroSpec? selectedDistro,
    DesktopEnvironmentSpec? selectedDesktop,
  }) async {
    // Clear log lines before starting so the log view shows only current session.
    G.logLines.value = [];
    // A full pacman install is thousands of lines: give it its own file and bigger caps,
    // restored once the first run is done (workflow() re-attaches boot.log).
    BootLog.maxLines = 40000;
    BootLog.maxFileBytes = 8 * 1024 * 1024;
    BootLog.attachFile("${G.dataPath}/install.log");
    BootLog.event('first run: installing the base system');
    // Initialize bootstrap binaries and scripts
    G.updateText.value = AppLocalizations.of(
      G.homePageStateContext,
    )!
        .installingBootPackage;
    await setupBootstrap();

    final distro =
        selectedDistro ?? await showDistroPicker(G.homePageStateContext);

    // Stage 1: bare base system, downloaded and verified. Stage 2 (the desktop) is
    // picked by the user once the base is known to work. Everything runs in the
    // visible setup terminal so failures can be read and copied.
    G.setupSession.value?.dispose();
    final session = SetupSession(G.dataPath);
    G.setupSession.value = session;
    final String base = "Installing ${distro.displayName} base system...";
    G.updateText.value = base;
    await ContainerInstaller.installBase(
      distro: distro,
      containerIndex: 0,
      run: session.run,
      log: session.log,
      onProgress: (m) => session.terminal.write(
        m.startsWith("Connection lost") ? "\r\n$m\r\n" : "\x1b[2K\r$m",
      ),
    );

    G.updateText.value = "Base system ready";
    final desktop = selectedDesktop ??
        await showDesktopPicker(G.homePageStateContext, distro: distro);
    if (desktop == null) {
      G.updateText.value = "Desktop selection cancelled";
      return;
    }
    G.updateText.value = "Installing ${desktop.displayName}...";
    await ContainerInstaller.installDesktop(
      distro: distro,
      desktop: desktop,
      containerIndex: 0,
      run: session.run,
      log: session.log,
    );
    G.settings.selectedDE = desktop.id;

    // Initialize container metadata
    String initialVncPassword = Util.generateRandomPassword();
    final containerName = distro.displayName;
    final String packageManager = distro.packageManager.name;
    final List<Map<String, dynamic>> initialCommands =
        D.getCommandsForPackageManager(
      packageManager,
      english:
          Localizations.localeOf(G.homePageStateContext).languageCode != 'zh',
    );
    final existing = List<String>.from(G.settings.containersInfo);
    existing.add('''{
  "name":"$containerName",
  "packageManager":"$packageManager",
  "boot":${jsonEncode(Workflow.getBootCommand())},
  "vnc":"start-desktop &",
  "vncPassword":"$initialVncPassword",
  "vncUrl":"http://localhost:36082/vnc.html?host=localhost&port=36082&autoconnect=true&resize=remote&password=$initialVncPassword",
  "vncUri":"vnc://127.0.0.1:5904?VncPassword=$initialVncPassword&SecurityType=2",
  "commands":${jsonEncode(initialCommands)}
}''');
    await G.prefs.setStringList("containersInfo", existing);
    G.settings.defaultContainer = existing.length - 1;

    G.updateText.value = AppLocalizations.of(
      G.homePageStateContext,
    )!
        .installationComplete;
    G.setupSession.value = null;
    session.dispose();
    BootLog.event('first run finished');
    BootLog.maxLines = 3000;
    BootLog.maxFileBytes = 512 * 1024;
  }

  static Future<void> initData() async {
    G.dataPath = (await getApplicationSupportDirectory()).path;
    G.termPtys = {};
    G.keyboard = VirtualKeyboard(defaultInputHandler);
    G.prefs = await SharedPreferences.getInstance();

    // Set currentContainer early so getCurrentProp is safe during first-time init.
    G.currentContainer = G.prefs.getInt("defaultContainer") ?? 0;

    G.settings = GlobalSettings();
    await G.settings.init(G.prefs);

    // Sync the showAdvancedLogs notifier so the LoadingPage reacts immediately.
    G.showAdvancedLogs.value = G.settings.advancedLogs;

    // Link native libraries to app-private data directory. This must exist
    // before setupBootstrap() runs, or every binary lookup there fails with a
    // generic, misleading "exit code 127" that hides this actual cause.
    Util.createDirFromString(G.dataPath);
    final String libPath = await D.androidChannel.invokeMethod("getNativeLibraryPath", {}) as String;
    final (linkExitCode, linkOutput) = await Util.executeCapture(
      Util.nativeLibLinkCommand(libPath, G.dataPath),
    );
    if (linkExitCode != 0) {
      throw Exception(
        "Failed to link native library directory ($libPath) into ${G.dataPath}/applib "
        "(exit code $linkExitCode): ${linkOutput.isEmpty ? '(no output)' : linkOutput}. "
        "Bootstrap cannot proceed without it.",
      );
    }

    // Mount sources for getBootCommand; rewritten every launch so containers
    // installed by an older build gain them without a reinstall.
    FakeProc.writeTo(G.dataPath);
    GuestShims.writeTo(G.dataPath);

    // Perform first-time setup if needed
    if (!G.prefs.containsKey("defaultContainer")) {
      await _runFirstTimeSetup();
    }

    G.currentContainer = G.settings.defaultContainer;

    // Check if bootstrap needs re-installation
    if (Util.getGlobal("reinstallBootstrap")) {
      G.updateText.value = AppLocalizations.of(
        G.homePageStateContext,
      )!
          .reinstallingBootPackage;
      await setupBootstrap();
      G.prefs.setBool("reinstallBootstrap", false);
    }

    // Refresh this app-managed script so APK updates also fix existing containers.
    await refreshDesktopStartupScript(G.dataPath);

    // Initialize display backends
    if (Util.getGlobal("useX11")) {
      G.wasX11Enabled = true;
      Workflow.launchXServer();
    } else if (Util.getGlobal("useAvnc")) {
      G.wasAvncEnabled = true;
    }

    G.termFontScale.value = Util.getGlobal("termFontScale") as double;
    G.controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    // Enable screen wakelock
    WakelockPlus.toggle(enable: Util.getGlobal("wakelock"));
  }

  // Internal helper for first-time configuration
  static Future<void> _runFirstTimeSetup() async {
    await initForFirstTime();

    if (Localizations.localeOf(G.homePageStateContext).languageCode != 'zh') {
      G.settings.isTerminalWriteEnabled = true;
      G.settings.isTerminalCommandsEnabled = true;
      G.settings.isStickyKey = false;
      G.settings.wakelock = true;
    }

    G.settings.getifaddrsBridge =
        (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 31;
  }

  static Future<void> initTerminalForCurrent() async {
    if (!G.termPtys.containsKey(G.currentContainer)) {
      G.termPtys[G.currentContainer] = TermPty();
    }
  }

  static Future<void> setupAudio() async {
    G.audioPty?.kill();
    G.audioPty = startShell();
    G.audioPty!.write(
      const Utf8Encoder().convert("""
export DATA_DIR=${G.dataPath}
export PATH=\$DATA_DIR/bin:\$PATH
export LD_LIBRARY_PATH=\$DATA_DIR/lib
\$DATA_DIR/bin/busybox sed "s/4713/${Util.getGlobal("defaultAudioPort") as int}/g" \$DATA_DIR/bin/pulseaudio.conf > \$DATA_DIR/bin/pulseaudio.conf.tmp
rm -rf \$DATA_DIR/pulseaudio_tmp/*
TMPDIR=\$DATA_DIR/pulseaudio_tmp HOME=\$DATA_DIR/pulseaudio_tmp XDG_CONFIG_HOME=\$DATA_DIR/pulseaudio_tmp LD_LIBRARY_PATH=\$DATA_DIR/bin:\$LD_LIBRARY_PATH \$DATA_DIR/bin/pulseaudio -F \$DATA_DIR/bin/pulseaudio.conf.tmp
exit
"""),
    );
    await G.audioPty?.exitCode;
  }

  static String virglServerArguments(String options, String containerPath) {
    final placeholder = RegExp(
      r'\$\{CONTAINER_DIR\}|\$CONTAINER_DIR(?![A-Za-z0-9_])',
    );
    // Substitute before quoting, but after tokenizing so spaces in the path
    // remain inside one argument. No other shell expansion is supported.
    return options
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s.replaceAllMapped(placeholder, (_) => containerPath))
        .map(Util.escapeShellArgument)
        .join(' ');
  }

  static Future<void> refreshDesktopStartupScript(String dataPath) async {
    final extra = Directory("$dataPath/tiny/extra");
    await extra.create(recursive: true);
    await Util.copyAsset(
      "assets/scripts/start-desktop",
      "${extra.path}/start-desktop",
    );
  }

  static Future<void> launchCurrentContainer() async {
    String extraMount = "";
    String extraOpt = "";

    // Configure Network Bridge
    // The preload library is not shipped in every build; a missing LD_PRELOAD target
    // makes Android's own binaries (getprop) fail to link, so only enable the bridge
    // when the library is really there.
    final bool bridgeLibPresent = File(
      "${G.dataPath}/tiny/extra/getifaddrs_bridge_client_lib.so",
    ).existsSync();
    if (Util.getGlobal("getifaddrsBridge") && bridgeLibPresent) {
      Util.executeBackground(
        "${Util.escapeShellArgument('${G.dataPath}/bin/getifaddrs_bridge_server')} ${Util.escapeShellArgument('${G.dataPath}/containers/${G.currentContainer}/tmp/.getifaddrs-bridge')}",
      );
      extraOpt +=
          "LD_PRELOAD=/home/tiny/.local/share/tiny/extra/getifaddrs_bridge_client_lib.so ";
    }

    // Configure Display Scaling
    if (Util.getGlobal("isHidpiEnabled")) {
      extraOpt += "${Util.getGlobal("defaultHidpiOpt")} ";
    }

    // Configure Hardware Acceleration (VirGL)
    if (Util.getGlobal("virgl")) {
      final arguments = virglServerArguments(
        Util.getGlobal("defaultVirglCommand").toString(),
        "${G.dataPath}/containers/${G.currentContainer}",
      );
      Util.executeBackground(
        """
export DATA_DIR=${Util.escapeShellArgument(G.dataPath)}
export PATH=\$DATA_DIR/bin:\$PATH
export LD_LIBRARY_PATH=\$DATA_DIR/lib
export CONTAINER_DIR=\$DATA_DIR/containers/${G.currentContainer}
\$DATA_DIR/bin/virgl_test_server $arguments""",
      );
      extraOpt += "${Util.getGlobal("defaultVirglOpt")} ";
    }

    // Configure Adreno Turnip Drivers
    if (Util.getGlobal("turnip")) {
      extraOpt += "${Util.getGlobal("defaultTurnipOpt")} ";
      if (!(Util.getGlobal("dri3"))) {
        extraOpt += "MESA_VK_WSI_DEBUG=sw ";
      }
    }

    if (Util.getGlobal("isJpEnabled")) {
      extraOpt += "LANG=ja_JP.UTF-8 ";
    }

    // Standard system mounts and scripts
    extraMount += "--mount=\$DATA_DIR/tiny/font:/usr/share/fonts/tiny ";
    extraMount += "--mount=\$DATA_DIR/tiny/extra/start-arch.sh:/usr/local/bin/start-arch.sh ";
    extraMount += "--mount=\$DATA_DIR/tiny/extra/start-desktop:/usr/local/bin/start-desktop ";
    extraMount += "--mount=\$DATA_DIR/tiny/extra/cmatrix:/home/tiny/.local/bin/cmatrix ";
    extraMount += "--mount=\$DATA_DIR/tiny/extra/tiny_virtual_mic:/home/tiny/.local/bin/tiny_virtual_mic ";
    extraMount += "--mount=\$DATA_DIR/tiny/extra/to_vault:/usr/local/bin/to_vault ";
    
    Util.termWrite("""
export DATA_DIR=${G.dataPath}
export PATH=\$DATA_DIR/bin:\$PATH
export LD_LIBRARY_PATH=\$DATA_DIR/lib
export CONTAINER_DIR=\$DATA_DIR/containers/${G.currentContainer}
export EXTRA_MOUNT=${Util.escapeShellArgument(extraMount)}
export EXTRA_OPT=${Util.escapeShellArgument(extraOpt)}
cd \$DATA_DIR
export PROOT_TMP_DIR=\$DATA_DIR/proot_tmp
export PROOT_LOADER=\$DATA_DIR/applib/libproot-loader.so
export PROOT_LOADER_32=\$DATA_DIR/applib/libproot-loader32.so
${Workflow.getBootCommand(extraMount: extraMount, extraOpt: extraOpt)}
clear""");
  }

  static Future<void> launchGUIBackend() async {
    Util.termWrite(
      (Util.getGlobal("autoLaunchVnc") as bool)
          ? ((Util.getGlobal("useX11") as bool)
              ? """mkdir -p "\$HOME/.vnc" && bash /etc/X11/xinit/xinitrc &> "\$HOME/.vnc/x.log" &"""
              : Util.getCurrentProp("vnc"))
          : "",
    );
    Util.termWrite("clear");
  }

  static Future<void> waitForConnection() async {
    await retry(
      // Make a GET request
      () => http
          .get(Uri.parse(Util.getCurrentProp("vncUrl")))
          .timeout(const Duration(milliseconds: 250)),
      // Retry on SocketException or TimeoutException
      retryIf: (e) => e is SocketException || e is TimeoutException,
    );
  }

  static Future<void> launchBrowser() async {
    G.controller.loadRequest(Uri.parse(Util.getCurrentProp("vncUrl")));
    Navigator.push(
      G.homePageStateContext,
      MaterialPageRoute(
        builder: (context) {
          return Focus(
            onKeyEvent: (node, event) {
              // Allow webview to handle cursor keys. Without this, the
              // arrow keys seem to get "eaten" by Flutter and therefore
              // never reach the webview.
              // (https://github.com/flutter/flutter/issues/102505).
              if (!kIsWeb) {
                if ({
                  LogicalKeyboardKey.arrowLeft,
                  LogicalKeyboardKey.arrowRight,
                  LogicalKeyboardKey.arrowUp,
                  LogicalKeyboardKey.arrowDown,
                  LogicalKeyboardKey.tab,
                }.contains(event.logicalKey)) {
                  return KeyEventResult.skipRemainingHandlers;
                }
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onSecondaryTap: () {},
              child: WebViewWidget(controller: G.controller),
            ),
          );
        },
      ),
    );
  }

  static Future<void> launchAvnc() async {
    await AvncFlutter.launchUsingUri(
      Util.getCurrentProp("vncUri") as String,
      resizeRemoteDesktop: Util.getGlobal("avncResizeDesktop") as bool,
      resizeRemoteDesktopScaleFactor: pow(
        4,
        Util.getGlobal("avncScaleFactor") as double,
      ).toDouble(),
    );
  }

  /// The X server runs outside proot, so it cannot follow an absolute symlink
  /// target. Arch ships `usr/share/X11/xkb -> /usr/share/xkeyboard-config-2`,
  /// which dangles against Android's root; point at the real directory instead.
  static String xkbRoot(String containerPath) {
    final real = Directory("$containerPath/usr/share/xkeyboard-config-2");
    if (real.existsSync()) return real.path;
    return "$containerPath/usr/share/X11/xkb";
  }

  static Future<void> startContainerForegroundService() async {
    try {
      await D.androidChannel.invokeMethod("startContainerService");
    } catch (_) {}
  }

  static Future<void> stopContainerForegroundService() async {
    try {
      await D.androidChannel.invokeMethod("stopContainerService");
    } catch (_) {}
  }

  static Future<void> launchXServer() async {
    await startContainerForegroundService();
    final container = "${G.dataPath}/containers/${G.currentContainer}";
    final xkb = xkbRoot(container);
    if (!Directory(xkb).existsSync() &&
        FileSystemEntity.typeSync(xkb, followLinks: false) ==
            FileSystemEntityType.notFound) {
      Util.createDirFromString(xkb);
    }
    BootLog.event('launching X server (xkb root: $xkb)');
    // The native side starts the server on its own thread and reports a failure
    // there (after it has already returned success) through this call.
    D.androidChannel.setMethodCallHandler((call) async {
      if (call.method == "xServerLaunchFailed") {
        Util.xServerLaunchError = "${call.arguments}";
        BootLog.event('X server entry point failed: ${call.arguments}');
      }
    });
    try {
      // Not X11Flutter.launchXServer: that runs CmdEntryPoint.main on the UI thread
      // and blocks it forever (see MainActivity.kt).
      await D.androidChannel.invokeMethod("launchXServer", {
        "tmpdir": "$container/tmp",
        "xkb": xkb,
        "xserverArgs": [":4", "-extension", "MIT-SHM"],
      });
      BootLog.event('X server thread started');
    } catch (e) {
      // launchXServer is fired without await; keep the reason for waitForXServer.
      Util.xServerLaunchError = e.toString();
      BootLog.event('X server launch failed: $e');
      rethrow;
    }
  }

  static Future<void> launchX11() async {
    await X11Flutter.launchX11Page();
  }

  static Future<void> workflow() async {
    await initData();
    BootLog.attachFile('${G.dataPath}/boot.log');
    BootLog.event('workflow started');
    final hasPermission = await grantPermissions();
    if (!hasPermission) {
      throw Exception("Storage permission is required to initialize the container system.");
    }
    await initTerminalForCurrent();
    // PulseAudio runs in the foreground of its pty, so setupAudio() only completes
    // when the daemon exits. Awaiting it here froze startup before the container
    // ever launched; upstream deliberately fires it and moves on.
    unawaited(setupAudio());
    BootLog.event('launching container ${G.currentContainer}');
    await startContainerForegroundService();
    await launchCurrentContainer();
    if (Util.getGlobal("autoLaunchVnc") as bool) {
      if (G.wasX11Enabled) {
        await Util.waitForXServer();
        launchGUIBackend();
        launchX11();
        return;
      }
      launchGUIBackend();
      waitForConnection().then(
        (value) => G.wasAvncEnabled ? launchAvnc() : launchBrowser(),
      );
    }
  }
}

class ShizukuHelper {
  static bool _available = false;

  @visibleForTesting
  static Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment,
    bool runInShell,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) processRunner = Process.run;

  static Future<void> init() async {
    try {
      final result = await processRunner('sh', ['-c', 'command -v rish']);
      _available = result.exitCode == 0;
    } catch (_) {
      _available = false;
    }
  }

  static bool get isAvailable => _available;

  // Single-quote escapes an argument for safe use inside a shell command string.
  static String _escapeArg(String arg) => "'${arg.replaceAll("'", "'\\''")}'";

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    if (!_available) {
      return processRunner(executable, arguments);
    }
    // rish only accepts a single command string, so we shell-escape every
    // argument to prevent command injection.
    final cmdString = [executable, ...arguments].map(_escapeArg).join(' ');
    return processRunner('rish', ['-c', cmdString]);
  }
}
