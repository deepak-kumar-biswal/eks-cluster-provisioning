# ═══════════════════════════════════════════════════════════════════════════
# ENTERPRISE EKS CLUSTER MODULE
# ═══════════════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.5.0"
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# DATA SOURCES
# ═══════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# ═══════════════════════════════════════════════════════════════════════════
# LOCAL VALUES
# ═══════════════════════════════════════════════════════════════════════════

locals {
  name            = var.cluster_name
  cluster_version = var.kubernetes_version
  region          = data.aws_region.current.name
  
  # Enhanced tagging strategy
  tags = merge(var.tags, {
    Environment   = var.environment
    Project       = "EKS-Enterprise-Automation"
    Owner         = var.owner
    CostCenter    = var.cost_center
    Compliance    = var.compliance_standard
    ManagedBy     = "Terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
    GitCommit     = var.git_commit_sha
    Repository    = var.git_repository
  })

  # VPC CIDR calculations for multi-AZ deployment
  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, var.availability_zones_count)
  
  # Subnet CIDR calculations
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  # Security configurations
  cluster_security_group_additional_rules = {
    ingress_nodes_443 = {
      description                = "Node groups to cluster API"
      protocol                   = "tcp"
      from_port                  = 443
      to_port                    = 443
      type                       = "ingress"
      source_node_security_group = true
    }
    # Additional custom rules based on requirements
    egress_nodes_kubelet = {
      description                = "Cluster API to node kubelets"
      protocol                   = "tcp"
      from_port                  = 10250
      to_port                    = 10250
      type                       = "egress"
      source_node_security_group = true
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# VPC CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  # Enhanced networking features
  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # Flow logs for security monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_max_aggregation_interval    = 60

  # Public subnet tags for Load Balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Private subnet tags for internal Load Balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.tags
}

# ═══════════════════════════════════════════════════════════════════════════
# EKS CLUSTER
# ═══════════════════════════════════════════════════════════════════════════

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  # Enhanced cluster configuration
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Cluster networking
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # Security configurations
  cluster_security_group_additional_rules = local.cluster_security_group_additional_rules
  
  # Enhanced logging
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
  cloudwatch_log_group_retention_in_days = var.log_retention_days
  cloudwatch_log_group_kms_key_id        = aws_kms_key.eks.arn

  # Encryption at rest
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # OIDC Identity Provider
  enable_irsa = true

  # Add-ons configuration
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        replicaCount = var.environment == "prod" ? 3 : 2
        resources = {
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
    snapshot-controller = {
      most_recent = true
    }
  }

  # Node groups
  eks_managed_node_groups = {
    # System node group for critical components
    system = {
      name            = "${local.name}-system"
      use_name_prefix = false

      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.system_node_min_size
      max_size     = var.system_node_max_size
      desired_size = var.system_node_desired_size

      # Enhanced configurations
      ami_type                   = "AL2_x86_64"
      platform                  = "linux"
      bootstrap_extra_args       = "--container-runtime containerd"
      pre_bootstrap_user_data    = file("${path.module}/userdata/system-nodes.sh")
      
      # Taints for system workloads
      taints = [
        {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]

      labels = {
        NodeType = "system"
        Role     = "system-workloads"
      }

      # Enhanced security
      enable_monitoring    = true
      create_security_group = false
      vpc_security_group_ids = [aws_security_group.node_group_additional.id]

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.system_node_disk_size
            volume_type           = "gp3"
            iops                  = 3000
            throughput           = 150
            encrypted            = true
            kms_key_id          = aws_kms_key.eks.arn
            delete_on_termination = true
          }
        }
      }
    }

    # Application node group for regular workloads
    applications = {
      name            = "${local.name}-apps"
      use_name_prefix = false

      instance_types = var.app_node_instance_types
      capacity_type  = var.app_node_capacity_type

      min_size     = var.app_node_min_size
      max_size     = var.app_node_max_size
      desired_size = var.app_node_desired_size

      # Mixed instance policy for cost optimization
      use_mixed_instances_policy = var.app_node_capacity_type == "MIXED"
      mixed_instances_policy = var.app_node_capacity_type == "MIXED" ? {
        instances_distribution = {
          on_demand_base_capacity                  = var.app_node_on_demand_base
          on_demand_percentage_above_base_capacity = var.app_node_on_demand_percentage
          spot_allocation_strategy                 = "diversified"
          spot_instance_pools                      = 4
        }
        override = [
          for instance_type in var.app_node_instance_types : {
            instance_type = instance_type
          }
        ]
      } : null

      labels = {
        NodeType = "application"
        Role     = "application-workloads"
      }

      # Enhanced security and monitoring
      enable_monitoring = true
      create_security_group = false
      vpc_security_group_ids = [aws_security_group.node_group_additional.id]

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.app_node_disk_size
            volume_type           = "gp3"
            iops                  = 3000
            throughput           = 150
            encrypted            = true
            kms_key_id          = aws_kms_key.eks.arn
            delete_on_termination = true
          }
        }
      }
    }

    # Spot node group for cost-effective non-critical workloads
    spot = {
      name            = "${local.name}-spot"
      use_name_prefix = false

      instance_types = var.spot_node_instance_types
      capacity_type  = "SPOT"

      min_size     = var.spot_node_min_size
      max_size     = var.spot_node_max_size
      desired_size = var.spot_node_desired_size

      labels = {
        NodeType = "spot"
        Role     = "batch-workloads"
      }

      taints = [
        {
          key    = "spot"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]

      # Spot-specific configurations
      create_security_group = false
      vpc_security_group_ids = [aws_security_group.node_group_additional.id]

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.spot_node_disk_size
            volume_type           = "gp3"
            encrypted            = true
            kms_key_id          = aws_kms_key.eks.arn
            delete_on_termination = true
          }
        }
      }
    }
  }

  # Access entries for enhanced security
  access_entries = merge(
    # Admin access
    {
      for admin in var.cluster_admin_arns : admin => {
        kubernetes_groups = ["system:masters"]
        principal_arn     = admin
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    },
    # Developer access
    {
      for dev in var.cluster_developer_arns : dev => {
        kubernetes_groups = ["developers"]
        principal_arn     = dev
        policy_associations = {
          developer = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = var.developer_namespaces
            }
          }
        }
      }
    }
  )

  tags = local.tags
}

