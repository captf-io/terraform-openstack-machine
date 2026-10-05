# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Unit tests of the machine role with a mocked OpenStack provider: nothing
# reaches a cloud. Plan-only runs come first, while the state is empty; the
# apply runs after them share one state. Run names follow CONVENTIONS.md
# section 14.

mock_provider "openstack" {
  # No id defaults: reapply_is_stable proves ids survive a second apply.
  mock_resource "openstack_networking_port_v2" {
    defaults = {
      all_fixed_ips = ["10.6.0.21"]
      mac_address   = "fa:16:3e:5d:7a:21"
    }
  }
  mock_data "openstack_compute_instance_v2" {
    defaults = {
      power_state       = "active"
      availability_zone = "az-3"
      flavor_name       = "m1.large"
    }
  }
}

# Every contract input the controller passes to the machine role, plus the
# user variables the module requires.
variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformMachine", name = "demo-md-0-abcde", namespace = "team-a" }
  captf_cluster_outputs = {
    schema             = "captf.io/openstack-cluster/v1"
    region             = "RegionOne"
    network_id         = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
    subnet_id          = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
    failure_domains    = { az-1 = {}, az-2 = {}, az-3 = {} }
    distribution       = "kubeadm"
    provider_id_format = "default"
    security_group_ids = {
      control_plane = ["2f6e1b8a-3c4d-4e5f-9a0b-1c2d3e4f5a6b", "6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"]
      worker        = ["6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"]
    }
    control_plane_server_group_id = "c3d4e5f6-a7b8-4c9d-8e0f-1a2b3c4d5e6f"
    node_allowed_address_cidrs    = ["192.168.0.0/16"]
    api = {
      pools = {
        kube_apiserver = { id = "d1e2f3a4-b5c6-4d7e-8f9a-0b1c2d3e4f5a", port = 6443 }
      }
    }
  }
  captf_tags = {
    "captf.io/cluster"    = "demo"
    "captf.io/namespace"  = "team-a"
    "captf.io/kind"       = "TerraformMachine"
    "captf.io/name"       = "demo-md-0-abcde"
    "captf.io/managed-by" = "captf"
    "captf.io/template"   = "demo-md-0"
  }
  machine_name       = "demo-md-0-7d9f8-xk2lq"
  bootstrap_data     = "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIGhlbGxvXQo="
  bootstrap_format   = "cloud-config"
  failure_domain     = null
  kubernetes_version = "v1.33.1"
  control_plane      = false

  flavor_name = "m1.large"
  image_name  = "ubuntu-24.04-kube-v1.33.1"
}

run "failure_domain_requested" {
  command = plan

  variables {
    failure_domain = "az-1"
  }

  assert {
    condition     = openstack_compute_instance_v2.node_instance[0].availability_zone == "az-1" && output.failure_domain == "az-1"
    error_message = "A requested failure domain must be the server's availability zone and the output, exactly."
  }
}

run "failure_domain_defaulted" {
  command = plan

  # sha256("demo-md-0-7d9f8-xk2lq") begins d01e282a; 3491637290 mod 3 is
  # 2, so the sorted zones give az-3. The pick depends on the name alone.
  assert {
    condition     = openstack_compute_instance_v2.node_instance[0].availability_zone == "az-3" && output.failure_domain == "az-3"
    error_message = "Without a request the zone is picked from the sha256 of machine_name: az-3 for this name."
  }
}

run "control_plane_registers_backend" {
  command = plan

  variables {
    machine_name  = "demo-control-plane-x7k2p"
    control_plane = true
  }

  assert {
    condition = (
      sort(keys(openstack_lb_member_v2.api_members)) == tolist(["kube_apiserver"])
      && openstack_lb_member_v2.api_members["kube_apiserver"].pool_id == "d1e2f3a4-b5c6-4d7e-8f9a-0b1c2d3e4f5a"
      && openstack_lb_member_v2.api_members["kube_apiserver"].protocol_port == 6443
      && openstack_lb_member_v2.api_members["kube_apiserver"].subnet_id == "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
    )
    error_message = "A control-plane machine must join every exported API pool on its backend port, on the cluster subnet."
  }
  assert {
    condition     = openstack_networking_port_v2.node_port[0].security_group_ids == toset(["2f6e1b8a-3c4d-4e5f-9a0b-1c2d3e4f5a6b", "6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"])
    error_message = "A control-plane port carries the control-plane and node groups."
  }
  assert {
    condition     = [for h in openstack_compute_instance_v2.node_instance[0].scheduler_hints : h.group] == ["c3d4e5f6-a7b8-4c9d-8e0f-1a2b3c4d5e6f"]
    error_message = "A control-plane server joins the cluster's server group."
  }
}

