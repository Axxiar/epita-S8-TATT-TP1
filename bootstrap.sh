#!/usr/bin/env bash
# Pentest lab host bootstrap.
#   ./bootstrap.sh           # check prereqs, auto-fix firewall (idempotent)
#   ./bootstrap.sh --clean   # undo firewall changes added by this script
#   ./bootstrap.sh --help    # this help
#
# Run as your normal user. The script uses sudo only where needed (firewall edits).
# Running as root would taint your Vagrant config (~/.vagrant.d) — script rejects it.
set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; D=$'\033[2;37m'; B=$'\033[1m'; N=$'\033[0m'
else
  G="" Y="" R="" D="" B="" N=""
fi
step() { printf '\n%s%s%s\n'         "$B" "$1" "$N"; }
ok()   { printf '  %s✓%s %s\n'       "$G" "$N" "$*"; }
info() { printf '  %si%s %s%s%s\n'   "$D" "$N" "$D" "$*" "$N"; }
warn() { printf '  %s!%s %s\n'       "$Y" "$N" "$*" >&2; }
hint() { printf '    %s%s%s\n'       "$D" "$*" "$N" >&2; }
fail() { printf '  %s✗%s %s\n'       "$R" "$N" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Robustness preflight ─ before anything else.
[[ $EUID -eq 0 ]] && fail "do not run as root — the script uses sudo internally where needed"
have sudo || fail "sudo not found — install it (or run firewall edits manually as root)"

ID=""; [[ -r /etc/os-release ]] && . /etc/os-release && ID="${ID:-}"

# ── Cleanup mode ───────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help)
    sed -n '2,5p' "$0" | sed 's/^# //; s/^#//'
    exit 0
    ;;
  --clean)
    step "Pentest lab — removing firewall rules added by bootstrap"

    if have firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then
      REMOVED=()
      for b in $(sudo firewall-cmd --zone=trusted --list-interfaces 2>/dev/null); do
        [[ "$b" == virbr* ]] || continue
        sudo firewall-cmd --zone=trusted --remove-interface="$b" --permanent >/dev/null
        REMOVED+=("$b")
      done
      (( ${#REMOVED[@]} )) && sudo firewall-cmd --reload >/dev/null
      ok "firewalld    ${REMOVED[*]:-nothing to remove from trusted zone}"
    fi

    if have ufw && systemctl is-active --quiet ufw 2>/dev/null; then
      if sudo grep -q 'virbr+' /etc/ufw/before.rules 2>/dev/null; then
        sudo awk '!/virbr\+/' /etc/ufw/before.rules | sudo tee /etc/ufw/before.rules.new >/dev/null
        sudo mv /etc/ufw/before.rules.new /etc/ufw/before.rules
        sudo ufw reload >/dev/null
        ok "ufw          virbr+ rules removed from before.rules"
      else
        ok "ufw          nothing to remove"
      fi
    fi

    REMOVED_IPT=0
    for c in INPUT FORWARD; do
      while sudo iptables -D "$c" -i virbr+ -j ACCEPT 2>/dev/null; do REMOVED_IPT=1; done
    done
    while sudo iptables -D FORWARD -o virbr+ -j ACCEPT 2>/dev/null; do REMOVED_IPT=1; done
    if (( REMOVED_IPT )); then
      ok "iptables     virbr+ runtime rules removed"
    fi

    step "Done"
    exit 0
    ;;
  '') ;;
  *)
    warn "unknown argument: $1"
    sed -n '2,5p' "$0" | sed 's/^# //; s/^#//'
    exit 1
    ;;
esac

# ── Check + fix mode ───────────────────────────────────────────────────
FAIL=0

step "Pentest lab — host check"
printf '  %schecks vagrant + libvirt + KVM + group + NAT + firewall + virt-manager%s\n' "$D" "$N"
printf '  %sauto-fixes firewall rules; other items show the fix command%s\n'             "$D" "$N"
printf '  %ssudo may be requested — only to read/edit your firewall:%s\n'                "$D" "$N"
printf '    %s· allow libvirt bridges (virbr+) for VM DHCP traffic%s\n'                  "$D" "$N"
printf '    %s· stack-aware (firewalld / ufw / iptables) — idempotent, only when needed%s\n' "$D" "$N"

# 1. vagrant
if have vagrant; then
  ok "vagrant      $(vagrant --version)"
else
  warn "vagrant is not installed"
  case " $ID " in
    *' arch '*)              have yay && hint 'yay -S --needed vagrant' || hint 'install via AUR (vagrant moved to AUR after BSL)' ;;
    *' debian '*)            hint 'sudo apt install -y vagrant' ;;
    *' ubuntu '*)            hint 'sudo apt install -y vagrant   # 24.04+: see https://developer.hashicorp.com/vagrant/install' ;;
    *' fedora '*|*' rhel '*) hint 'sudo dnf install -y vagrant' ;;
    *' nixos '*)             hint 'add pkgs.vagrant to environment.systemPackages' ;;
    *)                       hint 'https://developer.hashicorp.com/vagrant/install' ;;
  esac
  FAIL=1
