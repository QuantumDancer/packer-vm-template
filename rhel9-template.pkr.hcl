packer {
  required_plugins {
    proxmox = {
      version = "~> 1.2.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-iso" "rhel9" {
  # Proxmox Connection
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.insecure_skip_tls_verify
  node                     = var.proxmox_node

  # VM Settings
  vm_id   = var.vm_id
  vm_name = var.vm_name

  # ISO Settings
  boot_iso {
    iso_file = var.iso_file
    unmount  = true
  }

  # Kickstart delivery: anaconda automatically loads ks.cfg from a volume
  # labeled OEMDRV, so the installer needs no network access back to the
  # machine running Packer (the VM VLAN blocks traffic to private subnets).
  additional_iso_files {
    device           = "ide3"
    cd_files         = ["kickstart/ks.cfg"]
    cd_label         = "OEMDRV"
    iso_storage_pool = "local"
    unmount          = true
  }

  # System Settings
  qemu_agent      = true
  scsi_controller = "virtio-scsi-single"
  os              = "l26"

  # Disks
  disks {
    disk_size    = var.disk_size
    storage_pool = var.storage_pool
    type         = "scsi"
  }

  # CPU
  cores    = var.cpu_cores
  sockets  = var.cpu_sockets
  cpu_type = "host"

  # Memory
  memory = var.memory

  # Network
  network_adapters {
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = false
  }


  # BIOS
  bios = "ovmf"
  efi_config {
    efi_storage_pool = var.storage_pool
    efi_type         = "4m"
  }

  # Boot and Installation: select "Install Red Hat Enterprise Linux" (skips
  # the default media check); the kickstart comes from the OEMDRV CD.
  boot_command = ["<up><wait><enter>"]
  boot_wait    = "10s"

  # SSH Configuration
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 20

  # Template Conversion. No cloud-init drive is baked in: Proxmox puts it on
  # the IDE bus, which RHEL 9 guests booted via OVMF cannot see. Clones must
  # attach their own drive on the SCSI bus (terraform-infra uses scsi30).
  template_name        = var.template_name
  template_description = "RHEL 9 VM template built with Packer on ${formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())}"
}

build {
  sources = ["source.proxmox-iso.rhel9"]

  provisioner "shell" {
    script = "scripts/cloud-init-setup.sh"
  }

  provisioner "shell" {
    script = "scripts/template-cleanup.sh"
  }
}
