# Algorithm Diagrams

---

## 1. Installation Flow

```
User runs: ./install.sh [--skip <phase>] [--steps <spec>] [--dry-run]
                              │
                              ▼
                    ┌─────────────────────┐
                    │  Parse CLI flags    │
                    │  --skip, --steps,   │
                    │  --dry-run, --apps  │
                    └─────────┬───────────┘
                              │
                              ▼
              ┌─ should_run(1, preinstall) ?
              │       YES          NO
              ▼                    ▼
     ┌────────────────┐    ┌──────────────┐
     │ preinstall.sh  │    │    skip      │
     │ apt update     │    │              │
     │ 25+ packages   │    │              │
     │ yt-dlp         │    │              │
     │ fail2ban       │    │              │
     └───────┬────────┘    └──────────────┘
             │
             ▼
      ┌─ should_run(2, scripts) ?
      │       YES          NO
      ▼                    ▼
     ┌────────────────┐    ────────
     │ Copy bin/*     │
     │ → /usr/local   │
     │ Copy lib/      │
     │ → common.sh    │
     └───────┬────────┘
             │
             ▼
      ┌─ should_run(3, postinstall) ?
      │       YES          NO
      ▼                    ▼
     ┌──────────────────────────┐
     │ postinstall.sh          │
     │ • fail2ban config       │
     │ • ~/.bashrc PATH        │
     │ • bash completion       │
     │ • systemd services      │
     │ • SSH authorized_keys   │
     └──────────┬───────────────┘
                │
                ▼
      ┌─ should_run(4, scalepoint) ?
      │       YES          NO
      ▼                    ▼
     ┌──────────────────────────┐
     │ Clone ScaleTail         │
     │ → /usr/local/share/     │
     │   linux_post_install/   │
     └──────────┬───────────────┘
                │
                ▼
      ┌─ RUN_APPS ?
      │  ┌── 1 (--apps)   ─── interactive picker
      │  ├── 2 (--full)   ─── install all
      │  └── else         ─── skip
      ▼
     ┌──────────────────────┐
     │  Bootstrap complete  │
     └──────────────────────┘
```

---

## 2. `pos` CLI Dispatch

```
User: pos docker compose up jellyfin
              │
              ▼
     ┌──────────────────────┐
     │ args = [docker,      │
     │         compose,     │
     │         up,          │
     │         jellyfin]    │
     │ n = 4                │
     └──────────┬───────────┘
                │
                ▼
     ┌──────────────────────┐
     │ Loop i from n-1 to 0 │
     │ Build candidate:     │
     │ pos-args[0..i]       │
     └──────────┬───────────┘
                │
     ┌──────────┴──────────┐
     │ i=3: pos-up-jellyfin│  ✗ not found
     │ i=2: pos-up         │  ✗ not found
     │ i=1: pos-compose-up │  ✗ not found
     │ i=0: pos-docker     │  ✗ not found
     │                     │
     │ Fallback to         │
     │ pos-docker-compose  │  ✓ found!
     │ Remaining args:     │
     │ [up, jellyfin]      │
     └──────────┬──────────┘
                │
                ▼
        ┌───────────────┐
        │ Is this an    │
        │ interactive   │
        │ command?      │
        │ (system-      │
        │ firewall,     │
        │ media-mp4)    │
        └──┬────────┬───┘
           │ YES    │ NO
           ▼        ▼
     ┌────────┐  ┌──────────────┐
     │ Log    │  │ Run cmd     │
     │ invoc. │  │ + tee to   │
     │ only   │  │ log file   │
     │ exec   │  │ + log rc   │
     │ direct │  │ exit rc    │
     └────────┘  └──────────────┘
```

---

## 3. Docker Compose `up` Algorithm

