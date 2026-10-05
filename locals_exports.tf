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

# The cluster's exports (CONVENTIONS.md section 12; shape in README
# "Exports"): captf_cluster_outputs, or external_cluster_exports when the
# TerraformCluster is externally managed and the controller passes {}.
locals {
  exports_keys = [
    "schema", "region", "network_id", "subnet_id", "failure_domains", "provider_id_format",
    "security_group_ids", "control_plane_server_group_id", "node_allowed_address_cidrs", "api",
  ]

  externally_managed = try(length(keys(var.captf_cluster_outputs)) == 0, true)
  # The two sources are objects of different types, which a conditional
  # cannot return; a JSON round trip gives both branches one type.
  exports         = jsondecode(local.externally_managed ? jsonencode(var.external_cluster_exports) : jsonencode(var.captf_cluster_outputs))
  exports_missing = [for k in local.exports_keys : k if !can(local.exports[k])]

  # Every value below falls back to an empty one, so a plan with bad
  # exports reaches the precondition on node_port that explains it
  # instead of failing on a missing attribute.
  region                = try(local.exports.region, "")
  network_id            = try(local.exports.network_id, "")
  subnet_id             = try(local.exports.subnet_id, "")
  provider_id_format    = try(local.exports.provider_id_format, "default")
  security_group_ids    = try(tolist(local.exports.security_group_ids[var.control_plane ? "control_plane" : "worker"]), [])
  server_group_id       = var.control_plane ? try(local.exports.control_plane_server_group_id, null) : null
  allowed_address_cidrs = try(tolist(local.exports.node_allowed_address_cidrs), [])
  # Control-plane machines join every API pool; workers join none.
  api_pools = { for name, pool in try(local.exports.api.pools, {}) : name => pool if var.control_plane }
}
