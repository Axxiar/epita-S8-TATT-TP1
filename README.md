# EPITA S8 — TATT TP1

Pentest lab: Metasploitable 2 + Kali, isolated libvirt network.

## Setup

```bash
git clone https://github.com/KazeTachinuu/epita-S8-TATT-TP1.git
cd epita-S8-TATT-TP1
./bootstrap.sh
vagrant up
```

## Use

```bash
vagrant ssh kali                  # vagrant / vagrant
nmap -sV 192.168.242.102          # target = Metasploitable 2
```

## Tear down

```bash
vagrant destroy -f
./bootstrap.sh --clean            # remove firewall rules
```

## Logins

- Kali: `vagrant` / `vagrant` (desktop: `kali` / `kali`)
- Metasploitable 2: `msfadmin` / `msfadmin`
