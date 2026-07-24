# Digit Studio — Kubernetes one-click deploy

Helmfile deploy for Digit Studio on Kubernetes. Pattern matches [DIGIT-DevOps](https://github.com/egovernments/DIGIT-DevOps) `deploy-as-code`.

**Entry point:** `deploy-as-code/digit-helmfile.yaml`

---

## Prerequisites

### Tools (all environments)

| Tool | Version | Purpose |
|------|---------|---------|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | matches cluster | Apply and verify resources |
| [Helm](https://helm.sh/) | 3+ | Chart installs (used by Helmfile) |
| [Helmfile](https://github.com/helmfile/helmfile) | latest stable | Orchestrates layered deploy |
| [Docker](https://docs.docker.com/get-docker/) | — | Required for Kind; image pulls on nodes |

**Cloud / encrypted secrets (optional):** [SOPS](https://github.com/getsops/sops) + AWS KMS per `deploy-as-code/charts/.sops.yaml`.

### Kubernetes cluster

You need a working cluster and a kubeconfig context:

```bash
kubectl cluster-info
kubectl get nodes
```

Supported targets:

| Target | Use case |
|--------|----------|
| **Kind** (local) | Laptop dev — see [Local cluster (Kind)](#local-cluster-kind) |
| **EKS / GKE / AKS** | Shared or production environments |
| **Minikube** | Alternative local cluster (configure ingress separately) |
| **Any CNCF-compliant cluster** | Ensure enough CPU/RAM for backbone + core + studio |

**Rough capacity (full stack, in-cluster Postgres/Kafka/ES):** 10+ GB RAM and 8+ CPUs available to the cluster (Kind: allocate in Docker Desktop / Podman).

Helm charts and Helmfile deploy workloads; optional Terraform under `infra-as-code/terraform/` provisions AWS EKS/RDS (see [GitHub Actions (EKS)](#github-actions-eks) or `infra-as-code/terraform/sample-aws/`).

---

## Local cluster (Kind)

For local development, create a cluster from the repo root:

```bash
# Install Kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
kind create cluster --config kind-cluster.yaml
```

`kind-cluster.yaml` defines cluster name `digit-studio`, maps **host ports 80/443** to the control plane (for ingress-nginx), and adds worker nodes with `node-role=workload`.

Confirm context:

```bash
kubectl config use-context kind-digit-studio
kubectl get nodes
```

Then deploy with `HELMFILE_ENV=env` (see [Quick start](#quick-start)). For Kind without cert-manager, set `global.setup: quickstart` in `deploy-as-code/charts/environments/env.yaml`.

**Tear down:**

```bash
kind delete cluster --name digit-studio
```

**Without Kubernetes:** use Docker Compose in `../egov-digit-studio/`.

---

## Quick start

```bash
cd deploy-as-code
export HELMFILE_ENV=env
# Edit charts/environments/env.yaml (domain, configmaps, service config)
# Edit charts/environments/image-tags.yaml (image tags)

helmfile -f digit-helmfile.yaml apply --include-needs=true
```

```bash
helmfile -f digit-helmfile.yaml diff
helmfile -f digit-helmfile.yaml list
helmfile -f digit-helmfile.yaml template
```

Skip a layer: comment its path in `digit-helmfile.yaml` (backbone and monitoring are off by default).

**Verify:**

```bash
kubectl get ns core backbone monitoring
kubectl get configmap -n core egov-config egov-service-host
kubectl get secret -n core db
```

---

## GitHub Actions (EKS)

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| **Setup Infrastructure** | `workflow_dispatch` | Terraform plan for AWS EKS/RDS (`infra-as-code/terraform/sample-aws/`) |
| **Deploy Applications to Cluster** | `workflow_dispatch` | Optional infra step, then `helmfile apply` with `HELMFILE_ENV=env` on EKS |

Requires GitHub secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`; repo variable `CLUSTER_NAME`. SOPS decrypt steps are present but commented out pending KMS setup.

---

## What `helmfile apply` does

`digit-helmfile.yaml` includes sub-helmfiles; only **core** is enabled by default.

| # | Layer | Helmfile | Default | Namespace | What gets created |
|---|-------|----------|---------|-----------|-------------------|
| 1 | **core** (incl. configmaps + studio) | `charts/core-services/coreservices-helmfile.yaml` | on | `core` | `egov-config` / `egov-service-host`, Secrets, root ingress, DIGIT core, digit-studio, public-service, health services, … |
| 2 | **backbone** | `charts/backbone-services/backboneservices-helmfile.yaml` | off | `backbone` | cert-manager, Kafka, Redis, Elasticsearch, MinIO, ingress-nginx, pgadmin4, … |
| 3 | **monitoring** | `charts/monitoring/monitoring-helmfile.yaml` | off | `monitoring` | Prometheus, Grafana, Loki |

**DNS examples** (`env.yaml`):

| Target | URL |
|--------|-----|
| Postgres (RDS) | `studio-one-click-db.<region>.rds.amazonaws.com:5432` |
| MDMS | `http://mdms-v2.core:8080/` |
| Public service | `http://public-service.core:8080/` |

---

## Namespaces

Application workloads use three namespaces (`core`, `backbone`, `monitoring`). There is no namespace-provisioning chart — create them before deploy (e.g. `kubectl create ns core backbone monitoring`) or provision via `infra-as-code/`.

| Namespace | Workloads |
|-----------|-----------|
| `core` | DIGIT core, studio services, configmaps, root ingress |
| `backbone` | Kafka, Redis, Elasticsearch, ingress-nginx, cert-manager, pgadmin4, … |
| `monitoring` | Prometheus, Grafana, Loki *(when monitoring layer is enabled)* |

---

## JupyterHub (backbone)

`jupyterhub` (backbone layer, `charts/backbone-services/jupyterhub`) uses `NativeAuthenticator`, which has self-signup off by default — with no users provisioned yet, you can't log in.

**First deploy only:** before `helmfile apply`, set `open_signup: true` under `hub.config.NativeAuthenticator` in `jupyterhub/values.yaml` (or via an env override)

Then sign up your admin user (must match `hub.config.Authenticator.admin_users`, default `admin`) through the UI, then set `open_signup` back to `false` (or remove the override) and re-apply. Leaving it `true` lets anyone create an account.

**URL:** `https://<domain>/jupyterhub` (`ingress.hosts` = `global.domain`, path = `hub.baseUrl`).

---

## Why the configmaps release is required

The **configmaps** chart (first release in `coreservices-helmfile.yaml`) materializes shared platform config before services start:

| Resource | Names | Namespaces | Purpose |
|----------|-------|------------|---------|
| ConfigMap | `egov-config` | `core` | DB, Kafka, ES, domain, tenant IDs |
| ConfigMap | `egov-service-host` | `core` | Inter-service HTTP URLs |
| Secret | `db` | `core` | Postgres / Flyway credentials |
| Secret | `minio`, `kafka-kraft` | `core` / `backbone` | Object store, Kafka cluster id |
| Secret | `elasticsearch-master-credentials` | `core`, `backbone` | Elasticsearch auth |

Templates under `charts/core-services/configmaps/templates/` (`egov-config.yaml`, `egov-service-host.yaml`, `secrets/`, `root-ingress.yaml`).

---

## Environment files

| File | Role |
|------|------|
| `charts/environments/<HELMFILE_ENV>.yaml` | Domain, ConfigMaps, service URLs, replicas, per-service config |
| `charts/environments/<HELMFILE_ENV>-secrets.yaml` | Passwords, keys (plaintext for local; SOPS for cloud) |
| `charts/environments/image-tags.yaml` | Docker image tags for all charts |

```bash
export HELMFILE_ENV=env
```

### Image tags (core + digit-studio)

Tags live in `charts/environments/image-tags.yaml`. Each chart block sets `image.tag` (and `initContainers.dbMigration.image.tag` where applicable). `global.image.tag` in that file is the shared fallback for charts without an explicit override.

```yaml
global:
  image:
    tag: v2.9.2-4a60f20

health-individual:
  image:
    tag: master-nigeria-finalpull-dacaefe
```

Flyway init images (`egov-user-db`, etc.) use the **same tag** as the parent service.

### Root ingress

`root-ingress` (configmaps chart) routes `http(s)://<domain>/` to the **digit-studio** Service in **core** (`appRoot: digit-studio` → `/digit-studio/`). Ingress must live in the **same namespace** as that Service.

---

## AWS infrastructure (`sample-aws`)

Terraform under `infra-as-code/terraform/sample-aws/` provisions the AWS stack used by the `env` Helmfile environment. Full walkthrough: [DIGIT infrastructure setup (AWS)](https://core.digit.org/guides/installation-guide/infrastructure-setup/aws/3.-provision-infrastructure).

| Path | Role |
|------|------|
| `input.yaml` | High-level inputs (cluster name, domain, DB name/user, state bucket) — seed for `env.tfvars` |
| `variables/env.tfvars` | Values passed to `terraform plan/apply` |
| `variables.tf` | EKS version (default `1.33`), node sizing, RDS class, AZs |
| `backends/env.hcl` | S3 + DynamoDB remote state backend |
| `remote-state/` | One-time bootstrap: S3 bucket + DynamoDB lock table for Terraform state |
| `main.tf` | VPC, EKS cluster + node group (AL2023 AMI), RDS Postgres, S3 assets/filestore buckets, filestore IAM + K8s secret |

**What gets created**

| Resource | Notes |
|----------|-------|
| **EKS** | Cluster + managed node group (`m5a.xlarge` / `t4g.xlarge` by architecture); public + private API endpoint |
| **RDS** | Postgres 15 (`db.t4g.medium` default); endpoint surfaced as Terraform output |
| **S3** | Public assets bucket + private filestore bucket |
| **K8s** | `egov-filestore` Secret in `egov` namespace (filestore IAM keys) |

**Manual apply (two steps)**

```bash
# 1. Bootstrap remote state (once)
cd infra-as-code/terraform/sample-aws/remote-state
terraform init && terraform apply -var-file=../variables/env.tfvars

# 2. Provision cluster + DB
cd ..
terraform init -backend-config=./backends/env.hcl
terraform plan  -var-file=./variables/env.tfvars -var db_password='<password>'
terraform apply -var-file=./variables/env.tfvars -var db_password='<password>'
```

After apply, copy RDS endpoint / credentials into `deploy-as-code/charts/environments/env.yaml` and `env-secrets.yaml`, then run Helmfile (or use **Deploy Applications to Cluster**). The GitHub **Setup Infrastructure** workflow runs the same Terraform paths but currently stops at `plan` (apply steps are commented out).

**DNS after Helmfile apply:** `ingress-nginx` (`controller.service.type: LoadBalancer`) provisions an AWS ELB/NLB with an auto-generated hostname — there's no ExternalDNS wired up to do this for you. Get it with:

```bash
kubectl get svc -n backbone ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Then create a CNAME for `global.domain` (`deploy-as-code/charts/environments/env.yaml`) pointing at that hostname in your DNS provider. Do this before relying on TLS/cert-manager, since `HTTP-01` validation needs the domain resolving to the load balancer first.

---

## Layout

```
egov-digit-studio-one-click-deployment/
├── README.md
├── kind-cluster.yaml
├── .github/workflows/
│   ├── application_deployment.yaml
│   └── infra_setup.yaml
├── infra-as-code/
│   └── terraform/          # AWS EKS/RDS (sample-aws), GCP, Azure samples
└── deploy-as-code/
    ├── digit-helmfile.yaml
    └── charts/
        ├── environments/
        │   ├── env.yaml
        │   ├── env-secrets.yaml
        │   └── image-tags.yaml
        ├── common/
        ├── backbone-services/
        ├── core-services/
        └── monitoring/
```

---

## Notes

| Topic | Detail |
|-------|--------|
| **Namespaces** | `core`, `backbone`, `monitoring`; pgadmin/playground/cert-manager run in `backbone` when that layer is enabled |
| **External RDS** | Point `db-host` / `db-url` in `egov-config` at RDS instead of in-cluster Postgres |
| **Namespace rename** | YAML changes do not migrate existing workloads |
| **UI** | `digit-studio` chart owns the root ingress; the `gateway` release (`core-services/gateway`, Spring Cloud Gateway) is an internal backend service with no ingress of its own |
