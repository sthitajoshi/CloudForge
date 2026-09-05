# Design Decisions

Why this platform is built the way it is. Each decision records the reasoning, not just the outcome — including the ones that were forced by a constraint and the ones that were discovered the hard way.

---

## Networking

### Two availability zones, public and private subnets in each

Enough to demonstrate genuine multi-AZ layout without overbuilding. Public subnets route `0.0.0.0/0` to an internet gateway; private subnets get their own route table.

### No NAT gateway

Private subnets have a route table with **no** default route out. This is deliberate, not an omission.

NAT gateways bill hourly *plus* per-GB, continuously, with no free tier. Together with the EKS control plane (~$73/month) they are the two AWS resources that cost real money whether or not anything uses them, and this project avoids both by design. On the real-AWS path a NAT gateway would be added here, or replaced with VPC endpoints for the specific services the workload actually needs — which is usually cheaper anyway.

### Security group egress is enumerated, not wide open

The app security group allows outbound HTTPS on 443 and DNS on 53 within the VPC. It does **not** allow all protocols to `0.0.0.0/0`.

Unrestricted egress is the default almost everywhere and is what lets a compromised container reach an arbitrary host. Enumerating egress is more annoying and more correct. The Checkov gate enforces this (`CKV_AWS_382`).

### The VPC default security group is emptied

Every VPC ships with a default security group that permits all traffic between anything assigned to it. Nothing here uses it, so `aws_default_security_group` is declared with no rules — otherwise it stays as a quiet way to bypass every rule above.

---

## State management

### S3 bucket plus DynamoDB lock table

State lives in `cloudforge-tf-state` (versioned, encrypted, public access blocked, with lifecycle expiry after 90 days). Locking uses conditional writes against the `LockID` key in `cloudforge-tf-lock`.

**Why locking matters:** two concurrent applies — two engineers, or an engineer and a CI run — will corrupt state without it. The second `apply` blocks until the first releases the lock.

This was not theoretical during development. Two `terraform plan` runs were interrupted mid-flight and left stale locks behind; every subsequent apply on those environments refused to start until the locks were cleared with `terraform force-unlock`. The mechanism works exactly as intended, and the error message names the lock ID, host and user holding it.

### The bootstrap config keeps local state

`terraform/bootstrap` creates the bucket and table that every other configuration uses as its backend. It cannot store its own state in a backend it has not created yet, so it keeps local state and is applied once.

### Directory per environment, not Terraform workspaces

Each of `envs/dev`, `envs/staging`, `envs/prod` has its own directory, its own `.tfvars`, and its own state key.

**Why not workspaces:** blast radius. With directories, a mistake in dev's variables or module wiring physically cannot reach prod's state file. Workspaces share one backend configuration and one directory, so the only thing separating environments is a CLI flag someone can forget.

**The tradeoff, honestly:** directories duplicate the provider and backend blocks three times. Workspaces avoid that duplication. At this scale the isolation is worth the repetition, and shared modules keep the actual resource definitions in one place.

The environments are also genuinely different, not copies — `10.0.0.0/16`, `10.1.0.0/16`, `10.2.0.0/16`, with replica counts and resource limits scaling up accordingly.

---

## Identity and access

### No wildcards anywhere

No `*` appears in any action or resource across the IAM module. Broad permissions "just to get it working" are fine while debugging and fatal if they ship, so the gate enforces the final state.

### Object-level and bucket-level permissions are split

```
s3:GetObject   → arn:aws:s3:::bucket/*     (objects inside the bucket)
s3:ListBucket  → arn:aws:s3:::bucket       (the bucket itself)
```

This is the detail people get wrong. Collapsing these into one statement either over-grants or silently fails, because the two action types address different ARN shapes.

### The CI role trusts a named role, not the account root

An earlier version used `arn:aws:iam::<account>:root` as the trust principal. That delegates the decision to the account's own IAM, meaning any principal that can call `AssumeRole` gets in. The policy gate flagged it, and it now trusts a specific role name.

On real AWS this would instead be a GitHub OIDC federated principal, so no long-lived credentials exist in CI at all. LocalStack does not emulate the OIDC federation flow, so that variant is documented rather than applied.

---

## Kubernetes

### kind's default CNI is disabled in favour of Calico

**This is the single most important operational detail in the project.**

kind's default CNI accepts `NetworkPolicy` objects without error and enforces none of them. A policy appears applied, `kubectl get netpol` lists it, and traffic flows freely. The result is a security control that looks present and does nothing.

The cluster config sets `disableDefaultCNI: true` with `podSubnet: 192.168.0.0/16` to match what Calico's manifest expects, and Calico is installed before nodes will report Ready.

### Default-deny ingress, then one narrow allow

Kubernetes has no implicit deny: a pod that no policy selects accepts traffic from anywhere. The chart therefore ships two policies — one selecting every pod in the namespace and permitting nothing, and one re-opening exactly the app port from within the namespace. Policies are additive, so this composes into "deny everything except this."

Egress is deliberately left unrestricted. A default-deny egress policy also blocks DNS, which breaks service discovery in a way that is confusing to debug; doing it properly requires an explicit allow for `kube-dns` first.

### The security context needs a numeric UID

The image sets `USER nonroot:nonroot` by name. With `runAsNonRoot: true`, the kubelet cannot verify that a *named* user is non-root — it refuses to start the pod rather than guess, failing with `container has runAsNonRoot and image has non-numeric user`.

The fix is `runAsUser: 65532`, distroless's nonroot UID. Numeric UIDs in the image would work equally well.

### Liveness and readiness probes do different jobs

Liveness restarts a container that is wedged. Readiness only removes it from the Service's endpoints. Conflating them causes restart loops under load: a pod that is merely slow gets killed instead of temporarily taken out of rotation.

