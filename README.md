# Terraform module: Talos Kubernetes on Proxmox

This module provisions a Kubernetes cluster with Talos Linux on Proxmox.

## What it does

- Creates VMs for `masters` and `workers` using `bpg/proxmox`.
- Downloads the Talos image on every Proxmox node that will host at least one VM.
- Enforces UEFI (`ovmf`), `q35` machine type, and system disk on `scsi0` with `virtio-scsi-pci`.
- Configures first-boot networking via cloud-init (`dhcp` or static IP per node).
- Generates and applies Talos machine config, bootstraps the first master, and retrieves `kubeconfig`.
- Assigns deterministic `vm_id` values starting from `proxmox_vm_id_start` (default `100`).

## Example usage

```hcl
module "talos" {
  source = "./modules/talos-proxmox"

  talos_cluster_name = "prod-cluster"
  talos_version      = "1.12.6"
  talos_schematic_id = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"

  proxmox_vm_id_start           = 300
  proxmox_default_vm_datastore  = "local-lvm"
  proxmox_default_bridge        = "vmbr0"
  proxmox_machine_type          = "q35"
  proxmox_efi_disk_type         = "4m"
  proxmox_efi_pre_enrolled_keys = false

  masters = [
    {
      host         = "cp-01"
      proxmox_node = "pve1"
      ip_mode      = "static"
      ip           = "172.16.0.10"
      cidr         = 24
      gateway      = "172.16.0.1"

      ram_mb    = 8192
      cpu_cores = 4
      cpu_type  = "host"
      disk_gb   = 40
    }
  ]

  workers = [
    {
      host         = "wk-01"
      proxmox_node = "pve2"
      ip_mode      = "dhcp"

      ram_mb    = 12288
      cpu_cores = 6
      cpu_type  = "host"
      disk_gb   = 80
    }
  ]
}
```

## Important notes

- `talos_version` is required and is used for both image download and machine config generation.
- `talos_version` accepts both `1.12.6` and `v1.12.6` (the module normalizes it internally).
- `talos_schematic_id` must be a 64-character lowercase hexadecimal string.
- If set, `cluster_endpoint` must use `https://`.
- If `ip_mode = "static"`, you must set `ip`, `cidr`, and `gateway`.
- If `ip_mode = "dhcp"`, make sure QEMU guest agent is running so IPv4 can be discovered.
- The default cluster endpoint is `https://<first-master-ip>:6443`; you can override it with `cluster_endpoint`.
- Talos machine config apply now waits for VM creation resources to avoid race conditions during first apply.

## Technical reference (auto-generated)