fi

# 2. vagrant-libvirt plugin
if have vagrant && vagrant plugin list 2>/dev/null | grep -q '^vagrant-libvirt'; then
  ok "plugin       vagrant-libvirt"
else
  warn "vagrant-libvirt plugin missing"
  hint 'vagrant plugin install vagrant-libvirt'
  FAIL=1
fi

# 3. libvirtd reachable
if virsh -c qemu:///system uri >/dev/null 2>&1; then
  ok "libvirt      $(virsh -c qemu:///system uri)"
else
  warn "cannot reach libvirt at qemu:///system"
  hint 'sudo systemctl enable --now libvirtd.socket'
  hint 'sudo usermod -aG libvirt,kvm "$USER" && newgrp libvirt'
  FAIL=1
fi

# 4. /dev/kvm
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  ok "/dev/kvm     read+write"
else
  warn "/dev/kvm missing or not writable — VMs will fall back to slow TCG"
  hint 'enable VT-x/AMD-V in BIOS, then  sudo usermod -aG kvm "$USER" && newgrp kvm'
fi

# 5. libvirt group
if id -nG | grep -qw libvirt; then
  ok "groups       $USER in libvirt"
else
  warn "user '$USER' is not in the libvirt group"
  hint 'sudo usermod -aG libvirt "$USER" && newgrp libvirt'
  FAIL=1
fi

# 6. libvirt 'default' NAT network
if [[ "$(virsh -c qemu:///system net-info default 2>/dev/null | awk '/^Active:/{print $2}')" == "yes" ]]; then
  ok "default NAT  active"
else
  warn "libvirt 'default' NAT network is not active"
  hint 'sudo virsh -c qemu:///system net-start    default'
  hint 'sudo virsh -c qemu:///system net-autostart default'
fi

# 7. Firewall: detect active stack and ensure libvirt bridges (virbr+) are allowed.
#    Wildcard rules cover any current and future bridge — no re-run after vagrant up.
if have firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then
  mapfile -t BR < <(ip -br link 2>/dev/null | awk '/^virbr[0-9]+/ {print $1}')
  CHANGED=0
  for b in "${BR[@]}"; do
    z=$(sudo firewall-cmd --get-zone-of-interface="$b" 2>/dev/null)
    if [[ "$z" != "libvirt" && "$z" != "trusted" ]]; then
      sudo firewall-cmd --zone=trusted --change-interface="$b" --permanent >/dev/null
      CHANGED=1
    fi
  done
  (( CHANGED )) && sudo firewall-cmd --reload >/dev/null
  if (( CHANGED )); then
    ok "firewall     firewalld, libvirt bridges added to trusted zone"
  else
    ok "firewall     firewalld, libvirt bridges already trusted (${BR[*]:-none yet})"
  fi

