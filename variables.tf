variable "talos_cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "talos_version" {
  description = "Talos OS version used for both image download and machine configuration generation"
  type        = string
}

variable "talos_schematic_id" {
  description = "Talos Factory schematic ID used to build the image URL"
  type        = string
}

variable "talos_arch" {
  description = "Talos architecture"
  type        = string
  default     = "amd64"
}

variable "kubernetes_version" {
  description = "Optional Kubernetes version for generated Talos machine configuration"
  type        = string
  default     = null
}

variable "cluster_endpoint" {
  description = "Optional Kubernetes API endpoint (for example, a load balancer URL). If null, the first master IP is used"
  type        = string
  default     = null
}

variable "proxmox_iso_datastore" {
  description = "Proxmox datastore where the Talos qcow2 image is downloaded"
  type        = string
  default     = "local"
}

variable "proxmox_default_vm_datastore" {
  description = "Default Proxmox datastore for VM disks when a node does not define datastore_id"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_default_bridge" {
  description = "Default Proxmox network bridge when a node does not define bridge"
  type        = string
  default     = "vmbr0"
}

variable "proxmox_default_vlan_id" {
  description = "Default Proxmox VLAN ID when a node does not define vlan_id"
  type        = number
  default     = null
}

variable "proxmox_default_cpu_type" {
  description = "Default Proxmox emulated CPU type when a node does not define cpu_type"
  type        = string
  default     = "x86-64-v2-AES"
}

variable "proxmox_machine_type" {
  description = "Proxmox machine type for VMs"
  type        = string
  default     = "q35"
}

variable "proxmox_efi_disk_type" {
  description = "EFI disk type used with OVMF BIOS"
  type        = string
  default     = "4m"
}

variable "proxmox_efi_pre_enrolled_keys" {
  description = "Whether to enable pre-enrolled secure boot keys on EFI disk"
  type        = bool
  default     = false
}

variable "proxmox_vm_id_start" {
  description = "First VM ID to assign in Proxmox; IDs are allocated sequentially from this value"
  type        = number
  default     = 100

  validation {
    condition     = var.proxmox_vm_id_start >= 100
    error_message = "proxmox_vm_id_start must be >= 100."
  }
}

variable "proxmox_default_pool_id" {
  description = "Default Proxmox pool ID when a node does not define pool_id"
  type        = string
  default     = null
}

variable "master_default_disk_gb" {
  description = "Default disk size (GB) for masters when a node does not define disk_gb"
  type        = number
  default     = 32
}

variable "worker_default_disk_gb" {
  description = "Default disk size (GB) for workers when a node does not define disk_gb"
  type        = number
  default     = 80
}

variable "default_install_disk" {
  description = "Default Talos installation disk used in machine config patches"
  type        = string
  default     = "/dev/sda"
}

variable "default_talos_interface" {
  description = "Default Talos network interface used for static network patches"
  type        = string
  default     = "eth0"
}

variable "talos_nameservers" {
  description = "Optional list of DNS nameservers used when a node is configured with static IP"
  type        = list(string)
  default     = []
}

variable "control_plane_machine_config_patches" {
  description = "Additional YAML patches applied to all control-plane nodes"
  type        = list(string)
  default     = []
}

variable "worker_machine_config_patches" {
  description = "Additional YAML patches applied to all worker nodes"
  type        = list(string)
  default     = []
}

variable "masters" {
  description = "Master nodes definition"
  type = list(object({
    host         = string
    proxmox_node = string

    ip_mode = optional(string, "dhcp")
    ip      = optional(string)
    cidr    = optional(number)
    gateway = optional(string)

    ram_mb    = number
    cpu_cores = number
    cpu_type  = optional(string)

    disk_gb      = optional(number)
    datastore_id = optional(string)
    pool_id      = optional(string)
    bridge       = optional(string)
    vlan_id      = optional(number)
    mac_address  = optional(string)

    install_disk           = optional(string)
    machine_config_patches = optional(list(string), [])
  }))

  validation {
    condition     = length(var.masters) > 0
    error_message = "At least one master node is required."
  }

  validation {
    condition     = length(distinct([for node in var.masters : node.host])) == length(var.masters)
    error_message = "Master host names must be unique."
  }

  validation {
    condition     = alltrue([for node in var.masters : contains(["dhcp", "static"], lower(coalesce(try(node.ip_mode, null), "dhcp")))])
    error_message = "masters[*].ip_mode must be either 'dhcp' or 'static'."
  }

  validation {
    condition = alltrue([
      for node in var.masters :
      lower(coalesce(try(node.ip_mode, null), "dhcp")) != "static" || (
        try(trimspace(node.ip), "") != "" &&
        try(node.cidr, 0) >= 1 &&
        try(node.cidr, 0) <= 32 &&
        try(trimspace(node.gateway), "") != ""
      )
    ])
    error_message = "If masters[*].ip_mode is 'static', you must set ip, cidr (1-32), and gateway."
  }
}

variable "workers" {
  description = "Worker nodes definition"
  type = list(object({
    host         = string
    proxmox_node = string

    ip_mode = optional(string, "dhcp")
    ip      = optional(string)
    cidr    = optional(number)
    gateway = optional(string)

    ram_mb    = number
    cpu_cores = number
    cpu_type  = optional(string)

    disk_gb      = optional(number)
    datastore_id = optional(string)
    pool_id      = optional(string)
    bridge       = optional(string)
    vlan_id      = optional(number)
    mac_address  = optional(string)

    install_disk           = optional(string)
    machine_config_patches = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = length(distinct([for node in var.workers : node.host])) == length(var.workers)
    error_message = "Worker host names must be unique."
  }

  validation {
    condition     = alltrue([for node in var.workers : contains(["dhcp", "static"], lower(coalesce(try(node.ip_mode, null), "dhcp")))])
    error_message = "workers[*].ip_mode must be either 'dhcp' or 'static'."
  }

  validation {
    condition = alltrue([
      for node in var.workers :
      lower(coalesce(try(node.ip_mode, null), "dhcp")) != "static" || (
        try(trimspace(node.ip), "") != "" &&
        try(node.cidr, 0) >= 1 &&
        try(node.cidr, 0) <= 32 &&
        try(trimspace(node.gateway), "") != ""
      )
    ])
    error_message = "If workers[*].ip_mode is 'static', you must set ip, cidr (1-32), and gateway."
  }
}