```
pos docker compose up qbittorrent
              │
              ▼
     ┌──────────────────────┐
     │ check_deps: docker   │  ──✗──→ ERROR
     │ installed?           │
     └──────────┬───────────┘
                │ ✓
                ▼
     ┌──────────────────────┐
     │ check_templates:     │  ──✗──→ ERROR
     │ ScaleTail dir exist? │
     └──────────┬───────────┘
                │ ✓
                ▼
     ┌──────────────────────┐
     │ check_service:       │  ──✗──→ ERROR
     │ template for         │
     │ qbittorrent exists?  │
     └──────────┬───────────┘
                │ ✓
                ▼
     ┌──────────────────────┐
     │ load_global_config   │
     │ SERVICES_BASE=/srv   │
     │ target=/srv/         │
     │   qbittorrent        │
     └──────────┬───────────┘
                │
                ▼
        ┌──────────────┐
        │ /srv/        │
        │ qbittorrent/ │
        │ exists?      │
        └──┬───────┬───┘
         NO        YES
           │        │
           ▼        ▼
     ┌────────┐  ┌──────────┐
     │ Create │  │ mkdir -p │
     │ dirs   │  │ config/  │
     │ copy   │  │ data/    │
     │ compose│  │          │
     │ .yaml  │  │          │
     └───┬────┘  └──────────┘
         │           │
         └─────┬─────┘
               │
               ▼
        ┌──────────────┐
        │ .env file    │
        │ exists?      │
        └──┬───────┬───┘
         NO        YES
           │        │
           │        ▼
           │    (skip to
           │     startup)
           ▼
     ┌──────────────────────────┐
     │ Copy template .env  or   │
     │ create from defaults     │
     │                          │
     │ Fill in global values:   │
     │ • TS_AUTHKEY ← global    │
     │ • TZ         ← global    │
     │ • DNS_SERVER ← global    │
     │                          │
     │ If TS_AUTHKEY empty:     │
     │   prompt user            │
     └──────────┬───────────────┘
                │
                ▼
        ┌──────────────┐
        │ Prompt:      │
        │ "Edit .env   │
        │  before      │
        │  starting?"  │
        └──┬───────┬───┘
         YES       NO
           │        │
           ▼        ▼
     ┌────────┐  ┌──────────┐
     │ Open   │  │ Continue │
     │ $EDITOR│  │          │
     │ (nano) │  │          │
     └───┬────┘  └──────────┘
         │           │
         └─────┬─────┘
               │
               ▼
     ┌──────────────────────┐
     │ docker compose up -d │
     │ (in /srv/qbittorrent)│
     └──────────┬───────────┘
                │
                ▼
     ┌──────────────────────┐
     │ "qbittorrent is      │
     │  running"            │
     └──────────────────────┘
```

---

## 4. Config Cascade (Three Layers)

```
                            USER
                             │
              ┌──────────────┴──────────────┐
              │        sets via             │
              │  pos docker compose config  │
              │  set TS_AUTHKEY=...         │
              ▼                             │
     ┌────────────────────┐                 │
     │  Layer 2: Global   │◄────────────────┘
     │  ~/.config/        │
     │  linux_post_install│
     │  /compose.env      │
     │                    │
     │  TS_AUTHKEY=...    │
     │  TZ=Europe/...     │
     │  DNS_SERVER=9.9... │
     │  SERVICES_BASE=/srv│
     └────────┬───────────┘
              │
              │ values propagate to new deployments
              ▼
     ┌────────────────────┐
     │  Layer 1: Template │
     │  /usr/local/share/ │
     │  linux_post_install│
     │  /scale-tail/      │
     │  services/<name>/  │
     │  .env              │
     │                    │
     │  SERVICE=xxx       │
     │  IMAGE_URL=        │
     │  SERVICEPORT=      │
     └────────┬───────────┘
              │
              │ merged on first "up"
              ▼
     ┌────────────────────┐
     │  Layer 3: Per-svc  │
     │  /srv/<service>/   │
     │  .env              │
     │                    │
     │  ─── NEVER ───    │
     │  ─── TOUCHED ───  │
     │  ─── AFTER ─────  │
     └────────────────────┘
              │
              ▼
     ┌────────────────────┐
     │  docker compose    │
     │  up -d             │
     │                    │
     │  update only       │
     │  refreshes         │
     │  compose.yaml,     │
     │  NOT .env          │
     └────────────────────┘
```

---

## 5. Logging System

```
pos docker compose up jellyfin
              │
              ├── Is it an interactive command?
              │   (system-firewall, media-mp4)
              │
              ├── YES ──→ log: "pos system firewall → exit 0"
              │           exec: run directly (no tee)
              │
              └── NO ───→ LOG_DIR=~/.local/share/linux_post_install/logs/
                           │
                           ├── CMD_SAFE = docker_compose_up_jellyfin
                           │
                           ├── LOG_FILE = 20260728_120000_pos_docker_compose_up_jellyfin.log
                           │   (full stdout+stderr via tee)
                           │
                           ├── MAIN_LOG = pos.log
                           │   (appended: timestamp + command + logfile + exit code)
                           │
                           └── exit with command's exit code
```

---

## 6. `pos-vbox` Lifecycle

```
create lab1
    │
    ├── docker run -d --name lab1
    │   --label linux_post_install.vbox=true
    │   [--volume $PWD:/workspace]  ← --dir .
    │   image: ubuntu:latest sleep infinity
    │
    ├── "Enter now? [Y/n]"
    │   ├── Y → docker exec -it lab1 bash
    │   └── n → exit
    │
    └── Container is labeled → ls filters by label

enter lab1
    │
    ├── docker start lab1     ← auto-starts if stopped
    ├── Detect bind mount from labels
    └── docker exec -it lab1 bash

ls
    └── docker ps -a --filter label=linux_post_install.vbox=true
```
