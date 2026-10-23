crossplane-provider-aws FIPS Port Report
=========================================

## Summary

**Application:** crossplane-provider-aws — the Crossplane community provider for AWS. It is a
Kubernetes controller that reconciles AWS resources (EC2, S3, RDS, IAM, etc.) declared as
Kubernetes custom resources against the real AWS APIs.

**Triage results:**
- Language: Go 1.23
- FIPS mechanism: ENV GODEBUG=fips140=only (Go native FIPS enforcement)
- Build pattern: Pattern D — fresh Dockerfile generated from scratch
  (the upstream Dockerfile is a trivial 5-line distroless ADD-only file; a full
  multi-stage Pattern D build was more appropriate)
- Binary: /usr/local/bin/crossplane-aws-provider (from ./cmd/provider)
- User: nonroot (UID/GID 65532); groupadd+useradd required (gardenlinux ships only root+nobody)
- Ports: none — outbound-only Kubernetes controller

**Metadata:**
- Version: 0.59.0
- License: Apache-2.0
- Upstream git SHA: 5829880faaca3d4bcedd6554fd6a90ab4eb0928c

**FIPS-enabled crypto library:** Go standard library with GODEBUG=fips140=only (Go 1.23
FIPS mode enforced via the runtime environment variable; CGO_ENABLED=0 static binary)

**Docker image built:**
- gl-fips-crossplane-provider-aws:0.59.0-amd64
- Image size: 78 MB

---

## Steps taken

- Cloned https://github.com/crossplane-contrib/provider-aws, checked out v0.59.0
  (SHA 5829880faaca3d4bcedd6554fd6a90ab4eb0928c).

- Triage: go.mod confirmed Go 1.23; single binary in ./cmd/provider; no inbound ports
  (pure outbound Kubernetes controller); upstream Dockerfile uses distroless/static with
  a pre-built binary added via ADD — not suitable for a FIPS multi-stage build, so chose
  Pattern D (generate from scratch).

- Generated a two-stage Dockerfile: golang:1.23-bookworm builder (publishes amd64+arm64,
  safe without extra manifest check per the rules) compiling with CGO_ENABLED=0 and
  -ldflags embedding the version string; final stage on ghcr.io/gardenlinux/gardenlinux/fips:1877.22.

- Added groupadd -g 65532 nonroot && useradd ... before the COPY step because gardenlinux
  only ships root (0) and nobody (65534) — nonroot (65532) must be created explicitly.
  useradd emitted a UID_MIN/UID_MAX warning (65532 is outside the Debian default range
  of 1000–60000) but this is cosmetic; the user is created successfully.

- Injected GODEBUG=fips140=only, USER 65532, and all three OCI labels including
  org.opencontainers.image.revision (with ARG UPSTREAM_GIT_SHA redeclared in the final
  stage per the ARG scoping rule).

- Build succeeded on first attempt: no script fixes were required.

---

## Test script output

*** Checking if gl-fips-crossplane-provider-aws:0.59.0-amd64 docker image is available ***
[docker inspect: OK — image present, 81613420 bytes]
*** Checking if gl-fips-crossplane-provider-aws:0.59.0-amd64 is based on gardenlinux ***
NAME="Garden Linux" ✓
*** Checking if gl-fips-crossplane-provider-aws:0.59.0-amd64 is using FIPS-enabled gardenlinux image ***
VARIANT_ID=container-sslfips-amd64 ✓
*** Checking that gl-fips-crossplane-provider-aws:0.59.0-amd64 starts under a non-root user ***
effective_user=nonroot ✓
*** Checking if gl-fips-crossplane-provider-aws:0.59.0-amd64 has GO FIPS mode enabled ***
GODEBUG=fips140=only ✓
*** Checking org.opencontainers.image.description label ***
"A FIPS-enabled crossplane-provider-aws image" ✓
*** Checking org.opencontainers.image.licenses label ***
"Apache-2.0" ✓
*** Checking org.opencontainers.image.revision label ***
"5829880faaca3d4bcedd6554fd6a90ab4eb0928c" ✓

All test checks: PASSED

---

## Kubernetes (k3d) test run

Cluster: fips-test (k3d, already running)
Image imported with: k3d image import gl-fips-crossplane-provider-aws:0.59.0-amd64 --cluster fips-test

Pod manifest: .build/fips-port-crossplane-provider-aws-pod.yaml
  args: ["--help"]  (binary exits after printing help — expected Completed status)

Pod status after 30s: Completed (0 restarts)

Pod logs:
  usage: crossplane-aws-provider [<flags>]
  AWS support for Crossplane.
  Flags:
    --help / --debug / --sync / --poll / --leader-election / --max-reconcile-rate
    --namespace / --enable-external-secret-stores / --enable-management-policies

| Image tag                                       | Pod status | Pass/fail |
|-------------------------------------------------|------------|-----------|
| gl-fips-crossplane-provider-aws:0.59.0-amd64   | Completed  | PASS      |

Pod deleted after logging.
