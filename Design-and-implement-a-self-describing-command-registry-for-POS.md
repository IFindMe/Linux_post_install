Design and implement a **self-describing command registry** for POS.

The goal is NOT to redesign the POS CLI hierarchy.

Keep the existing horizontal command philosophy:

```text
pos <category>
pos <category> <tool>
pos <category> <tool> <action>
```

Examples:

```text
pos ai ask
pos ai chat
pos ai alias create

pos network scan
pos network checkport
pos network download add
pos network download pause

pos share nfs client mount
pos share smb server adduser

pos docker ps
pos docker compose restart
```

The command paths are already good. Preserve them.

---

# 1. Core idea

POS should become **self-describing**.

Today, information about commands can become duplicated across:

* `pos tree`
* `pos help`
* `pos menu`
* `pos config`
* `pos dashboard`
* command-specific documentation

Create a common command metadata/registry system so these interfaces can consume the same source of truth.

Conceptually:

```text
                 POS COMMAND REGISTRY
                         │
          ┌──────────────┼──────────────┐
          │              │              │
         tree           help           menu
          │                             │
          └──────────────┬──────────────┘
                         │
                     dashboard
```

The registry describes commands.

The command implementation remains separate.

---

# 2. Separation of metadata and implementation

Do NOT turn every command into a large framework object.

Keep this separation:

```text
COMMAND METADATA
    │
    ├── name
    ├── description
    ├── actions
    ├── arguments
    ├── options
    ├── dependencies
    ├── configuration
    └── examples

COMMAND IMPLEMENTATION
    │
    └── actual bash/python/etc. code
```

Metadata tells POS **what the command is**.

The implementation tells the system **how it works**.

Do not duplicate command implementation inside the registry.

---

# 3. Metadata should be progressive

Do not require every command to define every field.

Minimum metadata:

```text
name
description
```

Optional metadata:

```text
actions
arguments
options
dependencies
configuration
examples
```

A very simple command should remain very simple.

Example:

```text
network/scan

name:
    scan

description:
    Scan hosts in a CIDR network.
```

A complex command can describe more:

```text
network/download

name:
    download

description:
    Manage downloads through aria2.

actions:
    add
    remove
    pause
    resume
    restart
    retry
    status
    files
    peers

dependencies:
    aria2c
```

---

# 4. Registry hierarchy

The registry must preserve the existing POS hierarchy.

Example:

```text
pos
├── ai
│   ├── ask
│   ├── chat
│   └── alias
│       ├── create
│       ├── edit
│       ├── list
│       ├── remove
│       └── show
│
├── network
│   ├── scan
│   ├── ip
│   ├── checkport
│   └── download
│       ├── add
│       ├── pause
│       ├── resume
│       └── status
│
└── share
    ├── nfs
    │   ├── client
    │   │   ├── mount
    │   │   └── unmount
    │   └── server
    │       ├── share
    │       └── unshare
    └── smb
        ├── client
        └── server
```

The registry should represent this structure naturally.

Do NOT flatten everything into one giant list.

---

# 5. Example metadata

Use a format appropriate to the existing POS implementation.

For example, conceptually:

```yaml
name: download

description: Manage downloads through aria2.

actions:
  - name: add
    description: Add a download.

  - name: pause
    description: Pause a download.

  - name: resume
    description: Resume a download.

  - name: status
    description: Show download status.

dependencies:
  - aria2c
```

Another example:

```yaml
name: scan

description: Scan hosts in a CIDR range.

arguments:
  - name: cidr
    required: true
    description: Network range to scan.

dependencies:
  - ping
```

Do not copy these examples literally if POS already has an established format. Adapt the implementation to existing project conventions.

---

# 6. `pos tree`

`pos tree` must obtain command information from the registry instead of maintaining a separate hardcoded command tree.

Example:

```text
$ pos tree

pos
├── ai
│   ├── ask
│   ├── chat
│   └── alias
│       ├── create
│       ├── edit
│       ├── list
│       ├── remove
│       └── show
├── network
│   ├── scan
│   ├── ip
│   ├── checkport
│   └── download
│       ├── add
│       ├── pause
│       ├── resume
│       └── status
└── share
```

The tree must be generated from discovered command metadata.

---

# 7. `pos help`

Help should consume the same metadata.

Example:

```text
$ pos help network download

network download

Manage downloads through aria2.

Actions:
  add       Add a download
  pause     Pause a download
  resume    Resume a download
  status    Show download status

Dependencies:
  aria2c
```

