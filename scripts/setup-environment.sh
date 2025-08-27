#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════
# ENTERPRISE EKS CLUSTER SETUP SCRIPT
# ═══════════════════════════════════════════════════════════════════════════
# This script sets up the complete development environment for EKS cluster
# automation, including all necessary tools, dependencies, and configurations.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get OS type
get_os() {
    case "$(uname -s)" in
        Darwin*)    echo "darwin" ;;
        Linux*)     echo "linux" ;;
        CYGWIN*)    echo "windows" ;;
        MINGW*)     echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

# Function to get architecture
get_arch() {
    case "$(uname -m)" in
        x86_64*)    echo "amd64" ;;
        arm64*)     echo "arm64" ;;
        aarch64*)   echo "arm64" ;;
        *)          echo "amd64" ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log_section "CHECKING PREREQUISITES"
    
    # Check for required commands
    local required_commands=("curl" "wget" "unzip" "git")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install the missing commands and run this script again."
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

# Install AWS CLI v2
install_aws_cli() {
    log_section "INSTALLING AWS CLI V2"
    
    if command_exists "aws"; then
        local aws_version=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
        if [[ "$aws_version" =~ ^2\. ]]; then
            log_success "AWS CLI v2 already installed: $aws_version"
            return
        else
            log_warning "AWS CLI v1 detected. Installing v2..."
        fi
    fi
    
    local os=$(get_os)
    local arch=$(get_arch)
    
    case "$os" in
        "linux")
            curl -LO "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
            unzip -q awscli-exe-linux-x86_64.zip
            sudo ./aws/install --update
            rm -rf aws awscli-exe-linux-x86_64.zip
            ;;
        "darwin")
            curl -LO "https://awscli.amazonaws.com/AWSCLIV2.pkg"
            sudo installer -pkg AWSCLIV2.pkg -target /
            rm AWSCLIV2.pkg
            ;;
        "windows")
            log_warning "Please install AWS CLI v2 manually from: https://awscli.amazonaws.com/AWSCLIV2.msi"
            ;;
        *)
            log_error "Unsupported operating system: $os"
            exit 1
            ;;
    esac
    
    log_success "AWS CLI v2 installed successfully"
}

# Install Terraform
install_terraform() {
    log_section "INSTALLING TERRAFORM"
    
    local desired_version="1.8.0"
    
    if command_exists "terraform"; then
        local current_version=$(terraform version -json | jq -r '.terraform_version')
        if [[ "$current_version" == "$desired_version" ]]; then
            log_success "Terraform $desired_version already installed"
            return
        fi
    fi
    
    local os=$(get_os)
    local arch=$(get_arch)
    
    log_info "Installing Terraform $desired_version for $os/$arch"
    
    # Download and install Terraform
    curl -LO "https://releases.hashicorp.com/terraform/${desired_version}/terraform_${desired_version}_${os}_${arch}.zip"
    unzip -q "terraform_${desired_version}_${os}_${arch}.zip"
    
    # Install based on OS
    case "$os" in
        "linux"|"darwin")
            sudo mv terraform /usr/local/bin/
            sudo chmod +x /usr/local/bin/terraform
            ;;
        "windows")
            mkdir -p "$HOME/bin"
            mv terraform.exe "$HOME/bin/"
            ;;
    esac
    
    rm -f "terraform_${desired_version}_${os}_${arch}.zip"
    
    log_success "Terraform $desired_version installed successfully"
}

# Install kubectl
install_kubectl() {
    log_section "INSTALLING KUBECTL"
    
    local desired_version="1.28.9"
    
    if command_exists "kubectl"; then
        local current_version=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion' | sed 's/v//')
        if [[ "$current_version" == "$desired_version" ]]; then
            log_success "kubectl $desired_version already installed"
            return
        fi
    fi
    
    local os=$(get_os)
    local arch=$(get_arch)
    
    log_info "Installing kubectl $desired_version for $os/$arch"
    
    # Download kubectl
    case "$os" in
        "linux")
            curl -LO "https://dl.k8s.io/release/v${desired_version}/bin/linux/${arch}/kubectl"
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
            rm kubectl
            ;;
        "darwin")
            curl -LO "https://dl.k8s.io/release/v${desired_version}/bin/darwin/${arch}/kubectl"
            sudo install -o root -g wheel -m 0755 kubectl /usr/local/bin/kubectl
            rm kubectl
            ;;
        "windows")
            curl -LO "https://dl.k8s.io/release/v${desired_version}/bin/windows/${arch}/kubectl.exe"
            mkdir -p "$HOME/bin"
            mv kubectl.exe "$HOME/bin/"
            ;;
    esac
    
    log_success "kubectl $desired_version installed successfully"
}

# Install Helm
install_helm() {
    log_section "INSTALLING HELM"
    
    local desired_version="3.12.3"
    
    if command_exists "helm"; then
        local current_version=$(helm version --template='{{.Version}}' | sed 's/v//')
        if [[ "$current_version" == "$desired_version" ]]; then
            log_success "Helm $desired_version already installed"
            return
        fi
    fi
    
    log_info "Installing Helm $desired_version"
    
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    DESIRED_VERSION=v${desired_version} ./get_helm.sh
    rm get_helm.sh
    
    log_success "Helm $desired_version installed successfully"
}

