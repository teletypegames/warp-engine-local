# WarpEngine Local

A [WarpEngine](https://git.teletypegames.org/engines/warp_engine) on your own machine: one
container, one port, no setup. The [WarpEngine Toolbox](https://marketplace.visualstudio.com/items?itemName=TeletypeGames.warpengine-toolbox)
finds it by itself, you publish your games to it from VS Code, and it syncs the releases on to
a catalog of your choice — [Teletype Orbit](https://orbit.teletypegames.org) unless you name
another.

## Install

macOS and Linux (Docker Desktop, OrbStack or Docker Engine running):

```sh
curl -fsSL https://git.teletypegames.org/engines/warp-engine-local/raw/branch/master/install.sh | sh
```

Windows (Docker Desktop, PowerShell in Windows Terminal):

```powershell
irm https://git.teletypegames.org/engines/warp-engine-local/raw/branch/master/install.ps1 | iex
```

The installer checks Docker and the port, asks three things — where your releases go (Enter:
`https://orbit.teletypegames.org`), whether you want the admin web UI (no by default), and
whether to pull the builder images now (no by default: the pipelines pull them when they need
them) — then starts the engine and tells you where everything is. Run it again any time: it
remembers the answers, replaces the container and keeps your data.

| Option (`install.sh` / `install.ps1`) | |
| --- | --- |
| `--port N` / `-Port N` | the port on 127.0.0.1 (default 7470) |
| `--sync-target URL` / `-SyncTarget URL` | where your releases go; `none` for nowhere |
| `--admin on\|off` / `-Admin on\|off` | the admin web UI at `/admin` |
| `--builders none\|all\|"c64 love"` / `-Builders …` | pull builder images now |
| `--version V` / `-Version V` | another version of the engine image |
| `--yes` / `-Yes` | ask nothing: the saved answers, or the defaults |
| `--status` / `-Status` | what is installed |
| `--uninstall [--purge]` / `-Uninstall [-Purge]` | remove the container (and the data) |

Without a terminal (a script, CI, a tool running it) the installer asks nothing and takes the
saved answers or the defaults; `NO_COLOR=1` turns the colours off.

## What runs

`git.teletypegames.org/build/warp-engine-local`, for amd64 and arm64, as the container
`warp-engine-local`, bound to `127.0.0.1` only. Everything it keeps is in `~/.warpengine`:

| | |
| --- | --- |
| `warp_engine.sqlite3`, `queue.sqlite3` | the catalog and the job queue (SQLite) |
| `softwares/`, `images/` | the releases' files and the images |
| `local-token` | the token the Toolbox signs in with (every scope) |
| `secrets.json` | generated on first boot |
| `admin.json` | the admin web UI sign-in, once the admin is on |
| `config.json` | the installer's answers |

What answers on the port:

- `GET /.well-known/warp-engine` — what this is: `"profile": "local"`, the version, the sync
  target, whether the admin is on; the Toolbox probes it
- `/api/*` — the catalog (WECP), `/play` and `/file/*` — playing and downloading
- `/build/*` — uploads and publishing (`X-Update-Secret: <local-token>`)
- `/api/admin/v1` — the Admin API and its MCP endpoint (`Authorization: Bearer <local-token>`)
- `/admin` — the admin web UI, when it is on

### The local CI

The engine runs with the Docker socket (`/var/run/docker.sock`) and on the `warp-local` network,
so it can start a git server and a CI beside itself when a project wants them (the Toolbox's
**Set Up Local CI**, or the Admin API's `local_components`):

| | |
| --- | --- |
| `warp-local-gitea` | Gitea on `127.0.0.1:<port + 1>` (7471); your pushes go there (the `warp` remote) |
| `warp-local-woodpecker`, `warp-local-woodpecker-agent` | Woodpecker, reachable only on the network; it runs the pipelines on your Docker |

Everything is made with generated passwords, nobody signs in; the data lives in the
`warp-local-gitea-data` and `warp-local-woodpecker-data` volumes. `--uninstall` removes these
containers too, `--purge` their volumes and the network as well.

Inside the container: `docker exec warp-engine-local bin/warp-engine token` prints the token
(`--reset` issues a new one), `bin/warp-engine admin` the admin sign-in.

## Developing

The image takes the `warp_engine` gem from the TTG gem registry. To run it against an engine
checkout:

```sh
WARP_ENGINE_SOURCE=../warp_engine docker compose -f compose.dev.yml up --build
# or the installer against your own build:
docker build --build-context engine=../warp_engine --build-arg WARP_ENGINE_PATH=/warp_engine -t warp-engine-local:dev .
sh install.sh --image warp-engine-local:dev
```

`host_app/` is a small Rails app: SQLite, Solid Queue in Puma, the engine mounted at `/` with
`profile :local`, and ActiveAdmin + Devise loaded only when `WARP_ADMIN=1`.

## Releasing

Bump `INSTALLER_VERSION` in `install.sh` and `install.ps1`, push the image by hand, then commit,
tag `vX.Y.Z` and push:

```sh
docker login git.teletypegames.org
BUILDER=<a buildx builder for amd64 and arm64> bin/push-image
```

`bin/push-image` builds for amd64 and arm64 and pushes `X.Y.Z`, `X.Y`, `X` and `latest`. Push
the image before `master`: the installers there pull the version they name. The pipeline only
checks the installers (shellcheck, the two versions agree, the tag matches).

| Local | Engine | |
| --- | --- | --- |
| 1.2.0 | `warp_engine ~> 5.4` | the local CI: the Docker socket and the `warp-local` network, the full pipeline set |
| 1.1.0 | `warp_engine ~> 5.3` | per-peer channels, pairing with a remote engine, images go with the releases |
| 1.0.1 | `warp_engine ~> 5.2` | the image is pushed by hand, `bin/push-image` |
| 1.0.0 | `warp_engine ~> 5.2` | first release |

## License

MIT, see `LICENSE`.
