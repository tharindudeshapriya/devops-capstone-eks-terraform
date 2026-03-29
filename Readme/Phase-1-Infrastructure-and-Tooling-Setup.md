# Phase 1: Enterprise Infrastructure & Tooling Setup

To emulate an enterprise-grade environment, the infrastructure for this project is intentionally segregated into two distinct environments: **Cluster-Management/Tooling Servers** and the **Kubernetes Workload Cluster**.

This document details the architectural decisions, server specifications, the Infrastructure as Code (IaC) used to build this foundation, and the step-by-step execution guide.

## Part 1: Dedicated Tooling Instances (EC2)

In a production scenario, running heavy CI/CD tools inside the same Kubernetes cluster as your production applications can lead to resource starvation. If a Jenkins build consumes all available CPU, your live application could crash.

To prevent this, we provisioned dedicated, high-performance Ubuntu Virtual Machines (EC2 instances) for our DevOps tooling.

### 1. The Tooling Architecture

Based on our AWS environment, we utilized the following EC2 instances for optimal performance during heavy Java compilations and code analysis:

![Initial EC2 Instances](./images/Initial%20Ec2%20intances.png)

* **Bootstrap / Management Server (`c7i-flex.large`):** This acts as the secure "Jumpbox." It is the only server authorized to run Terraform and `eksctl` commands to build or modify the EKS cluster.
* **Jenkins CI/CD Server (`m7i-flex.large`):** Provisioned with a memory-optimized instance to easily handle concurrent Maven builds, heavy Docker image building, and Trivy security scanning without running out of RAM.
* **SonarQube Server (`c7i-flex.large`):** A compute-optimized instance dedicated to running intensive Static Application Security Testing (SAST) and managing the Quality Gate database.
* **Nexus Artifact Repository (`c7i-flex.large`):** Acts as the secure storage locker for our compiled Java `.jar` files and Docker images.

### 2. Security Group Configuration

To ensure these tools can communicate securely while allowing required web traffic, all tooling instances are attached to a unified security group named `primary-sg`. 

![Primary Security Group Configuration](./images/primary%20security%20group.png)

The inbound rules are configured as follows:

* **Port 22 (SSH):** For administrative shell access.
* **Port 80 (HTTP) & 443 (HTTPS):** For standard web traffic routing.
* **Port 587 (Custom TCP):** Open for TLS SMTP communication, allowing Jenkins to send automated success/failure emails.
* **Ports 3000 - 11000 (Custom TCP):** A broad internal range opened specifically to support our DevOps toolchain, encompassing:
    * `8080` (Jenkins UI and GitHub Webhooks)
    * `8081` (Nexus Artifact Management)
    * `9000` (SonarQube Dashboards)
    * `9090, 9100, etc.` (Prometheus/Grafana metric scraping)

## Part 2: Connecting and Preparing the VMs

Once your EC2 instances are running, you must connect to them and prepare the base operating system.

### 1. Connect to VMs via MobaXterm (Windows)

1. Open MobaXterm and create a new SSH session.
2. Save sessions with the Public IPs of your instances.

![MobaXterm Sessions](./images/Mobaextreme%204%20ec2%20instances.png)

3. Specify the user as `ubuntu`.
4. Attach your downloaded `.pem` SSH key in the Advanced SSH settings.

### 2. Update and Upgrade Packages

Run this on every VM immediately after logging in to ensure you have the latest security patches:

```bash
sudo apt update && sudo apt upgrade -y
```

## Part 3: EKS Cluster Setup (on Bootstrap Server)

We will use the Bootstrap/Management Server to configure AWS access and deploy our EKS cluster using Terraform.

### 1. Configure AWS Access

Install the AWS CLI and configure your credentials (use a root user or IAM user with full EKS/EC2 permissions):

```bash
sudo apt install awscli -y
aws configure
```

### 2. Install Terraform

Install Terraform from the official HashiCorp repository (do not use Snap):

```bash
# Add HashiCorp GPG key and repo
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Install Terraform
sudo apt update && sudo apt install terraform -y
```

### 3. Clone Terraform Repository & Deploy EKS

Clone your Infrastructure-as-Code repository to the Bootstrap server (ensure you use a Personal Access Token if it is private):

```bash
git clone https://github.com/tharindudeshapriya/devops-capstone-eks-terraform.git
cd devops-capstone-eks-terraform
```

> **Note:** Before initializing, make sure you update the `ssh_key_name` in your `variable.tf` file to match your exact AWS key pair name!

