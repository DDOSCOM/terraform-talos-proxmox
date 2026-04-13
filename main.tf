locals {
  masters_by_host          = { for node in var.masters : node.host => node }
  workers_by_host          = { for node in var.workers : node.host => node }
  storage_workers_by_host  = { for node in var.storage_workers : node.host => node }
  talos_version_normalized = trimprefix(var.talos_version, "v")
  talos_installer_image    = "factory.talos.dev/installer/${var.talos_schematic_id}:v${local.talos_version_normalized}"

  storage_worker_effective_datastore = {
    for host, node in local.storage_workers_by_host :
    host => coalesce(try(node.datastore_id, null), var.proxmox_default_vm_datastore)
  }

  storage_worker_effective_system_datastore = {
    for host, node in local.storage_workers_by_host :
    host => coalesce(
      try(node.system_datastore_id, null),
      contains(var.proxmox_iscsi_datastores, local.storage_worker_effective_datastore[host]) ? null : local.storage_worker_effective_datastore[host],
      var.proxmox_default_vm_datastore,
    )
  }

  storage_worker_effective_efi_datastore = {
    for host, node in local.storage_workers_by_host :
    host => coalesce(try(node.efi_datastore_id, null), local.storage_worker_effective_system_datastore[host])
  }

  storage_worker_effective_cloud_init_datastore = {
    for host, node in local.storage_workers_by_host :
    host => coalesce(try(node.cloud_init_datastore_id, null), local.storage_worker_effective_efi_datastore[host], var.proxmox_default_vm_datastore)
  }

  storage_worker_uses_iscsi = {
    for host, node in local.storage_workers_by_host :
    host => contains(var.proxmox_iscsi_datastores, local.storage_worker_effective_datastore[host])
  }

  proxmox_nodes_with_talos_image = distinct(concat(
    [for node in var.masters : node.proxmox_node],
    [for node in var.workers : node.proxmox_node],
    [for node in var.storage_workers : node.proxmox_node],
  ))

  all_hosts = concat(
    [for node in var.masters : node.host],
    [for node in var.storage_workers : node.host],
    [for node in var.workers : node.host],
  )
  vm_ids_by_host        = zipmap(local.all_hosts, range(var.proxmox_vm_id_start, var.proxmox_vm_id_start + length(local.all_hosts)))
  bootstrap_master_host = var.masters[0].host
}

