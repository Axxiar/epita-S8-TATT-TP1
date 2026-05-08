# EPITA S8 — TATT TP1

A reproducible local pentest lab: **Metasploitable 2** (target) and **Kali rolling** (attacker)
on an isolated libvirt network.

```
   [ kali (192.168.242.101) ] ──── 192.168.242.0/24 (isolated) ────► [ metasploitable2 (192.168.242.102) ]
                                       virbr+, no <forward>
```

## Quick start

```bash
git clone https://github.com/KazeTachinuu/epita-S8-TATT-TP1.git
cd epita-S8-TATT-TP1
./bootstrap.sh        # check prereqs, auto-fix firewall (idempotent)
vagrant up            # provision both VMs (~3-5 min on cached boxes; ~6 GB first run)
```

After provisioning:

```bash
vagrant ssh kali                      # log into the attacker (vagrant / vagrant)
nmap -sV 192.168.242.102               # from inside Kali — enumerate the target
msfconsole                             # then 'search metasploitable' / 'use exploit/...'
```

## Lab info

| | Box | IP | Login |
|---|---|---|---|
| Target  | `deargle/metasploitable2` | `192.168.242.102` | `msfadmin` / `msfadmin` |
| Attacker | `kalilinux/rolling` | `192.168.242.101` | `vagrant` / `vagrant` (`kali` / `kali` for desktop) |

The lab network is **isolated** (`libvirt__forward_mode: "none"`) — VMs reach each
other and the host, but cannot reach the internet through it. Each VM also has a
second NIC on Vagrant's management network, which is NAT'd, so `apt install` from
inside Kali still works.

## GUI desktop

Kali ships with Xfce already installed. After `vagrant up`:

```bash
yay -S --needed virt-manager     # one-time
virt-manager                     # double-click 'tools_kali' → desktop console
```

## Lifecycle

```bash
vagrant status            # see state
vagrant halt              # stop without destroying
vagrant up                # resume
vagrant destroy -f        # nuke both VMs
./bootstrap.sh --clean    # remove the firewall rules added by bootstrap
./bootstrap.sh --help     # short help
```

## Prerequisites

The `bootstrap.sh` script auto-detects and either fixes (firewall) or shows the
exact install command for:

- `vagrant` + `vagrant-libvirt` plugin
- `libvirtd` reachable, user in `libvirt` group, `/dev/kvm` writable
- libvirt `default` NAT network active
- Firewall (UFW / firewalld / iptables / nftables / NixOS) — wildcard ACCEPT on `virbr+`
- `virt-manager` (optional GUI)

Run as your **regular user** — the script refuses to run as root and uses `sudo`
internally only where required.

## Files

| File | Purpose |
|---|---|
| `Vagrantfile` | Declarative lab definition — only official `vagrant-libvirt` patterns |
| `bootstrap.sh` | Cross-distro host check + idempotent firewall fix |

## License

MIT — see [LICENSE](LICENSE) (or no license = "all rights reserved" if you skip it).
