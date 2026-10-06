<h1 align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="72" height="72" alt="CAPTF"></a>
  <br>
  terraform-openstack-machine
</h1>

<p align="center">The CAPTF machine module for OpenStack</p>

<p align="center">
  <a href="https://github.com/captf-io/terraform-openstack-machine/actions/workflows/ci.yml"><img
    src="https://img.shields.io/github/actions/workflow/status/captf-io/terraform-openstack-machine/ci.yml?branch=main&amp;label=build&amp;labelColor=161B3A&amp;style=flat-square"
    alt="build"></a>
  <a href="https://captf.io/docs/module-author/contract/index.html"><img
    src="https://img.shields.io/static/v1?label=contract&amp;message=v1alpha1&amp;color=A974FF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="contract v1alpha1"></a>
  <a href="https://captf.io/docs/"><img
    src="https://img.shields.io/static/v1?label=docs&amp;message=captf.io&amp;color=5B8CFF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="docs captf.io"></a>
  <a href="https://github.com/captf-io/terraform-openstack-machine/blob/main/LICENSE.md"><img
    src="https://img.shields.io/static/v1?label=license&amp;message=Apache-2.0&amp;color=FFD84D&amp;labelColor=161B3A&amp;style=flat-square"
    alt="license Apache-2.0"></a>
</p>

