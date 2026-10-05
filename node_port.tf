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

# The server's Neutron port on the cluster subnet, with the security groups
# and the allowed address pairs, created first so control-plane machines join
# the API pools before they boot (DESIGN.md decision 5).
resource "openstack_networking_port_v2" "node_port" {
  # Counted like node_instance, so addresses fall back to the hostname
  # after an out-of-band delete (DESIGN.md "Out-of-band deletes").
  count = 1

  description        = "CAPTF node ${var.machine_name} (${local.machine_key})"
  name               = local.name_prefix
  network_id         = local.network_id
  security_group_ids = concat(local.security_group_ids, var.additional_security_group_ids)
  tags               = [for k, v in local.tags : "${k}=${v}"]

  dynamic "allowed_address_pairs" {
    for_each = local.allowed_address_cidrs

    content {
      ip_address = allowed_address_pairs.value
    }
  }

  fixed_ip {
    subnet_id = local.subnet_id
  }

  lifecycle {
    precondition {
      condition     = !local.externally_managed || var.external_cluster_exports != null
      error_message = "external_cluster_exports must be set: the TerraformCluster is externally managed (captf_cluster_outputs is {}), so this module has no network to use. Set spec.template.spec.variables.external_cluster_exports on the TerraformMachineTemplate to the cluster's exports (README \"Exports\")."
    }
    precondition {
      condition     = length(local.exports_missing) == 0
      error_message = "captf_cluster_outputs (or external_cluster_exports) lacks ${join(", ", local.exports_missing)}: it must follow captf.io/openstack-cluster/v1 (README \"Exports\")."
    }
    precondition {
      condition     = length(local.oversized_tags) == 0
      error_message = "captf_tags and additional_tags must each fit in a 255-character \"<key>=<value>\" Neutron tag; too long: ${join(", ", local.oversized_tags)}. Shorten the Cluster, TerraformMachine or template name."
    }
  }
}