resource "terraform_data" "input_validation" {
  input = local.all_hosts

  lifecycle {
    precondition {
      condition     = length(local.all_hosts) == length(distinct(local.all_hosts))
      error_message = "Node host names must be unique across masters, workers, and storage_workers."
    }

    precondition {
      condition = alltrue([
        for host, node in local.storage_workers_by_host :
        !local.storage_worker_uses_iscsi[host] || try(trimspace(node.iscsi_disk_name), "") != ""
      ])
      error_message = "storage_workers[*].iscsi_disk_name must be set when datastore_id (or proxmox_default_vm_datastore) is listed in proxmox_iscsi_datastores."
    }

    precondition {
      condition = alltrue([
        for host, node in local.storage_workers_by_host :
        !local.storage_worker_uses_iscsi[host] || (try(node.iscsi_disk_gb, null) != null && try(node.iscsi_disk_gb, 0) > 0)
      ])
      error_message = "For iSCSI storage_workers, iscsi_disk_gb is required and must be greater than 0 (match the existing LUN size)."
    }

    precondition {
      condition = alltrue([
        for host, node in local.storage_workers_by_host :
        !local.storage_worker_uses_iscsi[host] || try(trimspace(node.system_datastore_id), "") != ""
      ])
      error_message = "For iSCSI storage_workers, system_datastore_id is required to place the system disk (scsi0) in a non-iSCSI datastore."
    }

    precondition {
      condition = alltrue([
        for host, node in local.storage_workers_by_host :
        !local.storage_worker_uses_iscsi[host] || !contains(var.proxmox_iscsi_datastores, local.storage_worker_effective_system_datastore[host])
      ])
      error_message = "For iSCSI storage_workers, system disk datastore must not be in proxmox_iscsi_datastores. Set system_datastore_id to a non-iSCSI datastore."
    }

    precondition {
      condition = alltrue([
        for host, node in local.storage_workers_by_host :
        !local.storage_worker_uses_iscsi[host] || !contains(var.proxmox_iscsi_datastores, local.storage_worker_effective_efi_datastore[host])
      ])
      error_message = "For iSCSI storage_workers, EFI disk datastore must not be in proxmox_iscsi_datastores. Set efi_datastore_id to a non-iSCSI datastore."
    }

    precondition {
      condition = alltrue([
        for host, node in local.storage_workers_by_host :
        !local.storage_worker_uses_iscsi[host] || !contains(var.proxmox_iscsi_datastores, local.storage_worker_effective_cloud_init_datastore[host])
      ])
      error_message = "For iSCSI storage_workers, cloud-init datastore must not be in proxmox_iscsi_datastores. Set cloud_init_datastore_id to a non-iSCSI datastore."
    }
  }
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  for_each = toset(local.proxmox_nodes_with_talos_image)

  depends_on = [terraform_data.input_validation]

  content_type            = "iso"
  datastore_id            = var.proxmox_iso_datastore
  decompression_algorithm = "zst"
  node_name               = each.key
  file_name               = "${var.talos_cluster_name}-talos-${var.talos_schematic_id}-${local.talos_version_normalized}-${var.talos_arch}.img"
  url                     = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${local.talos_version_normalized}/nocloud-${var.talos_arch}.raw.zst"
  overwrite               = false
}

