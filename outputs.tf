output "talosconfig" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubernetes kubeconfig"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "cluster_health_check_id" {
  description = "Final Talos cluster health check ID (null when wait_for_control_plane_health is false)"
  value       = try(data.talos_cluster_health.control_plane_ready[0].id, null)
}

output "master_ips" {
  description = "Map of master hostname to resolved IP"
  value       = local.master_node_ips
}

output "worker_ips" {
  description = "Map of worker hostname to resolved IP"
  value       = local.worker_node_ips
}

output "storage_worker_ips" {
  description = "Map of storage worker hostname to resolved IP"
  value       = local.storage_worker_node_ips
}

output "control_plane_ips" {
  description = "Ordered list of control-plane IPs"
  value       = local.control_plane_ips
}

output "all_node_ips" {
  description = "Ordered list of all node IPs (masters, workers, storage workers)"
  value       = local.all_node_ips
}

output "node_inventory" {
  description = "Node inventory with role, proxmox host, and resolved IP"
  value = merge(
    {
      for node in var.masters : node.host => {
        role         = "master"
        proxmox_node = node.proxmox_node
        ip           = local.master_node_ips[node.host]
      }
    },
    {
      for node in var.workers : node.host => {
        role         = "worker"
        proxmox_node = node.proxmox_node
        ip           = local.worker_node_ips[node.host]
      }
    },
    {
      for node in var.storage_workers : node.host => {
        role         = "storage_worker"
        proxmox_node = node.proxmox_node
        ip           = local.storage_worker_node_ips[node.host]
      }
    }
  )
}
