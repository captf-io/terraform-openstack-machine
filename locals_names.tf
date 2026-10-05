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

# Names of the machine's OpenStack resources (CONVENTIONS.md section 6). The
# server itself is named machine_name, the exception the role README
# documents: the cloud controller manager finds servers by Node name.
locals {
  machine_key  = "${var.captf_object.namespace}/${var.captf_object.name}"
  machine_hash = substr(sha256(local.machine_key), 0, 8)
  # Neutron and Octavia names allow 255 characters; minus 9 for "-" and
  # the hash.
  name_max    = 255
  name_prefix = "${trimsuffix(substr(replace(lower("captf-${var.captf_object.namespace}-${var.captf_object.name}"), "/[^a-z0-9-]/", "-"), 0, local.name_max - 9), "-")}-${local.machine_hash}"
}
