# How-To: `pos docker`

Watch containers and spin up disposable VMs.
Tools: `ps`, `health`, `stack`, `vbox`.

| Tool | What it does |
|------|--------------|
| `pos docker ps` | Enhanced container overview (health, IPs, ports, uptime) |
| `pos docker health` | One-glance health dashboard (exits 1 if unhealthy) |
| `pos docker stack` | Containers grouped by compose stack (`-a` includes stopped) |
| `pos docker vbox` | Disposable Docker containers as lightweight VMs |

---

## `pos docker ps` — better `docker ps`

```bash
pos docker ps
```

Enhanced overview: health status, uptime, IPs, port mappings.

**Recipe:** pair with the daily digest — the health report summarizes
unhealthy/restarting containers; when it flags one, `pos docker ps` shows the
details (IPs/ports/uptime) to investigate.

---

## `pos docker health` — is everything healthy?

```bash
pos docker health
```

Prints health + uptime per container; **exits 1 if any container is unhealthy**
(useful for scripts/CI/monitoring).

**Recipe:** fail your own script or monitor on unhealthy containers:
```bash
pos docker health >/dev/null || { echo "Docker unhealthy" >&2; exit 1; }
```

**Troubleshooting:** a container shows no health status if its image has no
`HEALTHCHECK` — that's fine, it counts as "no healthcheck configured" (exit 0),
not unhealthy.

---

## `pos docker stack` — containers by compose stack

```bash
pos docker stack          # running containers grouped by compose project
pos docker stack -a       # include stopped/exited containers
```

Grouped view of your compose deployments: every stack is a section with its
services (container name, status, ports); containers started outside compose
land in a `Standalone` group at the end. `-a` behaves like `docker ps -a` and
also shows exited services (e.g. one-shot migration jobs that `docker ps`
hides).

**Recipe:** confirm a container joined the right stack:

```bash
pos docker stack | grep -A5 <svc>
```

**Recipe:** spot what's restarting across all stacks at a glance (yellow
`Restarting` / red `Exited` statuses stand out on a terminal).

---

## `pos docker vbox` — disposable VMs

Docker containers with a bind-mounted host dir so files persist even after the
container is removed. Great for labs, downloads, kali, throwaway services.

```bash
pos docker vbox create lab1                        # default dir ~/lab1
pos docker vbox create lab1 --dir .                # files land in cwd
pos docker vbox create lab1 --dir /mnt/data/lab1
pos docker vbox create kali kalilinux/kali-rolling # custom image
pos docker vbox create lab --gpu --cpus 4 --memory 8g
pos docker vbox create iot --device /dev/ttyUSB0 --port 8080:80
pos docker vbox enter lab1
pos docker vbox stop lab1
pos docker vbox start lab1
pos docker vbox rm lab1
pos docker vbox ls
```

**Interactive create:** bare `pos docker vbox` (or the menu's "Create a VM")
walks a name prompt → category hub → review screen that renders the exact
`docker create` plan before anything is pulled; confirming runs the same
`create` verb as the CLI. Categories: image quick-picks, GPU/Nvidia (offers
`--gpus all` when the Nvidia container toolkit is present, explicit device
nodes otherwise, info line when no GPU exists), host devices (USB, serial,
video/sound, disks — system disks labelled), extra host-dir mounts, port
publishes, CPU/RAM limits. Quitting or EOF at any point discards — nothing is
created without an explicit `y` at the review.

**Recipe:** a disposable browsing/download box:
```bash
pos docker vbox create dl --dir /mnt/data/dl
pos docker vbox enter dl       # work inside; files persist in /mnt/data/dl
pos docker vbox rm dl          # container gone, files kept
```

**Troubleshooting:**
- `enter` needs a shell/SSH-capable image; `kalilinux/kali-rolling` works.
- If files "disappear" after `rm`, check you used `--dir` on a real path — the
  container image changes are lost, only the mounted dir persists.
- `--gpu` needs `nvidia-container-toolkit`; without it, pass explicit nodes
  instead (`--device /dev/nvidia0 --device /dev/nvidiactl --device /dev/nvidia-uvm`).

---

## Related

- Reference: [DOC/POS.md → docker](../POS.md)
- Container health in the daily digest: [system.md → health](system.md)
