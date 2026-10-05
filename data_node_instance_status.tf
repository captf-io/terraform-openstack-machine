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

# The server's status for the health output, re-read on every refresh
# (locals_health.tf). The resource's power_state is an argument tests cannot
# mock; this read's is computed, for one more GET (DESIGN.md decision 6).
data "openstack_compute_instance_v2" "node_instance_status" {
  # Counted over the server, never [0]: a server deleted out of band means
  # no read, not a failed refresh (DESIGN.md "Out-of-band deletes"). A
  # server in BUILD is not read either: this data source fails on BUILD,
  # which the resource accepts, and every destroy refreshes data sources,
  # so a server stuck building could never be destroyed.
  count = length(local.status_readable_servers)

  id = local.status_readable_servers[count.index].id
}
