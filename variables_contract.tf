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

# The machine role's contract inputs, in contract order, with the contract's
# types (https://captf.io/docs/module-author/contract/v1alpha1/common.html and
# https://captf.io/docs/module-author/contract/v1alpha1/machine.html).

# Read only by its own validation, which tflint does not count as a use.
# tflint-ignore: terraform_unused_declarations
variable "captf_contract" {
  description = "Contract version the controller rendered these inputs for (common.md \"Inputs\")."
  type        = string

  validation {
    condition     = var.captf_contract == "v1alpha1"
    error_message = "captf_contract must be \"v1alpha1\": this module implements the v1alpha1 machine role only."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "captf_cluster" {
  description = "The owning CAPI Cluster (common.md \"Inputs\"). Unused: captf_tags already carries the cluster name, and machine resources are keyed by the TerraformMachine."
  type = object({
    name      = string
    namespace = string
  })
}

variable "captf_object" {
  description = "The TerraformMachine being reconciled (common.md \"Inputs\"); its namespace and name key the port name."
  type = object({
    kind      = string
    name      = string
    namespace = string
  })
}

variable "captf_cluster_outputs" {
  description = "The cluster role's exports (common.md \"captf_cluster_outputs\"): network, security groups, server group, API pools and failure domains; {} (or null) when the TerraformCluster is externally managed, see external_cluster_exports."
  # No default: the controller always passes it to machines
  # (CONVENTIONS.md section 8).
  type = any

  validation {
    condition     = var.captf_cluster_outputs == null || try(length(keys(var.captf_cluster_outputs)) == 0, false) || try(var.captf_cluster_outputs.schema == "captf.io/openstack-cluster/v1", false)
    error_message = "captf_cluster_outputs must come from the OpenStack cluster module (exports schema captf.io/openstack-cluster/v1), or be {} for an externally managed TerraformCluster. Use an openstack-cluster image of the same release line as this machine image."
  }
}

variable "captf_tags" {
  description = "Tags the controller sets on every cloud resource (common.md \"captf_tags\"); mapped to Nova metadata keys and Neutron/Octavia tag strings in locals_tags.tf."
  type        = map(string)
}

variable "machine_name" {
  description = "Name of the owning CAPI Machine (machine.md \"Inputs\"): the Nova server name, which the cloud controller manager matches to the Node name."
  type        = string
}

variable "bootstrap_data" {
  description = "Base64 of the bootstrap Secret's value (machine.md \"bootstrap_data\"), passed to Nova as user data unchanged."
  type        = string
  sensitive   = true
}

variable "bootstrap_format" {
  description = "Format of the decoded bootstrap payload, cloud-config or ignition (machine.md \"bootstrap_format\"). Both pass through Nova user data unchanged; gzipped Ignition is refused."
  type        = string

  validation {
    condition     = contains(["cloud-config", "ignition"], var.bootstrap_format)
    error_message = "bootstrap_format must be cloud-config or ignition."
  }
}

variable "failure_domain" {
  description = "Machine.spec.failureDomain, a Nova availability zone from the cluster's exports, or null to let the module pick one (machine.md \"failure_domain (input)\")."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Machine.spec.version (machine.md \"kubernetes_version (input)\"), without its +rke2rN suffix: fills the {version} and {semver} placeholders of image_name."
  type        = string
  default     = null
}

variable "control_plane" {
  description = "Whether the Machine is a control-plane machine (machine.md \"control_plane (input)\"): it then joins the API pools, the control-plane security group and the server group."
  type        = bool
}
