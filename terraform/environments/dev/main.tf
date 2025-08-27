# ═══════════════════════════════════════════════════════════════════════════
# DEVELOPMENT ENVIRONMENT CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"
  
  backend "s3" {
    # Configuration will be provided via backend-config during init
    # bucket = "your-terraform-state-bucket-dev"
    # key    = "eks/dev/terraform.tfstate"
    # region = "us-west-2"
    # encrypt = true
    # dynamodb_table = "terraform-state-locks"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# PROVIDERS CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "EKS-Enterprise-Automation"
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ═══════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ═══════════════════════════════════════════════════════════════════════════
# LOCAL VALUES
# ═══════════════════════════════════════════════════════════════════════════

locals {
  cluster_name = "${var.project_name}-${var.environment}"
  
  common_tags = {
    Environment   = var.environment
    Project       = var.project_name
    Owner         = var.owner
    CostCenter    = var.cost_center
    ManagedBy     = "Terraform"
    Repository    = "eks-cluster-provisioning"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# EKS CLUSTER MODULE
# ═══════════════════════════════════════════════════════════════════════════

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  # Basic Configuration
  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  environment        = var.environment
  owner              = var.owner
  cost_center        = var.cost_center
  compliance_standard = var.compliance_standard

  # Git tracking
  git_commit_sha = var.git_commit_sha
  git_repository = var.git_repository

  # Networking
  vpc_cidr                             = var.vpc_cidr
  availability_zones_count             = var.availability_zones_count
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  route53_zone_arns                   = var.route53_zone_arns

  # System Node Group
  system_node_instance_types = var.system_node_instance_types
  system_node_min_size       = var.system_node_min_size
  system_node_max_size       = var.system_node_max_size
  system_node_desired_size   = var.system_node_desired_size
  system_node_disk_size      = var.system_node_disk_size

  # Application Node Group
  app_node_instance_types       = var.app_node_instance_types
  app_node_capacity_type        = var.app_node_capacity_type
  app_node_min_size            = var.app_node_min_size
  app_node_max_size            = var.app_node_max_size
  app_node_desired_size        = var.app_node_desired_size
  app_node_disk_size           = var.app_node_disk_size
  app_node_on_demand_base      = var.app_node_on_demand_base
  app_node_on_demand_percentage = var.app_node_on_demand_percentage

  # Spot Node Group
  spot_node_instance_types = var.spot_node_instance_types
  spot_node_min_size       = var.spot_node_min_size
  spot_node_max_size       = var.spot_node_max_size
  spot_node_desired_size   = var.spot_node_desired_size
  spot_node_disk_size      = var.spot_node_disk_size

  # Security & Access
  cluster_admin_arns     = var.cluster_admin_arns
  cluster_developer_arns = var.cluster_developer_arns
  developer_namespaces   = var.developer_namespaces
  kms_deletion_window    = var.kms_deletion_window

  # Monitoring & Logging
  log_retention_days    = var.log_retention_days
  enable_cluster_logging = var.enable_cluster_logging
  cluster_log_types     = var.cluster_log_types

  # Add-ons
  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller
  enable_external_dns                 = var.enable_external_dns
  enable_cluster_autoscaler           = var.enable_cluster_autoscaler
  enable_karpenter                    = var.enable_karpenter
  enable_metrics_server               = var.enable_metrics_server
  enable_prometheus                   = var.enable_prometheus
  enable_grafana                      = var.enable_grafana
  enable_istio                        = var.enable_istio
  enable_argocd                       = var.enable_argocd

  # Cost Optimization
  enable_cost_optimization  = var.enable_cost_optimization
  enable_scheduled_scaling  = var.enable_scheduled_scaling
  business_hours_schedule   = var.business_hours_schedule
  after_hours_schedule      = var.after_hours_schedule

  # Backup & DR
  enable_backup              = var.enable_backup
  backup_schedule            = var.backup_schedule
  backup_retention_days      = var.backup_retention_days
  enable_cross_region_backup = var.enable_cross_region_backup
  backup_regions             = var.backup_regions

  # Advanced Features
  enable_pod_security_standards  = var.enable_pod_security_standards
  pod_security_standard_level    = var.pod_security_standard_level
  enable_network_policies        = var.enable_network_policies
  enable_image_scanning          = var.enable_image_scanning
  enable_admission_controllers   = var.enable_admission_controllers
  enable_secrets_encryption      = var.enable_secrets_encryption
  enable_audit_logging           = var.enable_audit_logging

  tags = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════════════
# KUBERNETES PROVIDERS CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
    }
  }
}

provider "kubectl" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# ADDITIONAL KUBERNETES CONFIGURATIONS
# ═══════════════════════════════════════════════════════════════════════════

# Create development namespace
resource "kubernetes_namespace" "development" {
  metadata {
    name = "development"
    
    labels = {
      name        = "development"
      environment = "dev"
      managed-by  = "terraform"
    }
  }

  depends_on = [module.eks_cluster]
}

# Create staging namespace for dev environment testing
resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
    
    labels = {
      name        = "staging"
      environment = "dev"
      managed-by  = "terraform"
    }
  }

  depends_on = [module.eks_cluster]
}

# ═══════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_cluster.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks_cluster.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_cluster.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks_cluster.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "ID of the VPC where the cluster is created"
  value       = module.eks_cluster.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.eks_cluster.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.eks_cluster.public_subnets
}

# Service Account Role ARNs for GitOps
output "service_account_roles" {
  description = "Service Account IAM Role ARNs"
  value = {
    ebs_csi_driver         = module.eks_cluster.ebs_csi_driver_role_arn
    load_balancer_controller = module.eks_cluster.load_balancer_controller_role_arn
    external_dns           = module.eks_cluster.external_dns_role_arn
    cluster_autoscaler     = module.eks_cluster.cluster_autoscaler_role_arn
    karpenter             = module.eks_cluster.karpenter_role_arn
  }
}

# Cluster access command
output "cluster_access_command" {
  description = "Command to configure kubectl"
  value       = "aws eks --region ${data.aws_region.current.name} update-kubeconfig --name ${module.eks_cluster.cluster_name}"
}
