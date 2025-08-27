# 🚀 EKS Cluster Deployment Guide

## Overview

This guide walks you through deploying an enterprise-grade Amazon EKS cluster using our comprehensive automation platform. The solution is designed for organizations managing hundreds or thousands of clusters with the highest standards of security, observability, and operational excellence.

## 📋 Prerequisites

### Required Tools

- **AWS CLI v2.x** - For AWS API interactions
- **Terraform >= 1.5.x** - Infrastructure as Code
- **kubectl >= 1.28.x** - Kubernetes command-line tool
- **Helm >= 3.12.x** - Kubernetes package manager
- **Python 3.8+** - For testing and automation scripts
- **Git** - Version control

### AWS Requirements

- AWS Account with appropriate permissions
- IAM roles configured for GitHub Actions (if using CI/CD)
- Route53 hosted zones (optional, for External DNS)

## 🛠️ Quick Start

### 1. Environment Setup

Run the automated setup script:

```bash
./scripts/setup-environment.sh
```

This script will:
- ✅ Install all required tools
- ✅ Set up Python virtual environment
- ✅ Configure AWS CLI
- ✅ Create Terraform backend resources
- ✅ Generate example configurations

### 2. Configuration

#### AWS Configuration

```bash
# Option 1: Traditional AWS credentials
aws configure

# Option 2: AWS SSO (Recommended for enterprise)
aws configure sso
```

#### Terraform Variables

Copy and customize the example configuration:

```bash
cd terraform/environments/dev
cp dev.tfvars.example dev.tfvars
```

Edit `dev.tfvars` with your specific requirements:

```hcl
# Basic Configuration
aws_region              = "us-west-2"
project_name            = "my-company"
environment             = "dev"
owner                   = "Platform Team"

# Networking
vpc_cidr                = "10.0.0.0/16"
availability_zones_count = 3

# Security & Access
cluster_admin_arns = [
  "arn:aws:iam::123456789012:user/admin-user",
  "arn:aws:iam::123456789012:role/DevOpsAdminRole"
]

# Node Groups
system_node_instance_types = ["t3.medium", "t3a.medium"]
app_node_instance_types    = ["m5.large", "m5a.large"]

# Add-ons
enable_prometheus = true
enable_grafana    = true
enable_argocd     = true
```

### 3. Infrastructure Deployment

#### Initialize Terraform

```bash
cd terraform/environments/dev
terraform init -backend-config=backend.conf
```

#### Plan and Deploy

```bash
# Review the deployment plan
terraform plan -var-file=dev.tfvars

# Deploy the infrastructure
terraform apply -var-file=dev.tfvars
```

#### Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-west-2 --name eks-enterprise-dev

# Verify cluster access
kubectl get nodes
kubectl get pods -A
```

### 4. Deploy Applications

#### ArgoCD Setup

```bash
# Deploy ArgoCD and applications
kubectl apply -f argocd/applications/core-applications.yaml
kubectl apply -f argocd/applicationsets/cluster-management.yaml

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access ArgoCD at: https://localhost:8080

#### Monitoring Stack

The monitoring stack (Prometheus, Grafana, AlertManager) is automatically deployed via ArgoCD.

```bash
# Get Grafana admin password
kubectl get secret --namespace monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Port-forward to access Grafana
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
```

Access Grafana at: http://localhost:3000 (admin/password from above)

## 🏗️ Architecture Deep Dive

### Network Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                    VPC                                      │
│                                 10.0.0.0/16                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                              Public Subnets                                │
│  10.0.48.0/24    │  10.0.49.0/24    │  10.0.50.0/24                       │
│      AZ-1a       │      AZ-1b       │      AZ-1c                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                             Private Subnets                                │
│  10.0.0.0/20     │  10.0.16.0/20    │  10.0.32.0/20                       │
│      AZ-1a       │      AZ-1b       │      AZ-1c                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                          EKS Control Plane                                 │
│                      (Managed by AWS)                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Node Group Architecture

