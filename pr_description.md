🎯 **What:** The vulnerability fixed
Command Injection vulnerability in `Util.execute` where arbitrary strings were written to the standard input stream of an interactive `Pty` session (`sh`).

⚠️ **Risk:** The potential impact if left unfixed
User configurations and directory paths (e.g. `defaultVirglCommand`) interpolated directly into script executions could be crafted to inject malicious commands, allowing execution of unintended applications or potential file system destruction. The interactive `Pty` process parses commands as standard input, making it susceptible to evaluation bugs, output deadlocks, and severe security exploits.

🛡️ **Solution:** How the fix addresses the vulnerability
1. Substituted the vulnerable standard input write (`pty.write`) with Dart's standard `Process.run('sh', ['-c', ...])` to securely execute commands using bounded shell execution arguments.
2. Introduced `Util.executeBackground` (using `Process.start` with detached mode) to properly execute indefinite processes (like `virgl_test_server`) without hanging or buffering indefinitely.
3. Implemented a robust `Util.escapeShellArgument` utility method that safely encapsulates variables injected into setup scripts, stripping raw shell evaluations (`'...'`).
4. Applied the new shell escape functions securely across existing `Util.execute` invocations containing configurable environment paths or variables.
