# Compatibility notes

This image targets one deliberately narrow configuration: an ARM64 Raspberry Pi node running the official Linux Valheim Dedicated Server through Box64. It is not an ARMv7 image and it does not emulate a Windows installation.

## Runtime choices

| Component | Architecture | Role |
| --- | --- | --- |
| Debian 13 `trixie-slim` | ARM64 | Container user space |
| DepotDownloader | ARM64 | Downloads and validates Steam app 896660 |
| Valheim Dedicated Server | x86_64 Linux | Official server payload downloaded at startup |
| Box64 | ARM64 host / x86_64 guest | Runs the official Linux server binary |

Valve does not publish a native ARM64 Valheim server. The [current Steam depot listing](https://steamdb.info/app/896660/depots/) identifies the Linux server executable as `valheim_server.x86_64`, so an x86_64 compatibility layer is still required.

The image uses [DepotDownloader's native Linux ARM64 release](https://github.com/SteamRE/DepotDownloader/releases) instead of SteamCMD. SteamCMD's Linux bootstrap still relies on x86 binaries; choosing DepotDownloader avoids adding a second, 32-bit emulation path merely to install the game.

## Is Wine mandatory?

No. Wine is only required when running the Windows depot. This repository downloads the Linux depot and invokes it with [Box64](https://github.com/ptitSeb/box64), so Wine, a Wine prefix, and Xvfb are absent.

The [tsx-cloud/valheim-arm](https://github.com/tsx-cloud/valheim-arm) image makes the other defensible tradeoff: it downloads the Windows depot and runs it through Box64 plus Wine. That is useful for some Windows-focused mod stacks, but produces a larger and more complicated runtime. Its current image is Ubuntu-based, so it also does not satisfy this repository's Debian-base requirement. NTSYNC can improve some Wine workloads but is not mandatory for this Linux-native route.

## Expected support

| Scenario | Status | Notes |
| --- | --- | --- |
| Raspberry Pi OS 64-bit or another ARM64 Linux host | Targeted | The Kubernetes node must report `kubernetes.io/arch=arm64`. |
| Vanilla Steam-backend server | Targeted | `SERVER_CROSSPLAY=false` is the default. |
| PlayFab crossplay | Experimental | See the warning below. |
| ARMv7 / 32-bit Raspberry Pi OS | Unsupported | Box64 and this image require AArch64. |
| BepInEx or Valheim Plus | Not bundled | Mod compatibility must be tested per release. |
| Windows Valheim server | Out of scope | Use a Wine-based image if this is a hard requirement. |

### Crossplay warning

An open [Box64 issue about Valheim crossplay on Raspberry Pi](https://github.com/ptitSeb/box64/issues/4403) reports PlayFab join-code registration failing with current Box64 builds even while the native Linux server otherwise starts. For that reason crossplay is off by default and should not be considered production-compatible in this image until that upstream issue is resolved and verified on hardware.

If crossplay is mandatory today, test the Windows/Wine route from tsx-cloud on the exact Pi kernel and game release you intend to operate. Do not enable `SERVER_CROSSPLAY=true` here without confirming that a join code appears in the server logs and that an external client can connect.

### Unity and `libparty.so` startup output

Unity's `memorysetup-*` lines are allocator configuration diagnostics, not evidence that Kubernetes or the Pi has run out of memory. An actual allocation failure, OOM kill, or pod eviction will be reported separately by Unity, the container status, or the node.

Valheim's Linux payload includes `libparty.so`, which Unity may inspect even when crossplay is disabled. It imports Ogg functions that must cross Box64's x86_64-to-ARM64 library boundary. The image explicitly installs Debian's ARM64 [`libogg0`](https://packages.debian.org/trixie/libogg0), preloads `libogg.so.0` in the Box64 guest namespace, and enables `ogg_stream_pageout_fill` in [Box64 0.4.4's libogg wrapper declaration](https://github.com/ptitSeb/box64/blob/v0.4.4/src/wrapped/wrappedlibogg_private.h). This prevents the unresolved `ogg_*` relocation errors and the resulting `Failed to open plugin` message.

The same native-wrapper requirement applies to SDL. The image includes both SDL2 and Debian's ARM64 [`libsdl3-0`](https://packages.debian.org/trixie/libsdl3-0), which supplies the `libSDL3.so.0` expected by Box64 and current Valheim payloads.

This library-loading fix does not establish PlayFab compatibility. Keep crossplay disabled unless the join-code and external-client checks above pass on the deployed image.

## Base image and update policy

The Dockerfile defaults to `arm64v8/debian:trixie-slim`, the ARM64-specific official image for current Debian stable. The tag intentionally follows patched Trixie rebuilds. The scheduled GitHub Actions build refreshes the public image weekly; Box64 and DepotDownloader remain version- and checksum-pinned so compatibility changes are reviewed rather than silently introduced.

## What has to be tested on a real cluster

Static validation cannot prove Unity/Box64 behavior or networking on a particular Pi kernel. Before relying on the server:

1. Confirm the image builds as `linux/arm64` in GitHub Actions or on an ARM64 builder.
2. Start it on one Pi node and wait for the server log to report that the game server is connected.
3. Connect a Steam client from outside the cluster and exercise world save plus pod restart.
4. Confirm that the world reappears from the `config` persistent volume.
5. If using a load balancer, verify UDP 2456-2458 through MetalLB and any router or firewall.

The operational layout—persistent installation and world data, startup updates, non-root execution, health probes, and graceful `SIGINT` shutdown—follows the mature patterns in [community-valheim-tools/valheim-server-docker](https://github.com/community-valheim-tools/valheim-server-docker), formerly `lloesche/valheim-server`.
