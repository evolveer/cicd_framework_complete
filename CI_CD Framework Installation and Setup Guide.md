# CI/CD Framework Installation and Setup Guide

**Author:** evolveer and AI  
**Version:** 1.0  
**Date:** December 2024  

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Infrastructure Setup](#infrastructure-setup)
4. [Core Components Installation](#core-components-installation)
5. [Security Configuration](#security-configuration)
6. [Monitoring Setup](#monitoring-setup)
7. [Pipeline Configuration](#pipeline-configuration)
8. [Testing and Validation](#testing-and-validation)
9. [Troubleshooting](#troubleshooting)
10. [References](#references)

## Introduction

This comprehensive installation and setup guide provides step-by-step instructions for deploying the fully automated CI/CD framework. The framework is designed to support modern software development practices with a focus on security, scalability, and reliability. All components in this framework are open-source and require no paid licenses, making it accessible to organizations of all sizes.

The framework supports multiple technology stacks including Java Spring Boot, Node.js with React, and Python Django applications. It provides automated testing, security scanning, deployment orchestration, and comprehensive monitoring capabilities. The architecture follows industry best practices as outlined by the DevOps Research and Assessment (DORA) team and incorporates security recommendations from the Open Web Application Security Project (OWASP) [1].

The installation process is designed to be modular, allowing organizations to implement components incrementally based on their specific needs and existing infrastructure. Whether you are starting with a greenfield deployment or integrating with existing systems, this guide provides the flexibility to adapt the framework to your environment.

## Prerequisites

Before beginning the installation process, ensure that your environment meets the following requirements. These prerequisites are essential for the successful deployment and operation of the CI/CD framework.

### Hardware Requirements

The minimum hardware requirements vary based on the scale of your deployment and the number of applications you plan to support. For a production environment supporting 10-20 applications with moderate traffic, the following specifications are recommended:

**Kubernetes Cluster Nodes:**
- Master nodes: 3 nodes with 4 CPU cores, 8GB RAM, 100GB SSD storage each
- Worker nodes: 5 nodes with 8 CPU cores, 16GB RAM, 200GB SSD storage each
- Network bandwidth: 1Gbps minimum between nodes

**Database Servers:**
- PostgreSQL: 4 CPU cores, 16GB RAM, 500GB SSD storage with IOPS 3000+
- Redis: 2 CPU cores, 8GB RAM, 100GB SSD storage

**Monitoring Infrastructure:**
- Prometheus: 4 CPU cores, 16GB RAM, 1TB SSD storage
- Grafana: 2 CPU cores, 4GB RAM, 100GB SSD storage

For smaller deployments or development environments, these requirements can be scaled down proportionally. Cloud providers such as Amazon Web Services (AWS), Google Cloud Platform (GCP), and Microsoft Azure offer managed services that can reduce the operational overhead of managing these components [2].

### Software Prerequisites

The following software components must be installed and configured on your management workstation before proceeding with the framework installation:

**Container and Orchestration Tools:**
- Docker Engine version 20.10 or later
- Kubernetes cluster version 1.25 or later
- kubectl command-line tool matching your cluster version
- Helm package manager version 3.10 or later

**Infrastructure as Code Tools:**
- Terraform version 1.5 or later
- Ansible version 2.14 or later (optional, for configuration management)

**Development and Scripting Tools:**
- Python 3.9 or later with pip package manager
- Node.js version 18 or later with npm
- Git version 2.30 or later
- curl and wget utilities
- jq JSON processor

**Cloud Provider CLI Tools (if using cloud infrastructure):**
- AWS CLI version 2.x (for Amazon Web Services)
- gcloud CLI (for Google Cloud Platform)
- Azure CLI (for Microsoft Azure)

### Network Requirements

The framework requires specific network configurations to ensure proper communication between components and external access to services. The following network requirements must be met:

**Internal Network Communication:**
- All Kubernetes nodes must be able to communicate on ports 6443 (API server), 2379-2380 (etcd), and 10250 (kubelet)
- Container networking must support pod-to-pod communication across nodes
- DNS resolution must be functional within the cluster

**External Access Requirements:**
- HTTPS access (port 443) for web interfaces and API endpoints
- SSH access (port 22) for administrative tasks
- Git repository access (ports 22 for SSH, 443 for HTTPS)
- Container registry access for image pulls and pushes

**Security Considerations:**
- Network segmentation between production, staging, and development environments
- Firewall rules restricting access to administrative interfaces
- VPN or bastion host access for sensitive operations

### Access and Permissions

Proper access controls and permissions are crucial for the secure operation of the CI/CD framework. The following access requirements must be established before installation:

**Kubernetes Cluster Access:**
- Cluster administrator privileges for initial setup
- Namespace-specific permissions for application deployments
- Service account configurations for automated operations

**Cloud Provider Permissions (if applicable):**
- IAM roles with appropriate permissions for resource creation and management
- API access keys with necessary scopes
- Billing account access for cost monitoring

**Source Code Repository Access:**
- Administrative access to configure webhooks and integrations
- Service account credentials for automated operations
- Branch protection and merge policies configuration

**Container Registry Access:**
- Push and pull permissions for application images
- Administrative access for registry configuration
- Security scanning integration capabilities



## Infrastructure Setup

The infrastructure setup phase involves provisioning the underlying compute, storage, and networking resources required for the CI/CD framework. This section provides detailed instructions for both cloud-based and on-premises deployments, with a focus on Infrastructure as Code (IaC) practices using Terraform.

### Cloud Infrastructure Deployment

Cloud deployment offers several advantages including managed services, automatic scaling, and reduced operational overhead. The framework includes Terraform templates optimized for major cloud providers, incorporating security best practices and cost optimization strategies.

**Amazon Web Services (AWS) Deployment:**

The AWS deployment utilizes Amazon Elastic Kubernetes Service (EKS) for container orchestration, Amazon RDS for managed databases, and Amazon ElastiCache for Redis caching. The infrastructure is designed with high availability across multiple Availability Zones and includes comprehensive monitoring and logging capabilities.

Begin by configuring your AWS credentials and region settings. The Terraform configuration requires specific IAM permissions to create and manage resources. Create an IAM user with the following managed policies attached: AmazonEKSClusterPolicy, AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, and AmazonEC2ContainerRegistryReadOnly [3].

```bash
# Configure AWS credentials
aws configure set aws_access_key_id YOUR_ACCESS_KEY
aws configure set aws_secret_access_key YOUR_SECRET_KEY
aws configure set default.region us-west-2

# Initialize Terraform
cd cicd_framework_templates/environments/
terraform init

# Review and customize the terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific configuration
```

The Terraform configuration creates a Virtual Private Cloud (VPC) with public and private subnets across three Availability Zones. The EKS cluster is deployed in the private subnets for enhanced security, while Application Load Balancers in the public subnets provide external access. Network Address Translation (NAT) gateways enable outbound internet access for private resources.

Database services are configured with encryption at rest and in transit, automated backups, and Multi-AZ deployment for high availability. The RDS instance uses the latest PostgreSQL version with performance insights enabled for monitoring and optimization. ElastiCache Redis clusters are configured with cluster mode enabled for automatic failover and scaling capabilities.

**Google Cloud Platform (GCP) Deployment:**

For GCP deployments, the framework utilizes Google Kubernetes Engine (GKE) with Autopilot mode for simplified cluster management. Cloud SQL provides managed PostgreSQL services, while Memorystore offers Redis caching capabilities. The deployment includes Cloud Load Balancing for traffic distribution and Cloud Armor for DDoS protection.

```bash
# Authenticate with GCP
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable container.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable redis.googleapis.com

# Deploy infrastructure
terraform plan -var-file="gcp.tfvars"
terraform apply -var-file="gcp.tfvars"
```

The GCP deployment creates a regional GKE cluster with node auto-provisioning enabled, allowing the cluster to automatically create node pools based on workload requirements. Private Google Access is configured to enable nodes without external IP addresses to access Google Cloud services. Binary Authorization is enabled to ensure only verified container images are deployed to the cluster.

**Microsoft Azure Deployment:**

Azure deployments leverage Azure Kubernetes Service (AKS) with Azure Container Instances (ACI) integration for serverless scaling. Azure Database for PostgreSQL provides managed database services, while Azure Cache for Redis offers caching capabilities. Azure Application Gateway provides layer 7 load balancing with Web Application Firewall (WAF) protection.

The Azure deployment includes Azure Active Directory (AAD) integration for authentication and role-based access control (RBAC). Azure Key Vault is integrated for secrets management, and Azure Monitor provides comprehensive observability across all components.

### On-Premises Infrastructure Setup

On-premises deployments provide greater control over infrastructure and may be required for organizations with strict data residency or compliance requirements. The framework supports deployment on bare metal servers, virtualized environments, or hybrid cloud configurations.

**Kubernetes Cluster Setup:**

For on-premises Kubernetes deployments, the framework supports multiple installation methods including kubeadm for manual installations, Rancher for simplified management, or OpenShift for enterprise features. The following example demonstrates a kubeadm-based installation for a production-ready cluster.

Master node initialization requires careful consideration of networking and security configurations. The cluster should be configured with a pod network CIDR that does not conflict with existing network infrastructure. Certificate management should use a proper Certificate Authority (CA) for production deployments rather than self-signed certificates.

```bash
# Initialize the master node
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --apiserver-advertise-address=MASTER_NODE_IP

# Configure kubectl for the admin user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install a Container Network Interface (CNI) plugin
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

Worker nodes must be joined to the cluster using the token and certificate hash provided during master initialization. Each worker node should be configured with appropriate resource limits and monitoring agents. Container runtime configuration should include security policies and resource constraints to prevent resource exhaustion attacks.

**Storage Configuration:**

Persistent storage is critical for stateful applications including databases, monitoring systems, and artifact repositories. The framework supports multiple storage backends including local storage, Network File System (NFS), and distributed storage systems like Ceph or GlusterFS.

For production deployments, a distributed storage system is recommended to provide high availability and data redundancy. Ceph provides object, block, and file storage capabilities with automatic data replication and self-healing capabilities. The Rook operator simplifies Ceph deployment and management on Kubernetes clusters.

```bash
# Deploy Rook Ceph operator
kubectl create -f https://raw.githubusercontent.com/rook/rook/release-1.12/deploy/examples/crds.yaml
kubectl create -f https://raw.githubusercontent.com/rook/rook/release-1.12/deploy/examples/common.yaml
kubectl create -f https://raw.githubusercontent.com/rook/rook/release-1.12/deploy/examples/operator.yaml

# Create Ceph cluster
kubectl create -f https://raw.githubusercontent.com/rook/rook/release-1.12/deploy/examples/cluster.yaml
```

Storage classes should be configured with appropriate replication factors and performance characteristics based on application requirements. Database storage requires high IOPS and low latency, while artifact storage can utilize higher latency but more cost-effective storage tiers.

**Network Configuration:**

Network configuration for on-premises deployments requires careful planning to ensure proper segmentation, security, and performance. The framework recommends a three-tier network architecture with separate VLANs for management, application, and data traffic.

Load balancing can be implemented using hardware load balancers, software solutions like HAProxy or NGINX, or cloud-native solutions like MetalLB for Kubernetes environments. The load balancer configuration should include health checks, SSL termination, and traffic routing based on application requirements.

```bash
# Deploy MetalLB for on-premises load balancing
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Configure IP address pool
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: production-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.100-192.168.1.200
EOF
```

Firewall rules should be configured to restrict access to administrative interfaces and allow only necessary traffic between network segments. Intrusion detection and prevention systems (IDS/IPS) should be deployed to monitor network traffic for suspicious activities.

### Infrastructure Validation

After completing the infrastructure setup, comprehensive validation is essential to ensure all components are functioning correctly and meet performance requirements. This validation process includes connectivity tests, performance benchmarks, and security assessments.

**Connectivity Testing:**

Network connectivity between all components must be verified to ensure proper communication. This includes testing pod-to-pod communication within the Kubernetes cluster, database connectivity from application pods, and external access to web interfaces and APIs.

```bash
# Test cluster connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -- /bin/sh

# From within the test pod, verify DNS resolution
nslookup kubernetes.default.svc.cluster.local

# Test external connectivity
wget -qO- https://www.google.com
```

Database connectivity should be tested from application namespaces to ensure proper network policies and security group configurations. Redis connectivity and performance should be validated using redis-benchmark tools to establish baseline performance metrics.

**Performance Benchmarking:**

Performance benchmarking establishes baseline metrics for infrastructure components and identifies potential bottlenecks before application deployment. Storage performance should be tested using tools like fio to measure IOPS, throughput, and latency characteristics.

Network performance between nodes should be measured using tools like iperf3 to ensure adequate bandwidth for application communication and data replication. CPU and memory performance should be validated using stress testing tools to verify resource allocation and limits are functioning correctly.

**Security Assessment:**

Security assessment of the infrastructure includes vulnerability scanning, configuration validation, and penetration testing. Container images should be scanned for known vulnerabilities using tools like Trivy or Clair. Kubernetes configurations should be validated against security benchmarks such as the CIS Kubernetes Benchmark [4].

Network security should be assessed using port scanning tools to identify unnecessary open ports and services. SSL/TLS configurations should be validated using tools like SSL Labs' SSL Test to ensure proper cipher suites and certificate configurations are in place.


## Core Components Installation

The core components installation phase involves deploying and configuring the essential services that form the foundation of the CI/CD framework. These components include the CI/CD orchestration platform, container registry, secrets management, and artifact storage systems. Each component is configured with production-ready settings including high availability, security hardening, and monitoring integration.

### CI/CD Platform Deployment

The framework supports multiple CI/CD platforms including Jenkins, GitLab CI/CD, and GitHub Actions. The choice of platform depends on organizational requirements, existing tooling, and integration needs. This section provides detailed installation instructions for each supported platform.

**Jenkins Installation and Configuration:**

Jenkins serves as the primary CI/CD orchestration platform, providing a flexible and extensible automation server. The installation utilizes the official Jenkins Helm chart with customizations for security, scalability, and integration with Kubernetes-native features.

The Jenkins deployment includes persistent storage for job configurations and build artifacts, LDAP integration for authentication, and role-based access control for authorization. The configuration enables distributed builds using Kubernetes agents, allowing for dynamic scaling based on build queue demands.

```bash
# Add Jenkins Helm repository
helm repo add jenkins https://charts.jenkins.io
helm repo update

# Create namespace for Jenkins
kubectl create namespace jenkins

# Create persistent volume claim for Jenkins data
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: jenkins
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: fast-ssd
EOF

# Install Jenkins with custom values
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --set persistence.existingClaim=jenkins-pvc \
  --set controller.serviceType=ClusterIP \
  --set controller.ingress.enabled=true \
  --set controller.ingress.hostName=jenkins.yourdomain.com \
  --set controller.ingress.annotations."kubernetes\.io/ingress\.class"=nginx \
  --set controller.ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-prod
```

The Jenkins configuration includes pre-installed plugins for Kubernetes integration, Git repository management, Docker image building, and security scanning. The Blue Ocean plugin provides a modern user interface for pipeline visualization and management. The Kubernetes plugin enables dynamic agent provisioning, reducing resource consumption and improving build isolation.

Security configuration includes CSRF protection, content security policy headers, and secure communication protocols. The Jenkins security realm is configured to integrate with organizational identity providers such as Active Directory, LDAP, or SAML-based single sign-on systems. Role-based authorization ensures users have appropriate access levels based on their responsibilities and project assignments.

**GitLab CI/CD Installation:**

GitLab provides an integrated DevOps platform combining source code management, CI/CD pipelines, and project management capabilities. The GitLab installation includes both the GitLab instance and GitLab Runner for executing CI/CD jobs.

The GitLab deployment utilizes the official GitLab Helm chart with configurations optimized for Kubernetes environments. The installation includes PostgreSQL for metadata storage, Redis for caching and session management, and object storage for artifacts and container images.

```bash
# Add GitLab Helm repository
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Create namespace for GitLab
kubectl create namespace gitlab

# Install GitLab with custom configuration
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --set global.hosts.domain=yourdomain.com \
  --set global.hosts.externalIP=YOUR_EXTERNAL_IP \
  --set certmanager.install=false \
  --set global.ingress.configureCertmanager=false \
  --set gitlab-runner.install=true \
  --set gitlab-runner.runners.privileged=true \
  --set postgresql.persistence.size=100Gi \
  --set redis.persistence.size=20Gi
```

GitLab Runner configuration enables execution of CI/CD jobs within Kubernetes pods, providing isolation and scalability. The runner supports multiple executor types including Docker, Kubernetes, and shell executors. Auto-scaling configuration adjusts the number of concurrent jobs based on queue depth and resource availability.

Container registry integration allows GitLab to serve as both source code repository and container image registry. The registry includes vulnerability scanning capabilities using Clair scanner, providing security insights for container images before deployment. Image cleanup policies automatically remove old or unused images to manage storage consumption.

**GitHub Actions Integration:**

For organizations using GitHub as their primary source code repository, GitHub Actions provides native CI/CD capabilities with extensive marketplace integrations. While GitHub Actions runs on GitHub's infrastructure, self-hosted runners can be deployed within the Kubernetes cluster for enhanced security and control.

Self-hosted runners provide several advantages including access to internal resources, custom software installations, and compliance with data residency requirements. The runners are deployed as Kubernetes deployments with auto-scaling capabilities based on job queue metrics.

```bash
# Create namespace for GitHub Actions runners
kubectl create namespace github-actions

# Deploy self-hosted runner using actions-runner-controller
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# Install the controller
helm install actions-runner-controller actions-runner-controller/actions-runner-controller \
  --namespace github-actions \
  --set authSecret.github_token=YOUR_GITHUB_TOKEN

# Create runner deployment
kubectl apply -f - <<EOF
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: cicd-runners
  namespace: github-actions
spec:
  replicas: 3
  template:
    spec:
      repository: your-org/your-repo
      labels:
        - kubernetes
        - linux
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2
          memory: 4Gi
EOF
```

Runner security includes isolation between jobs, secure secret handling, and network policies restricting access to sensitive resources. The runners are configured with necessary tools for building and testing applications including Docker, kubectl, and language-specific build tools.

### Container Registry Setup

A container registry serves as the central repository for storing and distributing container images used throughout the CI/CD pipeline. The framework supports both cloud-managed registries and self-hosted solutions, with configurations optimized for security, performance, and integration with CI/CD workflows.

**Harbor Registry Installation:**

Harbor is an open-source container registry that provides enterprise-grade features including vulnerability scanning, image signing, and role-based access control. The Harbor installation includes integrated security scanning using Trivy scanner and supports multiple authentication backends.

```bash
# Add Harbor Helm repository
helm repo add harbor https://helm.goharbor.io
helm repo update

# Create namespace for Harbor
kubectl create namespace harbor

# Install Harbor with custom configuration
helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=ingress \
  --set expose.ingress.hosts.core=harbor.yourdomain.com \
  --set externalURL=https://harbor.yourdomain.com \
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.registry.size=500Gi \
  --set persistence.persistentVolumeClaim.database.size=100Gi \
  --set trivy.enabled=true \
  --set notary.enabled=true
```

Harbor configuration includes project-based access control, allowing different teams to manage their container images independently while maintaining organizational governance. Vulnerability scanning policies can be configured to prevent deployment of images with critical security vulnerabilities. Image retention policies automatically clean up old images to manage storage costs.

Replication policies enable Harbor to synchronize images with other registries, supporting multi-region deployments and disaster recovery scenarios. The replication can be configured for specific projects or image patterns, with scheduling options for bandwidth optimization.

**Cloud Registry Integration:**

For organizations preferring managed services, cloud provider registries offer simplified operations with integrated security and compliance features. The framework includes configurations for Amazon Elastic Container Registry (ECR), Google Container Registry (GCR), and Azure Container Registry (ACR).

Cloud registry integration includes automated image scanning, lifecycle policies for cost optimization, and integration with cloud identity and access management systems. The registries support both public and private repositories with fine-grained access controls.

```bash
# Configure Docker to use AWS ECR
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-west-2.amazonaws.com

# Create ECR repositories for applications
aws ecr create-repository --repository-name myapp-frontend
aws ecr create-repository --repository-name myapp-backend

# Configure lifecycle policies
aws ecr put-lifecycle-policy --repository-name myapp-frontend --lifecycle-policy-text file://lifecycle-policy.json
```

Registry authentication is configured using Kubernetes secrets, enabling pods to pull images from private registries. The authentication credentials are automatically refreshed using tools like ECR credential helper or service account token rotation.

### Secrets Management

Secrets management is critical for maintaining security throughout the CI/CD pipeline. The framework utilizes HashiCorp Vault as the primary secrets management solution, providing centralized secret storage, dynamic secret generation, and comprehensive audit logging.

**HashiCorp Vault Installation:**

Vault installation follows security best practices including high availability configuration, auto-unsealing using cloud key management services, and integration with Kubernetes authentication. The Vault deployment includes both the Vault server and Vault Agent for secret injection into application pods.

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create namespace for Vault
kubectl create namespace vault

# Install Vault in HA mode
helm install vault hashicorp/vault \
  --namespace vault \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set server.ha.raft.enabled=true \
  --set server.ha.raft.setNodeId=true \
  --set ui.enabled=true \
  --set ui.serviceType=ClusterIP \
  --set injector.enabled=true
```

Vault initialization requires careful handling of unseal keys and root tokens. The initialization process should be performed in a secure environment with proper key ceremony procedures. Unseal keys should be distributed among multiple trusted individuals using Shamir's Secret Sharing algorithm.

Auto-unsealing configuration eliminates the need for manual intervention during Vault restarts. Cloud key management services such as AWS KMS, Google Cloud KMS, or Azure Key Vault provide secure key storage and automatic unsealing capabilities.

```bash
# Initialize Vault (perform only once)
kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3

# Configure auto-unseal using AWS KMS
kubectl exec -n vault vault-0 -- vault write sys/config/seal/awskms \
  region=us-west-2 \
  kms_key_id=arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012
```

**Vault Authentication and Authorization:**

Vault authentication is configured to integrate with Kubernetes service accounts, enabling pods to authenticate using their service account tokens. This integration eliminates the need for static credentials and provides automatic token rotation.

```bash
# Enable Kubernetes authentication
kubectl exec -n vault vault-0 -- vault auth enable kubernetes

# Configure Kubernetes authentication
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create policies for different applications
kubectl exec -n vault vault-0 -- vault policy write myapp-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# Create authentication roles
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp \
  bound_service_account_namespaces=production \
  policies=myapp-policy \
  ttl=24h
```

Secret engines are configured for different types of secrets including static key-value pairs, dynamic database credentials, and PKI certificates. The database secret engine provides just-in-time credential generation, reducing the risk of credential compromise and simplifying credential rotation.

**Secret Injection and Rotation:**

The Vault Agent Injector automatically injects secrets into application pods using init containers and sidecar containers. This approach eliminates the need for applications to directly interact with Vault APIs while providing automatic secret rotation capabilities.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp"
        vault.hashicorp.com/agent-inject-secret-database: "secret/data/myapp/database"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "secret/data/myapp/database" -}}
          export DATABASE_URL="postgresql://{{ .Data.data.username }}:{{ .Data.data.password }}@postgres:5432/myapp"
          {{- end }}
    spec:
      serviceAccountName: myapp
      containers:
      - name: myapp
        image: myapp:latest
        command: ["/bin/sh"]
        args: ["-c", "source /vault/secrets/database && exec myapp"]
```

Secret rotation policies ensure credentials are regularly updated to minimize the impact of potential compromises. Automated rotation is configured for database credentials, API keys, and certificates with appropriate notification mechanisms for applications that require manual intervention.


## Security Configuration

Security configuration is paramount in any CI/CD framework, as it handles sensitive code, credentials, and deployment processes. This section covers comprehensive security hardening including network policies, RBAC configuration, security scanning integration, and compliance monitoring.

### Network Security Policies

Kubernetes Network Policies provide micro-segmentation capabilities, controlling traffic flow between pods, namespaces, and external services. The framework implements a zero-trust network model where all communication is explicitly defined and authorized.

```yaml
# Default deny-all policy for production namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

# Allow specific communication patterns
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### Role-Based Access Control (RBAC)

RBAC configuration ensures users and service accounts have minimal necessary permissions. The framework implements role separation between developers, operators, and administrators with appropriate access controls for each environment.

```yaml
# Developer role for application namespaces
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]

# Bind role to developer group
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: development
subjects:
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

## Monitoring Setup

Comprehensive monitoring provides visibility into system health, performance metrics, and security events. The monitoring stack includes Prometheus for metrics collection, Grafana for visualization, and AlertManager for notification management.

### Prometheus Installation

```bash
# Add Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=100Gi \
  --set grafana.adminPassword=secure-password \
  --set alertmanager.config.global.smtp_smarthost=smtp.company.com:587
```

### Custom Dashboards and Alerts

The framework includes pre-configured dashboards for application metrics, infrastructure monitoring, and security events. Custom alerts are configured for critical conditions including deployment failures, resource exhaustion, and security violations.

## Pipeline Configuration

Pipeline configuration involves setting up automated workflows for code integration, testing, security scanning, and deployment. The framework provides templates for common application types with customization options for specific requirements.

### Application Pipeline Templates

Each application type includes optimized pipeline configurations with appropriate testing strategies, security scanning, and deployment patterns. The templates follow GitOps principles with declarative configuration management.

### Security Integration

Security scanning is integrated throughout the pipeline including static code analysis, dependency vulnerability scanning, container image scanning, and runtime security monitoring. Security gates prevent deployment of applications with critical vulnerabilities.

## Testing and Validation

Comprehensive testing validates the framework installation and ensures all components are functioning correctly. This includes unit tests for automation scripts, integration tests for component interactions, and end-to-end tests for complete workflows.

### Automated Testing Suite

```bash
# Run framework validation tests
./cicd_framework_scripts/utilities/cicd-utils.py status --namespace monitoring
./cicd_framework_scripts/troubleshooting/troubleshoot.py --namespace production

# Validate monitoring stack
curl -f http://prometheus.monitoring.svc.cluster.local:9090/-/healthy
curl -f http://grafana.monitoring.svc.cluster.local:3000/api/health
```

### Performance Validation

Performance testing ensures the framework can handle expected workloads with appropriate response times and resource utilization. Load testing simulates realistic usage patterns to identify potential bottlenecks.

## Troubleshooting

Common installation issues and their resolutions are documented to assist with troubleshooting. The troubleshooting section includes diagnostic commands, log analysis techniques, and escalation procedures.

### Common Issues

**Pod Scheduling Failures:**
- Insufficient cluster resources
- Node selector constraints
- Taints and tolerations misconfigurations

**Network Connectivity Issues:**
- DNS resolution problems
- Network policy restrictions
- Service discovery failures

**Storage Problems:**
- Persistent volume provisioning failures
- Storage class misconfigurations
- Insufficient storage capacity

### Diagnostic Commands

```bash
# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces
kubectl top nodes
kubectl top pods --all-namespaces

# Analyze events
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --previous
kubectl logs -f deployment/<deployment-name> -n <namespace>
```

## References

[1] DevOps Research and Assessment (DORA). "State of DevOps Report 2024." https://cloud.google.com/devops/state-of-devops/

[2] Cloud Native Computing Foundation. "CNCF Cloud Native Landscape." https://landscape.cncf.io/

[3] Amazon Web Services. "Amazon EKS User Guide." https://docs.aws.amazon.com/eks/latest/userguide/

[4] Center for Internet Security. "CIS Kubernetes Benchmark." https://www.cisecurity.org/benchmark/kubernetes

[5] Open Web Application Security Project. "OWASP Top 10 CI/CD Security Risks." https://owasp.org/www-project-top-10-ci-cd-security-risks/

[6] HashiCorp. "Vault Documentation." https://www.vaultproject.io/docs

[7] Prometheus. "Prometheus Documentation." https://prometheus.io/docs/

[8] Kubernetes. "Kubernetes Documentation." https://kubernetes.io/docs/

[9] Harbor. "Harbor Documentation." https://goharbor.io/docs/

[10] Jenkins. "Jenkins User Documentation." https://www.jenkins.io/doc/