> [!NOTE]
> **Pre-release.** CAPTF is `v1alpha1`: its API and its
> [module contract](https://captf.io/docs/module-author/contract/index.html)
> may still change between releases.

The CAPTF OpenStack `machine` module: the Terraform/OpenTofu root module
behind `TerraformMachine`, implementing the
[machine role](https://captf.io/docs/module-author/contract/v1alpha1/machine.html)
of the module contract. It creates one Nova server on a Neutron port of the
cluster's subnet, boots it with the bootstrap payload as user data, and, for
a control-plane machine, adds the port's address to the cluster's API pools
before the server boots. It reads everything about the cluster from
`captf_cluster_outputs`, the
[cluster role's exports](https://github.com/captf-io/terraform-openstack-cluster/blob/main/README.md#exports).

The module image is `ghcr.io/captf-io/module-images/openstack-machine`, built and published by
[module-images](https://github.com/captf-io/module-images) from this repository's releases. Design and
evidence are in
[DESIGN.md](https://github.com/captf-io/terraform-openstack-machine/blob/main/DESIGN.md);
the rules every file follows are in
[CONVENTIONS.md](https://github.com/captf-io/terraform-openstack-machine/blob/main/CONVENTIONS.md).

## Using it

CAPTF runs this module from the module image
`ghcr.io/captf-io/module-images/openstack-machine`: set the image on a `TerraformMachine`'s
`spec.source.image` (through a `TerraformMachineTemplate`), and the controller
renders every input. The module is also published to the Terraform Registry as
`captf-io/machine/openstack` and can be called directly:

```hcl
module "machine" {
  source  = "captf-io/machine/openstack"
  version = "~> 0.1"

  # The contract inputs the controller would render (captf_contract,
  # captf_cluster, captf_object, captf_tags, ...; see Inputs), and any
  # user variables.
}
```

Called directly, the module is a CAPTF root module first:

- it configures its own `provider "openstack"` block, so the calling
  module cannot use `count`, `for_each` or `depends_on` on it, and the
  provider takes its credentials from the environment (see Identity
  Secret);
- its providers are pinned to exact versions (`versions.tf`), which the
  calling configuration has to accept;
- you set the `captf_*` inputs yourself.

## What it creates

| Resource | Count | Purpose |
| --- | --- | --- |
| `openstack_networking_port_v2.node_port` | 1 | Port on the cluster subnet: security groups, allowed address pairs |
| `openstack_lb_member_v2.api_members` | one per exported pool on a control-plane machine, else 0 | Membership in the API pools, deregistered by this machine's destroy |
| `openstack_compute_instance_v2.node_instance` | 1 | The Nova server, named `machine_name` |

Data source: `openstack_compute_instance_v2.node_instance_status`, the
server's status for the health output, not read while the server is in
`BUILD` (see Health).

The port comes first, then the members, then the server (`depends_on`),
so a control-plane machine is in the pools before it boots, as
`kubeadm init` and RKE2 joins require
([machine.md "Control-plane machines"](https://captf.io/docs/module-author/contract/v1alpha1/machine.html#control-plane-machines)).

## Prerequisites

- **A cluster.** An `openstack-cluster` TerraformCluster of the same
  release line, or for an externally managed TerraformCluster, its exports
  in `external_cluster_exports`.
- **Quotas**, per machine: 1 server with the flavor's vCPUs and RAM, 1
  port, 1 or 2 pool members on a control-plane machine, 1 volume with
  `root_volume_size_gib`.
- **Permissions.** As the [cluster role](https://github.com/captf-io/terraform-openstack-cluster/blob/main/README.md#prerequisites):
  `member` in the project, plus `load-balancer_member` on clouds with
  Octavia's legacy policy.
- **Image.** A Glance image with cloud-init (`cloud-config`) or Ignition
  (`ignition`), and the kubelet, kubeadm or RKE2 and a container runtime
  the bootstrap provider expects, for example one built with
  [image-builder](https://image-builder.sigs.k8s.io/capi/providers/openstack).
  It must take its hostname from the metadata service or config drive, so
  that the Node name equals the server name.

## Inputs

Contract inputs ([machine.md "Inputs"](https://captf.io/docs/module-author/contract/v1alpha1/machine.html#inputs)):

| Input | Used for |
| --- | --- |
| `captf_contract` | Validated to be `v1alpha1` |
| `captf_cluster` | Unused: `captf_tags` already names the cluster |
| `captf_object` | The port name (`captf-<namespace>-<name>-<hash>`) |
| `captf_cluster_outputs` | Network, subnet, groups, server group, pools, zones, region; validated to schema `captf.io/openstack-cluster/v1` or `{}` |
| `captf_tags` | Tags on the port and members, metadata on the server (see Tags) |
| `machine_name` | Server name, member names, the `Hostname` address, the default zone pick |
| `bootstrap_data` | Server user data, unchanged |
| `bootstrap_format` | Validated to be `cloud-config` or `ignition`; both pass through, gzipped Ignition is refused (see Bootstrap) |
| `failure_domain` | The server's availability zone; must be one of the cluster's |
| `kubernetes_version` | Fills `{version}` and `{semver}` in `image_name`, without its `+rke2rN` suffix |
| `control_plane` | Pool membership, the control-plane group, the server group |

User variables, set in the TerraformMachineTemplate's
`spec.template.spec.variables`
([Module Variables](https://captf.io/docs/user-guide/variables.html)):

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `additional_security_group_ids` | `list(string)` | `[]` | Extra Neutron security group UUIDs for the port |
| `additional_tags` | `map(string)` | `{}` | Extra tags, with the cluster role's rules |
| `config_drive` | `bool` | `false` | Attach a config drive with the user data and metadata |
| `external_cluster_exports` | `any` | `null` | The exports of an externally managed TerraformCluster, schema `captf.io/openstack-cluster/v1` |
| `flavor_name` | `string` | `null` | **Required.** Nova flavor |
| `image_id` | `string` | `null` | Glance image UUID. Exactly one of `image_id` and `image_name`; boot from volume needs `image_id` |
| `image_name` | `string` | `null` | Glance image name, resolved to an ID by the provider through Glance at create; must match exactly one image. `{version}` (`v1.31.4`) and `{semver}` (`1.31.4`) stand for `kubernetes_version` |
| `key_pair` | `string` | `null` | Nova key pair for SSH |
| `root_volume_size_gib` | `number` | `null` | Boot from a new Cinder volume of this size, deleted with the server. `null`: the flavor's disk |
| `root_volume_type` | `string` | `null` | Cinder volume type of the root volume |

## Outputs

| Output | Value |
| --- | --- |
| `provider_id` | `openstack:///<server-uuid>`, or `openstack://<region>/<server-uuid>` with the cluster's `provider_id_format = "regional"`; `null` once the server is gone |
| `addresses` | `InternalIP` for each fixed IP of the port, then `Hostname` = `machine_name` |
| `failure_domain` | The availability zone: the requested one, or the module's pick |
| `interruptible` | Always `false`: Nova has no spot or preemptible servers |
| `health` | See Health |
| `api_member_ids` | Not a contract output: Octavia member UUIDs keyed by pool; `{}` on a worker |
| `node_port_id` | Not a contract output: the Neutron port's UUID; `null` once it is gone |

`provider_id` is what the OpenStack cloud controller manager writes to
`Node.spec.providerID`: `makeInstanceID` in
[cloud-provider-openstack v1.34.1 `pkg/openstack/instances.go`](https://github.com/kubernetes/cloud-provider-openstack/blob/v1.34.1/pkg/openstack/instances.go)
returns `openstack:///<id>`, or `openstack://<region>/<id>` when
`OS_CCM_REGIONAL=true`. The addresses mirror what it reports for a server
without floating IPs (`instances_addresses.go` in the same release).

Without a requested failure domain the module picks
`sort(zones)[sha256(machine_name)[:8] mod len(zones)]`: deterministic, and
even across machines.

## Exports

This role reads the [cluster role's exports](https://github.com/captf-io/terraform-openstack-cluster/blob/main/README.md#exports).
A machine of an externally managed TerraformCluster receives
`captf_cluster_outputs = {}` and needs the same object, written by hand, in
`external_cluster_exports`; the plan fails with an explanation otherwise.

## Identity Secret

The same keys as the [cluster role](https://github.com/captf-io/terraform-openstack-cluster/blob/main/README.md#identity-secret).
The region comes from the exports, not the identity, so a machine with its
own identity still lands in the cluster's region.

## Lifecycle

Machines are immutable: the module applies once, then refreshes for health
and destroys on delete. Its inputs, `captf_cluster_outputs` included, are
pinned at the first apply, so a later change to the cluster's zones or
exports never reaches a running machine. Nothing updates in place, and
nothing replaces the server after creation; changes made outside Terraform
show up in drift reports only, which CAPTF reports for machines and never
applies:

- The server's image is ignored after creation (`ignore_changes`), so a
  rotated or deleted image never shows as drift: the provider would rebuild
  the server in place.
- A deleted flavor shows as a planned replacement (the provider forces a
  new server when the recorded flavor reads empty); a renamed or resized
  one as an in-place resize.
- On destroy, the server goes before its pool members (it depends on them,
  for register-then-boot); Cluster API has drained the node by then, and
  the load balancer's monitor takes the backend out.

## Bootstrap

- `bootstrap_data` goes to Nova as user data unchanged: gophercloud sends
  valid base64 as is, so gzipped cloud-config works, and state keeps only
  a SHA1 of it. Both `cloud-config` and `ignition` are accepted; gzipped
  Ignition fails a precondition (CONVENTIONS.md section 13).
- Nova accepts at most 65,535 bytes of base64 user data; a larger payload
  fails a precondition. Compress it (CAPRKE2 `gzipUserData`) if needed.
- **No staged delivery.** The control-plane payload carries the cluster CA
  keys, and anything that reaches the metadata service (169.254.169.254)
  can read it. OpenStack has no instance identity to fetch a staged
  payload from a store with, so there is no `bootstrap_delivery`; this is
  the documented exposure CONVENTIONS.md section 13 asks for (see
  Exceptions). Deny 169.254.169.254/32 to pods with a CNI NetworkPolicy.
  Cluster API Provider OpenStack has the same exposure.

## Tags

| Resource | Shape | Example |
| --- | --- | --- |
| `node_port`, `api_members` | Neutron/Octavia `tags`: `"<key>=<value>"`, `/` in the key mapped to `:` | `captf.io:name=demo-md-0-abcde` |
| `node_instance` | Nova metadata, `/` in the key mapped to `:` | `captf.io:name = demo-md-0-abcde` |

The server's Nova `tags` are not used: a Nova tag holds at most 60
characters and no `/`, too little for `<key>=<value>`, so the captf tags
go in metadata, whose keys allow `:` and values 255 characters. This is
the `hack/tags.json` exemption for `openstack_compute_instance_v2`.

## Health

From the server's Nova status, re-read on every refresh.

| Nova status | `state` | `healthy` | `reasons` |
| --- | --- | --- | --- |
| `ACTIVE`, `MIGRATING`, `PASSWORD` | `running` | `true` | `[]` |
| `BUILD` | `pending` | `false` | `ServerBuilding` |
| `REBOOT`, `HARD_REBOOT` | `pending` | `false` | `ServerRebooting` |
| `REBUILD` | `pending` | `false` | `ServerRebuilding` |
| `RESIZE`, `VERIFY_RESIZE`, `REVERT_RESIZE` | `pending` | `false` | `ServerResizing` |
| `SHUTOFF` | `stopped` | `false` | `ServerShutOff` |
| `SUSPENDED` | `stopped` | `false` | `ServerSuspended` |
| `PAUSED` | `stopped` | `false` | `ServerPaused` |
| `SHELVED`, `SHELVED_OFFLOADED` | `stopped` | `false` | `ServerShelved` |
| `RESCUE` | `degraded` | `false` | `ServerRescued` |
| `ERROR` | `degraded` | `false` | `ServerError` |
| `SOFT_DELETED`, `DELETED` | `terminated` | `false` | `ServerDeleted` |
| server deleted out of band | `terminated` | `false` | `ServerNotFound` |
| `UNKNOWN`, anything else | `unknown` | `false` | `ServerStatusUnknown` |

`message` names the server and its status. Provider 3.4.0 reads only some
statuses (DESIGN.md decision 6):

- The server resource reads `ACTIVE`, `BUILD`, `SHUTOFF`, `PAUSED`,
  `SHELVED`, `SHELVED_OFFLOADED`, `MIGRATING` and `ERROR`. In any other
  status (`REBOOT`, `HARD_REBOOT`, the resize states, `RESCUE`,
  `SUSPENDED`, `UNKNOWN`, ...) its refresh fails, and so does every drift
  Job and every destroy until the server leaves that status.
- The status data source reads the same list but `BUILD`, so it is not
  read while the server is in `BUILD`; health then comes from the
  resource (`pending`), and a server stuck building can still be
  destroyed.

The rows for the other statuses document the mapping for a provider that
reads them.

## Limitations

- **Bootstrap secrets in instance metadata**, and the user data size
  limit: see Bootstrap.
- **Names.** Nova derives the hostname from the server name, cut to 63
  characters. Keep `machine_name` within 63 characters and DNS-safe, or
  the Node name will not match the server and the cloud controller manager
  will not find it.
- **No spot.** `interruptible` is always `false`.
- **Port security groups.** Keep the cloud controller manager's
  `manage-security-groups` off: groups it adds to the port show as drift.

## Exceptions

- Server name: `machine_name`, not the convention's prefixed name
  (CONVENTIONS.md section 6), because the cloud controller manager finds
  servers by Node name.
- Bootstrap payloads, the control plane's with the cluster CA keys, are
  readable from the metadata service: a deviation from the contract's
  checklist ("keep key material out of readable instance metadata"),
  since OpenStack has no instance identity to stage them behind (DESIGN.md
  decision 12).
- `rejects_spot_control_plane` (CONVENTIONS.md section 14) has no run:
  Nova has no spot servers, so there is nothing to reject;
  `spot_is_interruptible` pins `interruptible = false` instead.
- The boot-from-volume root volume carries no tags (common.md
  `captf_tags`): Nova creates it from `block_device`, which takes no
  metadata. Creating the volume as a tagged resource instead would tie
  it to a Cinder availability zone named like the Nova one, which many
  clouds do not have (DESIGN.md "Unverified" 5). The volume is deleted
  with the server.
- No capacity labels on the image (CONVENTIONS.md section 16): there is no
  default flavor to describe; see the [archived openstack-modules README](https://github.com/captf-io/openstack-modules#images).
- `captf_cluster` is declared and unused, and `captf_contract` is read
  only by its validation (`tflint-ignore`).
- No `tfcapi-lint` warning is allowed; `make tfcapi-lint` runs with none.

## Examples

[`examples/cluster-kubeadm.yaml`](https://github.com/captf-io/terraform-openstack-machine/blob/main/examples/cluster-kubeadm.yaml) has a
control-plane and a worker TerraformMachineTemplate. A worker template:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: TerraformMachineTemplate
metadata:
  name: demo-md-0
spec:
  template:
    spec:
      source:
        image: ghcr.io/captf-io/module-images/openstack-machine:v0.1.0-opentofu
      variables:
        flavor_name: m1.large
        image_name: ubuntu-2404-kube-v1.33.1
```

## Developing

The host needs `make`, `podman` (or `docker` with `ENGINE=docker`), `jq` and
Go. Every other tool runs in a digest-pinned container. `make verify` is the
gate. Variables: `RUNTIMES` (default `terraform opentofu`), `ENGINE` and
`PROVIDER_DIR` (default `../cluster-api-provider-terraform`, where
`tfcapi-lint` is built from; the target skips when the directory is absent).

| Target | What it does |
| --- | --- |
| `make help` | Lists the targets |
| `make fmt` | Formats the module with `terraform fmt` and `tofu fmt`, in place |
| `make fmt-check` | Fails on any file the formatters would change |
| `make validate` | `init` and `validate` on both runtimes and on their floors (Terraform 1.5.7, OpenTofu 1.6.3) |
| `make unit-test` | `terraform test` / `tofu test` with mocked providers |
| `make tflint` | `tflint` with the terraform ruleset (preset all) and the cloud ruleset |
| `make tfcapi-lint` | `tfcapi-lint module --strict`, built from `PROVIDER_DIR` |
| `make scan` | `trivy config` over the repository |
| `make check-conventions` | `hack/check-layout.sh` and `hack/check-tags.sh` (CONVENTIONS.md) |
| `make shellcheck` | `shellcheck` over `hack/` and every shell template, rendered with placeholders |
| `make check-headers` | Fails on any source file without the Apache-2.0 license header |
| `make fix-headers` | Adds the license header to every source file missing it |
| `make verify` | All of the above, in parallel groups |
| `make clean` | Removes `build/`; keeps `.cache/` and `.tools/` |

Module images are not built here; [module-images](https://github.com/captf-io/module-images) builds them from
this repository's releases.

<br>
<p align="center">
  <img
    src="https://captf.io/assets/readme/divider.svg"
    width="100%" height="4" alt="">
</p>
<p align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="40" height="40" alt="CAPTF"></a>
  <br>
  <a href="https://captf.io/docs/"
    ><b>Documentation</b></a> ·
  <a href="https://captf.io/docs/getting-started/quick-start.html"
    ><b>Quick start</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/CONTRIBUTING.md"
    ><b>Contributing</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/SECURITY.md"
    ><b>Security</b></a>
  <br>
  <sub>Built for
    <a href="https://cluster-api.sigs.k8s.io/">Cluster API</a>.
    <a href="https://github.com/captf-io/terraform-openstack-machine/blob/main/LICENSE.md"
    >Apache 2.0</a>.</sub>
</p>
