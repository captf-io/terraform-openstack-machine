# Design: terraform-openstack-machine

Why this module looks the way it does. Each decision names the evidence it
rests on; anything not yet checked against a real cloud is listed under
"Unverified" and must be confirmed on the first reviewed apply. Decision
and item numbers are shared with the sibling repo
[terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster) and
are cited from code comments, so a number that concerns only the other
role is kept as a pointer.

Pins: `terraform-provider-openstack/openstack` 3.4.0. Runtimes: Terraform
>= 1.5, OpenTofu >= 1.6. Conventions: [CONVENTIONS.md](CONVENTIONS.md).
Contract: <https://captf.io/docs/module-author/contract/v1alpha1/>.

Provider facts below come from `providers schema -json` at the pin
(`hack/tf-run.sh schema`) and the provider source at tag `v3.4.0`; "the
provider" means that version.

## Scope

- This repo is the `machine` role; the `cluster` role is in
  [terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster).
  There is no `machinepool`: OpenStack
  has no native scaling group (Heat and Senlin are optional services many
  clouds do not deploy), and a pool of individually managed servers is
  what MachineDeployments already provide.
- Bring-your-own network: the network, subnet, router and floating IP
  network exist before the cluster. The cluster role creates security
  groups, the Octavia load balancer and a control-plane server group.
- No node identity (decision 4).

## Decisions

### 1. API load balancer (Octavia)

The load balancer, its listeners, pools and monitors are the cluster role; this role adds control-plane members to the pools (decision 5). See [DESIGN.md of terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md).

### 2. Security groups

The security groups and their rules are the cluster role; this role attaches them to the port. See [DESIGN.md of terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md).

### 3. Placement

Failure domains are Nova availability zones: `availability_zones`, or every
available zone from `data.openstack_compute_availability_zones_v2` (the
non-detailed list, which leaves out the `internal` zone). All are eligible
for the control plane. Without the variable, a zone Nova marks unavailable
drops out at the next refresh; the README recommends pinning the list.
Control-plane machines join a server group with the `soft-anti-affinity`
policy by default (configurable to `anti-affinity` or none), which spreads
them across hosts on single-zone clouds. A zone dropping out of the list never moves a machine: a machine's
inputs, its `captf_cluster_outputs` included, are pinned at its first
apply and re-fed unchanged to every refresh, drift and destroy
(machine.md "Lifecycle"), so its zone and the precondition that checks
it see the same list for the machine's whole life. Machines without a
requested failure domain pick
`sort(zones)[parseint(sha256(machine_name)[:8], 16) mod len(zones)]`
(CONVENTIONS.md section 11).

### 4. No node identity

The OpenStack cloud controller manager and Cinder CSI need a `cloud.conf`
with credentials inside the workload cluster. The modules do not create
them:

- an application credential belongs to the user Terraform runs as, so its
  lifetime and roles are tied to that user;
- Keystone refuses to let an application-credential session create another
  application credential unless the parent is unrestricted;
- the secret would sit in cluster state, and exports must not carry
  secrets.

The operator supplies `cloud.conf` (ClusterResourceSet or an add-on) with a
dedicated, ideally access-rule-restricted, application credential.
`examples/cloud-controller-manager.yaml` shows how.

### 5. Machine

- `openstack_networking_port_v2` first: security groups, fixed IP on the
  subnet, `allowed_address_pairs`, tags. The provider does not read
  `fixed_ip` back, so the port does not drift. Control-plane machines
  register the port's address as Octavia members, and the server
  `depends_on` them, so registration completes before the server boots
  (machine.md "Control-plane machines"); member creation can wait on a
  busy load balancer, and nothing else orders the two. On destroy the
  server goes first: CAPI has drained the node, and the monitor marks the
  member down.
- `openstack_compute_instance_v2`: `name = machine_name` (the cloud
  controller manager looks servers up by Node name, `getServerByName` in
  cloud-provider-openstack v1.34.1 `pkg/openstack/instances.go`),
  `flavor_name` (required: there is no universal default), `network
  { port }`, metadata, optional key pair, config drive and boot from
  volume, and a server group hint for control-plane machines.
- Image: `image_id` or `image_name`, exactly one, passed to the server;
  the provider resolves a name through Glance before create
  (`getImageIDFromConfig`). `image_name` may hold `{version}` and
  `{semver}` (CONVENTIONS.md section 8), filled from `kubernetes_version`
  without its `+rke2rN` suffix (machine.md); a name with placeholders
  and no version fails a precondition.
  There is no image data source: a data source is read on every refresh
  and destroy, so a rotated-out image would fail every drift Job and the
  final destroy. Boot from volume needs `image_id`, since Nova creates the
  volume from a UUID. `ignore_changes = [image_id, image_name]`: the
  provider rebuilds a server in place when either changes
  (`resourceComputeInstanceV2Update`), and its read sets `image_name` to
  "Image not found" once the image is deleted.