run "worker_has_no_backend" {
  command = plan

  assert {
    condition     = length(openstack_lb_member_v2.api_members) == 0
    error_message = "A worker joins no API pool."
  }
  assert {
    condition     = openstack_networking_port_v2.node_port[0].security_group_ids == toset(["6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"])
    error_message = "A worker port carries the node group only."
  }
  assert {
    condition     = length(openstack_compute_instance_v2.node_instance[0].scheduler_hints) == 0
    error_message = "A worker joins no server group."
  }
}

run "spot_is_interruptible" {
  command = plan

  # Nova has no spot or preemptible servers: interruptible is always false,
  # and this run pins it.
  assert {
    condition     = output.interruptible == false
    error_message = "interruptible must be false: no OpenStack server is preemptible."
  }
}

run "externally_managed_with_override" {
  command = plan

  variables {
    captf_cluster_outputs = {}
    external_cluster_exports = {
      schema                        = "captf.io/openstack-cluster/v1"
      region                        = "RegionTwo"
      network_id                    = "0a1b2c3d-4e5f-4061-8293-a4b5c6d7e8f9"
      subnet_id                     = "1b2c3d4e-5f60-4172-93a4-b5c6d7e8f90a"
      failure_domains               = { nova = {} }
      distribution                  = "kubeadm"
      provider_id_format            = "regional"
      security_group_ids            = { control_plane = [], worker = ["2c3d4e5f-6071-4283-a4b5-c6d7e8f90a1b"] }
      control_plane_server_group_id = null
      node_allowed_address_cidrs    = []
      api                           = null
    }
  }

  assert {
    condition = (
      openstack_networking_port_v2.node_port[0].network_id == "0a1b2c3d-4e5f-4061-8293-a4b5c6d7e8f9"
      && one(openstack_networking_port_v2.node_port[0].fixed_ip).subnet_id == "1b2c3d4e-5f60-4172-93a4-b5c6d7e8f90a"
      && openstack_compute_instance_v2.node_instance[0].availability_zone == "nova"
    )
    error_message = "external_cluster_exports must stand in for the empty captf_cluster_outputs."
  }
}

run "bootstrap_cloud_config" {
  command = plan

  assert {
    condition     = nonsensitive(openstack_compute_instance_v2.node_instance[0].user_data) == "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIGhlbGxvXQo="
    error_message = "cloud-config user data must be the bootstrap base64, unchanged."
  }
}

run "bootstrap_ignition" {
  command = plan

  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
  }

  assert {
    condition     = nonsensitive(openstack_compute_instance_v2.node_instance[0].user_data) == "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
    error_message = "Ignition user data must be the bootstrap base64, unchanged."
  }
}

run "bootstrap_gzip" {
  command = plan

  # CAPRKE2 gzipUserData: raw gzip, not UTF-8. Decoding it would fail; it
  # must pass through as base64.
  variables {
    bootstrap_data = "H4sIAAAAAAAC/1NOzskvTdFNzs9Ly0znKirNS85NsVKITk3OyFfISM3JyY/lAgDckH8lIwAAAA=="
  }

  assert {
    condition     = nonsensitive(openstack_compute_instance_v2.node_instance[0].user_data) == "H4sIAAAAAAAC/1NOzskvTdFNzs9Ly0znKirNS85NsVKITk3OyFfISM3JyY/lAgDckH8lIwAAAA=="
    error_message = "A gzip payload must pass through as base64, unchanged."
  }
}

