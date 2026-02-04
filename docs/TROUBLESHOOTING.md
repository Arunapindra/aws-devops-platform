# Troubleshooting Guide

This guide covers common issues you may encounter while working with the aws-devops-platform project, organized by component. Each issue includes the symptom, cause, and exact commands to resolve it.

---

## Table of Contents

1. [Minikube Issues](#1-minikube-issues)
2. [Docker Issues](#2-docker-issues)
3. [ArgoCD Issues](#3-argocd-issues)
4. [Helm Issues](#4-helm-issues)
5. [kubectl Issues](#5-kubectl-issues)
6. [Port-Forwarding Issues](#6-port-forwarding-issues)
7. [Terraform Issues](#7-terraform-issues)
8. [ECR Issues](#8-ecr-issues)
9. [Kustomize Issues](#9-kustomize-issues)
10. [GitHub Actions Issues](#10-github-actions-issues)
11. [Resource and Quota Issues](#11-resource-and-quota-issues)
12. [Pod CrashLoopBackOff Debugging](#12-pod-crashloopbackoff-debugging)
13. [Checking Logs for Each Component](#13-checking-logs-for-each-component)
14. [How to Reset Everything and Start Fresh](#14-how-to-reset-everything-and-start-fresh)

---

## 1. Minikube Issues

### Minikube won't start -- not enough resources

**Symptom:**
```
* Exiting due to RSRC_INSUFFICIENT_CORES: Requested cpu count 4 is greater than the available CPUs
```
or
```
* Exiting due to RSRC_INSUFFICIENT_MEMORY: Requested memory 8192MB is greater than available ...
```

**Cause:** Your machine does not have enough CPU or memory available, or Docker Desktop resource limits are too low.

**Solution:**

1. Open Docker Desktop > Settings > Resources and increase:
   - CPUs: At least 4
   - Memory: At least 8 GB

2. If your machine has limited resources, start Minikube with reduced settings:
   ```bash
   minikube start \
     --cpus=2 \
     --memory=4096 \
     --disk-size=20g \
     --driver=docker \
     --kubernetes-version=v1.29.2
   ```
   Note: ArgoCD requires at least 2 CPUs and 4 GB RAM. With fewer resources, some pods may not start.

3. Close other resource-heavy applications before starting Minikube.

---

### Minikube won't start -- driver issues

**Symptom:**
```
* Exiting due to DRV_NOT_DETECTED: No possible driver was detected
```
or
```
* Exiting due to PROVIDER_DOCKER_NOT_RUNNING: "docker" was found, but isn't running
```

**Cause:** Docker Desktop is not installed or not running.

**Solution:**

1. Verify Docker is installed:
   ```bash
   docker --version
   ```

2. Start Docker Desktop (macOS: open from Applications; Linux: `sudo systemctl start docker`).

3. Wait for Docker to fully start, then verify:
   ```bash
   docker info
   ```

4. Retry:
   ```bash
   minikube start --driver=docker
   ```

5. If Docker is running but Minikube still can't detect it, try specifying the driver explicitly:
   ```bash
   minikube start --driver=docker
   ```

---

### Minikube won't start -- stale state

**Symptom:**
```
* Exiting due to GUEST_PROVISION: Failed to start host
```
or the cluster starts but `kubectl get nodes` shows `NotReady`.

**Cause:** Previous Minikube state is corrupted.

**Solution:**

Delete the cluster and start fresh:
```bash
minikube delete --all --purge
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40g \
  --driver=docker \
  --kubernetes-version=v1.29.2 \
  --addons=ingress,metrics-server,dashboard
```

---

## 2. Docker Issues

### Docker daemon not running

**Symptom:**
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
```

**Cause:** Docker Desktop is not started.

**Solution:**

**macOS:**
```bash
open -a Docker
```
Wait 30-60 seconds for Docker to fully initialize, then verify:
```bash
docker info
```

**Linux:**
```bash
sudo systemctl start docker
sudo systemctl enable docker   # Enable auto-start on boot
docker info
```

---

### Docker out of disk space

**Symptom:**
```
ERROR: no space left on device
```

**Cause:** Docker images, containers, and build cache have consumed available disk space.

**Solution:**

```bash
# Remove stopped containers
docker container prune -f

# Remove unused images
docker image prune -a -f

# Remove build cache
docker builder prune -f

# Nuclear option: remove everything (containers, images, volumes, networks)
docker system prune -a --volumes -f
```

Then increase Docker Desktop disk size in Settings > Resources if needed.

---

## 3. ArgoCD Issues

### ArgoCD pods not becoming ready

**Symptom:**
```bash
kubectl get pods -n argocd
# Shows pods in Pending, CrashLoopBackOff, or ContainerCreating for > 5 minutes
```

**Cause:** Insufficient cluster resources or image pull issues.

**Solution:**

1. Check pod events:
   ```bash
   kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server
   ```

2. Look for these common events:
   - `Insufficient cpu` or `Insufficient memory`: Increase Minikube resources
   - `ImagePullBackOff`: Check internet connectivity
   - `CrashLoopBackOff`: Check pod logs

3. Check logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
   ```

4. If resources are the problem:
   ```bash
   minikube stop
   minikube start --cpus=4 --memory=8192
   ```

5. If the installation is corrupted, reinstall:
   ```bash
   kubectl delete namespace argocd
   kubectl create namespace argocd
   kubectl apply -n argocd \
     -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl wait --for=condition=available deployment/argocd-server \
     -n argocd --timeout=300s
   ```

---

### ArgoCD initial admin password not found

**Symptom:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
# Error: secrets "argocd-initial-admin-secret" not found
```

**Cause:** ArgoCD server has not fully initialized yet, or the secret was deleted after first login.

**Solution:**

1. Wait for ArgoCD to be fully ready:
   ```bash
   kubectl wait --for=condition=available deployment/argocd-server \
     -n argocd --timeout=300s
   ```

2. Then retry the password retrieval:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath="{.data.password}" | base64 -d
   ```

3. If the secret was deleted (ArgoCD deletes it after you change the password), reset it:
   ```bash
   # Generate a new bcrypt hash for password "admin123"
   kubectl -n argocd patch secret argocd-secret \
     -p '{"stringData": {"admin.password": "$2a$10$rNE8RlQlFkFpOLWy5YdNVOaZ1ULxgFvq/qYOX.WKTO3xHVOeGDUW6", "admin.passwordMtime": "'$(date +%FT%T%Z)'"}}'
   # New password is: admin123
   ```

---

### ArgoCD application shows "Unknown" or "ComparisonError"

**Symptom:** The ArgoCD UI shows the application status as "Unknown" or "ComparisonError".

**Cause:** ArgoCD cannot access the Git repository or the path specified in the application manifest is wrong.

**Solution:**

1. Check the application details:
   ```bash
   argocd app get devops-platform-dev
   ```

2. Verify the repository URL is correct in `argocd/applications/dev.yaml`. The default URL is `https://github.com/example/aws-devops-platform.git` -- you need to update this to your actual repository URL.

3. If using a private repo, register it with ArgoCD:
   ```bash
   argocd repo add https://github.com/YOUR-ORG/aws-devops-platform.git \
     --username git --password YOUR-GITHUB-PAT
   ```

---

## 4. Helm Issues

### Helm install fails -- namespace doesn't exist

**Symptom:**
```
Error: INSTALLATION FAILED: create: failed to create: namespaces "dev" not found
```

**Cause:** The target namespace has not been created.

**Solution:**

Create the namespace first:
```bash
kubectl create namespace dev
```

Or use the `--create-namespace` flag:
```bash
helm upgrade --install aws-devops-platform ./helm-charts/app \
  --namespace dev \
  --create-namespace
```

---

### Helm install fails -- chart values wrong

**Symptom:**
```
Error: INSTALLATION FAILED: template: devops-platform-app/templates/deployment.yaml:XX:
  executing "devops-platform-app/templates/deployment.yaml" at <.Values.some.field>: nil pointer
```

**Cause:** A required value is missing or has the wrong type in `values.yaml` or your override.

**Solution:**

1. Validate the chart templates without installing:
   ```bash
   helm template aws-devops-platform ./helm-charts/app --debug
   ```

2. Lint the chart:
   ```bash
   helm lint ./helm-charts/app --strict
   ```

3. Check for typos in your `--set` flags. Common mistakes:
   ```bash
   # Wrong (nested value needs dots)
   --set image-tag=v1.0.0

   # Correct
   --set image.tag=v1.0.0
   ```

---

### Helm upgrade fails -- another operation in progress

**Symptom:**
```
Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
```

**Cause:** A previous Helm operation was interrupted.

**Solution:**

```bash
# Check release history
helm history aws-devops-platform -n dev

# If the last release is in "pending-install" or "pending-upgrade" state:
helm rollback aws-devops-platform 0 -n dev

# If that doesn't work, uninstall and reinstall:
helm uninstall aws-devops-platform -n dev
helm install aws-devops-platform ./helm-charts/app -n dev
```

---

## 5. kubectl Issues

### kubectl connection refused

**Symptom:**
```
The connection to the server localhost:8443 was refused - did you specify the right host or port?
```
or
```
Unable to connect to the server: dial tcp 127.0.0.1:XXXXX: connect: connection refused
```

**Cause:** The Kubernetes cluster is not running, or kubectl is configured to talk to a different cluster.

**Solution:**

1. Check if Minikube is running:
   ```bash
   minikube status
   ```

2. If stopped, start it:
   ```bash
   minikube start
   ```

3. Verify kubectl context:
   ```bash
   kubectl config current-context
   # Should show "minikube" for local development
   ```

4. Switch to the Minikube context if needed:
   ```bash
   kubectl config use-context minikube
   ```

5. Test connectivity:
   ```bash
   kubectl cluster-info
   ```

---

### kubectl times out

**Symptom:**
```
Unable to connect to the server: net/http: TLS handshake timeout
```

**Cause:** The cluster API server is unreachable, possibly due to network issues or the cluster being overwhelmed.

**Solution:**

1. Check Minikube status:
   ```bash
   minikube status
   ```

2. If Minikube shows "Running" but kubectl can't connect:
   ```bash
   minikube stop
   minikube start
   ```

3. For EKS clusters, refresh your kubeconfig:
   ```bash
   aws eks update-kubeconfig --name devops-platform-dev --region us-east-1
   ```

---

## 6. Port-Forwarding Issues

### Port-forward not working -- address already in use

**Symptom:**
```
Unable to listen on port 8080: Listeners failed to create with the following errors:
  [unable to create listener: Error listen tcp4 127.0.0.1:8080: bind: address already in use]
```

**Cause:** Another process is using port 8080.

**Solution:**

1. Find and kill the process using the port:
   ```bash
   # macOS / Linux
   lsof -ti:8080 | xargs kill -9
   ```

2. Or use a different local port:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 9090:443
   # Then access at https://localhost:9090
   ```

---

### Port-forward dies silently

**Symptom:** The port-forward command exits without error after some time, and the connection stops working.

**Cause:** Port-forward connections are not designed for long-running use. They drop after idle timeouts or pod restarts.

**Solution:**

1. Restart the port-forward:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

2. For a more persistent solution, use a loop:
   ```bash
   while true; do
     kubectl port-forward svc/argocd-server -n argocd 8080:443
     echo "Port-forward disconnected. Reconnecting in 3s..."
     sleep 3
   done
   ```

3. For Minikube, use `minikube tunnel` instead for services with `type: LoadBalancer`:
   ```bash
   minikube tunnel
   ```

---

## 7. Terraform Issues

### Terraform init fails -- backend not configured

**Symptom:**
```
Error: Failed to get existing workspaces: S3 bucket does not exist.
```
or
```
Error: error configuring S3 Backend: no valid credential sources for S3 Backend found
```

**Cause:** The S3 backend bucket and DynamoDB table do not exist, or AWS credentials are not configured.

**Solution:**

1. For local development without AWS, use local backend by skipping the S3 backend:
   ```bash
   cd terraform/environments/dev
   terraform init -backend=false
   terraform validate   # You can still validate without a backend
   ```

2. For AWS deployment, create the backend resources first:
   ```bash
   # Create S3 bucket for state
   aws s3api create-bucket \
     --bucket aws-devops-platform-terraform-state \
     --region us-east-1

   # Enable versioning
   aws s3api put-bucket-versioning \
     --bucket aws-devops-platform-terraform-state \
     --versioning-configuration Status=Enabled

   # Create DynamoDB table for locking
   aws dynamodb create-table \
     --table-name aws-devops-platform-terraform-locks \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region us-east-1
   ```

3. Then run `terraform init` again.

---

### Terraform plan/apply fails -- provider version mismatch

**Symptom:**
```
Error: Incompatible provider version
  Provider registry.terraform.io/hashicorp/aws v5.XX.X does not match constraint "~> 5.40"
```

**Cause:** The installed provider version does not satisfy the version constraint in the module.

**Solution:**

1. Delete the lock file and reinitialize:
   ```bash
   cd terraform/environments/dev
   rm -f .terraform.lock.hcl
   rm -rf .terraform
   terraform init
   ```

2. If you need a specific provider version:
   ```bash
   terraform init -upgrade
   ```

---

### Terraform state lock error

**Symptom:**
```
Error: Error acquiring the state lock
  Lock Info:
    ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    Path:      ...
    Operation: OperationTypePlan
```

**Cause:** A previous Terraform operation crashed or was interrupted without releasing the DynamoDB lock.

**Solution:**

1. Wait a few minutes -- the lock may release automatically.

2. If you are certain no other operation is running, force-unlock:
   ```bash
   cd terraform/environments/dev
   terraform force-unlock <LOCK-ID>
   ```
   Replace `<LOCK-ID>` with the ID shown in the error message.

---

## 8. ECR Issues

### ECR login failures

**Symptom:**
```
Error: Cannot perform an interactive login from a non TTY device
```
or
```
Error: An error occurred (AccessDeniedException) when calling the GetAuthorizationToken operation
```

**Cause:** AWS credentials are not configured, expired, or do not have ECR permissions.

**Solution:**

1. Verify AWS credentials:
   ```bash
   aws sts get-caller-identity
   ```

2. Login to ECR:
   ```bash
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin \
     123456789012.dkr.ecr.us-east-1.amazonaws.com
   ```
   Replace `123456789012` with your AWS account ID.

3. If using SSO:
   ```bash
   aws sso login --profile your-profile
   export AWS_PROFILE=your-profile
   ```

---

### ECR push fails -- repository does not exist

**Symptom:**
```
name unknown: The repository with name 'xxx' does not exist in the registry
```

**Cause:** The ECR repository has not been created by Terraform.

**Solution:**

1. Check existing repositories:
   ```bash
   aws ecr describe-repositories --region us-east-1
   ```

2. Create the repository manually (for testing):
   ```bash
   aws ecr create-repository \
     --repository-name aws-devops-platform-dev/app \
     --region us-east-1
   ```

3. Or deploy the infrastructure with Terraform:
   ```bash
   cd terraform/environments/dev
   terraform init
   terraform apply
   ```

---

## 9. Kustomize Issues

### Kustomize build errors -- resource not found

**Symptom:**
```
Error: accumulating resources: accumulation err='accumulating resources from '../../base':
  read /path/to/kubernetes/base: file does not exist'
```

**Cause:** Running `kubectl kustomize` or `kubectl apply -k` from the wrong directory, or the base path is incorrect.

**Solution:**

1. Always run Kustomize commands from the project root:
   ```bash
   kubectl kustomize kubernetes/overlays/dev
   ```

2. Or specify the full path:
   ```bash
   kubectl apply -k /full/path/to/aws-devops-platform/kubernetes/overlays/dev
   ```

3. Verify the base directory exists and contains `kustomization.yaml`:
   ```bash
   ls kubernetes/base/kustomization.yaml
   ```

---

### Kustomize patch fails -- target not found

**Symptom:**
```
Error: no matches for Id Deployment.v1.apps/devops-platform-app
```

**Cause:** The patch target name does not match the resource name in the base, or the `namePrefix` in the overlay changed the resource name.

**Solution:**

1. Verify the resource name in the base:
   ```bash
   grep "name:" kubernetes/base/deployments/app.yaml
   ```

2. The patch target must match the **original** name in the base (before namePrefix is applied). Check the overlay's `kustomization.yaml`:
   ```yaml
   patches:
     - target:
         kind: Deployment
         name: devops-platform-app    # Must match base resource name
   ```

---

## 10. GitHub Actions Issues

### OIDC authentication failure

**Symptom:**
```
Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Cause:** The IAM OIDC trust policy does not allow the repository or branch.

**Solution:**

1. Verify the `AWS_OIDC_ROLE_ARN` secret is set correctly in GitHub repository settings.

2. Check the IAM role's trust policy. It should include:
   ```json
   {
     "Effect": "Allow",
     "Principal": {
       "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
     },
     "Action": "sts:AssumeRoleWithWebIdentity",
     "Condition": {
       "StringEquals": {
         "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
       },
       "StringLike": {
         "token.actions.githubusercontent.com:sub": "repo:YOUR-ORG/aws-devops-platform:*"
       }
     }
   }
   ```

3. Ensure the GitHub OIDC provider is registered in your AWS account:
   ```bash
   aws iam list-open-id-connect-providers
   ```

---

### GitHub Actions -- missing secrets

**Symptom:**
```
Error: Input required and not supplied: role-to-assume
```
or workflows fail with empty secret values.

**Cause:** Required GitHub secrets or environment variables are not configured.

**Solution:**

Required secrets (set in GitHub > Settings > Secrets and variables > Actions):

| Secret | Description | Required For |
|--------|-------------|--------------|
| `AWS_OIDC_ROLE_ARN` | IAM role ARN for OIDC authentication | CI, CD-dev, Terraform |
| `AWS_OIDC_ROLE_ARN_PROD` | IAM role ARN for production | CD-prod |
| `GITOPS_PAT` | GitHub PAT with repo access to the GitOps repo | CD-dev, CD-prod |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL | CD notifications |
| `PAGERDUTY_ROUTING_KEY` | PagerDuty integration key | CD-prod alerts |

Also configure GitHub Environments (Settings > Environments):
- `dev` -- no protection rules
- `staging` -- optional: required reviewers
- `production` -- required reviewers, deployment branch restrictions

---

### GitHub Actions workflow fails -- permission denied

**Symptom:**
```
Error: Resource not accessible by integration
```

**Cause:** The workflow does not have the required permissions.

**Solution:**

Check the `permissions` block in the workflow file. Required permissions for this project:
```yaml
permissions:
  id-token: write          # For OIDC authentication
  contents: read           # For checking out code
  contents: write          # For CD pipelines that push to GitOps repo
  pull-requests: write     # For posting PR comments
  security-events: write   # For uploading SARIF results
  issues: write            # For creating security scan issues
  packages: read           # For pulling packages
```

Also verify in GitHub > Settings > Actions > General that "Allow all actions" or specific action permissions are configured.

---

## 11. Resource and Quota Issues

### Resource quota exceeded

**Symptom:**
```
Error: pods "xxx" is forbidden: exceeded quota: resource-quota, requested: cpu=500m,
  used: cpu=1900m, limited: cpu=2000m
```

**Cause:** The namespace has a ResourceQuota and the new pod would exceed the limit.

**Solution:**

1. Check current resource usage:
   ```bash
   kubectl describe quota -n dev
   ```

2. Check resource requests across all pods:
   ```bash
   kubectl top pods -n dev
   ```

3. Options:
   - Reduce the resource requests in `values.yaml` or the Kustomize overlay
   - Increase the ResourceQuota
   - Delete unused deployments to free resources

---

### Pods stuck in Pending -- insufficient resources

**Symptom:**
```bash
kubectl get pods -n dev
# Shows pods in "Pending" state
```

```bash
kubectl describe pod <pod-name> -n dev
# Events show: "0/1 nodes are available: 1 Insufficient cpu" or "Insufficient memory"
```

**Cause:** The node does not have enough allocatable CPU or memory for the pod's resource requests.

**Solution:**

1. Check node capacity:
   ```bash
   kubectl describe node minikube | grep -A 5 "Allocatable"
   kubectl describe node minikube | grep -A 10 "Allocated resources"
   ```

2. Reduce pod resource requests. For local development, use lower values:
   ```bash
   helm upgrade aws-devops-platform ./helm-charts/app \
     --namespace dev \
     --set resources.requests.cpu=50m \
     --set resources.requests.memory=64Mi \
     --set resources.limits.cpu=200m \
     --set resources.limits.memory=256Mi
   ```

3. Or increase Minikube resources:
   ```bash
   minikube stop
   minikube start --cpus=6 --memory=12288
   ```

---

## 12. Pod CrashLoopBackOff Debugging

**Symptom:**
```bash
kubectl get pods -n dev
# NAME                                  READY   STATUS             RESTARTS   AGE
# app-xxxxxxxx-xxxxx                    0/1     CrashLoopBackOff   5          3m
```

**Cause:** The container is starting and immediately crashing. Common reasons:
- Application error on startup
- Missing environment variables or ConfigMap
- Health check failing (readiness/liveness probes)
- Insufficient permissions (security context too restrictive)
- Read-only filesystem and the app tries to write to a non-tmpfs path

**Step-by-step debugging:**

1. Check the pod events:
   ```bash
   kubectl describe pod <pod-name> -n dev
   ```
   Look at the "Events" section at the bottom.

2. Check the container logs:
   ```bash
   # Current attempt
   kubectl logs <pod-name> -n dev

   # Previous (crashed) attempt
   kubectl logs <pod-name> -n dev --previous
   ```

3. Check if the ConfigMap exists:
   ```bash
   kubectl get configmap -n dev
   ```

4. Check if the image exists and is pullable:
   ```bash
   kubectl describe pod <pod-name> -n dev | grep "Image:"
   ```

5. If the issue is the read-only filesystem, check if the app writes to a path that is not mounted as emptyDir:
   ```bash
   kubectl logs <pod-name> -n dev --previous | grep -i "read-only\|permission denied"
   ```
   The Helm chart mounts `/tmp` as writable via emptyDir. If your app writes elsewhere, add another emptyDir mount.

6. Test the container interactively (bypassing the health checks):
   ```bash
   kubectl run debug --image=nginx --rm -it --restart=Never -n dev -- /bin/sh
   ```

7. If the pod is crashing too fast to get logs, override the command:
   ```bash
   kubectl run debug --image=<your-image> --rm -it --restart=Never -n dev -- /bin/sh -c "sleep 3600"
   ```

---

## 13. Checking Logs for Each Component

### Application pods
```bash
# Stream live logs
kubectl logs -f deployment/aws-devops-platform -n dev

# Logs from all pods with a specific label
kubectl logs -l app.kubernetes.io/name=devops-platform-app -n dev --tail=100

# Previous container logs (after a crash)
kubectl logs <pod-name> -n dev --previous
```

### ArgoCD
```bash
# ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# ArgoCD application controller (handles syncing)
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# ArgoCD repo server (handles Git operations)
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=100

# ArgoCD app details via CLI
argocd app get devops-platform-dev
argocd app logs devops-platform-dev
```

### Kubernetes system components
```bash
# CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Ingress controller (Minikube)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Metrics server
kubectl logs -n kube-system -l k8s-app=metrics-server --tail=50

# All events in a namespace (sorted by time)
kubectl get events -n dev --sort-by='.lastTimestamp'

# Cluster-wide events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -30
```

### Minikube
```bash
# Minikube logs
minikube logs

# Minikube logs for a specific component
minikube logs --node=minikube | grep -i error

# SSH into the Minikube node for deeper debugging
minikube ssh
```

---

## 14. How to Reset Everything and Start Fresh

If things are too broken to debug, here is how to completely reset each component.

### Reset Minikube (delete cluster and start over)

```bash
minikube delete --all --purge
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40g \
  --driver=docker \
  --kubernetes-version=v1.29.2 \
  --addons=ingress,metrics-server,dashboard
```

### Reset ArgoCD

```bash
kubectl delete namespace argocd
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s
```

### Reset Helm releases

```bash
# List all releases
helm list -A

# Uninstall a release
helm uninstall aws-devops-platform -n dev

# Reinstall
helm install aws-devops-platform ./helm-charts/app -n dev --create-namespace
```

### Reset Kustomize deployments

```bash
# Delete all resources managed by the overlay
kubectl delete -k kubernetes/overlays/dev

# Reapply
kubectl apply -k kubernetes/overlays/dev
```

### Reset Terraform local state

```bash
# Remove all local Terraform files
find terraform/ -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null
find terraform/ -name "*.tfstate*" -delete 2>/dev/null
find terraform/ -name ".terraform.lock.hcl" -delete 2>/dev/null
find terraform/ -name "tfplan" -delete 2>/dev/null

# Reinitialize
cd terraform/environments/dev
terraform init -backend=false
terraform validate
```

### Reset Docker

```bash
# Remove project images
docker images | grep aws-devops | awk '{print $3}' | xargs docker rmi -f 2>/dev/null

# Remove all stopped containers
docker container prune -f

# Remove all unused images
docker image prune -a -f

# Remove build cache
docker builder prune -f
```

### Full reset using the cleanup script

```bash
./scripts/cleanup.sh --all --force
```

Then start over with the setup script:

```bash
./scripts/setup-local.sh
```

### Reset kubectl context

If your kubectl context is pointing to a non-existent or wrong cluster:

```bash
# List all contexts
kubectl config get-contexts

# Switch to minikube
kubectl config use-context minikube

# Delete a stale context
kubectl config delete-context old-cluster-name

# Delete a stale cluster entry
kubectl config delete-cluster old-cluster-name
```
