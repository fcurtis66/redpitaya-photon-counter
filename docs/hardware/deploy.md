# Deploy workflow

How code gets from this repo onto a Red Pitaya board. Two-board-aware from the start.

## Model

The Red Pitaya is a **deployment target**, not a development machine. It runs Linux on an ARM core but doesn't host Vivado or your editor. So:

- **Repo lives on your PC.** All editing, version control, and Vivado builds happen locally.
- **Boards receive deliverables**: a built bitstream (`.bit`), the compiled C server, and any helper scripts.
- **Remote-SSH (VSCode extension)** is used for *viewing/running* on the board — not for editing repo files.

```
┌──────────────────── your PC ────────────────────┐        ┌──── Red Pitaya ────┐
│  VSCode (local) ── this repo ── Vivado ──┐      │        │                    │
│                                          │      │  scp/  │  /root/photon_     │
│  Claude Code (terminal in repo)          ├──────┼──rsync─┤  counter/          │
│                                          │      │        │   ├ latest.bit     │
│  VSCode #2 (Remote-SSH) ── inspect/run ──┘      │  ssh   │   ├ tdc_server     │
│                                                 │        │   └ run.sh         │
└─────────────────────────────────────────────────┘        └────────────────────┘
```

## One-time setup

### 1. Find each board on the network

Each Pitaya advertises a hostname like `rp-XXXXXX.local` (mDNS). On your PC:

```bash
ping rp-XXXXXX.local       # replace XXXXXX with the MAC suffix from the board sticker
```

If mDNS doesn't resolve on your network, use the board's DHCP IP (check your router) and consider assigning a static lease.

### 2. SSH keys (no more password prompts)

```bash
# On your PC — generate a key if you don't have one
ssh-keygen -t ed25519 -C "redpitaya"

# Copy public key to each board (default password is 'root')
ssh-copy-id root@rp-AAAAAA.local
ssh-copy-id root@rp-BBBBBB.local

# Then change the root password on each board
ssh root@rp-AAAAAA.local 'passwd'
```

### 3. SSH config for friendly names

Put this in `~/.ssh/config` on your PC:

```
Host board-a
    HostName rp-AAAAAA.local
    User root
    IdentityFile ~/.ssh/id_ed25519

Host board-b
    HostName rp-BBBBBB.local
    User root
    IdentityFile ~/.ssh/id_ed25519
```

After this:

- `ssh board-a` just works.
- In VSCode's Remote-SSH extension, `board-a` and `board-b` appear by name.
- The deploy script targets boards by alias instead of hostname.

### 4. Decide which physical board is A and B and write it down

In `docs/hardware/inventory.md` (create when you have both boards in hand): record each board's MAC, serial, role (A = standard kit, B = external-clock IZD0031), and SSH alias. This matters because the two boards are *not* identical (clock-input wise), and confusing them costs time.

## Daily workflow

```bash
# In VSCode (local) — edit, then commit
git commit -am "feat: ..."

# Build bitstream in Vivado (GUI or tcl) → output lands in bitstreams/

# Deploy to one board
./scripts/deploy.sh board-a

# Open a second VSCode window via Remote-SSH to board-a
# to inspect logs / run the C server / poke at /dev/xdevcfg
```

## Deploy script

See `scripts/deploy.sh` — a thin wrapper around `rsync` + `ssh` that:

1. Pushes the latest bitstream and compiled server to a known directory on the board.
2. Loads the bitstream into the PL via `/dev/xdevcfg`.
3. Optionally restarts the C server.

The script is intentionally small. Claude Code can flesh it out once we know the upstream's exact file names and the compiled-binary location.

## Cross-compilation (later)

Compiling the C server *on* the Pitaya is fine for development (gcc is present). For reproducible builds, set up a cross-compiler on the PC (`arm-linux-gnueabihf-gcc`) and build into `host/build/` — this becomes important once we're iterating fast across two boards. Decide later; flagged in DESIGN.md if/when it matters.

## Two-board specifics

- All deploy commands take a board alias argument. **Never** assume a default.
- When running an experiment, deploy *the same commit* to both boards. The deploy script should print the git SHA it pushed; verify A and B match before trusting any coincidence data.
- Bitstreams should be identical across boards (the modularity goal). If they aren't, that's a design smell — record why in an ADR.