# ═══════════════════════════════════════════════════════════════════════════
# KMS KEY FOR ENCRYPTION
# ═══════════════════════════════════════════════════════════════════════════

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key for ${local.name}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  tags = merge(local.tags, {
    Name = "${local.name}-eks-key"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ═══════════════════════════════════════════════════════════════════════════
# ADDITIONAL SECURITY GROUPS
# ═══════════════════════════════════════════════════════════════════════════

resource "aws_security_group" "node_group_additional" {
  name_prefix = "${local.name}-node-additional"
  vpc_id      = module.vpc.vpc_id

  # Allow internal communication
  ingress {
    description = "Internal communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Allow HTTPS outbound for packages and container images
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP outbound for packages
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow DNS outbound
  egress {
    description = "DNS outbound"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name}-node-additional-sg"
  })
}

# ═══════════════════════════════════════════════════════════════════════════
# IAM ROLES FOR SERVICE ACCOUNTS (IRSA)
# ═══════════════════════════════════════════════════════════════════════════

# EBS CSI Driver IRSA
module "ebs_csi_driver_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${local.name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

# Load Balancer Controller IRSA
module "load_balancer_controller_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${local.name}-load-balancer-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

# External DNS IRSA
module "external_dns_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${local.name}-external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = var.route53_zone_arns

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = local.tags
}

# Cluster Autoscaler IRSA
module "cluster_autoscaler_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${local.name}-cluster-autoscaler"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [local.name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = local.tags
}

# Karpenter IRSA
module "karpenter_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix = "${local.name}-karpenter-controller"

  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_name       = local.name
  karpenter_controller_node_iam_role_arns = [module.eks.eks_managed_node_groups["applications"].iam_role_arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }

  tags = local.tags
}

# ═══════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═══════════════════════════════════════════════════════════════════════════

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = module.eks.cluster_iam_role_name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "vpc_id" {
  description = "ID of the VPC where the cluster security group is created"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

# Service Account Role ARNs
output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI Driver IAM role"
  value       = module.ebs_csi_driver_irsa.iam_role_arn
}

output "load_balancer_controller_role_arn" {
  description = "ARN of the Load Balancer Controller IAM role"
  value       = module.load_balancer_controller_irsa.iam_role_arn
}

output "external_dns_role_arn" {
  description = "ARN of the External DNS IAM role"
  value       = module.external_dns_irsa.iam_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IAM role"
  value       = module.cluster_autoscaler_irsa.iam_role_arn
}

output "karpenter_role_arn" {
  description = "ARN of the Karpenter Controller IAM role"
  value       = module.karpenter_irsa.iam_role_arn
}
