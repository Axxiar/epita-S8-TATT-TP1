#!/usr/bin/env bash
# Pentest lab host bootstrap.
#   ./bootstrap.sh           # check prereqs, auto-fix firewall (idempotent)
#   ./bootstrap.sh --clean   # undo firewall + storage pool added by this script
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
bad()  { printf '  %s✗%s %s\n'       "$R" "$N" "$*"; }
warn() { printf '  %s!%s %s\n'       "$Y" "$N" "$*" >&2; }
fail() { printf '  %s✗%s %s\n'       "$R" "$N" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Project-scoped libvirt storage pool. Keep in sync with Vagrantfile's POOL_NAME.
# Using a unique name + path so vagrant-libvirt never collides with whatever pool
# already owns /var/lib/libvirt/images on the host (default, vm, images, …).
POOL_NAME="tatt-pentest-lab"
POOL_PATH="/var/lib/libvirt/images/tatt-pentest-lab"

# Robustness preflight ─ before anything else.
[[ $EUID -eq 0 ]] && fail "do not run as root — the script uses sudo internally where needed"
have sudo || fail "sudo not found — install it (or run firewall edits manually as root)"
# Warm sudo timestamp once so subsequent sudo calls don't re-prompt.
[[ "${1:-}" != -h && "${1:-}" != --help ]] && sudo -v

ID=""; ID_LIKE=""; VERSION_ID=""; PRETTY_NAME=""
[[ -r /etc/os-release ]] && . /etc/os-release || true
ID="${ID:-}"; ID_LIKE="${ID_LIKE:-}"; VERSION_ID="${VERSION_ID:-}"; PRETTY_NAME="${PRETTY_NAME:-${ID:-unknown}}"
DISTRO=" ${ID} ${ID_LIKE} "   # space-padded so case '*\' debian \'*' patterns match Mint/Pop/Kali too

# ── Help / clean ───────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help)
    cat <<'EOF'
Pentest lab host bootstrap.
  ./bootstrap.sh           # check prereqs, auto-fix firewall (idempotent)
  ./bootstrap.sh --clean   # undo firewall + storage pool added by this script
  ./bootstrap.sh --help    # this help

Run as your normal user. Sudo is requested only for firewall edits.
EOF
    exit 0
    ;;
  --clean)
    step "Pentest lab — removing resources added by bootstrap"

    # Project pool — only undefine if empty, otherwise the user still has VMs
    # whose disks live in it and the operation would fail anyway.
    if sudo virsh -c qemu:///system pool-info "$POOL_NAME" >/dev/null 2>&1; then
      vols=$(sudo virsh -c qemu:///system vol-list "$POOL_NAME" 2>/dev/null | awk 'NR>2 && NF>0' | wc -l)
      if (( vols == 0 )); then
        sudo virsh -c qemu:///system pool-destroy  "$POOL_NAME" >/dev/null 2>&1 || true
        sudo virsh -c qemu:///system pool-undefine "$POOL_NAME" >/dev/null 2>&1 || true
        ok "pool         $POOL_NAME removed"
      else
        ok "pool         $POOL_NAME kept ($vols volume(s) — run 'vagrant destroy -f' first)"
      fi
    fi

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

    # Drop any traversal ACL we added for the qemu user.
    QEMU_USER=$(sudo sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' /etc/libvirt/qemu.conf 2>/dev/null | head -1)
    if have setfacl && [[ -n "$QEMU_USER" && "$QEMU_USER" != "root" ]]; then
      PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
      REMOVED_ACL=()
      p="$PROJECT_DIR"
      while [[ "$p" != "/" ]]; do
        if getfacl -p -- "$p" 2>/dev/null | grep -q "^user:${QEMU_USER}:"; then
          sudo setfacl -x "u:${QEMU_USER}" -- "$p"
          REMOVED_ACL+=("$p")
        fi
        p=$(dirname "$p")
      done
      (( ${#REMOVED_ACL[@]} )) && ok "9p host path  removed ${QEMU_USER} ACL on ${REMOVED_ACL[*]}"
    fi

    step "Done"
    exit 0
    ;;
  '') ;;
  *)
    printf 'unknown argument: %s\n' "$1" >&2
    printf 'try: ./bootstrap.sh --help\n' >&2
    exit 1
    ;;
esac

# ── Check + fix mode ───────────────────────────────────────────────────
FAIL=0

step "Pentest lab — host check"
printf '  %s%s%s\n' "$D" "$PRETTY_NAME" "$N"

# 1. vagrant
if have vagrant; then
  ok "vagrant       $(vagrant --version)"
else
  bad "vagrant       not installed"
  FAIL=1
fi

# 2. libvirt installed (separate from "reachable" — different fix)
if have virsh; then
  if virsh -c qemu:///system uri >/dev/null 2>&1; then
    ok "libvirt       $(virsh -c qemu:///system uri)"
  else
    bad "libvirt       installed but daemon unreachable at qemu:///system"
    FAIL=1
  fi
else
  bad "libvirt       not installed (need libvirt + qemu)"
  FAIL=1
fi

# 3. vagrant-libvirt plugin
if have vagrant && vagrant plugin list 2>/dev/null | grep -q '^vagrant-libvirt'; then
  ok "plugin        vagrant-libvirt"
else
  bad "plugin        vagrant-libvirt missing"
  FAIL=1
fi

# 4. /dev/kvm
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  ok "/dev/kvm      read+write"
else
  bad "/dev/kvm      missing or not writable"
  FAIL=1
fi

# 5. libvirt group
if id -nG | grep -qw libvirt; then
  ok "groups        $USER ∈ libvirt"
else
  bad "groups        $USER not in libvirt group"
  FAIL=1
fi

# 6. libvirt 'default' NAT network (only meaningful if libvirt is reachable)
if virsh -c qemu:///system uri >/dev/null 2>&1; then
  if [[ "$(virsh -c qemu:///system net-info default 2>/dev/null | awk '/^Active:/{print $2}')" == "yes" ]]; then
    ok "default NAT   active"
  else
    bad "default NAT   inactive"
    FAIL=1
  fi
fi

# 7. Project storage pool (idempotent). Skipped if libvirt unreachable; will run
#    on the next bootstrap once libvirt is fixed.
if virsh -c qemu:///system uri >/dev/null 2>&1; then
  if sudo virsh -c qemu:///system pool-info "$POOL_NAME" >/dev/null 2>&1; then
    pstate=$(sudo virsh -c qemu:///system pool-info "$POOL_NAME" 2>/dev/null | awk '/^State:/{print $2}')
    if [[ "$pstate" != "running" ]]; then
      sudo virsh -c qemu:///system pool-start     "$POOL_NAME" >/dev/null
      sudo virsh -c qemu:///system pool-autostart "$POOL_NAME" >/dev/null 2>&1 || true
      ok "pool          $POOL_NAME started ($POOL_PATH)"
    else
      ok "pool          $POOL_NAME running ($POOL_PATH)"
    fi
  else
    sudo mkdir -p "$POOL_PATH"
    sudo chown root:root "$POOL_PATH"
    sudo chmod 711       "$POOL_PATH"
    sudo virsh -c qemu:///system pool-define-as "$POOL_NAME" dir --target "$POOL_PATH" >/dev/null
    sudo virsh -c qemu:///system pool-start     "$POOL_NAME" >/dev/null
    sudo virsh -c qemu:///system pool-autostart "$POOL_NAME" >/dev/null
    ok "pool          $POOL_NAME created at $POOL_PATH"
  fi
fi

# 8. virt-manager (required — used as the lab GUI)
if have virt-manager; then
  ok "virt-manager  $(virt-manager --version 2>&1 | head -1)"
else
  bad "virt-manager  not installed"
  FAIL=1
fi

# 9. Firewall: detect active stack and ensure libvirt bridges (virbr+) are allowed.
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
    ok "firewall      firewalld, libvirt bridges added to trusted zone"
  else
    ok "firewall      firewalld, libvirt bridges already trusted (${BR[*]:-none yet})"
  fi

elif have ufw && systemctl is-active --quiet ufw 2>/dev/null; then
  if sudo grep -q '^-A ufw-before-input -i virbr+' /etc/ufw/before.rules 2>/dev/null; then
    ok "firewall      ufw, virbr+ already allowed in before.rules"
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
    ok "firewall      ufw, virbr+ wildcard added to before.rules"
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
    ok "firewall      iptables default-deny, virbr+ ACCEPT inserted (runtime)"
  else
    ok "firewall      iptables, virbr+ already allowed"
  fi

elif have nft && sudo nft list ruleset 2>/dev/null | grep -qE 'hook (input|forward) .*policy drop'; then
  warn "firewall      nftables default-deny — add: iifname \"virbr*\" accept (input + forward)"

else
  ok "firewall      no managed firewall blocking libvirt"
fi

# 10. 9p host traversal — only when libvirtd drops privileges to a non-root user
#     (Debian/Ubuntu). Adds traversal-only ACL on blocked ancestors of project dir.
QEMU_USER=$(sudo sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' /etc/libvirt/qemu.conf 2>/dev/null | head -1)
if [[ -n "$QEMU_USER" && "$QEMU_USER" != "root" ]] && id "$QEMU_USER" >/dev/null 2>&1; then
  PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
  BLOCKED=()
  p="$PROJECT_DIR"
  while [[ "$p" != "/" ]]; do
    sudo -u "$QEMU_USER" test -x "$p" 2>/dev/null || BLOCKED+=("$p")
    p=$(dirname "$p")
  done
  if (( ${#BLOCKED[@]} == 0 )); then
    ok "9p host path  $QEMU_USER can traverse $PROJECT_DIR"
  elif have setfacl; then
    for d in "${BLOCKED[@]}"; do sudo setfacl -m "u:${QEMU_USER}:--x" -- "$d"; done
    ok "9p host path  setfacl u:${QEMU_USER}:--x on ${BLOCKED[*]}"
  else
    bad "9p host path  $QEMU_USER blocked at ${BLOCKED[*]} — install package 'acl'"
    FAIL=1
  fi
fi

# ── Result ─────────────────────────────────────────────────────────────
if (( FAIL )); then
  step "Not ready — run the block below (copy-paste, safe to re-run):"
  printf '\n'

  PLUGIN_VIA_PKG=0   # set to 1 when distro ships vagrant-libvirt as a system package

  case "$DISTRO" in
    *' arch '*)
      # base-devel needed so `vagrant plugin install vagrant-libvirt` can compile
      # ruby-libvirt's native extension. Arch's vagrant is in the AUR (post-BSL).
      printf '  %syay -S --needed vagrant libvirt qemu-full virt-manager dnsmasq base-devel%s\n' "$B" "$N"
      ;;
    *' debian '*|*' ubuntu '*)
      # Vagrant on Ubuntu 24.04+ (and recommended for all versions): install from
      # HashiCorp's official apt repo — verbatim from developer.hashicorp.com/vagrant/install.
      # libvirt-daemon-system already pulls dnsmasq-base; do NOT add full dnsmasq (port 53 clash).
      # The -dev / build packages match the upstream vagrant-libvirt install guide; required
      # so `vagrant plugin install vagrant-libvirt` can compile ruby-libvirt natively.
      printf '  %swget -O - https://apt.releases.hashicorp.com/gpg \\%s\n' "$B" "$N"
      printf '  %s  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg%s\n' "$B" "$N"
      printf '  %secho "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \\%s\n' "$B" "$N"
      printf '  %s  https://apt.releases.hashicorp.com $(grep -oP '"'"'(?<=UBUNTU_CODENAME=).*'"'"' /etc/os-release || lsb_release -cs) main" \\%s\n' "$B" "$N"
      printf '  %s  | sudo tee /etc/apt/sources.list.d/hashicorp.list%s\n' "$B" "$N"
      printf '  %ssudo apt update && sudo apt install -y \\%s\n' "$B" "$N"
      printf '  %s    vagrant libvirt-daemon-system libvirt-clients \\%s\n' "$B" "$N"
      printf '  %s    qemu-system-x86 virt-manager ebtables \\%s\n' "$B" "$N"
      printf '  %s    libvirt-dev libxslt-dev libxml2-dev zlib1g-dev \\%s\n' "$B" "$N"
      printf '  %s    ruby-dev pkg-config gcc make%s\n' "$B" "$N"
      ;;
    *' fedora '*|*' rhel '*)
      # Fedora ships vagrant-libvirt as a real rpm — no `vagrant plugin install` needed.
      printf '  %ssudo dnf install -y vagrant vagrant-libvirt @virtualization virt-manager%s\n' "$B" "$N"
      PLUGIN_VIA_PKG=1
      ;;
    *' nixos '*)
      printf '  %s# Add to configuration.nix, then sudo nixos-rebuild switch:%s\n' "$D" "$N"
      printf '  %s  environment.systemPackages = with pkgs; [ vagrant ];%s\n' "$B" "$N"
      printf '  %s  virtualisation.libvirtd.enable = true;%s\n' "$B" "$N"
      printf '  %s  programs.virt-manager.enable = true;%s\n' "$B" "$N"
      printf '  %s  users.users.<you>.extraGroups = [ "libvirt" "kvm" ];%s\n' "$B" "$N"
      ;;
    *)
      printf '  %s# Unknown distro — install via your package manager:%s\n' "$D" "$N"
      printf '  %s#   vagrant, libvirt, qemu, virt-manager%s\n' "$D" "$N"
      ;;
  esac

  printf '  %ssudo systemctl enable --now libvirtd.socket%s\n'                "$B" "$N"
  printf '  %ssudo usermod -aG libvirt,kvm "$USER" && newgrp libvirt%s\n'     "$B" "$N"
  if (( ! PLUGIN_VIA_PKG )); then
    printf '  %svagrant plugin install vagrant-libvirt%s\n'                    "$B" "$N"
  fi

  if [[ ! -e /dev/kvm ]]; then
    printf '\n  %s# /dev/kvm missing — also enable VT-x/AMD-V in BIOS%s\n' "$D" "$N"
  fi
  if virsh -c qemu:///system uri >/dev/null 2>&1 \
     && [[ "$(virsh -c qemu:///system net-info default 2>/dev/null | awk '/^Active:/{print $2}')" != "yes" ]]; then
    printf '  %ssudo virsh -c qemu:///system net-start default && \\%s\n' "$B" "$N"
    printf '  %ssudo virsh -c qemu:///system net-autostart default%s\n' "$B" "$N"
  fi

  printf '\n  %sthen re-run ./bootstrap.sh%s\n' "$D" "$N"
  exit 1
fi

step "Ready — run the lab"
printf '  %s1.%s vagrant up                    %sprovision both VMs (~3-5 min first time)%s\n' "$B" "$N" "$D" "$N"
printf '  %s2.%s vagrant ssh kali              %sor: virt-manager → tools_kali (graphical)%s\n' "$B" "$N" "$D" "$N"
printf '  %s3.%s nmap -sV 192.168.242.102      %sscan the target from inside Kali%s\n' "$B" "$N" "$D" "$N"
printf '  %s4.%s msfconsole                    %sexploit%s\n' "$B" "$N" "$D" "$N"
printf '\n  %sTear down:%s vagrant destroy -f      %sUndo bootstrap:%s ./bootstrap.sh --clean\n' "$D" "$N" "$D" "$N"
