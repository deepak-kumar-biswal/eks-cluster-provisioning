# ═══════════════════════════════════════════════════════════════════════════
# DEVELOPMENT ENVIRONMENT VARIABLES
# ═══════════════════════════════════════════════════════════════════════════

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "eks-enterprise"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "DevOps Team"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

variable "compliance_standard" {
  description = "Compliance standard"
  type        = string
  default     = "SOC2"
}

variable "git_commit_sha" {
  description = "Git commit SHA"
  type        = string
  default     = "unknown"
}

variable "git_repository" {
  description = "Git repository URL"
  type        = string
  default     = "eks-cluster-provisioning"
}

# ─────────────────────────────────────────────────────────────────────────────
# CLUSTER CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

# ─────────────────────────────────────────────────────────────────────────────
# NETWORKING
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones_count" {
  description = "Number of AZs"
  type        = number
  default     = 3
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks for public access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "route53_zone_arns" {
  description = "Route53 zone ARNs"
  type        = list(string)
  default     = []
}

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM NODE GROUP
# ─────────────────────────────────────────────────────────────────────────────

variable "system_node_instance_types" {
  description = "System node instance types"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "system_node_min_size" {
  description = "System node minimum size"
  type        = number
  default     = 1
}

variable "system_node_max_size" {
  description = "System node maximum size"
  type        = number
  default     = 5
}

variable "system_node_desired_size" {
  description = "System node desired size"
  type        = number
  default     = 2
}

variable "system_node_disk_size" {
  description = "System node disk size"
  type        = number
  default     = 50
}

# ─────────────────────────────────────────────────────────────────────────────
# APPLICATION NODE GROUP
# ─────────────────────────────────────────────────────────────────────────────

variable "app_node_instance_types" {
  description = "Application node instance types"
  type        = list(string)
  default     = ["m5.large", "m5a.large"]
}

variable "app_node_capacity_type" {
  description = "Application node capacity type"
  type        = string
  default     = "ON_DEMAND"
}

variable "app_node_min_size" {
  description = "Application node minimum size"
  type        = number
  default     = 1
}

variable "app_node_max_size" {
  description = "Application node maximum size"
  type        = number
  default     = 10
}

variable "app_node_desired_size" {
  description = "Application node desired size"
  type        = number
  default     = 3
}

variable "app_node_disk_size" {
  description = "Application node disk size"
  type        = number
  default     = 100
}

variable "app_node_on_demand_base" {
  description = "On-demand base capacity"
  type        = number
  default     = 1
}

variable "app_node_on_demand_percentage" {
  description = "On-demand percentage above base"
  type        = number
  default     = 100
}

# ─────────────────────────────────────────────────────────────────────────────
# SPOT NODE GROUP
# ─────────────────────────────────────────────────────────────────────────────

variable "spot_node_instance_types" {
  description = "Spot node instance types"
  type        = list(string)
  default     = ["m5.large", "m5a.large", "m4.large"]
}

variable "spot_node_min_size" {
  description = "Spot node minimum size"
  type        = number
  default     = 0
}

variable "spot_node_max_size" {
  description = "Spot node maximum size"
  type        = number
  default     = 5
}

variable "spot_node_desired_size" {
  description = "Spot node desired size"
  type        = number
  default     = 1
}

variable "spot_node_disk_size" {
  description = "Spot node disk size"
  type        = number
  default     = 100
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY & ACCESS
# ─────────────────────────────────────────────────────────────────────────────

variable "cluster_admin_arns" {
  description = "Cluster admin ARNs"
  type        = list(string)
  default     = []
}

variable "cluster_developer_arns" {
  description = "Cluster developer ARNs"
  type        = list(string)
  default     = []
}

variable "developer_namespaces" {
  description = "Developer namespaces"
  type        = list(string)
  default     = ["default", "development", "staging"]
}

variable "kms_deletion_window" {
  description = "KMS key deletion window"
  type        = number
  default     = 7
}

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING & LOGGING
# ─────────────────────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = "Log retention days"
  type        = number
  default     = 7
}

variable "enable_cluster_logging" {
  description = "Enable cluster logging"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "Cluster log types"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

# ─────────────────────────────────────────────────────────────────────────────
# ADD-ONS
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable External DNS"
  type        = bool
  default     = false
}

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Enable Karpenter"
  type        = bool
  default     = false
}

variable "enable_metrics_server" {
  description = "Enable Metrics Server"
  type        = bool
  default     = true
}

variable "enable_prometheus" {
  description = "Enable Prometheus"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana"
  type        = bool
  default     = true
}

variable "enable_istio" {
  description = "Enable Istio"
  type        = bool
  default     = false
}

variable "enable_argocd" {
  description = "Enable ArgoCD"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# COST OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_cost_optimization" {
  description = "Enable cost optimization"
  type        = bool
  default     = true
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling"
  type        = bool
  default     = false
}

variable "business_hours_schedule" {
  description = "Business hours schedule"
  type        = string
  default     = "0 8 * * 1-5"
}

variable "after_hours_schedule" {
  description = "After hours schedule"
  type        = string
  default     = "0 20 * * 1-5"
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP & DR
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_backup" {
  description = "Enable backup"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Backup schedule"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_retention_days" {
  description = "Backup retention days"
  type        = number
  default     = 7
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup"
  type        = bool
  default     = false
}

variable "backup_regions" {
  description = "Backup regions"
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
  description = "Pod Security Standard level"
  type        = string
  default     = "baseline"
}

variable "enable_network_policies" {
  description = "Enable network policies"
  type        = bool
  default     = true
}

variable "enable_image_scanning" {
  description = "Enable image scanning"
  type        = bool
  default     = true
}

variable "enable_admission_controllers" {
  description = "Enable admission controllers"
  type        = bool
  default     = true
}

variable "enable_secrets_encryption" {
  description = "Enable secrets encryption"
  type        = bool
  default     = true
}

variable "enable_audit_logging" {
  description = "Enable audit logging"
  type        = bool
  default     = true
}
