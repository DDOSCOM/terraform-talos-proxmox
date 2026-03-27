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

output "master_ips" {
  description = "Map of master hostname to resolved IP"
  value       = local.master_node_ips
}

output "worker_ips" {
  description = "Map of worker hostname to resolved IP"
  value       = local.worker_node_ips
}

output "control_plane_ips" {
  description = "Ordered list of control-plane IPs"
  value       = local.control_plane_ips
}

output "all_node_ips" {
  description = "Ordered list of all node IPs"
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
    }
  )
}