# Install additional tools
install_additional_tools() {
    log_section "INSTALLING ADDITIONAL TOOLS"
    
    # Install jq if not present
    if ! command_exists "jq"; then
        log_info "Installing jq..."
        case "$(get_os)" in
            "linux")
                if command_exists "apt-get"; then
                    sudo apt-get update && sudo apt-get install -y jq
                elif command_exists "yum"; then
                    sudo yum install -y jq
                elif command_exists "dnf"; then
                    sudo dnf install -y jq
                fi
                ;;
            "darwin")
                if command_exists "brew"; then
                    brew install jq
                else
                    log_warning "Homebrew not found. Please install jq manually."
                fi
                ;;
        esac
        log_success "jq installed"
    fi
    
    # Install yq
    if ! command_exists "yq"; then
        log_info "Installing yq..."
        local os=$(get_os)
        local arch=$(get_arch)
        
        curl -LO "https://github.com/mikefarah/yq/releases/latest/download/yq_${os}_${arch}"
        case "$os" in
            "linux"|"darwin")
                sudo mv "yq_${os}_${arch}" /usr/local/bin/yq
                sudo chmod +x /usr/local/bin/yq
                ;;
            "windows")
                mkdir -p "$HOME/bin"
                mv "yq_${os}_${arch}" "$HOME/bin/yq.exe"
                ;;
        esac
        log_success "yq installed"
    fi
    
    # Install gh (GitHub CLI)
    if ! command_exists "gh"; then
        log_info "Installing GitHub CLI..."
        case "$(get_os)" in
            "linux")
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt update && sudo apt install gh
                ;;
            "darwin")
                if command_exists "brew"; then
                    brew install gh
                fi
                ;;
        esac
        log_success "GitHub CLI installed"
    fi
    
    # Install kubectx and kubens
    if ! command_exists "kubectx"; then
        log_info "Installing kubectx and kubens..."
        case "$(get_os)" in
            "linux"|"darwin")
                curl -LO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx
                curl -LO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens
                sudo mv kubectx kubens /usr/local/bin/
                sudo chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens
                ;;
        esac
        log_success "kubectx and kubens installed"
    fi
    
    # Install k9s
    if ! command_exists "k9s"; then
        log_info "Installing k9s..."
        local os=$(get_os)
        local arch=$(get_arch)
        
        case "$os" in
            "linux")
                curl -sL "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${arch}.tar.gz" | tar xz
                sudo mv k9s /usr/local/bin/
                ;;
            "darwin")
                curl -sL "https://github.com/derailed/k9s/releases/latest/download/k9s_Darwin_${arch}.tar.gz" | tar xz
                sudo mv k9s /usr/local/bin/
                ;;
        esac
        log_success "k9s installed"
    fi
}

# Setup Python environment
setup_python_environment() {
    log_section "SETTING UP PYTHON ENVIRONMENT"
    
    # Check if Python 3.8+ is available
    if ! command_exists "python3"; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi
    
    local python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    log_info "Python version: $python_version"
    
    # Create virtual environment for testing
    if [ ! -d "venv" ]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv venv
    fi
    
    log_info "Activating virtual environment..."
    source venv/bin/activate
    
    log_info "Installing Python dependencies..."
    pip install --upgrade pip
    pip install -r tests/requirements.txt
    
    log_success "Python environment setup complete"
}

# Configure AWS
configure_aws() {
    log_section "AWS CONFIGURATION"
    
    if [ ! -f "$HOME/.aws/credentials" ] && [ ! -f "$HOME/.aws/config" ]; then
        log_warning "AWS credentials not configured"
        log_info "Please run 'aws configure' to set up your credentials"
        log_info "Or set up AWS SSO with 'aws configure sso'"
    else
        log_success "AWS credentials are configured"
    fi
    
    # Test AWS connectivity
    if aws sts get-caller-identity >/dev/null 2>&1; then
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local user_arn=$(aws sts get-caller-identity --query Arn --output text)
        log_success "AWS connectivity verified"
        log_info "Account ID: $account_id"
        log_info "User/Role: $user_arn"
    else
        log_warning "Cannot verify AWS connectivity. Please check your credentials."
    fi
}

