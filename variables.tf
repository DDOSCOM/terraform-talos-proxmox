variable "talos_cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "talos_version" {
  description = "Talos OS version used for both image download and machine configuration generation"
  type        = string

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+([-.][0-9A-Za-z.-]+)?$", var.talos_version))
    error_message = "talos_version must be a valid Talos version (for example: 1.12.6, v1.12.6, or 1.13.0-beta.1)."
  }
}

variable "talos_schematic_id" {
  description = "Talos Factory schematic ID used to build the image URL"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.talos_schematic_id))
    error_message = "talos_schematic_id must be a 64-character lowercase hexadecimal string."
  }
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

  validation {
    condition     = var.cluster_endpoint == null || can(regex("^https://[^\\s]+$", var.cluster_endpoint))
    error_message = "cluster_endpoint must be a valid https URL when set."
  }
}

variable "proxmox_iso_datastore" {
  description = "Proxmox datastore where the Talos disk image is downloaded"
  type        = string
  default     = "local"
}

variable "proxmox_default_vm_datastore" {
  description = "Default Proxmox datastore for VM disks when a node does not define datastore_id"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_iscsi_datastores" {
  description = "Datastores that should be treated as iSCSI-compatible for storage_workers"
  type        = set(string)
  default     = []
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
  description = "Whether to enable pre-enrolled secure boot keys on EFI disk (recommended for Talos secure boot images)"
  type        = bool
  default     = true
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

variable "storage_worker_default_system_disk_gb" {
  description = "Default system disk size (GB) for storage workers when a node does not define disk_gb"
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

variable "wait_for_control_plane_health" {
  description = "Whether to run final Talos cluster health checks after all machine configurations are applied"
  type        = bool
  default     = true
}

variable "enable_metallb" {
  description = "Whether to install and configure MetalLB"
  type        = bool
  default     = true
}

variable "metallb_ip_ranges" {
  description = "MetalLB load balancer address ranges (CIDR or start-end range), for example [\"192.168.1.240-192.168.1.250\"]"
  type        = list(string)
  default     = []

  validation {
    condition     = var.enable_metallb ? length(var.metallb_ip_ranges) > 0 : true
    error_message = "When enable_metallb is true, metallb_ip_ranges must contain at least one CIDR or start-end range."
  }

  validation {
    condition = var.enable_metallb ? alltrue([
      for entry in var.metallb_ip_ranges : (
        can(cidrnetmask(trimspace(entry))) || (
          can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}-([0-9]{1,3}\\.){3}[0-9]{1,3}$", trimspace(entry))) &&
          can(cidrhost("${split("-", trimspace(entry))[0]}/32", 0)) &&
          can(cidrhost("${split("-", trimspace(entry))[1]}/32", 0)) &&
          (
            (
              tonumber(split(".", split("-", trimspace(entry))[0])[0]) * 16777216 +
              tonumber(split(".", split("-", trimspace(entry))[0])[1]) * 65536 +
              tonumber(split(".", split("-", trimspace(entry))[0])[2]) * 256 +
              tonumber(split(".", split("-", trimspace(entry))[0])[3])
              ) <= (
              tonumber(split(".", split("-", trimspace(entry))[1])[0]) * 16777216 +
              tonumber(split(".", split("-", trimspace(entry))[1])[1]) * 65536 +
              tonumber(split(".", split("-", trimspace(entry))[1])[2]) * 256 +
              tonumber(split(".", split("-", trimspace(entry))[1])[3])
            )
          )
        )
      )
    ]) : true
    error_message = "When enable_metallb is true, each metallb_ip_ranges entry must be a valid IPv4 CIDR (0-32 prefix) or a valid IPv4 range with start <= end."
  }
}

variable "metallb_namespace" {
  description = "Kubernetes namespace for MetalLB"
  type        = string
  default     = "metallb-system"
}

variable "metallb_release_name" {
  description = "Helm release name for MetalLB"
  type        = string
  default     = "metallb"
}

variable "metallb_ipaddresspool_name" {
  description = "Name of the MetalLB IPAddressPool resource"
  type        = string
  default     = "default-pool"
}

variable "metallb_l2advertisement_name" {
  description = "Name of the MetalLB L2Advertisement resource"
  type        = string
  default     = "default-l2advertisement"
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

variable "storage_workers" {
  description = "Storage worker nodes definition"
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

    disk_gb                 = optional(number)
    datastore_id            = optional(string)
    system_datastore_id     = optional(string)
    efi_datastore_id        = optional(string)
    cloud_init_datastore_id = optional(string)
    iscsi_disk_name         = optional(string)
    iscsi_disk_gb           = optional(number)
    pool_id                 = optional(string)
    bridge                  = optional(string)
    vlan_id                 = optional(number)
    mac_address             = optional(string)

    install_disk           = optional(string)
    machine_config_patches = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = length(distinct([for node in var.storage_workers : node.host])) == length(var.storage_workers)
    error_message = "Storage worker host names must be unique."
  }

  validation {
    condition     = alltrue([for node in var.storage_workers : contains(["dhcp", "static"], lower(coalesce(try(node.ip_mode, null), "dhcp")))])
    error_message = "storage_workers[*].ip_mode must be either 'dhcp' or 'static'."
  }

  validation {
    condition = alltrue([
      for node in var.storage_workers :
      lower(coalesce(try(node.ip_mode, null), "dhcp")) != "static" || (
        try(trimspace(node.ip), "") != "" &&
        try(node.cidr, 0) >= 1 &&
        try(node.cidr, 0) <= 32 &&
        try(trimspace(node.gateway), "") != ""
      )
    ])
    error_message = "If storage_workers[*].ip_mode is 'static', you must set ip, cidr (1-32), and gateway."
  }

  validation {
    condition = alltrue([
      for node in var.storage_workers :
      try(node.iscsi_disk_gb, null) == null || try(node.iscsi_disk_gb, 0) > 0
    ])
    error_message = "If set, storage_workers[*].iscsi_disk_gb must be greater than 0."
  }
}