- `user_data = var.bootstrap_data` verbatim: gophercloud v2.8.0
  `servers.CreateOpts.ToServerCreateMap` sends a value that decodes as
  base64 unchanged, so gzip and Ignition are safe, and the provider's
  `StateFunc` keeps only a SHA1 of it in state. Nova limits user data to
  65,535 bytes of base64 (`nova/api/openstack/compute/schemas/servers.py`);
  a precondition enforces it.
- `count = 1` on the server; see "Out-of-band deletes".

### 6. provider_id, addresses, health

- `openstack:///<server-uuid>`, or `openstack://<region>/<server-uuid>`
  with `provider_id_format = "regional"`, which must match the cloud
  controller manager's `OS_CCM_REGIONAL` (cloud-provider-openstack v1.34.1
  `makeInstanceID`). The region is the cluster's, exported from the
  subnet data source's `region`.
- Addresses: InternalIP for each fixed IP of the port; Hostname
  (`machine_name`). The controller manager reports the same for a server
  without floating IPs (`instances_addresses.go`).
- Machine health from the Nova status, read by
  `data.openstack_compute_instance_v2.node_instance_status`. The
  resource's `power_state` is an argument, not a computed attribute, so
  mocked tests cannot set it (Terraform 1.16.4 leaves it null; OpenTofu
  1.12.6 rejects the override: "Non-computed field `power_state` is not
  allowed to be overridden"); the data source's is computed. Every
  documented Nova status is mapped (README "Health"), but the data
  source's read (`data_source_openstack_compute_instance_v2.go`) accepts
  only `ACTIVE`, `SHUTOFF`, `PAUSED`, `SHELVED`, `SHELVED_OFFLOADED`,
  `MIGRATING` and `ERROR` and fails on the others, `BUILD` included (the
  resource's read also accepts `BUILD`). Every destroy refreshes data
  sources, so a server stuck in `BUILD` would make every destroy fail;
  the data source is therefore counted only over servers the resource
  reads as something else, and health falls back to the resource's
  `power_state` (`BUILD` -> `pending`). That branch cannot be mocked
  (the resource's `power_state` is not computed), so no test drives it.
  The resource itself fails its read in the statuses neither accepts
  (`REBOOT`, the resize states, `RESCUE`, `SUSPENDED`, `UNKNOWN`, ...), so
  drift Jobs and destroys fail until the server leaves them. Those rows
  of the mapping are unreachable with this provider and kept so the
  mapping survives a provider that reads them.
  `interruptible` is always false.

Cluster health is the cluster role's. See [DESIGN.md of terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md), decision 6.

### 7. Tags

- Nova server metadata keys allow `[a-zA-Z0-9-_:. ]`, no `/`
  (`nova/api/validation/parameter_types.py` `metadata`): keys map `/` to
  `:` (`captf.io:cluster`). Neutron and Octavia tags use the same mapped
  key, as `"<key>=<value>"` strings.
- Nova server tags (`^[^,/]*$`, at most 60 characters) cannot carry the
  captf tags and are not used.
- Neutron tags: at most 255 characters each and 50 per resource
  (`neutron/extensions/tagging.py` `MAX_TAG_LEN`, `MAX_TAGS_COUNT`), so
  `additional_tags` takes at most 44, and a longer pair fails a
  precondition rather than being truncated.
- Taggable in 3.4.0 (schema `tags`): security groups, load balancer,
  listeners, pools, members, floating IP, port. Not taggable: security
  group rules, monitors, server groups. The server carries metadata
  instead (`hack/tags.json` exemption).
- The boot-from-volume root volume is untagged: Nova creates it from
  `block_device`, which takes no metadata. A separate tagged
  `openstack_blockstorage_volume_v3` would have to name a Cinder
  availability zone matching the Nova one (Unverified 5); the machine
  README lists the exception.

### 8. Credentials

The provider block sets only `region` (cluster: `var.region`; machine: the
cluster's exported region). Identity Secret: `OS_CLOUD` and
`OS_CLIENT_CONFIG_FILE=/var/run/captf/credentials/clouds.yaml`, with
`clouds.yaml` (application credential) and an optional `cacert.pem` as file
keys; or the plain `OS_AUTH_URL`, `OS_APPLICATION_CREDENTIAL_ID`,
`OS_APPLICATION_CREDENTIAL_SECRET`, `OS_REGION_NAME`, `OS_CACERT`
variables. gophercloud/utils `clientconfig.FindAndReadCloudsYAML` reads
`OS_CLIENT_CONFIG_FILE` first, and the provider takes the region from the
`clouds.yaml` entry when none is set (`terraform/auth/config.go`).

### 9. Out-of-band deletes

When a refresh finds a resource gone, it drops it from state. What a
reference to it evaluates to then was checked with a `local_file` stand-in
on Terraform 1.16.4 and OpenTofu 1.12.6 (`apply`, delete the file,
`apply -refresh-only`), with identical results on both:

- a single resource (no `count`) evaluates to unknown, so every output
  built from it is stored as `null`;
- a counted resource evaluates to an empty tuple, a known value:
  `length(r) == 0` is true and `one(r[*].id)` is `null`;
- `r[0]` on that empty tuple fails the refresh when it appears in a data
  source argument or a condition (managed resource arguments are not
  evaluated in refresh-only mode).

So the server, its port and both security groups have `count = 1`, and
the load balancer its natural count;
both status data sources are counted with `count = length(<resource>)`;
nothing indexes `[0]` outside `try()`. A deleted server then reports
`provider_id = null` and `health.state = "terminated"`
(`ServerNotFound`), a deleted load balancer `terminated`
(`LoadBalancerNotFound`).

Data sources must not fail once a brought resource is gone, because every
destroy refreshes them (CONVENTIONS.md section 9). The subnet is read by
`openstack_networking_subnet_v2` only while
`openstack_networking_subnet_ids_v2` lists it (an empty listing never
fails); other plans then fail a precondition naming `subnet_id`, which a
destroy skips.

### 10. Images

The machine image carries no `io.captf.capacity` or `io.captf.node-info`
label: they describe a default instance shape, and `flavor_name` has no
default. The image contract makes them optional, and `tfcapi-lint image`
reports their absence as info.
[module-images](https://github.com/captf-io/module-images) adds the labels
only for an image with `capacity` and `arch` in its `images.json`, and
`openstack-machine` has neither, so its smoke test runs with
`MACHINE_LABELS=absent` to check the labels are absent. An empty label would not do: `tfcapi-lint image` parses
a present label and fails on an empty one.

### 11. Tests

Mocked tests per CONVENTIONS.md section 14, green on Terraform 1.16.4 and
OpenTofu 1.12.6. Two portability findings beyond the conventions:

- OpenTofu 1.12.6 does not resolve `run.<name>` (or even `output.<name>`
  in the same condition) in an `assert`; it does in a run's `variables`.
  `reapply_is_stable` passes the previous run's outputs as variables.
- OpenTofu rejects a mock default for an attribute the configuration sets
  ("overriding configuration values is not allowed"); Terraform ignores
  it. Mock defaults cover computed attributes only.

### 12. Bootstrap payload in instance metadata

A deviation from the contract checklist ("keep key material out of
readable instance metadata"): bootstrap payloads, which on control-plane
nodes include the cluster CA keys, are readable from the metadata service
by anything that can reach 169.254.169.254. OpenStack has no instance
identity to fetch a staged payload with (CONVENTIONS.md section 13), and a
config drive does not disable the metadata service. Mitigation (machine
README "Bootstrap"): a CNI NetworkPolicy denying 169.254.169.254/32 from
pods. Cluster API Provider OpenStack has the same exposure. Gzipped
Ignition fails a precondition (section 13); gzipped cloud-config passes
through.

## Exports consumed (`captf.io/openstack-cluster/v1`)

This role reads the cluster role's exports (`captf_cluster_outputs`, or
`external_cluster_exports` for an externally managed TerraformCluster):
`region`, `network_id`, `subnet_id`, `failure_domains`, `distribution`,
`provider_id_format`, `security_group_ids`, `control_plane_server_group_id`,
`node_allowed_address_cidrs` and `api.pools`. The schema is defined in
[DESIGN.md of terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md#exports-captfioopenstack-clusterv1).

## Unverified

1. See [terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md).
2. Octavia tag limits (assumed equal to Neutron's).
3. The operational cost of the provider failing a server refresh, and so
   drift Jobs and destroys, in transient Nova states (REBOOT, RESIZE,
   RESCUE, SUSPENDED, UNKNOWN, ...): verified in the provider source, not
   how often Jobs hit it. BUILD no longer blocks a destroy (decision 6);
   that branch is not driven by a test.
4. A cloud controller manager with `manage-security-groups` editing node
   ports' groups (machine drift); the README says to keep it off.
5. Cinder and Nova availability zone names differing for boot volumes.
6. See [terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md).
7. See [terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md).
8. The kubeadm templates' `{{ v1.local_hostname }}` (Node name) equalling
   the server name; Nova cuts hostnames to 63 characters.
9. See [terraform-openstack-cluster](https://github.com/captf-io/terraform-openstack-cluster/blob/main/DESIGN.md).
10. Neutron's ML2/OVN driver counting allowed address pairs as remote
    group members like the iptables/OVS driver does (verified in Neutron's
    RPC source only), which native pod routing relies on.

## Rejected alternatives

- A machinepool role (no native group).
- Creating application credentials (lifetime, Keystone restriction, state
  secret).
- Nova server tags for captf tags (character and length limits).
- A Glance image data source (fails refresh and destroy once the image is
  deleted).
- Empty capacity labels on the machine image (`tfcapi-lint` rejects them).