# Setup Terraform backend
setup_terraform_backend() {
    log_section "TERRAFORM BACKEND SETUP"
    
    log_info "Setting up Terraform S3 backend..."
    
    # Read AWS region from AWS config or default to us-west-2
    local aws_region=$(aws configure get region 2>/dev/null || echo "us-west-2")
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    
    if [ "$account_id" = "unknown" ]; then
        log_warning "Cannot determine AWS account ID. Please ensure AWS credentials are configured."
        return
    fi
    
    # Generate unique bucket name
    local bucket_name="eks-terraform-state-${account_id}-${aws_region}"
    local dynamodb_table="terraform-state-locks"
    
    log_info "Bucket name: $bucket_name"
    log_info "DynamoDB table: $dynamodb_table"
    
    # Create S3 bucket for Terraform state
    if ! aws s3 ls "s3://$bucket_name" >/dev/null 2>&1; then
        log_info "Creating S3 bucket for Terraform state..."
        
        if [ "$aws_region" = "us-east-1" ]; then
            aws s3 mb "s3://$bucket_name"
        else
            aws s3 mb "s3://$bucket_name" --region "$aws_region"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning --bucket "$bucket_name" --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'
        
        # Block public access
        aws s3api put-public-access-block --bucket "$bucket_name" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        log_success "S3 bucket created and configured"
    else
        log_success "S3 bucket already exists"
    fi
    
    # Create DynamoDB table for state locking
    if ! aws dynamodb describe-table --table-name "$dynamodb_table" >/dev/null 2>&1; then
        log_info "Creating DynamoDB table for state locking..."
        
        aws dynamodb create-table \
            --table-name "$dynamodb_table" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$aws_region"
        
        log_info "Waiting for DynamoDB table to be active..."
        aws dynamodb wait table-exists --table-name "$dynamodb_table" --region "$aws_region"
        
        log_success "DynamoDB table created"
    else
        log_success "DynamoDB table already exists"
    fi
    
    # Update Terraform backend configuration
    local backend_config="terraform/environments/dev/backend.conf"
    mkdir -p "$(dirname "$backend_config")"
    
    cat > "$backend_config" << EOF
bucket         = "$bucket_name"
key            = "eks/dev/terraform.tfstate"
region         = "$aws_region"
encrypt        = true
dynamodb_table = "$dynamodb_table"
EOF
    
    log_success "Terraform backend configuration updated"
    log_info "Backend config file: $backend_config"
}

# Create example configuration files
create_example_configs() {
    log_section "CREATING EXAMPLE CONFIGURATIONS"
    
    # Create example tfvars if not exists
    local example_tfvars="terraform/environments/dev/dev.tfvars.example"
    if [ ! -f "$example_tfvars" ]; then
        cp "terraform/environments/dev/dev.tfvars" "$example_tfvars"
        log_info "Created example tfvars: $example_tfvars"
    fi
    
    # Create GitHub secrets template
    cat > ".github/secrets-template.md" << 'EOF'
# GitHub Secrets Configuration

Configure the following secrets in your GitHub repository:

## AWS Access
- `AWS_ROLE_DEV`: IAM role ARN for development environment
- `AWS_ROLE_STAGING`: IAM role ARN for staging environment  
- `AWS_ROLE_PROD`: IAM role ARN for production environment

## Terraform State
- `TF_STATE_BUCKET_DEV`: S3 bucket for dev Terraform state
- `TF_STATE_BUCKET_STAGING`: S3 bucket for staging Terraform state
- `TF_STATE_BUCKET_PROD`: S3 bucket for production Terraform state

## Cost Management
- `INFRACOST_API_KEY`: API key for Infracost cost estimation

## Notifications
- `SLACK_WEBHOOK`: Slack webhook URL for notifications
- `TEAMS_WEBHOOK`: Microsoft Teams webhook URL for notifications

## Example Values
```bash
# Development
AWS_ROLE_DEV="arn:aws:iam::123456789012:role/GitHubActionsRole"
TF_STATE_BUCKET_DEV="eks-terraform-state-123456789012-us-west-2"

# Staging  
AWS_ROLE_STAGING="arn:aws:iam::123456789012:role/GitHubActionsRole"
TF_STATE_BUCKET_STAGING="eks-terraform-state-123456789012-us-west-2"

# Production
AWS_ROLE_PROD="arn:aws:iam::987654321098:role/GitHubActionsRole"
TF_STATE_BUCKET_PROD="eks-terraform-state-987654321098-us-west-2"
```
EOF
    
    log_info "Created GitHub secrets template: .github/secrets-template.md"
}

# Main setup function
main() {
    log_section "EKS ENTERPRISE CLUSTER SETUP"
    log_info "This script will set up your development environment for EKS cluster automation"
    log_info "$(date)"
    
    # Run setup steps
    check_prerequisites
    install_aws_cli
    install_terraform
    install_kubectl
    install_helm
    install_additional_tools
    setup_python_environment
    configure_aws
    setup_terraform_backend
    create_example_configs
    
    log_section "SETUP COMPLETE"
    log_success "Environment setup completed successfully!"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Review and customize terraform/environments/dev/dev.tfvars"
    log_info "2. Configure GitHub secrets using .github/secrets-template.md"
    log_info "3. Initialize Terraform: cd terraform/environments/dev && terraform init"
    log_info "4. Run tests: source venv/bin/activate && python -m pytest tests/"
    log_info "5. Deploy infrastructure: terraform plan -var-file=dev.tfvars"
    log_info ""
    log_info "Documentation: docs/deployment-guide.md"
    log_info "Support: Create an issue in the GitHub repository"
    
    echo ""
}

# Run main function
main "$@"