run "image_name_placeholders" {
  command = plan

  variables {
    image_name         = "ubuntu-2404-kube-{version}-{semver}"
    kubernetes_version = "v1.33.1+rke2r1"
  }

  assert {
    condition     = openstack_compute_instance_v2.node_instance[0].image_name == "ubuntu-2404-kube-v1.33.1-1.33.1"
    error_message = "{version} and {semver} must come from kubernetes_version without its +rke2rN suffix."
  }
}

run "boot_from_volume" {
  command = plan

  variables {
    image_name           = null
    image_id             = "e5f6a7b8-c9d0-4e1f-a2b3-c4d5e6f7a8b9"
    root_volume_size_gib = 40
    root_volume_type     = "ssd"
  }

  assert {
    condition = (
      openstack_compute_instance_v2.node_instance[0].block_device[0].uuid == "e5f6a7b8-c9d0-4e1f-a2b3-c4d5e6f7a8b9"
      && openstack_compute_instance_v2.node_instance[0].block_device[0].volume_size == 40
      && openstack_compute_instance_v2.node_instance[0].block_device[0].volume_type == "ssd"
      && openstack_compute_instance_v2.node_instance[0].block_device[0].delete_on_termination
    )
    error_message = "Boot from volume creates a root volume from image_id, deleted with the server."
  }
}

run "tags_on_taggable_resources" {
  command = plan

  variables {
    machine_name    = "demo-control-plane-x7k2p"
    control_plane   = true
    additional_tags = { team = "platform" }
  }

  assert {
    condition = alltrue([
      for tags in concat([openstack_networking_port_v2.node_port[0].tags], [for m in openstack_lb_member_v2.api_members : m.tags]) :
      tags == toset(["captf.io:cluster=demo", "captf.io:namespace=team-a", "captf.io:kind=TerraformMachine", "captf.io:name=demo-md-0-abcde", "captf.io:managed-by=captf", "captf.io:template=demo-md-0", "team=platform"])
    ])
    error_message = "The port and the pool members must carry the captf tags as captf.io:<key>=<value> strings, plus additional_tags."
  }
  assert {
    condition = openstack_compute_instance_v2.node_instance[0].metadata == tomap({
      "captf.io:cluster"    = "demo"
      "captf.io:namespace"  = "team-a"
      "captf.io:kind"       = "TerraformMachine"
      "captf.io:name"       = "demo-md-0-abcde"
      "captf.io:managed-by" = "captf"
      "captf.io:template"   = "demo-md-0"
      "team"                = "platform"
    })
    error_message = "The server must carry the captf tags as Nova metadata with \"/\" mapped to \":\", plus additional_tags."
  }
}

run "happy_path" {
  assert {
    condition     = output.provider_id == "openstack:///${openstack_compute_instance_v2.node_instance[0].id}"
    error_message = "provider_id must be openstack:///<server-id>, as the cloud controller manager writes it."
  }
  assert {
    condition     = jsonencode(output.addresses) == jsonencode([{ type = "InternalIP", address = "10.6.0.21" }, { type = "Hostname", address = "demo-md-0-7d9f8-xk2lq" }])
    error_message = "addresses must be the port's fixed IP and the hostname."
  }
  assert {
    condition     = output.failure_domain == "az-3"
    error_message = "failure_domain must be the zone the server was placed in."
  }
  assert {
    condition     = output.interruptible == false
    error_message = "interruptible is always false."
  }
  assert {
    condition = (
      output.health.state == "running" && output.health.healthy && length(output.health.reasons) == 0
      && output.health.message == "Nova server ${openstack_compute_instance_v2.node_instance[0].id} is ACTIVE"
    )
    error_message = "An ACTIVE server is running and healthy, and the message names the state."
  }
  assert {
    condition = (
      openstack_compute_instance_v2.node_instance[0].name == "demo-md-0-7d9f8-xk2lq"
      && openstack_compute_instance_v2.node_instance[0].flavor_name == "m1.large"
      && openstack_compute_instance_v2.node_instance[0].image_name == "ubuntu-24.04-kube-v1.33.1"
      && openstack_compute_instance_v2.node_instance[0].config_drive == false
      && openstack_compute_instance_v2.node_instance[0].key_pair == null
      && one(openstack_compute_instance_v2.node_instance[0].network).port == openstack_networking_port_v2.node_port[0].id
    )
    error_message = "The server is named machine_name, boots the image on the flavor, without key or config drive, on the node port."
  }
  assert {
    condition = (
      openstack_networking_port_v2.node_port[0].name == "captf-team-a-demo-md-0-abcde-8e0c006b"
      && openstack_networking_port_v2.node_port[0].network_id == "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
      && [for p in openstack_networking_port_v2.node_port[0].allowed_address_pairs : p.ip_address] == ["192.168.0.0/16"]
    )
    error_message = "The port is named from the TerraformMachine key, on the cluster network, and may send from the pod CIDR."
  }
}

