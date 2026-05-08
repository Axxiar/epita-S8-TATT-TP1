# EPITA S8 — TATT TP1

Pentest lab: Metasploitable 2 + Kali, isolated libvirt network.

## Setup

```bash
git clone https://github.com/KazeTachinuu/epita-S8-TATT-TP1.git
cd epita-S8-TATT-TP1
./bootstrap.sh
vagrant up
```

## Use the lab — GUI (recommended)

```bash
virt-manager &
```

Double-click **`tools_kali`** in the list → the Xfce desktop opens (login `kali` / `kali`).
From there, launch terminal/Burp/Wireshark/BloodHound/etc. like a normal Kali install.
Target Metasploitable 2 lives at `192.168.242.102`.

## Use the lab — CLI

```bash
vagrant ssh kali                  # login: vagrant / vagrant
nmap -sV 192.168.242.102          # target = Metasploitable 2
```

## Tear down

```bash
vagrant destroy -f
./bootstrap.sh --clean            # remove firewall rules
```

## Logins

- Kali: `vagrant` / `vagrant` (CLI) — `kali` / `kali` (GUI)
- Metasploitable 2: `msfadmin` / `msfadmin`
