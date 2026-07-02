# 🐍 Argocd-SNAKE

Jeu **Snake** (Node.js / Express) déployé sur **Kubernetes** et piloté de bout en
bout par **ArgoCD** (GitOps). Le projet couvre le déploiement continu, le
multi-environnement (Helm), les déploiements progressifs (Argo Rollouts) et
l'infrastructure as code (Terraform Controller).

---

## Architecture

```
         ┌───────────────┐        git push (app/)
         │   Développeur │ ───────────────────────────┐
         └───────────────┘                            ▼
                                          ┌──────────────────────┐
                                          │   GitHub (ce repo)    │
                                          │  main  ◄──  test      │
                                          └───────────┬──────────┘
                                                      │ surveille
                        ┌─────────────────────────────┼──────────────────────────┐
                        │                             │                            │
                        ▼                             ▼                            ▼
                 ┌────────────┐               ┌──────────────┐            ┌────────────────┐
                 │   ArgoCD   │               │ Argo Rollouts│            │ Terraform Ctrl │
                 │ (app CD)   │               │  (canary)    │            │  (Flux + IaC)  │
                 └─────┬──────┘               └──────┬───────┘            └───────┬────────┘
                       │ sync                        │                            │ apply
                       ▼                             ▼                            ▼
        ┌──────────────────────────────────────────────────────────────────────────────┐
        │                            Cluster Kubernetes (k3d)                            │
        │                                                                                │
        │   ns snake-dev            ns snake-prod                ns snake-infra          │
        │   Deployment (1 pod)      Rollout canary (3 pods)      (créé par Terraform)    │
        │   Service                 Service                      RBAC + NetworkPolicy    │
        └──────────────────────────────────────────────────────────────────────────────┘
```

**Principe GitOps** : l'état désiré vit dans Git (`main`). ArgoCD et Terraform
Controller réconcilient en continu le cluster avec ce qui est déclaré dans le
dépôt. Aucun `kubectl apply` manuel sur l'application.

## Structure du dépôt

```
Argocd-SNAKE/
├── app/                       # Application Snake (Express + jeu + API scores)
│   ├── src/                   #   serveur, API, front canvas
│   ├── tests/                 #   tests jest
│   └── Dockerfile             #   image multi-stage, non-root
├── gitops/
│   ├── apps/snake/            #   manifests Kustomize (base + overlays dev/prod)
│   ├── helm/snake/            #   chart Helm (Deployment ou Rollout) + values par env
│   ├── argocd/applications/   #   AppProject + Applications ArgoCD (dev/prod)
│   ├── rollouts/              #   Rollout canary / blue-green
│   ├── infrastructure/        #   module Terraform + ressources Flux TF Controller
│   └── security/              #   Sealed Secrets, RBAC ArgoCD, network policy
├── .github/workflows/         # CI GitHub Actions (build → push GHCR → maj tag)
├── scripts/                   # setup cluster / argocd / rollouts / terraform
├── demo.sh                    # script de démonstration guidée
└── README.md
```

## Prérequis

- **Docker Desktop** lancé
- `k3d`, `kubectl`, `helm`, `argocd`, plugin `kubectl-argo-rollouts`

```bash
brew install k3d kubectl helm argocd
brew install argoproj/tap/kubectl-argo-rollouts
```

## Lancer le projet (depuis zéro)

```bash
# 1. Cluster k3d + ArgoCD
./scripts/01-setup-cluster.sh
# récupérer le mot de passe admin ArgoCD (user = admin) :
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 2. Argo Rollouts (déploiements progressifs)
./scripts/02-install-rollouts.sh

# 3. Construire l'image et l'importer dans le cluster
docker build -t ghcr.io/brubru-420/argocd-snake:dev-latest ./app
docker tag  ghcr.io/brubru-420/argocd-snake:dev-latest \
            ghcr.io/brubru-420/argocd-snake:prod-latest
k3d image import ghcr.io/brubru-420/argocd-snake:dev-latest \
                 ghcr.io/brubru-420/argocd-snake:prod-latest -c snake

# 4. Enregistrer le repo dans ArgoCD, puis déclarer les Applications
#    (garder un port-forward ArgoCD actif : voir "Accès" ci-dessous)
argocd login localhost:8081 --username admin --insecure
argocd repo add https://github.com/brubru-420/Argocd-SNAKE.git   # + token si repo privé
./scripts/03-bootstrap-apps.sh

# 5. Infrastructure as Code (Terraform Controller)
./scripts/04-install-terraform-controller.sh
# donner au runner Terraform les droits de créer les ressources cluster :
kubectl create clusterrolebinding tf-runner-admin \
  --clusterrole=cluster-admin --serviceaccount=flux-system:tf-runner
```

ArgoCD synchronise alors la todo-... pardon, la **snake-api** dans `snake-dev`
et `snake-prod` automatiquement depuis Git.

## Accès aux interfaces

```bash
# Le jeu (environnement dev)
kubectl -n snake-dev port-forward svc/snake 3000:80        # http://localhost:3000

# Interface ArgoCD (user admin)
kubectl -n argocd port-forward svc/argocd-server 8081:443  # https://localhost:8081

# Dashboard Argo Rollouts
kubectl argo rollouts dashboard                            # http://localhost:3100
```

## Démonstration

Un script guidé déroule et prouve chaque étape sur le cluster :

```bash
./demo.sh
```

## Détruire l'environnement

```bash
./scripts/99-teardown.sh     # supprime le cluster k3d
```

## Branches

- **`main`** — branche stable, suivie par ArgoCD (`targetRevision: main`).
- **`test`** — branche de développement ; les features y sont intégrées avant merge.