### Requests drive autoscaling; limits are a ceiling

The HPA computes utilisation as a percentage of the **request**, not the limit. A container with no CPU request cannot be autoscaled on CPU at all.

The two limits also behave completely differently when exceeded: memory over the limit means the container is OOM-killed, while CPU over the limit means it is throttled and keeps running.

### metrics-server needs a flag on kind

kind's kubelets serve self-signed certificates. Without `--kubelet-insecure-tls`, metrics-server never becomes ready and every HPA sits at `<unknown>` indefinitely.

### The scale-down stabilization window is set deliberately

Scale up immediately, scale down after 120 seconds. Observed behaviour under load:

| Time | CPU | Pods |
|---|---|---|
| load applied | 148% / 60% | 2 → 5 |
| load removed | 67% → 1% | 5 |
| +120s below target | 1% | 5 → 2 |

Without the window, replica count oscillates as soon as traffic is bursty — scaling down on a brief dip, then straight back up.

---

## Policy as code

### Checkov rather than OPA/Rego

Checkov ships over a thousand maintained rules that are useful immediately, and custom rules are a short YAML file. OPA is more expressive and Rego is a genuinely useful language to know, but writing the equivalent coverage from scratch would consume days that were better spent on the rest of the platform.

### Custom checks are YAML, not Python

The Python check format (`BaseResourceCheck`) registers correctly — importing the module demonstrably adds the check to Checkov's resource registry — but the checks never execute during a scan and produce no results, passed or failed. Debug logging shows the external checks directory loading without error.

Rather than fight it, both custom rules were rewritten as YAML graph checks, which work reliably. Worth knowing before spending an afternoon on it.

### `policy/` lives outside `terraform/`

The gate scans `terraform/`, and `policy/tests/` contains configuration that is broken on purpose. Keeping the fixtures out of the scanned tree means the main scan stays clean without skip rules — and skip rules that exclude paths are exactly how a gate quietly stops covering real code.

### Every skip carries a reason

Four checks are skipped, each with the reasoning recorded inline: VPC flow logs and KMS customer-managed keys bill continuously (the same argument as the NAT gateway), S3 event notifications need a consumer that does not exist, and access logging needs a second bucket that then needs its own lifecycle policy.

A skip list without reasons is how a policy gate becomes decorative.

### The gate is itself tested

A dedicated CI job runs the same policies against `policy/tests/violations.tf` — a public bucket, a wildcard IAM policy, an oversized node group — and **fails the build if they come back clean**. A gate nobody tests is a gate that can silently stop gating after a config change.

### The gate found real problems

It was not a formality. On first run against this codebase it caught unrestricted security group egress, a missing DynamoDB point-in-time recovery setting, unencrypted EKS secrets, an over-broad CI trust policy, missing bucket lifecycle rules, and — via one of the custom rules — an untagged state bucket. All were genuine gaps, and all were fixed rather than skipped.

---

## LocalStack and kind versus real AWS

Every resource uses the real AWS provider. The only differences are the `endpoints` block and the dummy `test`/`test` credentials. Pointing this at a real account means deleting the endpoints block and supplying real credentials or an OIDC role — nothing in the resource definitions changes.

The `eks` module is written against the genuine AWS schema, `terraform validate`s clean, and is deliberately never applied. It carries KMS-encrypted secrets, all five control-plane log types, private-only endpoint access, and the three AWS-managed policies a node group actually requires.

**The honest framing:** this is a cost decision made during a job search, not a shortcut. The HCL is real, the policy gate and cost estimation work identically against a plan file regardless of target, and the Kubernetes work is the same `kubectl`, Helm and ArgoCD as any managed cluster. What it does not prove is that the EKS module applies cleanly — which is exactly why it is labelled as unapplied rather than quietly presented as running.

---

## Version pinning forced by licensing

### LocalStack is pinned to 4.9

From the 2026 releases onward, `localstack/localstack:latest` refuses to start without a `LOCALSTACK_AUTH_TOKEN`. It exits with code 55 and `License activation failed`, taking the whole CI job with it — the failure looks like a networking or readiness problem until you read the container logs.

Tags were tested downward from `latest`: 4.9, 4.5 and 4.0 all start unlicensed and report `edition: community`; the 2026 builds do not. **4.9 is therefore the newest usable tag**, and it exposes S3, DynamoDB, IAM, EC2 and STS — everything this project touches.

The alternative was storing a personal LocalStack token as a repository secret. That was rejected because it makes CI depend on one person's credential and prevents anyone forking the repo from running the pipeline. Pinning keeps the project genuinely credential-free.

### The Go builder is pinned above the CVE line, not to a fixed patch

The first real CI run failed the Trivy gate: `golang:1.22-alpine` pins the standard library at 1.22.12, which carries 21 HIGH and 1 CRITICAL advisories — TLS certificate validation during session resumption, x509 and HTTP/2 denial of service, and others.

The builder now tracks `golang:1.26-alpine`, currently 1.26.8, above the highest required fix of 1.26.6. Tracking the minor rather than pinning an exact patch means routine rebuilds pick up stdlib security fixes without a code change.

This is worth stating plainly: the vulnerability gate was not decorative. It caught a real supply-chain problem on its first genuine run and refused to publish the image.

### Container registries reject uppercase repository names

The GHCR push failed with `repository name (sthitajoshi/CloudForge) must be lowercase`. `github.repository` preserves the owner and repository casing exactly as created, and the OCI distribution spec requires lowercase.

The workflow now lowercases it explicitly rather than relying on the repository having been named in lowercase — the same class of bug as the ArgoCD `repoURL` mismatch, and worth fixing structurally in both places.