Do not maintain a separate help description if the metadata already contains the information.

---

# 8. `pos menu`

The interactive menu should discover commands from the same registry.

Example:

```text
POS
├── AI
├── Network
│   ├── Scan
│   ├── IP
│   ├── Check Port
│   └── Download
│       ├── Add
│       ├── Pause
│       ├── Resume
│       └── Status
├── Share
└── System
```

Adding a new command should automatically make it available to the menu without manually editing menu code.

---

# 9. `pos config`

Configuration metadata should be discoverable when applicable.

Example:

```text
network/download

configuration:
  download_dir:
    type: path
    description: Default download directory

  rpc_port:
    type: integer
    description: aria2 RPC port
```

`pos config` can then discover configurable commands from the registry.

A command that has no configuration should simply expose none.

Do not force configuration metadata onto commands that do not need it.

---

# 10. `pos dashboard`

The dashboard should eventually consume the same registry.

The registry can tell the dashboard:

```text
command
description
status/configuration information
available actions
```

Do not create a second dashboard-specific command definition.

---

# 11. Command discovery

The registry should support discovering installed commands.

Conceptually:

```text
command implementation
        +
command metadata
        ↓
      registry
```

POS can then answer:

```text
What commands exist?
What does this command do?
What actions does it support?
What dependencies does it require?
What configuration does it expose?
```

This makes the CLI self-describing.

---

# 12. Important rule: no unnecessary framework

Do NOT build a giant abstraction layer.

Avoid:

```text
CommandBase
AbstractCommand
CommandFactory
CommandProvider
CommandManager
CommandController
CommandResolver
CommandRegistryManager
```

unless the existing architecture genuinely requires them.

Prefer the smallest implementation that provides:

```text
discover
register
lookup
iterate
describe
```

The registry should be a practical internal mechanism, not a new programming language or framework.

---

# 13. Existing commands must keep working

This work must not unnecessarily change existing command paths.

For example:

```text
pos network scan
```

must remain:

```text
pos network scan
```

Do not change it to:

```text
pos network scanner run
```

or:

```text
pos network tools scan execute
```

Likewise:

```text
pos ai alias create
```

must remain the same.

The registry describes the existing CLI. It does not redesign it.

---

# 14. Convention for new POS commands

Every new POS command should follow this process:

```text
1. Decide category.
2. Decide tool.
3. Decide action if needed.
4. Implement the command.
5. Add its metadata.
6. Register/discover it.
7. Verify it appears in `pos tree`.
8. Verify it appears in `pos help`.
9. Verify it appears in `pos menu` when applicable.
```

Example:

A new feature is a system service monitor.

Use:

```text
pos system services
```

If actions are needed:

```text
pos system services list
pos system services status
pos system services restart
```

Metadata conceptually:

```yaml
name: services

description: Manage system services.

actions:
  - name: list
    description: List available services.

  - name: status
    description: Show service status.

  - name: restart
    description: Restart a service.
```

After adding it:

```text
pos tree
```

automatically shows:

```text
system
└── services
    ├── list
    ├── status
    └── restart
```

No separate tree definition should be required.

---

# 15. Source of truth

There must be **one authoritative source for command metadata**.

Do not manually maintain:

```text
tree definitions
menu definitions
help definitions
dashboard command definitions
```

separately.

Instead:

```text
                 metadata
                    │
                    ▼
                 registry
          ┌─────────┼─────────┐
          ▼         ▼         ▼
        tree      help      menu
                              │
                           dashboard
```

This is the main architectural goal.

---

# 16. Keep the filesystem and implementation compatible

Do not require the whole project to be rewritten at once.

Use an incremental approach.

Existing commands may continue working using their current implementation.

Add registry metadata around them.

Over time, migrate commands to the convention.

The migration should not require rewriting working commands merely to satisfy the registry.

---

# 17. Success criteria

The implementation is successful when:

```text
Adding one new command
        ↓
adding its metadata
        ↓
POS discovers it
        ↓
pos tree shows it
pos help knows it
pos menu can discover it
pos config can discover it when applicable
pos dashboard can consume it when applicable
```

without manually updating multiple unrelated files.

The CLI hierarchy remains horizontal, simple, readable, and backward compatible.

The key idea is:

> **POS commands describe themselves once, and POS uses that description everywhere.**

