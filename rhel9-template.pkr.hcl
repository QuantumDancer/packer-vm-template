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
    iso_file         = var.iso_file
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
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
  }

  # Boot and Installation
  boot_command = [
    "<up>",
    "e",
    "<down><down><end><wait>",
    " text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<leftCtrlOn>x<leftCtrlOff>"
  ]
  boot_wait = "10s"

  # HTTP Server for Kickstart
  http_directory = "http"
  http_port_min  = 8100
  http_port_max  = 8200

  # SSH Configuration
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 20

  # Template Conversion
  template_name        = var.template_name
  template_description = "RHEL 9 VM template built with Packer on ${formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())}"

  # Cloud-Init
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool
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
