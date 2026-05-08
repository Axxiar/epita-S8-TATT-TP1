# EPITA S8 — TATT TP1

Reproducible pentest lab for the EPITA TATT course: Metasploitable 2 (target)
and Kali rolling (attacker) on a host-isolated libvirt network.

## Components

| VM                | IP                | Login                   |
|-------------------|-------------------|-------------------------|
| `kali`            | `192.168.242.101` | `vagrant` / `vagrant`   |
| `metasploitable2` | `192.168.242.102` | `msfadmin` / `msfadmin` |

Network: `192.168.242.0/24` — isolated, no internet reach (`libvirt__forward_mode: "none"`).

## Setup

```bash
git clone https://github.com/KazeTachinuu/epita-S8-TATT-TP1.git
cd epita-S8-TATT-TP1
./bootstrap.sh
vagrant up
```

`bootstrap.sh` checks `vagrant` + `vagrant-libvirt` + `libvirtd` + KVM + group
membership + the libvirt `default` network, then auto-fixes the host firewall
(UFW / firewalld / iptables / nftables) so libvirt bridges aren't blocked.
Anything still missing is reported with the exact install command for your
distro (Arch, Debian/Ubuntu, Fedora, NixOS).

First `vagrant up` downloads ~6 GB of Vagrant boxes; subsequent runs are fast.

## Usage

**GUI (recommended).** Launch **Virtual Machine Manager** from your application
menu, double-click `tools_kali`. The Xfce desktop opens — log in as `vagrant`
(password `vagrant`), then use any tool as you would on a normal Kali install.

**CLI.**

```bash
vagrant ssh kali
nmap -sV 192.168.242.102
msfconsole
```

## Shared folder (Kali only)

The repo directory is rsynced to `/vagrant` inside Kali at `vagrant up` time
(one-way copy — not a live mount). Use `vagrant rsync` after editing files on
the host to push changes again. Metasploitable 2 has the share disabled.

## Tear down

```bash
vagrant destroy -f         # remove the VMs and their disks
./bootstrap.sh --clean     # remove the firewall rules added during setup
```
