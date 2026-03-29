# Phase 3: Kubernetes Security and Access Control (RBAC)

Before we secure Jenkins with Role-Based Access Control (RBAC), we must first connect to our newly provisioned EKS cluster from the Bootstrap Server and install the essential add-ons required for storage, routing, and SSL certificates.

## Part 1: Kubernetes (EKS) Setup on Server VM

### 1. Fix `kubectl` Connectivity Error
If you try to run `kubectl` immediately, you will get an error because the kubeconfig (Cluster config) is missing or incorrect. Run the following command on your Bootstrap Server to update the kubeconfig to point to your new cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name capstone-devops-cluster
```

### 2. Verify Connection
Ensure your Bootstrap Server can communicate with the worker nodes:

```bash
kubectl get nodes
```

![Kubernetes Worker Nodes](./images/k8s%20nodes.png)

*(You should see your `c7i-flex.large` worker nodes listed in a "Ready" state).*

## Part 2: Associate OIDC Provider and IAM Roles

**Context:** Kubernetes service accounts need permissions to use AWS resources natively. For example, our database needs to dynamically provision AWS EBS volumes for persistent storage.

### 1. Associate OIDC Provider with Cluster
This enables AWS IAM roles for Kubernetes service accounts (IRSA).

```bash
eksctl utils associate-iam-oidc-provider --region us-east-1 --cluster capstone-devops-cluster --approve
```

### 2. Create Service Account for EBS CSI Driver
This creates a Kubernetes ServiceAccount with the necessary AWS IAM permissions to create and manage EBS volumes dynamically.

```bash
eksctl create iamserviceaccount \
  --region us-east-1 \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster capstone-devops-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --override-existing-serviceaccounts
```

## Part 3: Install Helm and Core Kubernetes Add-ons

**Context:** Helm simplifies Kubernetes application deployments using pre-configured packages called "charts" (similar to `apt` for Ubuntu or Terraform for infrastructure). We need these tools for storage, ingress (routing), and certificate management.

### 1. Install Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### 2. Install EBS CSI Driver (Storage)
This driver allows Kubernetes to communicate with the AWS API to create EBS volumes on the fly when our MySQL database requests a `PersistentVolumeClaim`.

```bash
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/ecr"
```

### 3. Install Ingress Controller (NGINX)
The Ingress controller manages external routing and automatically provisions an AWS Network Load Balancer (NLB) to expose our application to the internet.

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx
```

### 4. Install Cert Manager (Automated SSL/TLS)
Cert-Manager automates the generation and renewal of Let's Encrypt HTTPS certificates for our DuckDNS domain.

```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml
```

## Part 4: Kubernetes Security and Access Control (RBAC)

Now that the cluster is fully operational, we must prepare it for our CI/CD pipeline.

To mitigate the security risks associated with granting unrestricted administrative access to the Jenkins server, Role-Based Access Control (RBAC) is strictly implemented. We will create a specific identity for Jenkins and grant it the exact permissions required to deploy the application, and nothing more.

### What Each File Does

To successfully configure RBAC, we create six specific YAML files:

* **`jenkins-sa.yaml` (ServiceAccount):** Creates the non-human "robot" identity for Jenkins inside the Kubernetes cluster.
* **`jenkins-role.yaml` (Role):** Acts as a permission checklist. It defines exactly what actions (create, delete, update) are allowed on specific resources (Pods, Deployments, Services) only inside the `webapps` namespace.
* **`jenkins-rolebinding.yaml` (RoleBinding):** The bridge that connects the ServiceAccount (`jenkins`) to the Role (`jenkins-role`).
* **`jenkins-clusterrole.yaml` (ClusterRole):** Similar to a Role, but for global resources that exist across the entire cluster (like StorageClasses for AWS EBS volumes or Let's Encrypt SSL Issuers).
* **`jenkins-clusterrolebinding.yaml` (ClusterRoleBinding):** Connects the `jenkins` ServiceAccount to the `jenkins-cluster-role`.
* **`jenkins-token.yaml` (Secret):** Instructs Kubernetes to generate a permanent API token that Jenkins will use to authenticate.

### Step-by-Step RBAC Configuration

Run the following commands and apply the YAML manifests directly from your Bootstrap Server using `kubectl`.

#### Step 1: Create a Kubernetes Namespace
We’ll use a namespace called `webapps` to isolate our application resources.
*(Namespaces allow you to separate resources, making it easier to apply roles, set limits, and improve overall manageability).*

```bash
kubectl create ns webapps
```

#### Step 2: Create the Jenkins ServiceAccount
Create `jenkins-sa.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: webapps
```

Apply the file:
```bash
kubectl apply -f jenkins-sa.yaml
```

#### Step 3: Create a Role with Namespace-Scoped Permissions
Create `jenkins-role.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-role
  namespace: webapps
rules:
  # Permissions for core API resources
  - apiGroups: [""]
    resources:
      - secrets
      - configmaps
      - persistentvolumeclaims
      - services
      - pods
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]

  # Permissions for apps API group (Deployments)
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]

  # Permissions for networking API group (Ingress routing)
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]

  # Permissions for autoscaling API group (HPA)
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["get", "list", "watch", "create", "update", "delete", "patch"]
```

Apply the file:
```bash
kubectl apply -f jenkins-role.yaml
```

#### Step 4: Bind the Role to the ServiceAccount
Create `jenkins-rolebinding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-rolebinding
  namespace: webapps
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: jenkins-role
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: webapps
```

Apply the file:
```bash
kubectl apply -f jenkins-rolebinding.yaml
```

#### Step 5: Create a ClusterRole & Binding (For Storage/SSL)
Create `jenkins-clusterrole.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-cluster-role
rules:
  # Permissions for dynamic EBS persistentvolumes & storageclasses
  - apiGroups: ["", "storage.k8s.io"]
    resources:
      - persistentvolumes
      - storageclasses
    verbs: ["get", "list", "watch", "create", "update", "delete"]
  # Permissions for Let's Encrypt ClusterIssuer
  - apiGroups: ["cert-manager.io"]
    resources:
      - clusterissuers
    verbs: ["get", "list", "watch", "create", "update", "delete"]
```

Create `jenkins-clusterrolebinding.yaml`:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-cluster-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins-cluster-role
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: webapps
```

Apply the files:
```bash
kubectl apply -f jenkins-clusterrole.yaml
kubectl apply -f jenkins-clusterrolebinding.yaml
```

#### Step 6: Generate & Retrieve the Authentication Token
Create `jenkins-token.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-secret
  namespace: webapps
  annotations:
    kubernetes.io/service-account.name: jenkins
type: kubernetes.io/service-account-token
```

Apply the file and retrieve the token:
```bash
kubectl apply -f jenkins-token.yaml
kubectl describe secret jenkins-secret -n webapps
```
*(Copy the long `token` string. Treat this string as highly sensitive!)*

## Step 7: Final Jenkins Integration

To complete the RBAC integration, the generated token must be securely stored in Jenkins so the CI/CD pipeline can assume the `jenkins` ServiceAccount identity during deployments.

1. Navigate to your **Jenkins Dashboard → Manage Jenkins → Credentials → System → Global credentials (unrestricted)**.
2. Click **Add Credentials**.
3. Set the **Kind** to `Secret Text`.
4. **Secret:** *(Paste the massive token retrieved in Step 6)*.
5. **ID:** `k8s-token` *(This exact ID is referenced in the CD Jenkinsfile)*.
6. **Description:** `EKS Jenkins ServiceAccount Token`.
7. Click **Create**.

**Jenkins is now securely authorized to deploy the application into the `webapps` namespace!**
