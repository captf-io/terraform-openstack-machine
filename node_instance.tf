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

# The machine's Nova server, booted on the pre-created port with the bootstrap
# payload as user data (DESIGN.md decision 5). It is named machine_name: the
# cloud controller manager finds servers by Node name.
resource "openstack_compute_instance_v2" "node_instance" {
  # count = 1 makes the server a collection: after an out-of-band delete a
  # refresh sees an empty one, a known value, so provider_id turns null and
  # health reports terminated; a single resource would read as unknown
  # (DESIGN.md "Out-of-band deletes").
  count = 1

  availability_zone = local.failure_domain
  config_drive      = var.config_drive
  flavor_name       = var.flavor_name
  # Boot from volume names the image in block_device instead.
  image_id   = var.root_volume_size_gib == null ? var.image_id : null
  image_name = var.root_volume_size_gib == null ? local.image_name : null
  key_pair   = var.key_pair
  # Nova metadata instead of Nova tags: tags allow 60 characters and no
  # "/", too little for the captf tags (README "Tags").
  metadata = local.tags
  name     = var.machine_name
  # Base64 passes through to Nova unchanged (gophercloud v2.8.0 sends
  # valid base64 as is), so gzip and Ignition payloads are safe; state
  # keeps only its SHA1.
  user_data = var.bootstrap_data

  dynamic "block_device" {
    for_each = var.root_volume_size_gib == null ? [] : [var.root_volume_size_gib]

    content {
      boot_index            = 0
      delete_on_termination = true
      destination_type      = "volume"
      source_type           = "image"
      uuid                  = var.image_id
      volume_size           = block_device.value
      volume_type           = var.root_volume_type
    }
  }

  network {
    port = openstack_networking_port_v2.node_port[0].id
  }

  # Control-plane machines join the cluster's server group (anti-affinity).
  dynamic "scheduler_hints" {
    for_each = local.server_group_id == null ? [] : [local.server_group_id]

    content {
      group = scheduler_hints.value
    }
  }

  lifecycle {
    # A newer image under the same name, or a deleted one, must never
    # rebuild a running node: the provider rebuilds in place on an image
    # change. Machines are immutable; a new image is a new template.
    ignore_changes = [image_id, image_name]

    precondition {
      condition     = (var.image_id == null) != (var.image_name == null)
      error_message = "image_id and image_name: set exactly one of them in spec.template.spec.variables of the TerraformMachineTemplate."
    }
    precondition {
      condition     = !local.image_name_templated || var.kubernetes_version != null
      error_message = "image_name holds {version} or {semver}, but kubernetes_version (Machine.spec.version) is null: set spec.version on the Machine, or name the image without placeholders."
    }
    precondition {
      condition     = var.root_volume_size_gib == null || var.image_id != null
      error_message = "image_id must be set with root_volume_size_gib: Nova creates the root volume from an image UUID, not a name."
    }
    precondition {
      condition     = var.failure_domain == null || contains(local.failure_domain_names, coalesce(var.failure_domain, "-"))
      error_message = "failure_domain ${coalesce(var.failure_domain, "-")} is not one of the cluster's availability zones (${join(", ", local.failure_domain_names)})."
    }
    precondition {
      # CONVENTIONS.md section 13: Ignition is not known to take gzip here.
      condition     = !(var.bootstrap_format == "ignition" && startswith(var.bootstrap_data, "H4sI"))
      error_message = "bootstrap_data is gzipped Ignition, which this module refuses: turn off gzipUserData for Ignition, or use cloud-config."
    }
    precondition {
      # Nova's limit on user_data, which is base64 (compute API schema
      # servers.py: maxLength 65535).
      condition     = length(var.bootstrap_data) <= 65535
      error_message = "bootstrap_data is over Nova's 65,535-byte user data limit once base64-encoded: compress it (CAPRKE2 gzipUserData) or shrink the bootstrap configuration."
    }
  }

  # The members share no reference with the server, so only this orders
  # them: a control-plane machine is in the API pools before its server
  # boots (machine.md "Control-plane machines"). On destroy the server goes
  # first; the monitor marks the member down, after CAPI drained the node.
  depends_on = [openstack_lb_member_v2.api_members]
}
