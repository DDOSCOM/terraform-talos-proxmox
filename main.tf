locals {
  masters_by_host          = { for node in var.masters : node.host => node }
  workers_by_host          = { for node in var.workers : node.host => node }
  talos_version_normalized = trimprefix(var.talos_version, "v")
  proxmox_nodes_with_vms   = distinct(concat([for node in var.masters : node.proxmox_node], [for node in var.workers : node.proxmox_node]))

  all_hosts             = concat([for node in var.masters : node.host], [for node in var.workers : node.host])
  vm_ids_by_host        = zipmap(local.all_hosts, range(var.proxmox_vm_id_start, var.proxmox_vm_id_start + length(local.all_hosts)))
  bootstrap_master_host = var.masters[0].host
}

resource "terraform_data" "input_validation" {
  input = local.all_hosts

  lifecycle {
    precondition {
      condition     = length(local.all_hosts) == length(distinct(local.all_hosts))
      error_message = "Node host names must be unique across masters and workers."
    }
  }
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  for_each = toset(local.proxmox_nodes_with_vms)

  depends_on = [terraform_data.input_validation]

  content_type = "iso"
  datastore_id = var.proxmox_iso_datastore
  node_name    = each.key
  file_name    = "${var.talos_cluster_name}-talos-${var.talos_schematic_id}-${local.talos_version_normalized}-${var.talos_arch}.img"
  url          = "https://factory.talos.dev/image/${var.talos_schematic_id}/v${local.talos_version_normalized}/nocloud-${var.talos_arch}.qcow2"
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

  master_node_ips = {
    for host, node in local.masters_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.ip : lookup(local.detected_master_ips, host, null)
  }

  worker_node_ips = {
    for host, node in local.workers_by_host :
    host => lower(coalesce(try(node.ip_mode, null), "dhcp")) == "static" ? node.ip : lookup(local.detected_worker_ips, host, null)
  }

  control_plane_ips = [for node in var.masters : local.master_node_ips[node.host]]
  worker_ips        = [for node in var.workers : local.worker_node_ips[node.host]]
  all_node_ips      = concat(local.control_plane_ips, local.worker_ips)

  resolved_cluster_endpoint = var.cluster_endpoint != null ? var.cluster_endpoint : "https://${local.master_node_ips[local.bootstrap_master_host]}:6443"

  master_config_patches = {
    for host, node in local.masters_by_host :
    host => concat(
      [
        yamlencode({
          machine = {
            install = {
              disk = coalesce(try(node.install_disk, null), var.default_install_disk)
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
              disk = coalesce(try(node.install_disk, null), var.default_install_disk)
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

data "talos_client_configuration" "this" {
  depends_on = [
    talos_machine_configuration_apply.master,
    talos_machine_configuration_apply.worker,
  ]

  cluster_name         = var.talos_cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = local.all_node_ips
}
