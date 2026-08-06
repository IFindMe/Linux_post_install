# How-To: `pos ssh`

SSH agent key management. Tool: `load-keys`.

| Tool | What it does |
|------|--------------|
| `pos ssh load-keys` | Load all `~/.ssh/id_*` private keys into the ssh-agent |

---

## `pos ssh load-keys` — keys into the agent

```bash
pos ssh load-keys
```

Loads every `~/.ssh/id_*` private key into a shared ssh-agent. Skips `.pub`,
`known_hosts`, `authorized_keys`, and `config`; validates keys before adding.

Requires the system-wide `ssh-agent.service` (socket `/run/ssh-agent/socket`),
installed by `postinstall.sh`. `~/.bashrc` exports `SSH_AUTH_SOCK` to it, so
agent-using tools (git, ssh, rsync) work from any session.

**Recipe:** after a fresh boot, before pushing to your server:
```bash
pos ssh load-keys && ssh -T git@gitea.skink-platy.ts.net
```

**Troubleshooting:**
- "Could not connect to agent" → `ssh-agent.service` isn't running:
  `sudo systemctl start ssh-agent && sudo systemctl enable ssh-agent`, then
  re-login or re-source `.bashrc` for `SSH_AUTH_SOCK`.
- Key not loaded → confirm it's `~/.ssh/id_*` (non-`.pub`), perms `600`, and has
  no passphrase prompt issue; use `ssh-add -l` to list loaded keys.

---

## Related

- Service details: [DOC/SYSTEMD.md → ssh-agent.service](../SYSTEMD.md)
- Reference: [DOC/POS.md → ssh](../POS.md)
