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

# Machine health from the Nova server status (CONVENTIONS.md section 10),
# every documented status mapped (README "Health").
# https://docs.openstack.org/api-guide/compute/server_concepts.html
locals {
  # Nova server status -> contract health ("health" in common.md). The
  # status data source reads only ACTIVE, SHUTOFF, PAUSED, SHELVED,
  # SHELVED_OFFLOADED, MIGRATING and ERROR, and fails the refresh on the
  # others; they are mapped all the same (DESIGN.md "Unverified").
  health_by_state = {
    ACTIVE = { state = "running", healthy = true, reason = null }
    # Live migration and a password reset keep the guest running.
    MIGRATING         = { state = "running", healthy = true, reason = null }
    PASSWORD          = { state = "running", healthy = true, reason = null }
    BUILD             = { state = "pending", healthy = false, reason = "ServerBuilding" }
    REBOOT            = { state = "pending", healthy = false, reason = "ServerRebooting" }
    HARD_REBOOT       = { state = "pending", healthy = false, reason = "ServerRebooting" }
    REBUILD           = { state = "pending", healthy = false, reason = "ServerRebuilding" }
    RESIZE            = { state = "pending", healthy = false, reason = "ServerResizing" }
    VERIFY_RESIZE     = { state = "pending", healthy = false, reason = "ServerResizing" }
    REVERT_RESIZE     = { state = "pending", healthy = false, reason = "ServerResizing" }
    SHUTOFF           = { state = "stopped", healthy = false, reason = "ServerShutOff" }
    SUSPENDED         = { state = "stopped", healthy = false, reason = "ServerSuspended" }
    PAUSED            = { state = "stopped", healthy = false, reason = "ServerPaused" }
    SHELVED           = { state = "stopped", healthy = false, reason = "ServerShelved" }
    SHELVED_OFFLOADED = { state = "stopped", healthy = false, reason = "ServerShelved" }
    RESCUE            = { state = "degraded", healthy = false, reason = "ServerRescued" }
    ERROR             = { state = "degraded", healthy = false, reason = "ServerError" }
    SOFT_DELETED      = { state = "terminated", healthy = false, reason = "ServerDeleted" }
    DELETED           = { state = "terminated", healthy = false, reason = "ServerDeleted" }
    UNKNOWN           = { state = "unknown", healthy = false, reason = "ServerStatusUnknown" }
  }
  # The resource's own refreshed power_state decides whether the status
  # data source may read: it fails on BUILD (data_node_instance_status.tf).
  status_readable_servers = [for s in openstack_compute_instance_v2.node_instance : s if s.power_state != "build"]
  # The data source's status when it read one, else the resource's (BUILD).
  server_status  = try(upper(data.openstack_compute_instance_v2.node_instance_status[0].power_state), upper(one(openstack_compute_instance_v2.node_instance[*].power_state)), "")
  health_reading = lookup(local.health_by_state, local.server_status, { state = "unknown", healthy = false, reason = "ServerStatusUnknown" })

  # A refresh drops a server deleted out of band from state, which leaves
  # the counted resource empty: a known value, so it reads as gone
  # (node_instance.tf).
  server_gone = length(openstack_compute_instance_v2.node_instance) == 0

  health = local.server_gone ? {
    state   = "terminated"
    healthy = false
    message = "Nova server ${var.machine_name} not found: deleted outside this module"
    reasons = ["ServerNotFound"]
    } : {
    state   = local.health_reading.state
    healthy = local.health_reading.healthy
    message = "Nova server ${coalesce(one(openstack_compute_instance_v2.node_instance[*].id), "-")} is ${local.server_status == "" ? "UNKNOWN" : local.server_status}"
    reasons = local.health_reading.healthy ? [] : [local.health_reading.reason]
  }
}
