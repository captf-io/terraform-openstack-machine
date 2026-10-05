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

# Non-contract outputs, for operators: the controller never reads them.

output "api_member_ids" {
  description = "UUIDs of the Octavia pool members, keyed by pool (kube_apiserver, rke2_supervisor); empty on a worker."
  value       = { for name, member in openstack_lb_member_v2.api_members : name => member.id }
}

output "node_port_id" {
  description = "UUID of the server's Neutron port (`openstack port show <id>`); null once it is gone."
  value       = one(openstack_networking_port_v2.node_port[*].id)
}
