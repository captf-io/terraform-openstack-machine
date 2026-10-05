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

# The server's availability zone (CONVENTIONS.md section 11): the requested
# failure domain, else one picked from the cluster's zones by the sha256 of
# machine_name, so it never depends on apply order and machines spread evenly.
locals {
  failure_domain_names = sort(try(keys(local.exports.failure_domains), []))
  # Null only when the cluster lists no zone (the index fails): Nova then
  # picks.
  failure_domain_pick = try(local.failure_domain_names[parseint(substr(sha256(var.machine_name), 0, 8), 16) % length(local.failure_domain_names)], null)
  failure_domain      = var.failure_domain != null ? var.failure_domain : local.failure_domain_pick
}