elif have ufw && systemctl is-active --quiet ufw 2>/dev/null; then
  if sudo grep -q '^-A ufw-before-input -i virbr+' /etc/ufw/before.rules 2>/dev/null; then
    ok "firewall     ufw, virbr+ already allowed in before.rules"
  else
    sudo awk '
      /^COMMIT$/ && !done {
        print "-A ufw-before-input   -i virbr+ -j ACCEPT"
        print "-A ufw-before-forward -i virbr+ -j ACCEPT"
        print "-A ufw-before-forward -o virbr+ -j ACCEPT"
        done=1
      } { print }
    ' /etc/ufw/before.rules | sudo tee /etc/ufw/before.rules.new >/dev/null
    sudo mv /etc/ufw/before.rules.new /etc/ufw/before.rules
    sudo ufw reload >/dev/null
    ok "firewall     ufw, virbr+ wildcard added to before.rules"
  fi

elif sudo iptables -L INPUT   -n 2>/dev/null | head -1 | grep -qE 'policy (DROP|REJECT)' \
  || sudo iptables -L FORWARD -n 2>/dev/null | head -1 | grep -qE 'policy (DROP|REJECT)'; then
  CHANGED=0
  for c in INPUT FORWARD; do
    sudo iptables -C "$c" -i virbr+ -j ACCEPT 2>/dev/null \
      || { sudo iptables -I "$c" -i virbr+ -j ACCEPT; CHANGED=1; }
  done
  sudo iptables -C FORWARD -o virbr+ -j ACCEPT 2>/dev/null \
    || { sudo iptables -I FORWARD -o virbr+ -j ACCEPT; CHANGED=1; }
  if (( CHANGED )); then
    ok "firewall     iptables default-deny, virbr+ ACCEPT inserted (runtime)"
    hint 'persist with: sudo iptables-save | sudo tee /etc/iptables/iptables.rules'
    [[ "$ID" == "nixos" ]] && hint 'NixOS: also set networking.firewall.extraCommands in configuration.nix'
  else
    ok "firewall     iptables, virbr+ already allowed"
  fi

elif have nft && sudo nft list ruleset 2>/dev/null | grep -qE 'hook (input|forward) .*policy drop'; then
  warn "nftables default-deny — libvirt traffic blocked"
  hint 'add to your ruleset: iifname "virbr*" accept (and oifname for forward)'
  [[ "$ID" == "nixos" ]] && hint 'NixOS: set networking.firewall.extraInputRules / extraForwardRules'

else
  ok "firewall     no managed firewall blocking libvirt"
fi

# 8. virt-manager (optional GUI for libvirt) — soft check, never fails.
if have virt-manager; then
  ok "virt-manager $(virt-manager --version 2>&1 | head -1)"
else
  info "virt-manager not installed (optional GUI for libvirt)"
  case " $ID " in
    *' arch '*)                hint 'sudo pacman -S --needed virt-manager' ;;
    *' debian '*|*' ubuntu '*) hint 'sudo apt install -y virt-manager' ;;
    *' fedora '*|*' rhel '*)   hint 'sudo dnf install -y virt-manager' ;;
    *' nixos '*)               hint 'programs.virt-manager.enable = true; in configuration.nix' ;;
    *)                         hint 'install virt-manager via your package manager' ;;
  esac
fi

if (( FAIL )); then
  step "Not ready"
  printf '  %sfix the items above (each shows the install/sudo command), then re-run %s%s\n' "$D" "$0" "$N"
  exit 1
fi

step "Ready — next steps"
printf '  %svagrant up%s              provision both VMs (~3-5 min, boxes cached after first run)\n' "$B" "$N"
printf '  %svagrant ssh kali%s        log into the attacker\n' "$B" "$N"
printf '  %svirt-manager &%s          libvirt GUI (if installed)\n' "$B" "$N"
printf '  %svagrant destroy -f%s      tear down the lab\n' "$B" "$N"
printf '  %s%s --clean%s   undo firewall rules\n' "$B" "$0" "$N"
