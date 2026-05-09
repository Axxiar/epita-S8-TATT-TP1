# EPITA S8 — TATT TP1

Pentest lab: Metasploitable 2 + Kali on an isolated libvirt network.

| VM                | IP                | Login                   |
|-------------------|-------------------|-------------------------|
| `kali`            | `192.168.242.101` | `vagrant` / `vagrant`   |
| `metasploitable2` | `192.168.242.102` | `msfadmin` / `msfadmin` |

Lab network `192.168.242.0/24` is host-only — no internet reach.

## Setup

```bash
git clone https://github.com/KazeTachinuu/epita-S8-TATT-TP1.git
cd epita-S8-TATT-TP1
./bootstrap.sh
vagrant up
```

`bootstrap.sh` checks vagrant + libvirt + KVM + firewall across
Arch / Debian / Ubuntu / Fedora / NixOS, and prints the install command for
anything missing. First `vagrant up` downloads ~6 GB of boxes (cached after).

## Use

**GUI** — open *Virtual Machine Manager*, double-click `tools_kali`.
**CLI** — `vagrant ssh kali`.

Then attack from inside Kali:

```bash
nmap -sV 192.168.242.102
msfconsole
```

The repo dir is live-mounted at `/vagrant` inside Kali (9p, bidirectional).
Drop loot there and it appears in the host repo dir instantly.

## Stop / resume

```bash
vagrant halt [name]   # graceful shutdown — disks and state kept
vagrant up   [name]   # boot back up
vagrant halt -f       # hard power-off if a VM hangs
```

`vagrant suspend` / `vagrant resume` for faster resume (saves RAM to disk).
`vagrant status` shows current state.

## Tear down

```bash
vagrant destroy -f
./bootstrap.sh --clean
```