The sections below (`Requirements`, `Providers`, `Resources`, `Inputs`, `Outputs`) are generated with `terraform-docs`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | >= 0.75.0, < 1.0.0 |
| <a name="requirement_talos"></a> [talos](#requirement\_talos) | >= 0.7.0, < 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.99.0 |
| <a name="provider_talos"></a> [talos](#provider\_talos) | 0.10.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [proxmox_virtual_environment_download_file.talos_image](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_download_file) | resource |
| [proxmox_virtual_environment_vm.master](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [proxmox_virtual_environment_vm.worker](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm) | resource |
| [talos_cluster_kubeconfig.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/cluster_kubeconfig) | resource |
| [talos_machine_bootstrap.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_bootstrap) | resource |
| [talos_machine_configuration_apply.master](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_configuration_apply.worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_configuration_apply) | resource |
| [talos_machine_secrets.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine_secrets) | resource |
| [terraform_data.input_validation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [talos_client_configuration.this](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/client_configuration) | data source |
| [talos_machine_configuration.controlplane](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |
| [talos_machine_configuration.worker](https://registry.terraform.io/providers/siderolabs/talos/latest/docs/data-sources/machine_configuration) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | Optional Kubernetes API endpoint (for example, a load balancer URL). If null, the first master IP is used | `string` | `null` | no |
| <a name="input_control_plane_machine_config_patches"></a> [control\_plane\_machine\_config\_patches](#input\_control\_plane\_machine\_config\_patches) | Additional YAML patches applied to all control-plane nodes | `list(string)` | `[]` | no |
| <a name="input_default_install_disk"></a> [default\_install\_disk](#input\_default\_install\_disk) | Default Talos installation disk used in machine config patches | `string` | `"/dev/sda"` | no |
| <a name="input_default_talos_interface"></a> [default\_talos\_interface](#input\_default\_talos\_interface) | Default Talos network interface used for static network patches | `string` | `"eth0"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Optional Kubernetes version for generated Talos machine configuration | `string` | `null` | no |
| <a name="input_master_default_disk_gb"></a> [master\_default\_disk\_gb](#input\_master\_default\_disk\_gb) | Default disk size (GB) for masters when a node does not define disk\_gb | `number` | `32` | no |
| <a name="input_masters"></a> [masters](#input\_masters) | Master nodes definition | <pre>list(object({<br/>    host         = string<br/>    proxmox_node = string<br/><br/>    ip_mode = optional(string, "dhcp")<br/>    ip      = optional(string)<br/>    cidr    = optional(number)<br/>    gateway = optional(string)<br/><br/>    ram_mb    = number<br/>    cpu_cores = number<br/>    cpu_type  = optional(string)<br/><br/>    disk_gb      = optional(number)<br/>    datastore_id = optional(string)<br/>    pool_id      = optional(string)<br/>    bridge       = optional(string)<br/>    vlan_id      = optional(number)<br/>    mac_address  = optional(string)<br/><br/>    install_disk           = optional(string)<br/>    machine_config_patches = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_proxmox_default_bridge"></a> [proxmox\_default\_bridge](#input\_proxmox\_default\_bridge) | Default Proxmox network bridge when a node does not define bridge | `string` | `"vmbr0"` | no |
| <a name="input_proxmox_default_cpu_type"></a> [proxmox\_default\_cpu\_type](#input\_proxmox\_default\_cpu\_type) | Default Proxmox emulated CPU type when a node does not define cpu\_type | `string` | `"x86-64-v2-AES"` | no |
| <a name="input_proxmox_default_pool_id"></a> [proxmox\_default\_pool\_id](#input\_proxmox\_default\_pool\_id) | Default Proxmox pool ID when a node does not define pool\_id | `string` | `null` | no |
| <a name="input_proxmox_default_vlan_id"></a> [proxmox\_default\_vlan\_id](#input\_proxmox\_default\_vlan\_id) | Default Proxmox VLAN ID when a node does not define vlan\_id | `number` | `null` | no |
| <a name="input_proxmox_default_vm_datastore"></a> [proxmox\_default\_vm\_datastore](#input\_proxmox\_default\_vm\_datastore) | Default Proxmox datastore for VM disks when a node does not define datastore\_id | `string` | `"local-lvm"` | no |
| <a name="input_proxmox_efi_disk_type"></a> [proxmox\_efi\_disk\_type](#input\_proxmox\_efi\_disk\_type) | EFI disk type used with OVMF BIOS | `string` | `"4m"` | no |
| <a name="input_proxmox_efi_pre_enrolled_keys"></a> [proxmox\_efi\_pre\_enrolled\_keys](#input\_proxmox\_efi\_pre\_enrolled\_keys) | Whether to enable pre-enrolled secure boot keys on EFI disk | `bool` | `false` | no |
| <a name="input_proxmox_iso_datastore"></a> [proxmox\_iso\_datastore](#input\_proxmox\_iso\_datastore) | Proxmox datastore where the Talos qcow2 image is downloaded | `string` | `"local"` | no |
| <a name="input_proxmox_machine_type"></a> [proxmox\_machine\_type](#input\_proxmox\_machine\_type) | Proxmox machine type for VMs | `string` | `"q35"` | no |
| <a name="input_proxmox_vm_id_start"></a> [proxmox\_vm\_id\_start](#input\_proxmox\_vm\_id\_start) | First VM ID to assign in Proxmox; IDs are allocated sequentially from this value | `number` | `100` | no |
| <a name="input_talos_arch"></a> [talos\_arch](#input\_talos\_arch) | Talos architecture | `string` | `"amd64"` | no |
| <a name="input_talos_cluster_name"></a> [talos\_cluster\_name](#input\_talos\_cluster\_name) | Talos cluster name | `string` | n/a | yes |
| <a name="input_talos_nameservers"></a> [talos\_nameservers](#input\_talos\_nameservers) | Optional list of DNS nameservers used when a node is configured with static IP | `list(string)` | `[]` | no |
| <a name="input_talos_schematic_id"></a> [talos\_schematic\_id](#input\_talos\_schematic\_id) | Talos Factory schematic ID used to build the image URL | `string` | n/a | yes |
| <a name="input_talos_version"></a> [talos\_version](#input\_talos\_version) | Talos OS version used for both image download and machine configuration generation | `string` | n/a | yes |
| <a name="input_worker_default_disk_gb"></a> [worker\_default\_disk\_gb](#input\_worker\_default\_disk\_gb) | Default disk size (GB) for workers when a node does not define disk\_gb | `number` | `80` | no |
| <a name="input_worker_machine_config_patches"></a> [worker\_machine\_config\_patches](#input\_worker\_machine\_config\_patches) | Additional YAML patches applied to all worker nodes | `list(string)` | `[]` | no |
| <a name="input_workers"></a> [workers](#input\_workers) | Worker nodes definition | <pre>list(object({<br/>    host         = string<br/>    proxmox_node = string<br/><br/>    ip_mode = optional(string, "dhcp")<br/>    ip      = optional(string)<br/>    cidr    = optional(number)<br/>    gateway = optional(string)<br/><br/>    ram_mb    = number<br/>    cpu_cores = number<br/>    cpu_type  = optional(string)<br/><br/>    disk_gb      = optional(number)<br/>    datastore_id = optional(string)<br/>    pool_id      = optional(string)<br/>    bridge       = optional(string)<br/>    vlan_id      = optional(number)<br/>    mac_address  = optional(string)<br/><br/>    install_disk           = optional(string)<br/>    machine_config_patches = optional(list(string), [])<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_all_node_ips"></a> [all\_node\_ips](#output\_all\_node\_ips) | Ordered list of all node IPs |
| <a name="output_control_plane_ips"></a> [control\_plane\_ips](#output\_control\_plane\_ips) | Ordered list of control-plane IPs |
| <a name="output_kubeconfig"></a> [kubeconfig](#output\_kubeconfig) | Kubernetes kubeconfig |
| <a name="output_master_ips"></a> [master\_ips](#output\_master\_ips) | Map of master hostname to resolved IP |
| <a name="output_node_inventory"></a> [node\_inventory](#output\_node\_inventory) | Node inventory with role, proxmox host, and resolved IP |
| <a name="output_talosconfig"></a> [talosconfig](#output\_talosconfig) | Talos client configuration |
| <a name="output_worker_ips"></a> [worker\_ips](#output\_worker\_ips) | Map of worker hostname to resolved IP |
<!-- END_TF_DOCS -->

## Regenerate documentation

From the repository root:

```bash
terraform-docs markdown table --output-file README.md --output-mode inject .
```

## Release policy

- On each merge of a PR to `main`, GitHub Actions creates a new release automatically.
- Version bump defaults to patch (`vX.Y.Z` -> `vX.Y.Z+1` patch part).
- The workflow is idempotent for retries and reruns: if the merge commit already has a released tag, it exits without creating a newer version.
- To control bump level, add one of these labels to the PR:
  - `release:major` (or `semver:major`)
  - `release:minor` (or `semver:minor`)
