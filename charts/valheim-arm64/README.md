# valheim-arm64 Helm chart

Deploys one Valheim dedicated server on an ARM64 Kubernetes node. The chart preserves the container's secure defaults, exposes three consecutive UDP ports, and creates separate persistent volumes for the server installation and world data.

## Prerequisites

- Kubernetes 1.33 or newer with an `arm64` node
- Helm 3 or newer
- A default StorageClass, unless existing claims or explicit storage classes are configured
- A UDP-capable `LoadBalancer`, or a different `service.type` and external UDP routing
- UDP ports 2456-2458 allowed through cluster, host, and edge firewalls

## Install

Create the password outside Helm so it is not stored in Helm release values:

```bash
kubectl create namespace valheim
kubectl --namespace valheim create secret generic valheim-secret \
  --from-literal=server-password='CHOOSE-A-PRIVATE-PASSWORD'
helm upgrade --install valheim ./charts/valheim-arm64 \
  --namespace valheim \
  --set server.existingSecret.name=valheim-secret
```

If this repository was forked, set `image.repository` to the image published by the fork. For a private GHCR image, create a registry Secret and set `imagePullSecrets[0].name`.

For disposable testing only, `--set-string server.password=...` creates a Secret. That password remains in Helm release history. The password must contain at least five characters and Valheim necessarily receives it as a process argument.

The initial startup downloads Steam app `896660` and may take several minutes:

```bash
kubectl --namespace valheim rollout status statefulset/valheim-valheim-arm64 --timeout=15m
kubectl --namespace valheim logs --follow statefulset/valheim-valheim-arm64
kubectl --namespace valheim get service valheim-valheim-arm64
```

## Important values

| Value | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/zhmarvi/valheim-arm64` | Container image repository |
| `image.tag` | `latest` | Moving default-branch alias; use a `build-YYYYMMDD-HHmmss` tag for repeatable deployments |
| `server.name` | `Valheim ARM64` | Public server name |
| `server.worldName` | `Dedicated` | World save name |
| `server.port` | `2456` | First of three consecutive UDP ports; all manifests derive the other two |
| `server.public` | `1` | `1` lists the server; `0` hides it |
| `server.crossplay` | `false` | Enables experimental PlayFab crossplay |
| `server.updateOnStart` | `true` | Validates/downloads the game before launch |
| `server.existingSecret.name` | empty | Preferred Secret containing the password |
| `server.existingSecret.key` | `server-password` | Password key in the existing Secret |
| `service.type` | `LoadBalancer` | External Service type |
| `persistence.server.size` | `5Gi` | Installation and update-cache claim size |
| `persistence.config.size` | `2Gi` | World, save, and backup claim size |
| `restartCronJob.enabled` | `true` | Create the scheduled StatefulSet restart job and RBAC |
| `restartCronJob.schedule` | `0 6 * * *` | Daily restart schedule interpreted in `restartCronJob.timeZone` |
| `restartCronJob.timeZone` | `Etc/UTC` | IANA timezone used by the CronJob controller |
| `resources.requests` | `1 CPU`, `2Gi` | Scheduler reservation |
| `resources.limits` | `4 CPU`, `6Gi` | Container limits |

Every published image has a UTC timestamp tag such as `build-20260926-174532`. Default-branch builds also update `latest`. Set `image.tag` to a timestamp tag and `image.pullPolicy: IfNotPresent` to keep a known build, or use `image.digest` for a fully immutable deployment.

See `values.yaml` for service annotations, storage classes, existing claims, security contexts, scheduling, probes, and resource controls.

## Persistence

The StatefulSet creates two claims by default:

- `server-<statefulset>-0`, mounted at `/opt/valheim`, caches the downloaded server.
- `config-<statefulset>-0`, mounted at `/config`, contains worlds, saves, and backups. Back up this claim.

Set `persistence.<name>.existingClaim` to mount an existing claim, or set `enabled: false` to use non-persistent `emptyDir` storage. StatefulSet claim templates are generally not mutable after creation. Changing a size or storage class may require expanding the PVC directly or migrating to a new claim. Helm uninstall does not normally delete StatefulSet-created PVCs.

## Scheduled restart

The chart creates a CronJob by default that runs at `06:00 Etc/UTC` every day and performs `kubectl rollout restart` against only this release's StatefulSet. The restart gives Valheim a clean `SIGINT` shutdown and, because `server.updateOnStart` defaults to `true`, validates game files when the replacement pod starts.

The job uses a dedicated ServiceAccount and a namespace-scoped Role limited to `get` and `patch` on the named StatefulSet. Its official multi-architecture `kubectl` image is pinned by digest. Kubernetes 1.33 or newer is required for stable CronJob `timeZone` support.

Disable the CronJob and all of its RBAC resources with:

```yaml
restartCronJob:
  enabled: false
```

Change the schedule or timezone independently when needed:

```yaml
restartCronJob:
  enabled: true
  schedule: "0 6 * * *"
  timeZone: Etc/UTC
```

A scheduled restart causes brief server downtime. Players should disconnect before the configured time so the graceful shutdown can save the world.

## Networking and operation

Valheim always uses `server.port`, `server.port + 1`, and `server.port + 2` over UDP. A home-hosted cluster must forward that entire range to the load-balancer address. If the external IP remains pending, configure a UDP-capable load balancer such as MetalLB or choose another Service type.

The probes confirm only that the launched process is alive; they do not test UDP reachability or Steam registration. The default ten-minute startup allowance covers the first download. Pod termination sends Valheim `SIGINT` and allows 120 seconds for a clean save.

The chart is intentionally fixed at one replica. Multiple replicas would create unrelated worlds while one Service load-balances clients across them.

Changing chart-managed configuration or password data rolls the pod through checksum annotations. Changes to an external Secret do not; restart the StatefulSet after rotating that Secret.

Crossplay remains experimental because of the Box64/PlayFab compatibility issue documented in the repository README. Vanilla Steam-backend operation is the supported default.

## Validate and remove

```bash
helm lint ./charts/valheim-arm64 --set-string server.password=validation-only
helm template valheim ./charts/valheim-arm64 \
  --namespace valheim \
  --set server.existingSecret.name=valheim-secret
helm uninstall valheim --namespace valheim
```

Review retained PVCs after uninstall and delete them only when their data is no longer needed.