resource "proxmox_virtual_environment_vm" "master" {
  for_each = local.masters_by_host

  name          = each.key
  vm_id         = local.vm_ids_by_host[each.key]
  node_name     = each.value.proxmox_node
  pool_id       = try(each.value.pool_id, null) != null ? each.value.pool_id : var.proxmox_default_pool_id
  bios          = "ovmf"
  machine       = var.proxmox_machine_type
  scsi_hardware = "virtio-scsi-pci"


  agent {
    enabled = true

    wait_for_ip {
      ipv4 = true
    }
  }

  cpu {
    cores = each.value.cpu_cores
    type  = coalesce(try(each.value.cpu_type, null), var.proxmox_default_cpu_type)
  }

  memory {
    dedicated = each.value.ram_mb
    floating  = each.value.ram_mb
  }

  disk {
    datastore_id = coalesce(try(each.value.datastore_id, null), var.proxmox_default_vm_datastore)
    file_id      = proxmox_virtual_environment_download_file.talos_image[each.value.proxmox_node].id
    file_format  = "raw"
    interface    = "scsi0"
    discard      = "on"
    size         = coalesce(try(each.value.disk_gb, null), var.master_default_disk_gb)
  }

  initialization {
    datastore_id = coalesce(try(each.value.datastore_id, null), var.proxmox_default_vm_datastore)

    ip_config {
      ipv4 {
        address = local.master_boot_ipv4[each.key]
        gateway = local.master_boot_gateway[each.key]
      }
    }
  }

  efi_disk {
    datastore_id      = coalesce(try(each.value.datastore_id, null), var.proxmox_default_vm_datastore)
    type              = var.proxmox_efi_disk_type
    pre_enrolled_keys = var.proxmox_efi_pre_enrolled_keys
  }

  network_device {
    bridge      = coalesce(try(each.value.bridge, null), var.proxmox_default_bridge)
    vlan_id     = try(each.value.vlan_id, null) != null ? each.value.vlan_id : var.proxmox_default_vlan_id
    mac_address = try(each.value.mac_address, null)
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = local.workers_by_host
  depends_on = [
    talos_cluster_kubeconfig.this,
    proxmox_virtual_environment_vm.storage_worker,
  ]

  name          = each.key
  vm_id         = local.vm_ids_by_host[each.key]
  node_name     = each.value.proxmox_node
  pool_id       = try(each.value.pool_id, null) != null ? each.value.pool_id : var.proxmox_default_pool_id
  bios          = "ovmf"
  machine       = var.proxmox_machine_type
  scsi_hardware = "virtio-scsi-pci"

  agent {
    enabled = true

    wait_for_ip {
      ipv4 = true
    }
  }

  cpu {
    cores = each.value.cpu_cores
    type  = coalesce(try(each.value.cpu_type, null), var.proxmox_default_cpu_type)
  }

  memory {
    dedicated = each.value.ram_mb
    floating  = each.value.ram_mb
  }

  disk {
    datastore_id = coalesce(try(each.value.datastore_id, null), var.proxmox_default_vm_datastore)
    file_id      = proxmox_virtual_environment_download_file.talos_image[each.value.proxmox_node].id
    file_format  = "raw"
    interface    = "scsi0"
    discard      = "on"
    size         = coalesce(try(each.value.disk_gb, null), var.worker_default_disk_gb)
  }

  initialization {
    datastore_id = coalesce(try(each.value.datastore_id, null), var.proxmox_default_vm_datastore)

    ip_config {
      ipv4 {
        address = local.worker_boot_ipv4[each.key]
        gateway = local.worker_boot_gateway[each.key]
      }
    }
  }

  efi_disk {
    datastore_id      = coalesce(try(each.value.datastore_id, null), var.proxmox_default_vm_datastore)
    type              = var.proxmox_efi_disk_type
    pre_enrolled_keys = var.proxmox_efi_pre_enrolled_keys
  }

  network_device {
    bridge      = coalesce(try(each.value.bridge, null), var.proxmox_default_bridge)
    vlan_id     = try(each.value.vlan_id, null) != null ? each.value.vlan_id : var.proxmox_default_vlan_id
    mac_address = try(each.value.mac_address, null)
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "storage_worker" {
  for_each = local.storage_workers_by_host
  depends_on = [
    talos_cluster_kubeconfig.this,
  ]

  name          = each.key
  vm_id         = local.vm_ids_by_host[each.key]
  node_name     = each.value.proxmox_node
  pool_id       = try(each.value.pool_id, null) != null ? each.value.pool_id : var.proxmox_default_pool_id
  bios          = "ovmf"
  machine       = var.proxmox_machine_type
  scsi_hardware = "virtio-scsi-pci"

  agent {
    enabled = true

    wait_for_ip {
      ipv4 = true
    }
  }

  cpu {
    cores = each.value.cpu_cores
    type  = coalesce(try(each.value.cpu_type, null), var.proxmox_default_cpu_type)
  }

  memory {
    dedicated = each.value.ram_mb
    floating  = each.value.ram_mb
  }

  disk {
    datastore_id = local.storage_worker_effective_system_datastore[each.key]
    file_id      = proxmox_virtual_environment_download_file.talos_image[each.value.proxmox_node].id
    file_format  = "raw"
    interface    = "scsi0"
    discard      = "on"
    size         = coalesce(try(each.value.disk_gb, null), var.storage_worker_default_system_disk_gb)
  }

  dynamic "disk" {
    for_each = local.storage_worker_uses_iscsi[each.key] ? [1] : []

    content {
      datastore_id      = local.storage_worker_effective_datastore[each.key]
      path_in_datastore = each.value.iscsi_disk_name
      file_format       = "raw"
      interface         = "scsi1"
      discard           = "on"
      size              = each.value.iscsi_disk_gb
    }
  }

  initialization {
    datastore_id = local.storage_worker_effective_cloud_init_datastore[each.key]

    ip_config {
      ipv4 {
        address = local.storage_worker_boot_ipv4[each.key]
        gateway = local.storage_worker_boot_gateway[each.key]
      }
    }
  }

  efi_disk {
    datastore_id      = local.storage_worker_effective_efi_datastore[each.key]
    type              = var.proxmox_efi_disk_type
    pre_enrolled_keys = var.proxmox_efi_pre_enrolled_keys
  }

  network_device {
    bridge      = coalesce(try(each.value.bridge, null), var.proxmox_default_bridge)
    vlan_id     = try(each.value.vlan_id, null) != null ? each.value.vlan_id : var.proxmox_default_vlan_id
    mac_address = try(each.value.mac_address, null)
  }

  operating_system {
    type = "l26"
  }
}

locals {
  master_boot_ipv4 = {
    for host, node in local.masters_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? "${node.ip}/${node.cidr}" : "dhcp"
  }

  master_boot_gateway = {
    for host, node in local.masters_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.gateway : null
  }

  worker_boot_ipv4 = {
    for host, node in local.workers_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? "${node.ip}/${node.cidr}" : "dhcp"
  }

  worker_boot_gateway = {
    for host, node in local.workers_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.gateway : null
  }

  storage_worker_boot_ipv4 = {
    for host, node in local.storage_workers_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? "${node.ip}/${node.cidr}" : "dhcp"
  }

  storage_worker_boot_gateway = {
    for host, node in local.storage_workers_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.gateway : null
  }

  detected_master_ips = {
    for host, vm in proxmox_virtual_environment_vm.master :
    host => try(
      [
        for ip in flatten(try(vm.ipv4_addresses, [])) : ip
        if can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && !startswith(ip, "127.") && !startswith(ip, "169.254.")
      ][0],
      null
    )
  }

  detected_worker_ips = {
    for host, vm in proxmox_virtual_environment_vm.worker :
    host => try(
      [
        for ip in flatten(try(vm.ipv4_addresses, [])) : ip
        if can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && !startswith(ip, "127.") && !startswith(ip, "169.254.")
      ][0],
      null
    )
  }

  detected_storage_worker_ips = {
    for host, vm in proxmox_virtual_environment_vm.storage_worker :
    host => try(
      [
        for ip in flatten(try(vm.ipv4_addresses, [])) : ip
        if can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && !startswith(ip, "127.") && !startswith(ip, "169.254.")
      ][0],
      null
    )
  }

  master_node_ips = {
    for host, node in local.masters_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.ip : lookup(local.detected_master_ips, host, null)
  }

  worker_node_ips = {
    for host, node in local.workers_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.ip : lookup(local.detected_worker_ips, host, null)
  }

  storage_worker_node_ips = {
    for host, node in local.storage_workers_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.ip : lookup(local.detected_storage_worker_ips, host, null)
  }

  control_plane_ips  = [for node in var.masters : local.master_node_ips[node.host]]
  worker_ips         = [for node in var.workers : local.worker_node_ips[node.host]]
  storage_worker_ips = [for node in var.storage_workers : local.storage_worker_node_ips[node.host]]
  all_node_ips       = concat(local.control_plane_ips, local.worker_ips, local.storage_worker_ips)

  resolved_cluster_endpoint = var.cluster_endpoint != null ? var.cluster_endpoint : "https://${local.master_node_ips[local.bootstrap_master_host]}:6443"

  master_config_patches = {
    for host, node in local.masters_by_host :
    host => concat(
      [
        yamlencode({
          machine = {
            install = {
              disk  = coalesce(try(node.install_disk, null), var.default_install_disk)
              image = local.talos_installer_image
            }
          }
        })
      ],
      lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? [
        yamlencode({
          machine = {
            network = merge(
              length(var.talos_nameservers) > 0 ? { nameservers = var.talos_nameservers } : {},
              {
                interfaces = [
                  {
                    interface = var.default_talos_interface
                    dhcp      = false
                    addresses = ["${node.ip}/${node.cidr}"]
                    routes = [
                      {
                        network = "0.0.0.0/0"
                        gateway = node.gateway
                      }
                    ]
                  }
                ]
              }
            )
          }
        })
      ] : [],
      var.control_plane_machine_config_patches,
      try(node.machine_config_patches, [])
    )
  }

  worker_config_patches = {
    for host, node in local.workers_by_host :
    host => concat(
      [
        yamlencode({
          machine = {
            install = {
              disk  = coalesce(try(node.install_disk, null), var.default_install_disk)
              image = local.talos_installer_image
            }
          }
        })
      ],
      lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? [
        yamlencode({
          machine = {
            network = merge(
              length(var.talos_nameservers) > 0 ? { nameservers = var.talos_nameservers } : {},
              {
                interfaces = [
                  {
                    interface = var.default_talos_interface
                    dhcp      = false
                    addresses = ["${node.ip}/${node.cidr}"]
                    routes = [
                      {
                        network = "0.0.0.0/0"
                        gateway = node.gateway
                      }
                    ]
                  }
                ]
              }
            )
          }
        })
      ] : [],
      var.worker_machine_config_patches,
      try(node.machine_config_patches, [])
    )
  }

  storage_worker_config_patches = {
    for host, node in local.storage_workers_by_host :
    host => concat(
      [
        yamlencode({
          machine = {
            install = {
              disk  = coalesce(try(node.install_disk, null), var.default_install_disk)
              image = local.talos_installer_image
            }
          }
        })
      ],
      lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? [
        yamlencode({
          machine = {
            network = merge(
              length(var.talos_nameservers) > 0 ? { nameservers = var.talos_nameservers } : {},
              {
                interfaces = [
                  {
                    interface = var.default_talos_interface
                    dhcp      = false
                    addresses = ["${node.ip}/${node.cidr}"]
                    routes = [
                      {
                        network = "0.0.0.0/0"
                        gateway = node.gateway
                      }
                    ]
                  }
                ]
              }
            )
          }
        })
      ] : [],
      var.worker_machine_config_patches,
      try(node.machine_config_patches, [])
    )
  }

  kubeconfig_decoded = try(yamldecode(talos_cluster_kubeconfig.this.kubeconfig_raw), null)

  kubernetes_host = try(local.kubeconfig_decoded.clusters[0].cluster.server, null)

  kubernetes_cluster_ca_certificate = try(base64decode(local.kubeconfig_decoded.clusters[0].cluster["certificate-authority-data"]), null)

  kubernetes_client_certificate = try(base64decode(local.kubeconfig_decoded.users[0].user["client-certificate-data"]), null)

  kubernetes_client_key = try(base64decode(local.kubeconfig_decoded.users[0].user["client-key-data"]), null)
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.talos_cluster_name
  cluster_endpoint   = local.resolved_cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = local.talos_version_normalized
  kubernetes_version = var.kubernetes_version
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.talos_cluster_name
  cluster_endpoint   = local.resolved_cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = local.talos_version_normalized
  kubernetes_version = var.kubernetes_version
}

provider "kubernetes" {
  host                   = local.kubernetes_host
  cluster_ca_certificate = local.kubernetes_cluster_ca_certificate
  client_certificate     = local.kubernetes_client_certificate
  client_key             = local.kubernetes_client_key
}

provider "helm" {
  kubernetes {
    host                   = local.kubernetes_host
    cluster_ca_certificate = local.kubernetes_cluster_ca_certificate
    client_certificate     = local.kubernetes_client_certificate
    client_key             = local.kubernetes_client_key
  }
}

resource "talos_machine_configuration_apply" "master" {
  for_each = local.masters_by_host
  depends_on = [
    proxmox_virtual_environment_vm.master
  ]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = local.master_node_ips[each.key]
  config_patches              = local.master_config_patches[each.key]

  lifecycle {
    precondition {
      condition     = local.master_node_ips[each.key] != null
      error_message = "No IPv4 was resolved for master '${each.key}'. If using DHCP, verify Proxmox guest agent and DHCP lease; otherwise set ip_mode='static' with ip/cidr/gateway."
    }
  }
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.workers_by_host
  depends_on = [
    proxmox_virtual_environment_vm.worker
  ]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.worker_node_ips[each.key]
  config_patches              = local.worker_config_patches[each.key]

  lifecycle {
    precondition {
      condition     = local.worker_node_ips[each.key] != null
      error_message = "No IPv4 was resolved for worker '${each.key}'. If using DHCP, verify Proxmox guest agent and DHCP lease; otherwise set ip_mode='static' with ip/cidr/gateway."
    }
  }
}

resource "talos_machine_configuration_apply" "storage_worker" {
  for_each = local.storage_workers_by_host
  depends_on = [
    proxmox_virtual_environment_vm.storage_worker
  ]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.storage_worker_node_ips[each.key]
  config_patches              = local.storage_worker_config_patches[each.key]

  lifecycle {
    precondition {
      condition     = local.storage_worker_node_ips[each.key] != null
      error_message = "No IPv4 was resolved for storage worker '${each.key}'. If using DHCP, verify Proxmox guest agent and DHCP lease; otherwise set ip_mode='static' with ip/cidr/gateway."
    }
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.master]

  node                 = local.master_node_ips[local.bootstrap_master_host]
  client_configuration = talos_machine_secrets.this.client_configuration

  lifecycle {
    precondition {
      condition     = local.master_node_ips[local.bootstrap_master_host] != null
      error_message = "Bootstrap master IP is not resolved. Set cluster_endpoint explicitly or ensure the first master has a resolvable IP."
    }
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = local.master_node_ips[local.bootstrap_master_host]
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_cluster_health" "control_plane_ready" {
  count = var.wait_for_control_plane_health ? 1 : 0

  depends_on = [
    talos_cluster_kubeconfig.this,
    talos_machine_configuration_apply.master,
    talos_machine_configuration_apply.storage_worker,
    talos_machine_configuration_apply.worker,
  ]

  client_configuration   = talos_machine_secrets.this.client_configuration
  endpoints              = [for ip in local.control_plane_ips : ip if ip != null]
  control_plane_nodes    = [for ip in local.control_plane_ips : ip if ip != null]
  worker_nodes           = [for ip in concat(local.storage_worker_ips, local.worker_ips) : ip if ip != null]
  skip_kubernetes_checks = false
}

data "talos_client_configuration" "this" {
  depends_on = [
    talos_machine_configuration_apply.master,
    talos_machine_configuration_apply.worker,
    talos_machine_configuration_apply.storage_worker,
  ]

  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = local.all_node_ips
}

resource "helm_release" "metallb" {
  count = var.enable_metallb ? 1 : 0

  depends_on = [
    kubernetes_manifest.metallb_namespace,
    talos_cluster_kubeconfig.this,
    talos_machine_configuration_apply.master,
    talos_machine_configuration_apply.worker,
    talos_machine_configuration_apply.storage_worker,
    data.talos_cluster_health.control_plane_ready,
  ]

  name             = var.metallb_release_name
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = var.metallb_namespace
  create_namespace = false
  version          = "0.15.3"
  wait             = true
  timeout          = 600
}

resource "kubernetes_manifest" "metallb_namespace" {
  count = var.enable_metallb ? 1 : 0

  depends_on = [talos_cluster_kubeconfig.this]

  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.metallb_namespace
      labels = {
        "pod-security.kubernetes.io/enforce" = "privileged"
        "pod-security.kubernetes.io/audit"   = "privileged"
        "pod-security.kubernetes.io/warn"    = "privileged"
      }
    }
  }
}

resource "helm_release" "metallb_config" {
  count = var.enable_metallb ? 1 : 0

  depends_on = [helm_release.metallb]

  name             = "${var.metallb_release_name}-config"
  chart            = "${path.module}/charts/metallb-config"
  namespace        = var.metallb_namespace
  create_namespace = false
  wait             = true
  timeout          = 300

  values = [yamlencode({
    ipAddressPoolName   = var.metallb_ipaddresspool_name
    l2AdvertisementName = var.metallb_l2advertisement_name
    addresses           = var.metallb_ip_ranges
  })]
}
