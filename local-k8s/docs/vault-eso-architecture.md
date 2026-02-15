# Vault + ESO Architecture

## What gets deployed

The Vault Helm chart deploys **Vault server itself** as a pod inside the cluster — not an operator or proxy.

### `helm_release.vault` — Vault server

Runs an actual Vault server instance (`vault-0` pod) in **standalone mode with persistent file storage** (NFS-backed PVC). It's the same HashiCorp Vault you'd run anywhere, just containerized.

Terraform automatically handles the init/unseal/configure ceremony during provisioning:
1. **Initialize** with 1 unseal key share (simplified for lab)
2. **Unseal** the Vault
3. **Store** the unseal key and root token in a Kubernetes secret (`vault-unseal-key`)
4. **Enable** the KV v2 secrets engine at `secret/`
5. **Create** the `vault-token` secret for ESO authentication

On pod restart, a `postStart` lifecycle hook automatically unseals Vault using the key from the mounted `vault-unseal-key` secret — no manual intervention needed.

Vault exposes an HTTP API (port 8200) that any client inside the cluster can use to read/write secrets. Secrets are persisted to a 1Gi NFS PVC and survive pod restarts.

### `helm_release.external_secrets` — External Secrets Operator (ESO)

ESO is a Kubernetes **operator** — a controller that extends Kubernetes with custom resources (`ExternalSecret`, `ClusterSecretStore`, etc.) and runs a reconciliation loop that watches for them.

When you create an `ExternalSecret` resource in a namespace, the ESO controller:
1. Reads the spec to determine which secret to fetch and from where
2. Connects to the configured secret store (Vault in our case) via its API
3. Creates or updates a regular Kubernetes `Secret` with the fetched data
4. Keeps it in sync — if the value changes in Vault, ESO updates the K8s Secret

### Secret delivery flow

```
Vault server (pod in cluster, port 8200)
    ↑ fetches secrets via HTTP API
ESO controller (operator, runs in external-secrets namespace)
    ↑ watches for changes
ExternalSecret CR (created in app namespace)
    ↓ creates/updates
Kubernetes Secret (consumed by application pods)
```

## Two approaches to delivering secrets: Injector vs ESO

The Vault Helm chart includes an optional **Agent Injector** (`injector.enabled`). We disabled it because we use ESO instead. These are two fundamentally different approaches to the same problem: getting secrets from Vault into application pods.

### Vault Agent Injector (`injector.enabled = true`)

The injector is a **mutating admission webhook**. When a pod is created with specific annotations, the injector automatically modifies it:

1. Adds an **init container** that authenticates to Vault and fetches secrets before the app starts
2. Adds a **sidecar container** (`vault-agent`) that keeps secrets refreshed throughout the pod's lifecycle
3. Secrets are written as **files** to a shared volume (e.g., `/vault/secrets/db-password`)

```yaml
# Application pod with Vault annotations
apiVersion: v1
kind: Pod
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-app"
    vault.hashicorp.com/agent-inject-secret-db-password: "secret/data/db"
spec:
  containers:
    - name: my-app
      # reads secrets from /vault/secrets/db-password
```

**How it works:** webhook intercepts pod creation → injects sidecar → sidecar authenticates to Vault → writes secrets as files inside the pod.

### External Secrets Operator (ESO)

ESO takes a different approach — it creates **native Kubernetes Secrets** that pods consume the standard way (env vars or volume mounts).

```yaml
# ExternalSecret tells ESO what to fetch
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: db-credentials    # K8s Secret to create
  data:
    - secretKey: password   # key in K8s Secret
      remoteRef:
        key: secret/data/db # path in Vault
        property: password  # field in Vault secret
```

**How it works:** ESO controller watches ExternalSecret CRs → fetches values from Vault → creates/updates standard K8s Secrets → pods use them normally via `envFrom` or `volumeMounts`.

### Comparison

| Aspect | Vault Agent Injector | External Secrets Operator |
|---|---|---|
| **Secret format** | Files inside pod (`/vault/secrets/...`) | Standard K8s Secret (env vars or volumes) |
| **Pod modification** | Injects sidecar container into every pod | No pod modification — creates Secrets externally |
| **Resource overhead** | Extra container per pod (memory + CPU) | Single controller for the whole cluster |
| **Application awareness** | App must read files from specific path | App uses standard K8s Secret — no Vault awareness |
| **GitOps compatibility** | Annotations on pod spec (in Git) | ExternalSecret manifests (in Git) |
| **Vault dependency** | Each pod directly depends on Vault at startup | Only ESO depends on Vault; pods depend on K8s Secrets |

### Why we chose ESO

- **No sidecar overhead** — with the injector, every pod gets an extra container consuming memory and CPU. In a resource-constrained lab environment running on student laptops, this adds up quickly.
- **Standard Kubernetes Secrets** — applications don't need to know about Vault. They consume secrets the standard Kubernetes way (`envFrom`, `secretKeyRef`). This means no application code changes.
- **GitOps-native** — `ExternalSecret` manifests live in the deployment repo alongside other K8s resources. ArgoCD syncs them like any other resource.
- **Single controller** — one ESO deployment handles all namespaces, vs. a sidecar per pod with the injector.
