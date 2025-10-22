# Proxmox Connection
variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox API username (e.g., root@pam!packer)"
}

variable "proxmox_token" {
  type        = string
  description = "Proxmox API token"
  sensitive   = true
}

variable "insecure_skip_tls_verify" {
  type        = bool
  description = "Skip TLS verification for Proxmox API"
  default     = false
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name to build on"
}

# VM Configuration
variable "vm_id" {
  type        = number
  description = "VM ID for the template"
  default     = 9000
}

variable "vm_name" {
  type        = string
  description = "Temporary VM name during build"
  default     = "rhel9-packer-build"
}

variable "template_name" {
  type        = string
  description = "Final template name"
  default     = "rhel-9-template"
}

# ISO Configuration
variable "iso_file" {
  type        = string
  description = "Path to RHEL 9 ISO on Proxmox (e.g., local:iso/rhel-9.4-x86_64-dvd.iso)"
}

# Hardware Configuration
variable "cpu_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 2
}

variable "cpu_sockets" {
  type        = number
  description = "Number of CPU sockets"
  default     = 1
}

variable "memory" {
  type        = number
  description = "Memory in MB"
  default     = 2048
}

variable "disk_size" {
  type        = string
  description = "Disk size (e.g., 20G)"
  default     = "20G"
}

variable "storage_pool" {
  type        = string
  description = "Storage pool for VM disk"
  default     = "local-zfs"
}

# Network Configuration
variable "network_bridge" {
  type        = string
  description = "Network bridge to use"
  default     = "vmbr1"
}

# SSH Configuration
variable "ssh_username" {
  type        = string
  description = "SSH username for provisioning"
  default     = "packer"
}

variable "ssh_password" {
  type        = string
  description = "SSH password for provisioning"
  sensitive   = true
}
