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

The decrypt step is currently commented out in the GitHub Actions workflows, so `env-secrets.yaml` ships as plaintext today — wire the `sops -d` step back in before relying on encryption.

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
| **Any CNCF-compliant cluster** | Ensure enough CPU/RAM for backbone + core |

**Rough capacity (full stack, in-cluster Kafka/ES/MinIO):** 10+ GB RAM and 4+ CPUs available to the cluster (Kind: allocate in Docker Desktop / Podman). Postgres is expected to be an external RDS instance by default (see [Notes](#notes)).

This repo does **not** provision cloud accounts or managed Kubernetes — only Helm charts and Helmfile.

Terraform for infra live under `infra-as-code/` and are invoked separately by the `infra_setup.yaml` / `infra_destroy.yaml` GitHub workflows.

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

Then deploy with `HELMFILE_ENV=env` (see [Quick start](#quick-start)). For local testing without cert-manager, set `global.setup: quickstart` in `env.yaml` — this drops the `cert-manager.io/cluster-issuer` annotation and TLS block from the root ingress template.

**Tear down:**

```bash
kind delete cluster --name digit-studio
```

---

## Quick start

```bash
cd deploy-as-code
export HELMFILE_ENV=env
# Edit charts/environments/image-tags.yaml → per-service image.tag
# Edit charts/environments/env.yaml → domain, egov-config / egov-service-host data
# Edit charts/environments/env-secrets.yaml → db/minio/kafka/etc. credentials

helmfile -f digit-helmfile.yaml apply --include-needs=true
```

`digit-helmfile.yaml` only wires in `core-services` by default — `backbone-services` and `monitoring` are commented out:

```yaml
helmfiles:
#  - path: ./charts/backbone-services/backboneservices-helmfile.yaml
   - path: ./charts/core-services/coreservices-helmfile.yaml
  # - path: ./charts/monitoring/monitoring-helmfile.yaml
```

`env.yaml` already points Kafka/Elasticsearch/MinIO at `*.backbone` service hosts, so **uncomment the `backbone-services` line** unless those are provided externally. Uncomment `monitoring` if you want Prometheus/Grafana/Loki.

```bash
helmfile -f digit-helmfile.yaml diff
helmfile -f digit-helmfile.yaml list
helmfile -f digit-helmfile.yaml template
```

Skip a layer: comment its path in `digit-helmfile.yaml` (backbone-services and monitoring is off by default).

**Verify:**

```bash
kubectl get ns core backbone monitoring
kubectl get configmap -n core egov-config egov-service-host
kubectl get secret -n core db
```

---

## What `helmfile apply` does

| # | Helmfile | Namespace | What gets created |
|---|----------|-----------|-------------------|
| 1 | `charts/backbone-services/backboneservices-helmfile.yaml` | `backbone` | Kafka, Redis, Elasticsearch, MinIO, ingress-nginx, cert-manager, kibana, playground, jupyterhub, pgadmin4 (in-cluster `postgresql` chart present but `installed: false`) |
| 2 | `charts/core-services/coreservices-helmfile.yaml` | `core` | `configmaps` release (ConfigMaps/Secrets/root ingress) + all DIGIT core services + gateway + studio services (`digit-studio`, `public-service`, `studio-individual`, `studio-pdf`, `studio-service-request`, `health-individual`, `health-service-request`) |
| 3 | `charts/monitoring/monitoring-helmfile.yaml` | `monitoring` (+ `kafka-ui` in `backbone`) | Prometheus, Grafana, Loki (`jaeger`/`blackbox` present but `installed: false`) |


**DNS examples** (`env.yaml` defaults):

| Target | URL |
|--------|-----|
| Postgres | external RDS host set in `egov-config.db-host` (in-cluster `postgres.backbone:5432` if you enable the disabled `postgresql` release) |
| MDMS | `http://mdms-v2.core:8080/` |
| Public service | `http://public-service.core:8080/` |

---

## Namespaces

Namespaces `core`, `backbone`, and `monitoring` are created automatically by Helm the first time a release targeting them is applied.

---

## Why the `configmaps` release is required

`configmaps` (`charts/core-services/configmaps`) is a normal release inside `coreservices-helmfile.yaml` — not a separate layer. It renders:

| Resource | Names | Namespace | Purpose |
|----------|-------|-----------|---------|
| ConfigMap | `egov-config`, `egov-service-host` | `core` | DB, Kafka, ES, domain, tenant IDs, inter-service HTTP URLs |
| Secret | `db`, `git-creds`, `egov-filestore`, `egov-location`, `egov-enc-service`, `egov-notification-sms`, `egov-notification-mail`, `elasticsearch-master-credentials`, `egov-hrms`, `minio` | `core` | Per-service credentials |
| Secret | `pgadmin` | `backbone` | pgAdmin login |
| Secret | `alertmanager-main` | `monitoring` | Alertmanager routing config |
| Ingress | `root-ingress` | `core` | Routes `http(s)://<domain>/` to the `digit-studio` Service |

Templates under `charts/core-services/configmaps/templates/` (`egov-config.yaml`, `egov-service-host.yaml`, `root-ingress.yaml`, `secrets/`). Values for all of the above live in `configmaps/values.yaml` and get overridden per environment from `charts/environments/env.yaml` / `env-secrets.yaml`.

---

## Environment files

All environment files live under `deploy-as-code/charts/environments/`:

| File | Role |
|------|------|
| `environments/<HELMFILE_ENV>.yaml` | Domain, `egov-config` / `egov-service-host` data, per-service replicas/tuning |
| `environments/<HELMFILE_ENV>-secrets.yaml` | Passwords, keys — plaintext for testing; SOPS for cloud |
| `environments/image-tags.yaml` | Per-service `image.tag` (and `initContainers.dbMigration.image.tag`) |

```bash
export HELMFILE_ENV=env
```

### Image tags (core + studio services)

Each chart block in `image-tags.yaml` sets its own `image.tag` directly — there's no `defaultTag`/`overrides`/`global.image.tag` fallback chain; whatever `image-tags.yaml` sets simply overrides that chart's own `values.yaml` default when Helmfile merges values.

```yaml
egov-user:
  image:
    tag: sandbox-log-f4a87d0
  initContainers:
    dbMigration:
      image:
        tag: sandbox-log-f4a87d0
```

Flyway/db-migration init containers get their tag set alongside the parent service in the same block.

### Root ingress

The `root-ingress` release (part of `configmaps`) routes `http(s)://<domain>/` to the **digit-studio** Service in **core** (`appRoot: digit-studio` → `/digit-studio/`). Ingress must live in the same namespace as that Service.

Setting `global.setup: quickstart` drops the cert-manager annotation and TLS block for local/no-TLS testing.

---

## Layout

```bash
egov-digit-studio-one-click-deployment/
├── README.md
├── kind-cluster.yaml
├── configs/                          # static assets (e.g. globalConfigsStudio.js)
├── infra-as-code/                    # Terraform + Ansible, driven by infra_setup/infra_destroy workflows
└── deploy-as-code/
    ├── digit-helmfile.yaml
    └── charts/
        ├── .sops.yaml
        ├── environments/
        │   ├── env.yaml
        │   ├── env-secrets.yaml
        │   └── image-tags.yaml
        ├── common/                   # shared library chart (_deployment, _service, _ingress, …)
        ├── common-chart-template/    # scaffold for new service charts
        ├── backbone-services/        # backboneservices-helmfile.yaml + charts (kafka-kraft, elasticsearch, minio, ingress-nginx, cert-manager, …)
        ├── core-services/            # coreservices-helmfile.yaml + charts (DIGIT core, gateway, configmaps, and studio services)
        └── monitoring/               # monitoring-helmfile.yaml + charts (prometheus, grafana, loki, kafka-ui)
```

---

## Notes

| Topic | Detail |
|-------|--------|
| **Three namespaces** | `core`, `backbone`, `monitoring` — studio services now deploy into `core` alongside DIGIT core; pgadmin4/playground/cert-manager run in `backbone` |
| **Postgres** | Default (`env.yaml`) points `db-host`/`db-url` at an external RDS instance; the in-cluster `postgresql` chart under `backbone-services` exists but is `installed: false` |
| **Namespace rename** | YAML changes do not migrate existing workloads |
| **UI** | `digit-studio` chart owns the ingress; the `gateway` chart has no ingress template of its own |
| **Default-off layers** | `backbone-services` and `monitoring` are commented out in `digit-helmfile.yaml` — uncomment to deploy them |
