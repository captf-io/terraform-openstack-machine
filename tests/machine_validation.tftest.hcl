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

# One plan per variable validation and precondition of the machine role,
# each expected to fail on exactly that check (CONVENTIONS.md section 14).

mock_provider "openstack" {
  mock_resource "openstack_networking_port_v2" {
    defaults = {
      all_fixed_ips = ["10.6.0.21"]
    }
  }
}

variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformMachine", name = "demo-md-0-abcde", namespace = "team-a" }
  captf_cluster_outputs = {
    schema                        = "captf.io/openstack-cluster/v1"
    region                        = "RegionOne"
    network_id                    = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38"
    subnet_id                     = "5c1d7a0e-2b4f-4e83-9a61-0d8f3b2c4e71"
    failure_domains               = { az-1 = {}, az-2 = {} }
    distribution                  = "kubeadm"
    provider_id_format            = "default"
    security_group_ids            = { control_plane = [], worker = ["6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"] }
    control_plane_server_group_id = null
    node_allowed_address_cidrs    = []
    api                           = null
  }
  captf_tags = {
    "captf.io/cluster"    = "demo"
    "captf.io/namespace"  = "team-a"
    "captf.io/kind"       = "TerraformMachine"
    "captf.io/name"       = "demo-md-0-abcde"
    "captf.io/managed-by" = "captf"
    "captf.io/template"   = ""
  }
  machine_name       = "demo-md-0-7d9f8-xk2lq"
  bootstrap_data     = "I2Nsb3VkLWNvbmZpZwpydW5jbWQ6IFtlY2hvIGhlbGxvXQo="
  bootstrap_format   = "cloud-config"
  failure_domain     = null
  kubernetes_version = null
  control_plane      = false

  flavor_name = "m1.large"
  image_name  = "ubuntu-24.04-kube-v1.33.1"
}

run "invalid_captf_contract" {
  command = plan
  variables {
    captf_contract = "v1beta1"
  }
  expect_failures = [var.captf_contract]
}

run "invalid_bootstrap_format" {
  command = plan
  variables {
    bootstrap_format = "shell"
  }
  expect_failures = [var.bootstrap_format]
}

run "invalid_additional_security_group_ids" {
  command = plan
  variables {
    additional_security_group_ids = ["default"]
  }
  expect_failures = [var.additional_security_group_ids]
}

run "invalid_additional_tags_count" {
  command = plan
  variables {
    additional_tags = { for i in range(45) : "tag-${i}" => "x" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_key" {
  command = plan
  variables {
    additional_tags = { "example.com/team" = "platform" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_reserved" {
  command = plan
  variables {
    additional_tags = { "captf.io:name" = "other" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_length" {
  command = plan
  variables {
    additional_tags = { note = format("%0251d", 0) }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_external_cluster_exports" {
  command = plan
  variables {
    external_cluster_exports = { schema = "captf.io/aws-cluster/v1" }
  }
  expect_failures = [var.external_cluster_exports]
}

run "invalid_flavor_name" {
  command = plan
  variables {
    flavor_name = null
  }
  expect_failures = [var.flavor_name]
}

run "invalid_image_id" {
  command = plan
  variables {
    image_name = null
    image_id   = "ubuntu"
  }
  expect_failures = [var.image_id]
}

run "invalid_image_name" {
  command = plan
  variables {
    image_name = ""
  }
  expect_failures = [var.image_name]
}

run "invalid_key_pair" {
  command = plan
  variables {
    key_pair = ""
  }
  expect_failures = [var.key_pair]
}

run "invalid_root_volume_size_gib" {
  command = plan
  variables {
    image_name           = null
    image_id             = "e5f6a7b8-c9d0-4e1f-a2b3-c4d5e6f7a8b9"
    root_volume_size_gib = 0.5
  }
  expect_failures = [var.root_volume_size_gib]
}

run "invalid_root_volume_type" {
  command = plan
  variables {
    root_volume_type = ""
  }
  expect_failures = [var.root_volume_type]
}

run "wrong_exports_schema" {
  command = plan
  variables {
    captf_cluster_outputs = { schema = "captf.io/openstack-cluster/v2" }
  }
  expect_failures = [var.captf_cluster_outputs]
}

run "externally_managed_without_override" {
  command = plan
  variables {
    captf_cluster_outputs = {}
  }
  expect_failures = [openstack_networking_port_v2.node_port]
}

run "externally_managed_with_incomplete_override" {
  command = plan
  variables {
    captf_cluster_outputs    = {}
    external_cluster_exports = { schema = "captf.io/openstack-cluster/v1", network_id = "9e4b2c71-6a3d-4f05-8b19-7c2e5d0a6f38" }
  }
  expect_failures = [openstack_networking_port_v2.node_port]
}

run "rejects_oversized_tags" {
  command = plan
  variables {
    captf_tags = {
      "captf.io/cluster"  = "demo"
      "captf.io/template" = format("%0240d", 0)
    }
  }
  expect_failures = [openstack_networking_port_v2.node_port]
}

run "unknown_failure_domain" {
  command = plan
  variables {
    failure_domain = "az-9"
  }
  expect_failures = [openstack_compute_instance_v2.node_instance]
}

run "bootstrap_too_large" {
  command = plan
  variables {
    bootstrap_data = format("%065536d", 0)
  }
  expect_failures = [openstack_compute_instance_v2.node_instance]
}

run "rejects_gzipped_ignition" {
  command = plan
  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "H4sIAAAAAAAC/1NOzskvTdFNzs9Ly0znKirNS85NsVKITk3OyFfISM3JyY/lAgDckH8lIwAAAA=="
  }
  expect_failures = [openstack_compute_instance_v2.node_instance]
}

run "rejects_image_placeholder_without_version" {
  command = plan
  variables {
    image_name         = "ubuntu-kube-{version}"
    kubernetes_version = null
  }
  expect_failures = [openstack_compute_instance_v2.node_instance]
}

run "rejects_both_images" {
  command = plan
  variables {
    image_id = "e5f6a7b8-c9d0-4e1f-a2b3-c4d5e6f7a8b9"
  }
  expect_failures = [openstack_compute_instance_v2.node_instance]
}

run "rejects_no_image" {
  command = plan
  variables {
    image_name = null
  }
  expect_failures = [openstack_compute_instance_v2.node_instance]
}

run "rejects_root_volume_without_image_id" {
  command = plan
  variables {
    root_volume_size_gib = 40
  }
  expect_failures = [openstack_compute_instance_v2.node_instance]
}
