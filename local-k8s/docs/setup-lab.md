## GitHub Organization Creation

A GitHub account is required before proceeding. Create a new organization at [github.com/organizations/plan](https://github.com/organizations/plan) with a unique name, for example `kse-<your_unique_id>`. Start with the **Free** plan — you can upgrade later.

In later labs you will need to upgrade to the **Team** plan (a free trial is available). The Free plan does not include the security features used in this course. See [github.com/security/plans](https://github.com/security/plans) for a full comparison.

### Fork the course repositories

Create fork of the following repositories in your organization:
```bash
https://github.com/kse-bd8338bbe006/lab-env-setup.git
https://github.com/kse-bd8338bbe006/kse-labs-deployment.git
https://github.com/kse-bd8338bbe006/kse-labs-trusted-workflows.git
https://github.com/kse-bd8338bbe006/simple-go-service-a.git
```

For **each** repository, create a new **empty** repository with the **same name** in your organization via GitHub UI (no README, no .gitignore).

Then run this script to re-host all 3 repos at once (replace `YOUR_ORG` with your organization name):

```bash
ORG=YOUR_ORG

for REPO in kse-labs-deployment kse-labs-trusted-workflows simple-go-service-a; do
  cd "$REPO"
  rm -rf .git
  git init
  git add .
  git commit -m "Initial commit"
  git remote add origin "https://github.com/$ORG/$REPO.git"
  git push -u origin main
  cd ..
done
```

### Instructor access

Once your organization and repositories are set up:
1. Submit your organization name to the instructor.
2. Invite the instructor's GitHub account as an **outside collaborator** (with read access) to your organization. This allows the instructor to review your commit history, workflow runs, and overall progress.

> **Note:** In future labs we will transition to **GitHub Classroom** (classroom.github.com), which auto-creates repos from templates per student, tracks progress, and provides a grading dashboard.

### Setup K8s

Clone the lab environment repository:
```bash
git clone https://github.com/kse-bd8338bbe006/lab-env.git
```

Based on your OS, follow the corresponding setup:

| OS | Virtualization | Setup |
|----|---------------|-------|
| **macOS** | Multipass (QEMU) | `cd lab-env/local-k8s/scripts/macos && terraform init && terraform apply` |
| **Windows Pro/Enterprise/Education** | Multipass (Hyper-V) | `cd lab-env\local-k8s\scripts\windows` then run `setup-network.ps1`, `terraform init`, `terraform apply` |
| **Windows Home** | VirtualBox + Vagrant | `cd lab-env\local-k8s\scripts\virtual-box` then run `.\create-cluster.cmd` |

**macOS only:** After the first `terraform apply`, run `sudo ./setup-network.sh` to enable host connectivity to the cluster IPs, then re-run `terraform apply`.

See [Setup Guide](setup-guide.md) for detailed step-by-step instructions.


### kubeconfig configuration
```bash
cp config-multipass config
```
or use export:
```bash
export KUBECONFIG=$(pwd)/config-multipass
```


### Configure ArgoCD

Retrieve the initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Open the ArgoCD UI in your browser (e.g. `http://argocd.192.168.50.10.nip.io`) and log in with:
- **Username:** `admin`
- **Password:** the value from the command above

First we need to create two project in argocd:
- one with the name "infra" for infra related components like opa gatekeeper that we will use later
- second one for the service. 

ArgoCD **Projects** provide logical grouping of applications and are important from a security perspective. Each project defines a set of allowed Kubernetes resources (via RBAC) that applications within it can create. This enforces least-privilege access per project:

- **`infra`** project — may need elevated permissions such as configuring admission controller webhooks, CRDs, ClusterRoles, and namespace-level policies
- **`services`** project — regular microservices only need a limited set of permissions:
  - Deployments
  - Services
  - Ingresses
  - Secrets
  - ConfigMaps
Projects are especially useful in multi-team environments where multiple teams deploy to the same cluster. By combining Kubernetes namespaces, RBAC, and ArgoCD project configurations, you can enforce the **least-privilege principle** — each team can only deploy to their own namespaces and create only the resource types they need.
 The projects roles has set of the permissions that restrict what resources can be created/patched/deleted basd on the k8s RBAC and the code which is synced. 
 And we can grant CI system the specific access to project applications, it muse be associated with JWT. And we can use it to grant oidc groups a specific access to project applications

 Recomendation: do not use default project created argocd from the box, create your own that you will be use.


Go to settings / repo 
http://argocd.192.168.50.10.nip.io/settings/repos
and click on "connect repo"

Select HTTPS and connect the repo using:
- **Type:** git
- **Project:** leave empty (credentials will be available to all projects)
- **Repository URL:** `https://github.com/<your-org>/kse-labs-deployment.git`
- **Username:** `x-access-token`
- **Password:** a GitHub **Fine-grained Personal Access Token**. To generate one:
  1. Go to GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**
  2. Click **Generate new token**
  3. Give it a descriptive name (e.g. `argocd-repo-access`)
  4. Set **Resource owner** to your organization name
  5. Under **Repository access**, select **All repositories**
  6. Under **Permissions** → **Repository permissions**, set **Contents** to **Read-only**
  7. Click **Generate token** and copy the value
  8. Paste it as the password in ArgoCD

You should see Connection Status = successfull
![alt text](image.png)


Or use the ArgoCD CLI:
```bash
brew install argocd
argocd login argocd.192.168.50.10.nip.io:80 --username admin --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --insecure --grpc-web
```
You should see output like:
```
WARNING: server is not configured with TLS. Proceed (y/n)? y
'admin:login' logged in successfully
Context 'argocd.192.168.50.10.nip.io:80' updated
```

To connect the repository via CLI:
```bash
argocd repo add https://github.com/<your-org>/kse-labs-deployment.git \
  --username x-access-token \
  --password <your-fine-grained-token> \
  --grpc-web
```

### Deploy via bootstrap

The deployment repo uses a **bootstrap pattern** — a single ArgoCD Application that recursively syncs the `argocd/` directory, which contains all AppProjects and ApplicationSets. These in turn create the actual applications.

```
bootstrap.yaml (applies manually)
  └── argocd/
      ├── projects/
      │   ├── applications-project.yaml   (AppProject: applications)
      │   └── infra-project.yaml          (AppProject: infra)
      └── applicationsets/
          ├── applications.yaml           (ApplicationSet: scans applications/*)
          └── infra.yaml                  (ApplicationSet: scans infra/*)
```

The bootstrap app itself needs a dedicated project with minimal permissions. Apply it in two steps:

**Step 1:** Create the bootstrap project (solves the chicken-and-egg problem):
```bash
cd kse-labs-deployment
kubectl apply -f bootstrap-project.yaml
```

This creates a `bootstrap` AppProject that can **only** create AppProjects and ApplicationSets in the `argocd` namespace — nothing else.

**Step 2:** Apply the bootstrap application:
```bash
kubectl apply -f bootstrap.yaml
```

ArgoCD will now:
1. Sync `argocd/projects/` → create `infra` and `applications` AppProjects
2. Sync `argocd/applicationsets/` → create ApplicationSets that scan `infra/*` and `applications/*` directories
3. ApplicationSets auto-generate Applications for each subdirectory (e.g. `applications/simple-go-service-a`)

**Important:** Before pushing to your org, replace `kse-bd8338bbe006` with your organization name in all YAML files:
```bash
cd kse-labs-deployment
grep -rl "kse-bd8338bbe006" . | xargs sed -i '' 's/kse-bd8338bbe006/<your-org>/g'
git add -A && git commit -m "Update org name" && git push
```

### Configure container registry pull secret

Application images are stored in GitHub Container Registry (GHCR), which is private by default. Kubernetes needs credentials to pull images. The deployments reference an `imagePullSecret` named `ghcr-pull-secret`.

**Step 1:** Create a GitHub token with package read access. You can reuse your existing fine-grained token if you add the **`packages:read`** permission, or create a classic token with the `read:packages` scope.

**Step 2:** Create the secret in each application namespace:
```bash
kubectl create secret docker-registry ghcr-pull-secret \
  -n applications \
  --docker-server=ghcr.io \
  --docker-username=x-access-token \
  --docker-password=<your-github-token>
```

> **Note:** The namespace must exist before creating the secret. ArgoCD creates it automatically via `CreateNamespace=true` in the ApplicationSet sync policy, so run this command **after** the bootstrap has synced.

For multiple services, repeat for each namespace or use a script:
```bash
TOKEN=<your-github-token>
for NS in applications; do
  kubectl create secret docker-registry ghcr-pull-secret \
    -n "$NS" \
    --docker-server=ghcr.io \
    --docker-username=x-access-token \
    --docker-password="$TOKEN"
done
```

#### Secret management with Vault + ESO

Manually creating secrets via `kubectl` works for initial setup, but doesn't scale and isn't GitOps-friendly. The lab cluster comes with **HashiCorp Vault** and **External Secrets Operator (ESO)** pre-installed via Terraform.

**How it works:**
- **Vault** runs as a standalone server inside the cluster with **persistent file storage** (NFS-backed PVC). Secrets survive pod restarts. Terraform automatically initializes, unseals, and configures Vault during provisioning.
- **ESO** is a Kubernetes operator that watches for `ExternalSecret` resources and fetches secrets from Vault, creating standard Kubernetes `Secret` objects automatically.

**Accessing Vault:**

Retrieve the root token:
```bash
kubectl -n vault get secret vault-unseal-key -o jsonpath='{.data.root-token}' | base64 -d
```

Access Vault UI at `http://vault.<haproxy-ip>.nip.io` and log in with the token above.

> **Auto-unseal:** The Vault pod has a `postStart` lifecycle hook that automatically unseals Vault on restart using the unseal key stored in the `vault-unseal-key` Kubernetes secret. No manual intervention is needed after pod restarts.

The deployment repo already contains an `ExternalSecret` manifest at `applications/simple-go-service-a/ghcr-pull-secret.yaml` that references Vault. You only need to store the actual credentials in Vault:

```bash
# Get the root token
ROOT_TOKEN=$(kubectl -n vault get secret vault-unseal-key -o jsonpath='{.data.root-token}' | base64 -d)

# Store the GHCR credentials in Vault
kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault kv put secret/github/ghcr-pull-secret \
  docker-server=ghcr.io \
  docker-username=x-access-token \
  docker-password=<your-github-token>"
```

Once ArgoCD syncs the `ExternalSecret`, ESO fetches the credentials from Vault and creates the `ghcr-pull-secret` Kubernetes Secret automatically.

The `ExternalSecret` in the repo looks like this:

```yaml
# applications/simple-go-service-a/ghcr-pull-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ghcr-pull-secret
  namespace: applications
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: ghcr-pull-secret
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"{{ .dockerServer }}":{"username":"{{ .dockerUsername }}","password":"{{ .dockerPassword }}"}}}
  data:
    - secretKey: dockerServer
      remoteRef:
        key: secret/data/github/ghcr-pull-secret
        property: docker-server
    - secretKey: dockerUsername
      remoteRef:
        key: secret/data/github/ghcr-pull-secret
        property: docker-username
    - secretKey: dockerPassword
      remoteRef:
        key: secret/data/github/ghcr-pull-secret
        property: docker-password
```

> **Why this is better:** secrets never appear in Git (not even encrypted). The `ExternalSecret` only contains a *reference* to where the secret lives in Vault. The actual credentials exist only in Vault and in the auto-generated Kubernetes Secret.

For more details on the architecture and the difference between ESO and Vault Agent Injector, see [Vault + ESO Architecture](vault-eso-architecture.md).

### Create GitHub token to pull images from GHCR

The last step is to create a GitHub PAT with **Packages: Read** permission and store it in Vault. This token will be used to authenticate against the GitHub Container Registry (ghcr.io).

1. Go to **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token (classic)**
3. Name it `ghcr-pull` and select the `read:packages` scope
4. Click **Generate token** and copy the value

![alt text](image-1.png)

Store the token in Vault:

```bash
# Get the root token
ROOT_TOKEN=$(kubectl -n vault get secret vault-unseal-key -o jsonpath='{.data.root-token}' | base64 -d)

# Store credentials in Vault
kubectl exec -n vault vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault kv put secret/github/ghcr-pull-secret \
  docker-server=ghcr.io \
  docker-username=x-access-token \
  docker-password=ghp_yourTokenHere"
```

You should see a response like:

```
======== Secret Path ========
secret/data/github/ghcr-pull-secret

======= Metadata =======
Key                Value
---                -----
created_time       2026-02-14T07:56:27.840465062Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```
