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

# A control-plane machine's membership in each API pool of the cluster, in
# its own state so its destroy deregisters it (machine.md "Control-plane
# machines"). Workers join no pool.
resource "openstack_lb_member_v2" "api_members" {
  for_each = local.api_pools

  # The server waits for the members (node_instance.tf depends_on), so
  # they exist before it boots, as kubeadm init and RKE2 joins require.
  address       = openstack_networking_port_v2.node_port[0].all_fixed_ips[0]
  name          = var.machine_name
  pool_id       = each.value.id
  protocol_port = each.value.port
  subnet_id     = local.subnet_id
  tags          = [for k, v in local.tags : "${k}=${v}"]
}
