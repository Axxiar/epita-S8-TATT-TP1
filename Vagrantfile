# -*- mode: ruby -*-
# Pentest lab: Metasploitable 2 (target) + Kali (attacker) on a shared private network.
#
#   vagrant up           # provision both VMs (downloads ~6 GB the first time)
#   vagrant status       # see state and IPs
#   vagrant ssh kali     # log in to attacker
#   vagrant destroy -f   # tear it all down
#
# Requires: vagrant + vagrant-libvirt plugin + libvirtd running.
# Run ./bootstrap.sh first to verify host prereqs and firewall.

Vagrant.configure("2") do |config|
  # Force a known TERM so vim/colors/clear work over `vagrant ssh`.
  config.ssh.extra_args = ["-o", "SetEnv=TERM=xterm"]

  # ── Target: Metasploitable 2 ────────────────────────────────────────
  config.vm.define "metasploitable2" do |ms2|
    ms2.vm.box       = "deargle/metasploitable2"
    ms2.ssh.username = "msfadmin"
    ms2.ssh.password = "msfadmin"
    ms2.vm.synced_folder ".", "/vagrant", disabled: true
    ms2.vm.network :private_network,
      ip: "192.168.242.102",
      libvirt__forward_mode: "none"
    ms2.vm.provider :libvirt do |v|
      v.memory         = 1024
      v.cpus           = 1
      v.nic_model_type = "rtl8139"   # MS2's 2.6.24 kernel lacks reliable virtio
    end
  end

  # ── Attacker: Kali rolling ──────────────────────────────────────────
  config.vm.define "kali" do |k|
    k.vm.box = "kalilinux/rolling"
    k.vm.network :private_network,
      ip: "192.168.242.101",
      libvirt__forward_mode: "none"
    k.vm.provider :libvirt do |v|
      v.memory        = 4096
      v.cpus          = 2
      v.graphics_type = "spice"   # snappy desktop (Xfce already inside the box)
      v.video_type    = "qxl"
    end
  end
end