### 4. Overview of Terraform Configuration Files

Before applying the configurations, it is important to understand the structure of the provided infrastructure code:

* **`variable.tf`**
  This file defines reusable variables for our Terraform configuration. Instead of hardcoding the SSH key name everywhere, we define it here.

* **`main.tf`**
  This is the core infrastructure file. It creates the entire network from scratch, establishes the Kubernetes control plane, and spins up the worker nodes.
  
  **Detailed Explanations:**
  * **VPC & Networking:** We create a custom VPC (`10.0.0.0/16`) with DNS support enabled, which is required for worker nodes to communicate with the EKS API. We also create two public subnets with specific `kubernetes.io` tags. These tags are critical—they tell the Kubernetes AWS Load Balancer Controller exactly where it is allowed to provision external load balancers.
  * **Security Groups:** We define `capstone_devops_cluster_sg` for the control plane and `capstone_devops_node_sg` for the worker nodes, currently allowing all outbound and inbound traffic for seamless integration during setup.
  * **EKS Control Plane:** The `aws_eks_cluster` block creates the managed control plane. It assumes a specific IAM role (`AmazonEKSClusterPolicy`) that gives AWS permission to manage the underlying infrastructure on our behalf.
  * **EKS Worker Nodes:** The `aws_eks_node_group` provisions the actual EC2 instances (`c7i-flex.large`) where our pods will run. It uses an autoscaling configuration with a minimum and maximum of 3 nodes.
  * **Node IAM Roles:** The worker nodes are attached to a role containing `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` (for networking), `AmazonEC2ContainerRegistryReadOnly` (to pull Docker images), and notably, the `AmazonEBSCSIDriverPolicy` which allows the nodes to dynamically provision EBS volumes for our database!

* **`output.tf`**
  Once Terraform successfully builds the infrastructure, this file outputs the unique IDs of the created resources to the terminal. This is helpful for auditing and validating the build.

### 5. Initialize and Deploy the EKS Cluster

Initialize and apply the Terraform configuration:

```bash
terraform init
terraform apply --auto-approve
```

![Terraform EKS Cluster Creation](images/terraform%20eks%20cluster.png)
![AWS CloudFormation Stacks](images/aws%20-%20cloud%20formation.png)
![AWS EKS Console](images/aws%20-%20eks.png)

*(Wait 10-15 minutes. Your EKS cluster is now created!)*

## Part 4: DevSecOps Tooling Installations

With the infrastructure running, we must install the core applications on their respective VMs.

### 1. Set Up Jenkins (on Jenkins VM)

Jenkins requires Java to run. We will install OpenJDK 17 (required for modern Jenkins and Sonar scanners).

```bash
# Install Java
sudo apt install openjdk-17-jdk -y

# Install Jenkins using the official Debian-based steps
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install jenkins -y

# Start and verify Jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins
```

* **Open Jenkins URL:** Navigate to `http://<Jenkins-Public-IP>:8080` in your browser.
* **Unlock Jenkins:** Retrieve the initial admin password by running:
  `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
* **Finalize:** Install suggested plugins and create your first Admin user.

### 2. SonarQube Setup (on SonarQube VM)

SonarQube handles our static code analysis. For an easier setup, it is highly recommended to run this as a Docker container.

1. **Install Docker:** `sudo apt install docker.io -y`
2. **Run SonarQube:** `sudo docker run -d --name sonarqube -p 9000:9000 sonarqube:lts-community`
3. **Access:** Open `http://<SonarQube-Public-IP>:9000` in your browser.
4. **Initial Admin Login:** `admin` / `admin` (You will be prompted to change this immediately).

### 3. Nexus Setup (on Nexus VM)

Nexus manages our build artifacts (Java `.jar` files). We will also run this using Docker for simplicity.

1. **Install Docker:** `sudo apt install docker.io -y`
2. **Run Nexus:** `sudo docker run -d -p 8081:8081 --name nexus sonatype/nexus3`
3. **Access:** Open `http://<Nexus-Public-IP>:8081` in your browser.
4. **Initial Admin Login:** Retrieve the auto-generated password by entering the container:
   `sudo docker exec -it nexus cat /nexus-data/admin.password`

By the end of this phase, the raw infrastructure is completely established. We have isolated EC2 environments hosting our Jenkins, SonarQube, and Nexus instances, and a fully functional, secure Amazon EKS cluster waiting to receive application deployments.

---
[⬅️ Back to Main README](../README.md)
