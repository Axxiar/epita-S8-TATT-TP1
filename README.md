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

Open **Virtual Machine Manager** from your applications menu, double-click
**`tools_kali`** in the list. The Xfce desktop opens — login: `vagrant` / `vagrant`.
Launch terminal / Burp / Wireshark / BloodHound / etc. as you would on a
real Kali install. Target Metasploitable 2 is at `192.168.242.102`.

## Use the lab — CLI

```bash
vagrant ssh kali
nmap -sV 192.168.242.102
```

## Tear down

```bash
vagrant destroy -f
./bootstrap.sh --clean            # remove firewall rules
```

## Logins

- Kali (attacker, GUI + CLI): `vagrant` / `vagrant`
- Metasploitable 2 (target): `msfadmin` / `msfadmin`
