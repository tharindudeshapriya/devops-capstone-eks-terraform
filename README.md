# Enterprise DevSecOps Capstone Project

## System Architecture and Implementation Overview

This repository showcases a comprehensive, end-to-end DevSecOps and Cloud DevOps pipeline. It demonstrates the automation of infrastructure provisioning, continuous integration, security scanning, artifact management, continuous deployment, and cluster monitoring utilizing industry-standard tools and methodologies.

## Project Repositories

This project adopts a decoupled architecture into three specialized repositories, adhering to microservice and GitOps best practices:

* **Application Source Code (CI):** [tharindudeshapriya/devops-capstone-app](https://github.com/tharindudeshapriya/devops-capstone-app)
* **Kubernetes Manifests (CD/GitOps):** [tharindudeshapriya/devops-capstone-k8s-manifests](https://github.com/tharindudeshapriya/devops-capstone-k8s-manifests)
* **Infrastructure as Code (Terraform) (Current Repository):** [tharindudeshapriya/devops-capstone-eks-terraform](https://github.com/tharindudeshapriya/devops-capstone-eks-terraform)

## Technology Stack

* **Cloud Provider:** Amazon Web Services (AWS)
* **Infrastructure as Code (IaC):** Terraform
* **Container Orchestration:** Amazon Elastic Kubernetes Service (EKS)
* **CI/CD:** Jenkins
* **Code Quality Analysis:** SonarQube
* **Artifact Management:** Sonatype Nexus
* **Containerization:** Docker & DockerHub
* **Security Scanning (DevSecOps):** Trivy
* **Routing & SSL/TLS:** NGINX Ingress Controller, Cert-Manager (Let's Encrypt), DuckDNS
* **Monitoring & Observability:** Prometheus & Grafana (`kube-prometheus-stack`)

## Implementation Phases

### Phase 1: Infrastructure and Tooling Setup

*[Read the detailed guide here: Phase 1 - Infrastructure and Tooling Setup](./Readme/Phase-1-Infrastructure-and-Tooling-Setup.md)*

To emulate an enterprise-grade environment, the infrastructure is intentionally segregated between cluster-management/tooling servers and the Kubernetes workload cluster.

* **Dedicated Tooling Instances (EC2):** Provisioned dedicated Ubuntu Virtual Machines for Jenkins (CI/CD), SonarQube (Code Analysis), and Nexus (Artifacts). This isolation prevents intensive continuous integration workloads from consuming Kubernetes cluster resources.
* **EKS Provisioning:** Utilized Terraform to dynamically provision a highly available Amazon EKS cluster (`capstone-devops-cluster`), complete with a custom VPC, Subnets, and the necessary IAM roles for cluster operations.

### Phase 2: Continuous Integration (CI) Pipeline

*[Read the detailed guide here: Phase 2 - Continuous Integration Pipeline](./Readme/Phase-2-Continuous-Integration-Pipeline.md)*

The CI pipeline is fully automated via Jenkins and is triggered by GitHub Webhooks upon code commits.

**Pipeline Stages:**

1. **Source Code Checkout:** Retrieves the latest Java Spring Boot application code.
2. **Compilation and Testing (Maven):** Compiles the source code and executes unit tests. Pipeline execution is halted upon test failure to prevent the propagation of erroneous code.
3. **Static Configuration Analysis (Trivy FS):** Scans the repository file system to identify hardcoded secrets and structural misconfigurations.
4. **Static Application Security Testing (SonarQube):** Analyzes code quality and security. The pipeline enforces a strict Quality Gate, requiring zero critical vulnerabilities to proceed.
5. **Artifact Build and Publication:** Packages the application into a `.jar` artifact and securely publishes it to the Sonatype Nexus repository.
6. **Containerization:** Builds the application Docker image and pushes the tagged image to DockerHub (`tmdeshapriya/bankapp`).
7. **Container Vulnerability Scanning (Trivy):** Scans the generated Docker image for Common Vulnerabilities and Exposures (CVEs) and aggregates a comprehensive security report.
8. **GitOps Manifest Update:** Jenkins clones the CD repository, updates the deployment manifests with the newly built Docker image tag, and automatically pushes the changes back to GitHub.
9. **Status Notification:** Dispatches an automated email detailing the pipeline execution status, including the attached Trivy vulnerability scan report.

### Phase 3: Kubernetes Security and Access Control (RBAC)

*[Read the detailed guide here: Phase 3 - Kubernetes Security and Access Control (RBAC)](./Readme/Phase-3-Kubernetes-Security-and-Access-Control-RBAC.md)*

To mitigate the security risks associated with granting unrestricted access to the CI/CD server, Role-Based Access Control (RBAC) was strictly implemented:

* Provisioned a dedicated `jenkins` ServiceAccount within the target `webapps` namespace.
* Configured a specific Role and RoleBinding to restrict Jenkins' permissions, allowing it to manage only necessary resources (Pods, Deployments, Services, HPA) exclusively within the designated namespace.
* Secured cluster authentication utilizing short-lived tokens.

### Phase 4: Continuous Deployment (CD), GitOps, and Network Routing

*[Read the detailed guide here: Phase 4 - Continuous Deployment and GitOps](./Readme/Phase-4-Continuous-Deployment-and-GitOps.md)*

The Continuous Deployment phase automatically triggers following the automated commit generated during the CI phase, executing both application rollout and network exposure.

**Application Deployment:**
1. Jenkins authenticates to the EKS cluster using the restricted ServiceAccount credentials.
2. The revised deployment manifests (Deployments, Services, and Persistent Volume Claims for the MySQL database) are applied to the `webapps` namespace.
3. Kubernetes orchestrates a rolling update, ensuring zero-downtime deployment for the application.

**Network Routing, DNS, and TLS:**
To securely expose the application to external traffic:
* **Ingress Controller Optimization:** Deployed the NGINX Ingress Controller to route external requests, backed by an AWS Network Load Balancer (NLB) for high availability.
* **DNS Resolution:** Configured DNS mapping to link the NLB domain name to a custom host (`tharindu-bank.duckdns.org`).
* **Automated Certificate Management:** Integrated Cert-Manager with a ClusterIssuer to automatically provision and renew valid, production-ready SSL/TLS certificates via Let's Encrypt.

### Phase 5: Observability, Monitoring, and Autoscaling

*[Read the detailed guide here: Phase 5 - Observability and Monitoring](./Readme/Phase-5-Observability-and-Monitoring.md)*

#### Telemetry and Visualization

Deployed the `kube-prometheus-stack` via Helm to aggregate cluster metrics. A customized `values.yaml` configuration was implemented to securely expose the Grafana dashboard and capture system-level metrics utilizing `node-exporter` and `kube-state-metrics`.

## System Demonstrations and Screenshots

*(Visual documentation of the active pipeline, infrastructure topology, and monitoring dashboards)*

### 1. Secured Application Interface
The final deployment of the banking application, accessible securely via valid Let's Encrypt SSL/TLS certificates.

![Secured Application Interface](./Readme/images/ssl%20certified%20live%20webapp.png)

### 2. Jenkins DevSecOps CI/CD Pipeline
The execution dashboard of the integrated CI/CD pipeline, demonstrating successful completion of all automation stages.

![Jenkins DevSecOps CI/CD Pipeline](./Readme/images/CI%20pipeline%20stages.png)

### 3. SonarQube Quality Assurance
Static analysis reporting, detailing the successful passage of the strict security Quality Gate.

![SonarQube Quality Assurance](./Readme/images/Sonarqube%20report.png)

### 4. Nexus Artifact Storage
The successfully compiled Java `.jar` artifact, securely hosted within the Sonatype Nexus repository.

![Nexus Artifact Storage](./Readme/images/nexus%20artifacts.png)

### 5. Automated GitOps Synchronization
The automated commit sequence generated by Jenkins, updating the Kubernetes deployment manifests repository with the new release tag.

![Automated GitOps Synchronization](./Readme/images/pipeline%20commits.png)

### 6. Grafana Autoscaling Telemetry
Performance visualization demonstrating the cluster's dynamic response to the synthetic load test, highlighting automated scaling operations.

![Grafana Autoscaling Telemetry](./Readme/images/grafana%20dashboard.png)

### 7. Kubernetes Cluster State Analysis
The operational state of the `webapps` namespace, detailing active Pods, HPA status, and configured Ingress routing.

![Kubernetes Cluster State Analysis](./Readme/images/k8s%20webapps%20namespace.png)

### 8. AWS Infrastructure Architecture
The foundational architecture of the deployment, including the primary EKS cluster and the dedicated EC2 CI/CD tooling instances.

![AWS EKS Overview](./Readme/images/aws%20-%20eks.png)
![Initial EC2 Instances](./Readme/images/Initial%20Ec2%20intances.png)

## Acknowledgments

This project was built following the architectural principles and guidance from the DevOps Shack ecosystem. Special thanks to the original creators for providing the roadmap and resources used to implement this enterprise-grade pipeline.

* **Architecture Tutorial:** DevOps Shack Youtube Channel
* **Original Application Source:** Based on the Spring Boot Banking Application used in the DevOps Shack capstone series.
* **Community:** Thanks to the open-source community for the tools used (Terraform, Jenkins, Kubernetes, Prometheus).
