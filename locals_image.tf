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

# The Glance image name with its version placeholders filled in
# (CONVENTIONS.md section 8): {version} is Machine.spec.version (v1.31.4),
# {semver} the same without the "v" (1.31.4).
locals {
  # Without the +rke2rN build metadata (machine.md "kubernetes_version
  # (input)"); "-" only stands in for a null version, which a precondition
  # rejects when the name needs it.
  kubernetes_version   = split("+", coalesce(var.kubernetes_version, "-"))[0]
  image_name_templated = can(regex("\\{(version|semver)\\}", coalesce(var.image_name, "")))
  image_name           = var.image_name == null ? null : replace(replace(var.image_name, "{version}", local.kubernetes_version), "{semver}", trimprefix(local.kubernetes_version, "v"))
}
