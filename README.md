# Valheim ARM64 server

A Debian-based container for running the official Valheim Dedicated Server on ARM64 Raspberry Pi Kubernetes nodes. It downloads Steam app `896660` with native ARM64 DepotDownloader, then runs the official x86_64 Linux server with Box64.

> [!IMPORTANT]
> This is an ARM64 compatibility build, not a native ARM64 Valheim server. Vanilla Steam-backend operation is the target. PlayFab crossplay is experimental because of a current upstream Box64 compatibility report; it is disabled by default.

## Why this design

```text
ARM64 DepotDownloader ──downloads──> official Linux x86_64 depot (persistent)
                                                │
Debian 13 ARM64 host <── Box64 dynamic recompiler ┘
```

- **Current Debian stable:** the image starts from the official ARM64-specific `arm64v8/debian:trixie-slim` tag. Debian identifies Trixie as the current stable release, and the moving tag picks up patched Debian rebuilds.
- **No Wine in the vanilla path:** the Steam depot includes an x86_64 Linux server, so Box64 is required but Wine is not.
- **No emulated SteamCMD:** [DepotDownloader](https://github.com/SteamRE/DepotDownloader) publishes a native Linux ARM64 binary and downloads the same official Steam application anonymously.
- **Persistent and Kubernetes-friendly:** server files and world data use separate volumes; the process is non-root, supports a read-only root filesystem, exposes probes, and converts pod termination into Valheim's clean `SIGINT` shutdown.
- **Conservative updates:** Valheim validates on each start; [Box64](https://github.com/ptitSeb/box64/releases) and DepotDownloader are checksum-pinned. A weekly workflow rebuild refreshes Debian security packages.

The operational patterns come from [community-valheim-tools/valheim-server-docker](https://github.com/community-valheim-tools/valheim-server-docker), formerly `lloesche/valheim-server`. The alternate Windows/Wine approach was evaluated against [tsx-cloud/valheim-arm](https://github.com/tsx-cloud/valheim-arm). See [the compatibility analysis](docs/compatibility.md) for the tradeoffs and current limitations.

## Requirements

- A 64-bit Raspberry Pi Kubernetes node (`aarch64` / `arm64`), preferably a Pi 4 or Pi 5 with at least 4 GiB RAM.
- A default Kubernetes StorageClass for the two persistent-volume claims.
- A UDP-capable `LoadBalancer` implementation such as MetalLB, or an equivalent service exposure you configure yourself.
- UDP ports 2456-2458 allowed through host and edge firewalls.
- Docker Buildx for a local build, or GitHub Actions after the repository is pushed.

## Run with Docker Compose on an ARM64 host

```bash
cp .env.example .env
# Edit .env and set a private SERVER_PASSWORD of at least five characters.
docker compose up --detach --build
docker compose logs --follow valheim
```

The initial download can take several minutes. Stop with `docker compose down`; do not add `--volumes` unless you intend to remove the installation cache and saved world.

## Deploy to Kubernetes with Helm

The chart in [`charts/valheim-arm64`](charts/valheim-arm64) is the recommended Kubernetes installation method. Create the password outside Helm so it is not stored in Helm release values or history:

```bash
kubectl create namespace valheim
kubectl --namespace valheim create secret generic valheim-secret \
  --from-literal=server-password='CHOOSE-A-PRIVATE-PASSWORD'
helm upgrade --install valheim ./charts/valheim-arm64 \
  --namespace valheim \
  --set server.existingSecret.name=valheim-secret
kubectl --namespace valheim rollout status \
  statefulset/valheim-valheim-arm64 --timeout=15m
kubectl --namespace valheim logs --follow \
  statefulset/valheim-valheim-arm64
```

The chart defaults to `ghcr.io/zhmarvi/valheim-arm64:latest`. Set `image.repository` if you publish the image from a fork. It derives all three UDP ports from `server.port`, supports LoadBalancer/NodePort/ClusterIP Services, and allows storage classes or existing claims to be configured. See the [chart README](charts/valheim-arm64/README.md) and [`values.yaml`](charts/valheim-arm64/values.yaml) for all options.

Inspect the external address with:

```bash
kubectl --namespace valheim get service valheim-valheim-arm64
```

If `EXTERNAL-IP` remains pending, install/configure a UDP-capable load balancer or change `service.type`. Home-hosted clusters also need all three UDP ports forwarded from the router to the load-balancer address.

The default Helm release creates:

- `server-valheim-valheim-arm64-0`, a 5 GiB installation/update cache mounted at `/opt/valheim`.
- `config-valheim-valheim-arm64-0`, a 2 GiB world/config volume mounted at `/config`. Back up this claim.

### Kustomize alternative

The static manifests remain available for installations that do not use Helm. Edit `k8s/base/kustomization.yaml` and replace `ghcr.io/replace-me/valheim-arm64` with the image published by your repository, then run:

```bash
kubectl apply -f k8s/base/namespace.yaml
kubectl --namespace valheim create secret generic valheim-secret \
  --from-literal=server-password='CHOOSE-A-PRIVATE-PASSWORD' \
  --dry-run=client --output=yaml | kubectl apply -f -
kubectl apply -k k8s/base
```

## Configuration

Compose reads environment variables from `.env`; Kustomize reads non-secret values from `k8s/base/configmap.yaml`. Helm exposes the corresponding settings under `server` in the chart values.

| Variable | Default | Purpose |
| --- | --- | --- |
| `SERVER_NAME` | `Valheim ARM64` | Public server name |
| `WORLD_NAME` | `Dedicated` | World save name |
| `SERVER_PASSWORD` | required | At least five characters; stored in a Kubernetes Secret |
| `SERVER_PORT` | `2456` | First of three UDP ports |
| `SERVER_PORT_END` | `2458` | Compose host-port range end; keep it at `SERVER_PORT + 2` |
| `SERVER_PUBLIC` | `1` | `1` lists the server; `0` hides it |
| `SERVER_CROSSPLAY` | `false` | Adds `-crossplay`; read the warning below first |
| `UPDATE_ON_START` | `true` | Validate/update app 896660 before launch |
| `SAVE_INTERVAL` | `1800` | Seconds between saves |
| `BACKUPS` | `4` | Automatic backup count |
| `BACKUP_SHORT` | `7200` | Short backup interval in seconds |
| `BACKUP_LONG` | `43200` | Long backup interval in seconds |

`SERVER_PORT_END` is Compose-only. Helm derives the complete port range from `server.port`; Kustomize users must update the ConfigMap, container ports, and Service ports together. Valheim necessarily receives the password as a process argument. Kubernetes Secrets prevent it from being committed to Git, but cluster administrators with pod-debug permissions can still inspect it.

## Wine and compatibility conclusion

Wine is **not mandatory** for the official Linux server. Box64 is mandatory because Valve's current Linux depot is x86_64 rather than ARM64. Using the Windows depot would require both Box64 and Wine and usually Xvfb; that is the approach used by tsx-cloud and can be useful for Windows-oriented mod stacks, but it adds more translation layers and its current base is Ubuntu rather than Debian.

Crossplay is the important caveat. [Box64 issue #4403](https://github.com/ptitSeb/box64/issues/4403) reports that recent Box64 builds can start Valheim on Raspberry Pi while PlayFab join-code registration never completes. This repository therefore defaults to the Steam backend. If crossplay is a hard requirement, test the tsx-cloud Windows/Wine image on your exact Pi kernel and game version, or wait for and verify the Box64 fix before enabling it here.

The official [Valheim dedicated-server guide](https://valheim.com/support/a-guide-to-dedicated-servers/) remains the authority for server flags and network behavior. The [Steam depot listing](https://steamdb.info/app/896660/depots/) shows the platform-specific server payloads.

## Validate and build

```bash
make validate
make build IMAGE=valheim-arm64:local
```

`make validate` checks shell syntax, ShellCheck findings, Kustomize rendering, Helm linting/rendering, YAML lint, and Compose configuration when the corresponding tools are installed. The GitHub workflow performs the ARM64 Buildx build under QEMU and publishes to GHCR on `main`, version tags, manual runs, and the weekly refresh.

### Published image tags

Every published image receives an immutable UTC timestamp tag in the form `build-YYYYMMDD-HHmmss`, for example `build-20260926-174532`. Successful default-branch builds also move the convenient `latest` alias to that same image. Git tags beginning with `v` additionally publish semantic-version tags.

Use `latest` to follow new default-branch builds automatically, or pin a timestamp tag for a repeatable deployment:

```yaml
image:
  repository: ghcr.io/zhmarvi/valheim-arm64
  tag: build-20260926-174532
  digest: ""
  pullPolicy: IfNotPresent
```

An OCI digest remains the strongest immutable pin.

## Licenses

Repository code is MIT licensed. Box64, DepotDownloader, Debian packages, and Valheim retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The proprietary Valheim payload is downloaded from Steam at runtime and is not redistributed by this repository image.