- **System Node Group**: Dedicated for critical system components
  - Instance Types: `t3.medium`, `t3a.medium`
  - Taints: `CriticalAddonsOnly=true:NoSchedule`
  - Components: CoreDNS, AWS Load Balancer Controller, etc.

- **Application Node Group**: For regular application workloads
  - Instance Types: `m5.large`, `m5a.large`, `m5.xlarge`
  - Mixed instances (On-Demand + Spot)
  - Auto-scaling enabled

- **Spot Node Group**: Cost-effective batch workloads
  - Instance Types: Multiple for diversification
  - 100% Spot instances
  - Taints: `spot=true:NoSchedule`

### Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Security Layers                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ Network Security                                                           │
│ • VPC with private subnets                                                 │
│ • Security Groups (least privilege)                                        │
│ • Network Policies                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ Identity & Access                                                          │
│ • IAM Roles for Service Accounts (IRSA)                                    │
│ • RBAC with fine-grained permissions                                       │
│ • AWS IAM integration                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│ Data Protection                                                            │
│ • Encryption at rest (EBS, Secrets)                                        │
│ • Encryption in transit (TLS)                                              │
│ • KMS key management                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│ Runtime Security                                                           │
│ • Pod Security Standards                                                   │
│ • Container image scanning                                                 │
│ • Admission controllers                                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🔧 Configuration Options

### Environment Types

#### Development Environment
- **Purpose**: Testing and development
- **Node Types**: Smaller instances (t3.medium, m5.large)
- **Logging**: 7-day retention
- **Monitoring**: Basic Prometheus setup
- **Cost Optimization**: Aggressive spot instance usage

#### Staging Environment
- **Purpose**: Pre-production validation
- **Node Types**: Production-like instances
- **Logging**: 30-day retention
- **Monitoring**: Enhanced observability
- **Cost Optimization**: Balanced On-Demand/Spot mix

#### Production Environment
- **Purpose**: Live workloads
- **Node Types**: Enterprise-grade instances
- **Logging**: 90-day retention
- **Monitoring**: Full observability stack
- **Cost Optimization**: Primarily On-Demand with strategic Spot usage

### Node Group Sizing Guidelines

| Environment | System Nodes | App Nodes | Spot Nodes |
|-------------|-------------|-----------|------------|
| Development | 2 x t3.medium | 2-6 x m5.large | 1-5 x m5.large |
| Staging | 3 x t3.large | 3-10 x m5.xlarge | 2-10 x m5.xlarge |
| Production | 3 x m5.large | 6-50 x m5.2xlarge | 5-20 x m5.2xlarge |

## 📊 Monitoring and Observability

### Grafana Dashboards

The platform includes pre-built Grafana dashboards:

1. **Cluster Overview**: High-level cluster health metrics
2. **Node Metrics**: Detailed node performance and resource usage
3. **Pod Metrics**: Application-level monitoring
4. **Network Metrics**: Network performance and security
5. **Cost Analytics**: Resource cost breakdown and optimization

### Key Metrics to Monitor

#### Cluster Health
- Node availability and readiness
- Control plane API latency
- etcd performance metrics
- Certificate expiration dates

#### Resource Usage
- CPU and memory utilization
- Disk space and I/O performance
- Network throughput and latency
- Pod resource consumption

#### Security Metrics
- Failed authentication attempts
- RBAC violations
- Network policy violations
- Container security events

#### Cost Metrics
- Node costs by instance type
- Spot instance savings
- Resource waste identification
- Cost per namespace/application

### Alerting Rules

Critical alerts are pre-configured for:
- **Node failures** or high resource usage
- **Pod crash loops** or deployment failures
- **Security violations** or unauthorized access
- **Performance degradation** above thresholds
- **Cost anomalies** or budget overruns

## 🔒 Security Best Practices

### Network Security

```yaml
# Example Network Policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  # No ingress rules = deny all ingress traffic
```

### Pod Security

