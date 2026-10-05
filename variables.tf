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

# User variables of the machine role, set through the TerraformMachineTemplate's
# spec.template.spec.variables or variablesFrom
# (https://captf.io/docs/user-guide/variables.html). Alphabetical.

variable "additional_security_group_ids" {
  description = "UUIDs of extra Neutron security groups for the node port, for example to admit monitoring. Empty by default: the cluster's groups cover Kubernetes."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.additional_security_group_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "additional_security_group_ids entries must be Neutron security group UUIDs."
  }
}

variable "additional_tags" {
  description = "Extra tags for every resource, as Nova metadata pairs and Neutron/Octavia \"<key>=<value>\" tags. Empty by default: captf_tags already identifies every resource."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    # Neutron allows 50 tags per resource and captf_tags takes 6.
    condition     = length(var.additional_tags) <= 44
    error_message = "additional_tags may hold at most 44 entries: Neutron allows 50 tags per resource and captf_tags takes 6."
  }
  validation {
    # The Nova server metadata key rule; it excludes "/" and "=", so every
    # Neutron tag string splits at its first "=".
    condition     = alltrue([for k in keys(var.additional_tags) : can(regex("^[a-zA-Z0-9-_:. ]{1,255}$", k))])
    error_message = "additional_tags keys must be 1 to 255 characters of letters, digits, \"-\", \"_\", \":\", \".\" and space (the Nova metadata key rule)."
  }
  validation {
    condition     = alltrue([for k in keys(var.additional_tags) : !startswith(lower(k), "captf.io:")])
    error_message = "additional_tags keys must not start with \"captf.io:\": that prefix holds the captf_tags."
  }
  validation {
    condition     = alltrue([for k, v in var.additional_tags : length("${k}=${v}") <= 255])
    error_message = "additional_tags entries must each fit in a 255-character \"<key>=<value>\" Neutron tag."
  }
}

variable "config_drive" {
  description = "Attach a config drive carrying the user data and metadata, for clouds or images that need it. False by default: the metadata service serves both. It does not turn the metadata service off."
  type        = bool
  default     = false
  nullable    = false
}

variable "external_cluster_exports" {
  description = "The exports of an externally managed TerraformCluster (captf_cluster_outputs is then {}), in the shape of captf.io/openstack-cluster/v1 (README \"Exports\"). Null by default: the cluster module's exports are used."
  type        = any
  default     = null

  validation {
    condition     = var.external_cluster_exports == null || try(var.external_cluster_exports.schema == "captf.io/openstack-cluster/v1", false)
    error_message = "external_cluster_exports must be null or an object with schema = \"captf.io/openstack-cluster/v1\" (README \"Exports\")."
  }
}

variable "flavor_name" {
  description = "Nova flavor of the server. Required: clouds share no flavor names, so there is no default; set spec.template.spec.variables.flavor_name on the TerraformMachineTemplate."
  type        = string
  default     = null

  validation {
    condition     = try(length(var.flavor_name) > 0, false)
    error_message = "flavor_name is required: set spec.template.spec.variables.flavor_name on the TerraformMachineTemplate to a Nova flavor name."
  }
}

variable "image_id" {
  description = "UUID of the Glance image to boot. Set exactly one of image_id and image_name; boot from volume needs image_id. Pinning the UUID keeps every machine of a template identical."
  type        = string
  default     = null

  validation {
    condition     = var.image_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.image_id))
    error_message = "image_id must be a Glance image UUID, or null."
  }
}

variable "image_name" {
  description = "Name of the Glance image to boot, resolved to an ID by the provider through Glance when the server is created; it must match exactly one image. {version} and {semver} stand for kubernetes_version (v1.31.4, 1.31.4). Set exactly one of image_id and image_name."
  type        = string
  default     = null

  validation {
    condition     = var.image_name == null || try(length(var.image_name) > 0, false)
    error_message = "image_name must be a non-empty Glance image name, or null."
  }
}

variable "key_pair" {
  description = "Name of a Nova key pair to inject for SSH. Null by default: no key, and the cluster admits no SSH unless ssh_allowed_cidrs is set."
  type        = string
  default     = null

  validation {
    condition     = var.key_pair == null || try(length(var.key_pair) > 0, false)
    error_message = "key_pair must be a non-empty Nova key pair name, or null."
  }
}

variable "root_volume_size_gib" {
  description = "Boot from a new Cinder volume of this size, created from image_id and deleted with the server. Null by default: boot from the flavor's local disk."
  type        = number
  default     = null

  validation {
    condition     = var.root_volume_size_gib == null || try(var.root_volume_size_gib >= 1 && floor(var.root_volume_size_gib) == var.root_volume_size_gib, false)
    error_message = "root_volume_size_gib must be a whole number of GiB, at least 1, or null."
  }
}

variable "root_volume_type" {
  description = "Cinder volume type of the root volume. Null by default: the cloud's default type. Used only with root_volume_size_gib."
  type        = string
  default     = null

  validation {
    condition     = var.root_volume_type == null || try(length(var.root_volume_type) > 0, false)
    error_message = "root_volume_type must be a non-empty Cinder volume type name, or null."
  }
}