run "reapply_is_stable" {
  # run.<name> works in OpenTofu's run variables but not in its assertions.
  variables {
    previous_provider_id = run.happy_path.provider_id
    previous_node_port   = run.happy_path.node_port_id
  }

  assert {
    condition     = output.provider_id == var.previous_provider_id
    error_message = "A second identical apply must keep the server."
  }
  assert {
    condition     = output.node_port_id == var.previous_node_port
    error_message = "A second identical apply must keep the port."
  }
}

run "provider_id_regional" {
  variables {
    captf_cluster_outputs = {
      schema                        = "captf.io/openstack-cluster/v1"
      region                        = "RegionOne"
      network_id                    = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
      subnet_id                     = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
      failure_domains               = { az-1 = {}, az-2 = {}, az-3 = {} }
      distribution                  = "kubeadm"
      provider_id_format            = "regional"
      security_group_ids            = { control_plane = [], worker = ["6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"] }
      control_plane_server_group_id = null
      node_allowed_address_cidrs    = ["192.168.0.0/16"]
      api                           = null
    }
  }

  assert {
    condition     = output.provider_id == "openstack://RegionOne/${openstack_compute_instance_v2.node_instance[0].id}"
    error_message = "With provider_id_format regional, provider_id is openstack://<region>/<server-id> (OS_CCM_REGIONAL)."
  }
}

run "health_running" {
  assert {
    condition     = output.health.state == "running" && output.health.healthy && length(output.health.reasons) == 0
    error_message = "ACTIVE is running and healthy."
  }
}

run "health_pending" {
  # In a cloud BUILD comes from the server resource itself: the status data
  # source is not read then (data_node_instance_status.tf). The override
  # drives the same mapping.
  override_data {
    target = data.openstack_compute_instance_v2.node_instance_status
    values = { power_state = "build" }
  }

  assert {
    condition     = output.health.state == "pending" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["ServerBuilding"])
    error_message = "BUILD is pending."
  }
}

run "health_stopped" {
  override_data {
    target = data.openstack_compute_instance_v2.node_instance_status
    values = { power_state = "shutoff" }
  }

  assert {
    condition     = output.health.state == "stopped" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["ServerShutOff"])
    error_message = "SHUTOFF is stopped."
  }
  assert {
    condition     = endswith(output.health.message, " is SHUTOFF")
    error_message = "health.message must name the Nova status."
  }
}

run "health_degraded" {
  override_data {
    target = data.openstack_compute_instance_v2.node_instance_status
    values = { power_state = "error" }
  }

  assert {
    condition     = output.health.state == "degraded" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["ServerError"])
    error_message = "ERROR is degraded."
  }
}

run "health_terminated" {
  override_data {
    target = data.openstack_compute_instance_v2.node_instance_status
    values = { power_state = "soft_deleted" }
  }

  assert {
    condition     = output.health.state == "terminated" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["ServerDeleted"])
    error_message = "SOFT_DELETED is terminated."
  }
}

run "health_unknown" {
  override_data {
    target = data.openstack_compute_instance_v2.node_instance_status
    values = { power_state = "something_new" }
  }

  assert {
    condition     = output.health.state == "unknown" && !output.health.healthy && jsonencode(output.health.reasons) == jsonencode(["ServerStatusUnknown"])
    error_message = "An unmapped status is unknown."
  }
}