```yaml
# Example Pod Security Standards
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### RBAC Configuration

```yaml
# Example developer role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: developer
rules:
- apiGroups: ["", "apps", "extensions"]
  resources: ["*"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

## 💰 Cost Optimization

### Spot Instance Strategy

- **Development**: 80-90% spot instances
- **Staging**: 50-70% spot instances  
- **Production**: 20-40% spot instances for fault-tolerant workloads

### Right-sizing Guidelines

1. **Start Small**: Begin with smaller instance types
2. **Monitor Usage**: Use Prometheus metrics to identify patterns
3. **Scale Appropriately**: Adjust based on actual resource consumption
4. **Use Mixed Instances**: Combine different instance types for optimal cost

### Scheduled Scaling

```yaml
# Example: Scale down non-production environments after hours
businessHours:
  schedule: "0 8 * * 1-5"  # 8 AM, Monday-Friday
  minNodes: 3
  
afterHours:
  schedule: "0 20 * * 1-5"  # 8 PM, Monday-Friday
  minNodes: 1
```

## 🧪 Testing and Validation

### Run Test Suite

```bash
# Activate Python environment
source venv/bin/activate

# Run comprehensive tests
python -m pytest tests/ -v

# Run specific test categories
python -m pytest tests/ -v -k "test_terraform"
python -m pytest tests/ -v -k "test_kubernetes"
python -m pytest tests/ -v -k "test_security"
```

### Validation Checklist

- [ ] All nodes are in Ready state
- [ ] Essential system pods are running
- [ ] DNS resolution works correctly
- [ ] Load balancer provisioning works
- [ ] Monitoring stack is accessible
- [ ] ArgoCD is operational
- [ ] Security policies are enforced
- [ ] Backup solution is working

## 🔄 CI/CD Integration

### GitHub Actions

The platform includes comprehensive GitHub Actions workflows:

1. **Infrastructure CI/CD**: Terraform validation and deployment
2. **Application CI/CD**: Container build and deployment
3. **Security Scanning**: Container and infrastructure security
4. **Cost Analysis**: Infrastructure cost estimation

### Required Secrets

Configure these secrets in your GitHub repository:

```bash
# AWS Access
AWS_ROLE_DEV="arn:aws:iam::123456789012:role/GitHubActionsRole"
AWS_ROLE_STAGING="arn:aws:iam::123456789012:role/GitHubActionsRole"
AWS_ROLE_PROD="arn:aws:iam::987654321098:role/GitHubActionsRole"

# Terraform State
TF_STATE_BUCKET_DEV="eks-terraform-state-123456789012-us-west-2"
TF_STATE_BUCKET_STAGING="eks-terraform-state-123456789012-us-west-2"
TF_STATE_BUCKET_PROD="eks-terraform-state-987654321098-us-west-2"

# Cost Management
INFRACOST_API_KEY="ico-xxxxxxxxxxxxx"

# Notifications
SLACK_WEBHOOK="https://hooks.slack.com/services/xxx/xxx/xxx"
```

## 🆘 Troubleshooting

### Common Issues

#### 1. Terraform Apply Fails

```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify permissions
aws iam get-user
aws iam list-attached-user-policies --user-name <username>

# Check Terraform state
terraform refresh
terraform state list
```

#### 2. Nodes Not Ready

```bash
# Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>

# Check system pods
kubectl get pods -n kube-system
kubectl describe pod -n kube-system <pod-name>

# Check logs
kubectl logs -n kube-system <pod-name>
```

#### 3. Applications Not Deploying

```bash
# Check ArgoCD status
kubectl get applications -n argocd
kubectl describe application -n argocd <app-name>

# Check pod status
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Support Channels

- **Documentation**: Check the docs/ directory for detailed guides
- **Issues**: Create an issue in the GitHub repository
- **Monitoring**: Check Grafana dashboards for system health
- **Logs**: Use kubectl logs or centralized logging solution

## 📚 Additional Resources

- [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)

---

**Happy Clustering! 🎉**

For questions or contributions, please refer to our [Contributing Guide](contributing.md).
