# ═══════════════════════════════════════════════════════════════════════════
# ENTERPRISE EKS CLUSTER VARIABLES
# ═══════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# CLUSTER BASIC CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  validation {
    condition     = length(var.cluster_name) > 1 && length(var.cluster_name) <= 100
    error_message = "Cluster name must be between 1 and 100 characters."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
  validation {
    condition     = can(regex("^1\\.(2[8-9]|[3-9][0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.28 or higher."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner/Team responsible for the cluster"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

variable "compliance_standard" {
  description = "Compliance standard to follow (SOC2, ISO27001, PCI-DSS)"
  type        = string
  default     = "SOC2"
  validation {
    condition     = contains(["SOC2", "ISO27001", "PCI-DSS", "HIPAA"], var.compliance_standard)
    error_message = "Compliance standard must be one of: SOC2, ISO27001, PCI-DSS, HIPAA."
  }
}

variable "git_commit_sha" {
  description = "Git commit SHA for traceability"
  type        = string
  default     = "unknown"
}

variable "git_repository" {
  description = "Git repository URL"
  type        = string
  default     = "unknown"
}

# ─────────────────────────────────────────────────────────────────────────────
# NETWORKING CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "availability_zones_count" {
  description = "Number of AZs to spread the cluster across"
  type        = number
  default     = 3
  validation {
    condition     = var.availability_zones_count >= 2 && var.availability_zones_count <= 6
    error_message = "Availability zones count must be between 2 and 6."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "route53_zone_arns" {
  description = "List of Route53 hosted zone ARNs for External DNS"
  type        = list(string)
  default     = []
}

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM NODE GROUP CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "system_node_instance_types" {
  description = "Instance types for system node group"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "system_node_min_size" {
  description = "Minimum number of nodes in system node group"
  type        = number
  default     = 1
  validation {
    condition     = var.system_node_min_size >= 1
    error_message = "System node group minimum size must be at least 1."
  }
}

variable "system_node_max_size" {
  description = "Maximum number of nodes in system node group"
  type        = number
  default     = 10
}

variable "system_node_desired_size" {
  description = "Desired number of nodes in system node group"
  type        = number
  default     = 3
}

variable "system_node_disk_size" {
  description = "Disk size for system nodes (GB)"
  type        = number
  default     = 50
  validation {
    condition     = var.system_node_disk_size >= 20
    error_message = "System node disk size must be at least 20 GB."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# APPLICATION NODE GROUP CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "app_node_instance_types" {
  description = "Instance types for application node group"
  type        = list(string)
  default     = ["m5.large", "m5a.large", "m5.xlarge", "m5a.xlarge"]
}

variable "app_node_capacity_type" {
  description = "Capacity type for application nodes (ON_DEMAND, SPOT, MIXED)"
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT", "MIXED"], var.app_node_capacity_type)
    error_message = "Application node capacity type must be ON_DEMAND, SPOT, or MIXED."
  }
}

variable "app_node_min_size" {
  description = "Minimum number of nodes in application node group"
  type        = number
  default     = 2
}

variable "app_node_max_size" {
  description = "Maximum number of nodes in application node group"
  type        = number
  default     = 50
}

variable "app_node_desired_size" {
  description = "Desired number of nodes in application node group"
  type        = number
  default     = 6
}

variable "app_node_disk_size" {
  description = "Disk size for application nodes (GB)"
  type        = number
  default     = 100
  validation {
    condition     = var.app_node_disk_size >= 50
    error_message = "Application node disk size must be at least 50 GB."
  }
}

variable "app_node_on_demand_base" {
  description = "Absolute minimum amount of desired capacity for on-demand instances"
  type        = number
  default     = 2
}

variable "app_node_on_demand_percentage" {
  description = "Percentage of on-demand instances above base capacity"
  type        = number
  default     = 50
  validation {
    condition     = var.app_node_on_demand_percentage >= 0 && var.app_node_on_demand_percentage <= 100
    error_message = "On-demand percentage must be between 0 and 100."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# SPOT NODE GROUP CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "spot_node_instance_types" {
  description = "Instance types for spot node group"
  type        = list(string)
  default     = ["m5.large", "m5a.large", "m4.large", "m5.xlarge", "m5a.xlarge", "m4.xlarge"]
}

variable "spot_node_min_size" {
  description = "Minimum number of nodes in spot node group"
  type        = number
  default     = 0
}

variable "spot_node_max_size" {
  description = "Maximum number of nodes in spot node group"
  type        = number
  default     = 20
}

variable "spot_node_desired_size" {
  description = "Desired number of nodes in spot node group"
  type        = number
  default     = 3
}

variable "spot_node_disk_size" {
  description = "Disk size for spot nodes (GB)"
  type        = number
  default     = 100
  validation {
    condition     = var.spot_node_disk_size >= 50
    error_message = "Spot node disk size must be at least 50 GB."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY & ACCESS CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_admin_arns" {
  description = "List of IAM user/role ARNs to have admin access to the cluster"
  type        = list(string)
  default     = []
}

variable "cluster_developer_arns" {
  description = "List of IAM user/role ARNs to have developer access to the cluster"
  type        = list(string)
  default     = []
}

variable "developer_namespaces" {
  description = "List of namespaces developers should have access to"
  type        = list(string)
  default     = ["default", "development"]
}

variable "kms_deletion_window" {
  description = "Number of days to wait before deleting KMS key"
  type        = number
  default     = 30
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING & LOGGING CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention period."
  }
}

variable "enable_cluster_logging" {
  description = "Enable EKS cluster logging"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "List of control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  validation {
    condition = alltrue([
      for log_type in var.cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
    ])
    error_message = "Invalid cluster log type. Valid types are: api, audit, authenticator, controllerManager, scheduler."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ADD-ONS CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable External DNS"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Enable Karpenter for node provisioning"
  type        = bool
  default     = false
}

variable "enable_metrics_server" {
  description = "Enable Metrics Server"
  type        = bool
  default     = true
}

variable "enable_prometheus" {
  description = "Enable Prometheus monitoring stack"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "enable_istio" {
  description = "Enable Istio service mesh"
  type        = bool
  default     = false
}

variable "enable_argocd" {
  description = "Enable ArgoCD for GitOps"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# COST OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling based on business hours"
  type        = bool
  default     = false
}

variable "business_hours_schedule" {
  description = "Cron expression for business hours scaling up"
  type        = string
  default     = "0 8 * * 1-5"  # 8 AM Monday to Friday
}

variable "after_hours_schedule" {
  description = "Cron expression for after hours scaling down"
  type        = string
  default     = "0 20 * * 1-5"  # 8 PM Monday to Friday
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP & DISASTER RECOVERY
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_backup" {
  description = "Enable automated backup solutions"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule"
  type        = string
  default     = "0 2 * * *"  # 2 AM daily
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup for disaster recovery"
  type        = bool
  default     = false
}

variable "backup_regions" {
  description = "List of regions for cross-region backup"
  type        = list(string)
  default     = ["us-east-1"]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADVANCED FEATURES
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_pod_security_standards" {
  description = "Enable Pod Security Standards"
  type        = bool
  default     = true
}

variable "pod_security_standard_level" {
  description = "Pod Security Standard level (privileged, baseline, restricted)"
  type        = string
  default     = "restricted"
  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.pod_security_standard_level)
    error_message = "Pod Security Standard level must be privileged, baseline, or restricted."
  }
}

variable "enable_network_policies" {
  description = "Enable Kubernetes Network Policies"
  type        = bool
  default     = true
}

variable "enable_image_scanning" {
  description = "Enable container image vulnerability scanning"
  type        = bool
  default     = true
}

variable "enable_admission_controllers" {
  description = "Enable additional admission controllers (OPA Gatekeeper, etc.)"
  type        = bool
  default     = true
}

variable "enable_secrets_encryption" {
  description = "Enable encryption of Kubernetes secrets at rest"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable Kubernetes audit logging"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# TAGGING
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
