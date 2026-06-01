# Digit Studio — Kubernetes one-click deploy

Helmfile deploy for Digit Studio on Kubernetes. Pattern matches [DIGIT-DevOps](https://github.com/egovernments/DIGIT-DevOps) `deploy-as-code`.

**Entry point:** `deploy-as-code/helm/digit-helmfile.yaml`

---

## Prerequisites

### Tools (all environments)

| Tool | Version | Purpose |
|------|---------|---------|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | matches cluster | Apply and verify resources |
| [Helm](https://helm.sh/) | 3+ | Chart installs (used by Helmfile) |
| [Helmfile](https://github.com/helmfile/helmfile) | latest stable | Orchestrates layered deploy |
| [Docker](https://docs.docker.com/get-docker/) | — | Required for Kind; image pulls on nodes |

**Cloud / encrypted secrets (optional):** [SOPS](https://github.com/getsops/sops) + AWS KMS per `deploy-as-code/helm/.sops.yaml`.

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

**Rough capacity (full stack, in-cluster Postgres/Kafka/ES):** 10+ GB RAM and 4+ CPUs available to the cluster (Kind: allocate in Docker Desktop / Podman).

This repo does **not** provision cloud accounts or managed Kubernetes — only Helm charts and Helmfile.

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

Then deploy with `HELMFILE_ENV=testing` (see [Quick start](#quick-start)). Use `global.setup: quickstart` in `testing.yaml` (no cert-manager).

**Tear down:**

```bash
kind delete cluster --name digit-studio
```

**Without Kubernetes:** use Docker Compose in `../egov-digit-studio/`.

---

## Quick start

```bash
cd deploy-as-code/helm
export HELMFILE_ENV=testing
export COMMON_TAG=v2.9.2-4a60f20     # optional

helmfile -f digit-helmfile.yaml apply --include-needs=true
```

```bash
helmfile -f digit-helmfile.yaml diff
helmfile -f digit-helmfile.yaml list
helmfile -f digit-helmfile.yaml template
```

Skip a layer: comment its path in `digit-helmfile.yaml` (monitoring is off by default).

**Verify:**

```bash
kubectl get ns core backbone digit-studio monitoring
kubectl get configmap -n core egov-config egov-service-host
kubectl get secret -n core db
```

---

## What `helmfile apply` does

| # | Layer | Namespace | What gets created |
|---|--------|-----------|-------------------|
| 1 | **cluster-configs** | release in `core` | Namespaces, `egov-config` / `egov-service-host`, Secrets, RBAC, root ingress |
| 2 | **backbone** | `backbone` | Postgres, Kafka, Redis, Elasticsearch, MinIO, ingress-nginx |
| 3 | **core** | `core` | DIGIT core + egov-hrms |
| 4 | **studio** | `digit-studio` | digit-studio, public-service, health services, … |
| 5 | **monitoring** | `monitoring` | Prometheus, Grafana, Loki *(optional)* |

**DNS examples** (`testing.yaml`):

| Target | URL |
|--------|-----|
| Postgres | `postgres.backbone:5432` |
| MDMS | `http://mdms-v2.core:8080/` |
| Public service | `http://public-service.digit-studio:8080/` |

---

## Namespaces

Created by the **cluster-configs** chart (not Helmfile directly):

1. Template: `charts/cluster-configs/templates/namespaces.yaml`
2. When `cluster-configs.namespaces.create: true`, emits one `Namespace` per entry in `cluster-configs.namespaces.values`
3. Later layers deploy into those namespaces

```yaml
# environments/<env>.yaml
cluster-configs:
  namespaces:
    create: true
    values:
      - core
      - backbone
      - digit-studio
      - monitoring
```

---

## Why cluster-configs is required

| Resource | Names | Namespaces | Purpose |
|----------|-------|------------|---------|
| ConfigMap | `egov-config` | `core`, `digit-studio` | DB, Kafka, ES, domain, tenant IDs |
| ConfigMap | `egov-service-host` | `core`, `digit-studio` | Inter-service HTTP URLs |
| Secret | `db` | `core` | Postgres / Flyway credentials |
| Secret | `minio`, `kafka-kraft` | `backbone` | Object store, Kafka cluster id |
| Secret | `elasticsearch-master-creds` | `backbone`, `core` | Elasticsearch auth |

Templates under `charts/cluster-configs/templates/` (`namespaces.yaml`, `configmaps/`, `secrets/`).

---

## Environment files

| File | Role |
|------|------|
| `environments/<HELMFILE_ENV>.yaml` | Domain, namespaces, ConfigMaps, service URLs, replicas |
| `environments/<HELMFILE_ENV>-secrets.yaml` | Passwords, keys (plaintext for `testing`; SOPS for cloud) |

```bash
export HELMFILE_ENV=testing
```

---

## Layout

```
egov-digit-studio-one-click-deployment/
├── README.md
├── kind-cluster.yaml
└── deploy-as-code/helm/
    ├── digit-helmfile.yaml
    ├── environments/
    │   ├── testing.yaml
    │   └── testing-secrets.yaml
    └── charts/
        ├── cluster-configs/
        ├── backbone-services/
        ├── core-services/
        ├── studio-services/
        └── monitoring/
```

---

## Notes

| Topic | Detail |
|-------|--------|
| **External RDS** | Point `db-host` / `db-url` in `egov-config` at RDS instead of `postgres.backbone` |
| **Namespace rename** | YAML changes do not migrate existing workloads |
| **UI** | `digit-studio` chart ingress (no separate gateway chart) |
