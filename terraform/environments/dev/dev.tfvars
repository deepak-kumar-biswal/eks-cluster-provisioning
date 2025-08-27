# ═══════════════════════════════════════════════════════════════════════════
# DEVELOPMENT ENVIRONMENT CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
# This file contains the actual values for the development environment.
# Customize these values according to your requirements.

# ─────────────────────────────────────────────────────────────────────────────
# BASIC CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

aws_region              = "us-west-2"
project_name            = "eks-enterprise"
environment             = "dev"
owner                   = "DevOps Team"
cost_center             = "engineering-dev"
compliance_standard     = "SOC2"

# ─────────────────────────────────────────────────────────────────────────────
# CLUSTER CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

kubernetes_version = "1.28"

# ─────────────────────────────────────────────────────────────────────────────
# NETWORKING CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

vpc_cidr                             = "10.0.0.0/16"
availability_zones_count             = 3
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]  # Restrict this in production!

# Route53 zones for External DNS (add your hosted zone ARNs)
route53_zone_arns = []

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM NODE GROUP - For critical system components
# ─────────────────────────────────────────────────────────────────────────────

system_node_instance_types = ["t3.medium", "t3a.medium"]
system_node_min_size       = 1
system_node_max_size       = 3
system_node_desired_size   = 2
system_node_disk_size      = 50

# ─────────────────────────────────────────────────────────────────────────────
# APPLICATION NODE GROUP - For regular workloads
# ─────────────────────────────────────────────────────────────────────────────

app_node_instance_types       = ["m5.large", "m5a.large"]
app_node_capacity_type        = "ON_DEMAND"
app_node_min_size            = 1
app_node_max_size            = 10
app_node_desired_size        = 2
app_node_disk_size           = 100
app_node_on_demand_base      = 1
app_node_on_demand_percentage = 100

# ─────────────────────────────────────────────────────────────────────────────
# SPOT NODE GROUP - For cost-effective batch workloads
# ─────────────────────────────────────────────────────────────────────────────

spot_node_instance_types = ["m5.large", "m5a.large", "m4.large", "c5.large", "c5a.large"]
spot_node_min_size       = 0
spot_node_max_size       = 5
spot_node_desired_size   = 1
spot_node_disk_size      = 100

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY & ACCESS CONTROL
# ─────────────────────────────────────────────────────────────────────────────

# Add your IAM user/role ARNs here
cluster_admin_arns = [
  # Example: "arn:aws:iam::123456789012:user/admin-user",
  # Example: "arn:aws:iam::123456789012:role/DevOpsAdminRole"
]

cluster_developer_arns = [
  # Example: "arn:aws:iam::123456789012:user/developer-user",
  # Example: "arn:aws:iam::123456789012:role/DeveloperRole"
]

developer_namespaces = ["default", "development", "staging", "testing"]
kms_deletion_window  = 7  # Shorter window for dev environment

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING & LOGGING - Optimized for development
# ─────────────────────────────────────────────────────────────────────────────

log_retention_days    = 7   # Shorter retention for cost optimization
enable_cluster_logging = true
cluster_log_types     = ["api", "audit", "authenticator"]  # Essential logs only

# ─────────────────────────────────────────────────────────────────────────────
# ADD-ONS CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

# Core add-ons
enable_aws_load_balancer_controller = true
enable_external_dns                 = false  # Enable if you have Route53 zones
enable_cluster_autoscaler           = true
enable_karpenter                    = false  # Can be enabled later for advanced scaling
enable_metrics_server               = true

# Monitoring stack
enable_prometheus = true
enable_grafana    = true

# Service mesh (disabled for simplicity in dev)
enable_istio = false

# GitOps
enable_argocd = true

# ─────────────────────────────────────────────────────────────────────────────
# COST OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

enable_cost_optimization = true
enable_scheduled_scaling  = false  # Can be enabled for predictable workloads

# Business hours (8 AM - 8 PM, Monday to Friday)
business_hours_schedule = "0 8 * * 1-5"
after_hours_schedule    = "0 20 * * 1-5"

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP & DISASTER RECOVERY
# ─────────────────────────────────────────────────────────────────────────────

enable_backup              = true
backup_schedule            = "0 2 * * *"  # Daily at 2 AM
backup_retention_days      = 7
enable_cross_region_backup = false  # Disable for cost optimization in dev
backup_regions             = ["us-east-1"]

# ─────────────────────────────────────────────────────────────────────────────
# ADVANCED SECURITY FEATURES
# ─────────────────────────────────────────────────────────────────────────────

enable_pod_security_standards = true
pod_security_standard_level   = "baseline"  # Less restrictive for dev
enable_network_policies       = true
enable_image_scanning         = true
enable_admission_controllers  = true
enable_secrets_encryption     = true
enable_audit_logging          = true
