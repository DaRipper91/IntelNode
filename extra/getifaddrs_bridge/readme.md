# getifaddrs_bridge

A C Unix-socket IPC bridge that lets a proot container query Android's network interfaces. Part of [DaRipped Tiny Computer](../../README.md).

---

## Problem

Inside a proot container, calls to `getifaddrs()` fail or return empty results. The container process cannot read Android's `/proc/net` data directly, so the standard libc implementation has nothing to work with.

`getifaddrs_bridge` solves this by splitting the call across a process boundary:

- The **server** runs natively on Android, outside proot, where `/proc/net` is fully accessible.
- The **client library** runs inside the container and intercepts `getifaddrs()` via `LD_PRELOAD`, forwarding the request to the server over a Unix domain socket.

---

## Architecture

```
┌─────────────────────────────────┐     Unix socket     ┌──────────────────────────────────┐
│        proot container          │                      │        Android host process        │
│                                 │                      │                                    │
│  your_program                   │                      │  getifaddrs_bridge_server          │
│    └─ getifaddrs()  ◄──────── LD_PRELOAD ──────────►  │    └─ getifaddrs()  (real)         │
│         │                       │  'S' signal ──────►  │         │                          │
│         │                       │  serialized data ◄─  │    serialize_ifaddrs()             │
│    deserialize_ifaddrs()        │                      │                                    │
└─────────────────────────────────┘                      └──────────────────────────────────┘
```

**Protocol (per call):**
1. Client connects to the Unix socket and sends the single byte `'S'`.
2. Server calls the real `getifaddrs()`, serializes the result into a flat byte buffer, and writes it back.
3. Client deserializes the buffer into a heap-allocated `ifaddrs` linked list and returns it to the caller.

---

## Files

| File | Description |
|---|---|
| `getifaddrs_bridge_server.c` | Server — compile with NDK, run on Android host |
| `getifaddrs_bridge_client_lib.c` | Client — compile as shared lib inside the proot container |

---

## Build

### Server (Android host — requires NDK)

Cross-compile for `aarch64` on your build machine:

```bash
aarch64-linux-android-clang getifaddrs_bridge_server.c -o getifaddrs_bridge_server
```

Copy the resulting binary to somewhere accessible on the Android device (e.g. inside the Tiny Computer app's data directory or `/data/local/tmp`).

### Client library (inside the proot container)

Run this from within the proot shell using the container's own GCC:

```bash
gcc getifaddrs_bridge_client_lib.c -o getifaddrs_bridge_client_lib.so -shared
```

---

## Usage

**1. Start the server on the Android side** (before launching the container):

```bash
getifaddrs_bridge_server /path/to/container/tmp/.getifaddrs-bridge
```

The server blocks and listens indefinitely. It accepts one client connection at a time and handles repeated queries on that connection until the client disconnects.

**2. Inside the proot container**, preload the client library for any program that calls `getifaddrs()`:

```bash
LD_PRELOAD=/path/to/getifaddrs_bridge_client_lib.so <your_program>
```

---

## Socket path convention

The server takes the socket path as its only argument. The client library hardcodes the path `/tmp/.getifaddrs-bridge` at compile time.

To match, the server **must** be started with the container's `/tmp` directory as the target — for example:

```bash
getifaddrs_bridge_server /path/to/container/rootfs/tmp/.getifaddrs-bridge
```

Because proot bind-mounts the container's `/tmp` at `/tmp` inside the container, both sides will see the same socket file.

---

## Known limitations

- **Buffer size is fixed at 1024 bytes.** The serialized `ifaddrs` data is truncated silently if the total size of all interfaces exceeds this limit. Devices with a large number of virtual network interfaces may see incomplete results.
- **`ifa_data` is always `NULL`** in the deserialized result. Interface-specific statistics data is not forwarded (marked `TODO` in the source).
- **The client calls `exit(1)` on any connection or I/O error.** If the server is not running when a preloaded program starts, the program will terminate immediately rather than falling back gracefully.
- The server handles one client connection at a time (sequential, not concurrent). This is sufficient for typical single-program proot use cases.

---

## License

Copyright © 2023 Caten Hu. GPL-3.0-or-later — see [COPYING](../../COPYING).