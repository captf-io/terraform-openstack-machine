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

# The machine role's contract outputs, in contract order
# (https://captf.io/docs/module-author/contract/v1alpha1/machine.html
# "Outputs" and common.md "Outputs").

output "provider_id" {
  description = "openstack:///<server-uuid>, or openstack://<region>/<server-uuid> with provider_id_format regional: what the OpenStack cloud controller manager writes to Node.spec.providerID (machine.md \"provider_id (output)\")."
  value = try(
    local.provider_id_format == "regional"
    ? "openstack://${local.region}/${openstack_compute_instance_v2.node_instance[0].id}"
    : "openstack:///${openstack_compute_instance_v2.node_instance[0].id}",
    null,
  )
}

output "addresses" {
  description = "An InternalIP per fixed IP of the node port and the Hostname, as the cloud controller manager reports them (machine.md \"addresses (output)\")."
  value = concat(
    [for ip in try(openstack_networking_port_v2.node_port[0].all_fixed_ips, []) : { type = "InternalIP", address = ip }],
    [{ type = "Hostname", address = var.machine_name }],
  )
}

output "failure_domain" {
  description = "The server's availability zone: the requested failure domain, or the one the module picked (machine.md \"failure_domain (output)\")."
  value       = local.failure_domain != null ? local.failure_domain : one(openstack_compute_instance_v2.node_instance[*].availability_zone)
}

output "interruptible" {
  description = "Always false: Nova has no spot or preemptible servers (machine.md \"interruptible (output)\")."
  value       = false
}

output "health" {
  description = "Health of the server from its Nova status (common.md \"Outputs\"; mapping in README \"Health\")."
  value       = local.health
}
