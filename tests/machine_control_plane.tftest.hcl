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

# A control-plane machine applied twice: its pool memberships, server group
# and port must survive an identical re-apply.

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
  machine_name       = "demo-control-plane-x7k2p"
  bootstrap_data     = "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIGhlbGxvXQo="
  bootstrap_format   = "cloud-config"
  failure_domain     = null
  kubernetes_version = "v1.33.1"
  control_plane      = true

  flavor_name = "m1.large"
  image_name  = "ubuntu-24.04-kube-v1.33.1"
}

run "control_plane_happy_path" {
  assert {
    condition     = sort(keys(output.api_member_ids)) == tolist(["kube_apiserver"])
    error_message = "A control-plane machine has one member per exported pool."
  }
  assert {
    condition     = openstack_lb_member_v2.api_members["kube_apiserver"].address == "10.6.0.21"
    error_message = "The member address is the port's fixed IP."
  }
}

run "control_plane_reapply_is_stable" {
  # run.<name> works in OpenTofu's run variables but not in its assertions.
  variables {
    previous_member_ids  = run.control_plane_happy_path.api_member_ids
    previous_provider_id = run.control_plane_happy_path.provider_id
    previous_node_port   = run.control_plane_happy_path.node_port_id
  }

  assert {
    condition     = jsonencode(output.api_member_ids) == jsonencode(var.previous_member_ids)
    error_message = "A second identical apply must keep the pool members."
  }
  assert {
    condition     = output.provider_id == var.previous_provider_id && output.node_port_id == var.previous_node_port
    error_message = "A second identical apply must keep the server and the port."
  }
}
