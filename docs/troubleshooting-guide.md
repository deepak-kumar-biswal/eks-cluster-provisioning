# 🔧 Troubleshooting Guide for Enterprise EKS

## Overview

This comprehensive troubleshooting guide provides solutions for common issues encountered when deploying and managing Amazon EKS clusters at enterprise scale. It covers infrastructure, application, security, and operational challenges with step-by-step resolution procedures.

## 🏗️ Infrastructure Issues

### EKS Cluster Creation Failures

#### Issue: Cluster Creation Timeout
```
Error: operation error EKS: CreateCluster, timeout, context deadline exceeded
```

**Diagnosis Steps:**
```bash
# Check AWS service status
aws health describe-events --filter services=EKS --region us-west-2

# Verify IAM permissions
aws sts get-caller-identity
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:role/EKS-ServiceRole \
  --action-names eks:CreateCluster \
  --resource-arns "*"

# Check quota limits
aws service-quotas get-service-quota \
  --service-code eks \
  --quota-code L-1194D53C  # Clusters per region
```

**Solutions:**
1. **Increase Timeout Values:**
```hcl
resource "aws_eks_cluster" "main" {
  # ... other configuration ...
  
  timeouts {
    create = "30m"
    update = "60m"
    delete = "15m"
  }
}
```

2. **Verify Network Configuration:**
```bash
# Check VPC and subnet configuration
aws ec2 describe-vpcs --vpc-ids vpc-12345678
aws ec2 describe-subnets --subnet-ids subnet-12345678 subnet-87654321

# Verify internet gateway for public subnets
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-12345678"
```

#### Issue: Insufficient IP Addresses
```
Error: CreateNodegroup: InvalidParameterException: Insufficient IP addresses in subnet
```

**Diagnosis Steps:**
```bash
# Check available IP addresses in subnets
aws ec2 describe-subnets --subnet-ids subnet-12345678 \
  --query 'Subnets[0].{AvailableIpAddressCount:AvailableIpAddressCount,CidrBlock:CidrBlock}'

# Calculate required IPs
echo "Required IPs: (desired_capacity * max_pods_per_node) + buffer"
echo "Example: (10 nodes * 58 pods) + 100 buffer = 680 IPs minimum"
```

**Solutions:**
1. **Expand Subnet CIDR Blocks:**
```hcl
# Use larger subnet CIDR blocks
variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  default = {
    0 = "10.0.32.0/19"   # 8,192 IP addresses
    1 = "10.0.64.0/19"   # 8,192 IP addresses
    2 = "10.0.96.0/19"   # 8,192 IP addresses
  }
}
```

2. **Optimize Pod Density:**
```hcl
# Configure custom networking for pod density optimization
resource "aws_eks_addon" "aws_load_balancer_controller" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-load-balancer-controller"
  
  configuration_values = jsonencode({
    resources = {
      limits = {
        cpu    = "200m"
        memory = "500Mi"
      }
      requests = {
        cpu    = "100m"
        memory = "200Mi"
      }
    }
    # Enable prefix delegation for more pods per node
    enablePrefixDelegation = true
  })
}
```

### Node Group Issues

#### Issue: Nodes Not Joining Cluster
```
Error: Node never joined cluster (bootstrapping timeout)
```

**Diagnosis Steps:**
```bash
# Check node status
kubectl get nodes

# Examine node logs
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo journalctl -u kubelet.service -f"]' \
  --targets "Key=tag:aws:autoscaling:groupName,Values=eks-node-group"

# Verify security group rules
aws ec2 describe-security-groups \
  --group-ids sg-12345678 \
  --query 'SecurityGroups[0].IpPermissions'
```

**Solutions:**
1. **Fix Security Group Configuration:**
```hcl
# Node group security group rules
resource "aws_security_group_rule" "node_ingress_cluster" {
  description              = "Allow cluster to communicate with nodes"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  type                     = "ingress"
}

resource "aws_security_group_rule" "node_ingress_self" {
  description       = "Allow nodes to communicate with each other"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.nodes.id
  self              = true
  type              = "ingress"
}
```

2. **Update User Data Script:**
```bash
#!/bin/bash
set -o xtrace

# Enhanced bootstrap script with error handling
/etc/eks/bootstrap.sh ${cluster_name} \
  --b64-cluster-ca ${cluster_ca} \
  --apiserver-endpoint ${cluster_endpoint} \
  --container-runtime containerd \
  --kubelet-extra-args '--node-labels=nodegroup=${node_group_name},lifecycle=on-demand'

# Wait for kubelet to start
while ! systemctl is-active --quiet kubelet; do
  echo "Waiting for kubelet to start..."
  sleep 10
done

echo "Node bootstrap completed successfully"
```

#### Issue: Spot Instance Interruptions
```
Warning: Node will be terminated in 2 minutes due to spot interruption
```

**Diagnosis Steps:**
```bash
# Monitor spot instance interruption warnings
kubectl get events --field-selector reason=SpotInterruption

# Check node conditions
kubectl describe node NODE_NAME | grep -A 10 "Conditions:"
```

**Solutions:**
1. **Implement AWS Node Termination Handler:**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: aws-node-termination-handler
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: aws-node-termination-handler
  template:
    metadata:
      labels:
        app: aws-node-termination-handler
    spec:
      serviceAccountName: aws-node-termination-handler
      hostNetwork: true
      containers:
      - name: aws-node-termination-handler
        image: public.ecr.aws/aws-ec2/aws-node-termination-handler:v1.19.0
        args:
        - --node-name=$(NODE_NAME)
        - --namespace=kube-system
        - --taint-node=true
        - --cordon-only=false
        - --metadata-tries=10
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
```

2. **Configure Mixed Instance Types:**
```hcl
resource "aws_eks_node_group" "spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "spot-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  capacity_type = "SPOT"
  
  # Use multiple instance types for better availability
  instance_types = [
    "m5.large",
    "m5.xlarge", 
    "m5a.large",
    "m5a.xlarge",
    "m4.large",
    "m4.xlarge"
  ]

  scaling_config {
    desired_size = 2
    max_size     = 10
    min_size     = 0
  }
}
```

## 🚀 Application Deployment Issues

### Pod Scheduling Failures

#### Issue: Pod Stuck in Pending State
```
Status: Pending
Reason: Insufficient cpu, Insufficient memory
```

**Diagnosis Steps:**
```bash
# Check pod events
kubectl describe pod POD_NAME -n NAMESPACE

# Check node resources
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check resource requests vs available
kubectl get pods --all-namespaces -o custom-columns='NAME:.metadata.name,NAMESPACE:.metadata.namespace,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'
```

**Solutions:**
1. **Adjust Resource Requests:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-optimized-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: nginx:1.21
        resources:
          # Use realistic resource requests
          requests:
            cpu: "100m"      # 0.1 CPU cores
            memory: "128Mi"   # 128 MiB
          limits:
            cpu: "500m"      # 0.5 CPU cores
            memory: "512Mi"   # 512 MiB
```

2. **Implement Cluster Autoscaler:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.21.3
        name: cluster-autoscaler
        command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/eks-cluster-name
        - --balance-similar-node-groups
        - --skip-nodes-with-system-pods=false
```

#### Issue: Pod Failing Due to Resource Limits
```
Status: OOMKilled
ExitCode: 137
```

**Diagnosis Steps:**
```bash
# Check pod resource usage
kubectl top pod POD_NAME -n NAMESPACE --containers

# Review pod logs for OOM patterns
kubectl logs POD_NAME -n NAMESPACE --previous

# Check memory usage patterns
kubectl exec -it POD_NAME -n NAMESPACE -- cat /sys/fs/cgroup/memory/memory.usage_in_bytes
```

**Solutions:**
1. **Optimize Memory Configuration:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-optimized-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        resources:
          requests:
            memory: "256Mi"
          limits:
            memory: "1Gi"     # Increased limit
        # Add JVM memory settings for Java apps
        env:
        - name: JAVA_OPTS
          value: "-Xmx800m -Xms256m -XX:+UseG1GC"
```

2. **Implement Vertical Pod Autoscaler:**
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: app-vpa
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: app
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 2
        memory: 2Gi
```

### Image Pull Failures

#### Issue: ImagePullBackOff
```
Status: ImagePullBackOff
Message: Failed to pull image "myregistry/app:latest": pull access denied
```

**Diagnosis Steps:**
```bash
# Check image pull secrets
kubectl get secrets -n NAMESPACE

# Test image pull manually
docker pull myregistry/app:latest

# Check node's ability to pull images
kubectl debug node/NODE_NAME -it --image=alpine
```

**Solutions:**
1. **Configure Image Pull Secrets:**
```bash
# Create Docker registry secret
kubectl create secret docker-registry myregistry-secret \
  --docker-server=myregistry.com \
  --docker-username=USERNAME \
  --docker-password=PASSWORD \
  --docker-email=EMAIL \
  -n NAMESPACE
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      imagePullSecrets:
      - name: myregistry-secret
      containers:
      - name: app
        image: myregistry/app:v1.2.3  # Use specific tags, not 'latest'
```

2. **Use ECR with IRSA:**
```yaml
# Service account with ECR access
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/ECR-Access-Role
```

## 🌐 Networking Issues

### Service Connectivity Problems

#### Issue: Service Not Accessible
```
Error: connection timed out or connection refused
```

**Diagnosis Steps:**
```bash
# Check service and endpoints
kubectl get svc,ep -n NAMESPACE

# Test connectivity from within cluster
kubectl run test-pod --image=busybox --restart=Never --rm -it -- sh
# Inside pod: wget -qO- http://SERVICE_NAME.NAMESPACE.svc.cluster.local

# Check network policies
kubectl get networkpolicies -n NAMESPACE

# Verify DNS resolution
kubectl exec test-pod -- nslookup SERVICE_NAME.NAMESPACE.svc.cluster.local
```

**Solutions:**
1. **Fix Service Configuration:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
  namespace: production
spec:
  # Ensure selector matches pod labels
  selector:
    app: myapp
    version: v1
  ports:
  - port: 80
    targetPort: 8080  # Must match container port
    protocol: TCP
  type: ClusterIP
```

2. **Configure Network Policies:**
```yaml
# Allow ingress to application
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-ingress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-system
    - podSelector:
        matchLabels:
          app: nginx-ingress
    ports:
    - protocol: TCP
      port: 8080
```

#### Issue: LoadBalancer Service Not Getting External IP
```
External-IP: <pending>
```

**Diagnosis Steps:**
```bash
# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check service events
kubectl describe svc LOAD_BALANCER_SERVICE -n NAMESPACE

# Verify controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Solutions:**
1. **Install AWS Load Balancer Controller:**
```bash
# Create service account with IRSA
eksctl create iamserviceaccount \
  --cluster=my-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::ACCOUNT:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# Install controller via Helm
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

2. **Configure Service with Annotations:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-loadbalancer
  namespace: production
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
```

### DNS Resolution Issues

#### Issue: Pod Cannot Resolve Service Names
```
Error: nslookup: can't resolve 'service-name.namespace.svc.cluster.local'
```

**Diagnosis Steps:**
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS configuration
kubectl get configmap coredns -n kube-system -o yaml

# Test DNS from pod
kubectl exec test-pod -- nslookup kubernetes.default.svc.cluster.local
```

**Solutions:**
1. **Restart CoreDNS:**
```bash
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system
```

2. **Configure Custom DNS:**
```yaml
# Custom CoreDNS configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
    # Custom domain forwarding
    company.local:53 {
        forward . 10.0.0.10 10.0.0.11
    }
```

## 🔐 Security and RBAC Issues

### Authentication Failures

#### Issue: User Cannot Access Cluster
```
Error: You must be logged in to the server (Unauthorized)
```

**Diagnosis Steps:**
```bash
# Check current context
kubectl config current-context

# Verify AWS credentials
aws sts get-caller-identity

# Check aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml

# Test with different user/role
aws sts assume-role --role-arn arn:aws:iam::ACCOUNT:role/EKS-Admin \
  --role-session-name test-session
```

**Solutions:**
1. **Update aws-auth ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapUsers: |
    - userarn: arn:aws:iam::ACCOUNT:user/admin-user
      username: admin-user
      groups:
        - system:masters
    - userarn: arn:aws:iam::ACCOUNT:user/developer-user
      username: developer-user
      groups:
        - developers
  mapRoles: |
    - rolearn: arn:aws:iam::ACCOUNT:role/EKS-Admin-Role
      username: eks-admin
      groups:
        - system:masters
    - rolearn: arn:aws:iam::ACCOUNT:role/EKS-Developer-Role
      username: eks-developer
      groups:
        - developers
```

2. **Create Proper RBAC:**
```yaml
# Developer ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developers-binding
subjects:
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

### Permission Denied Issues

#### Issue: Service Account Cannot Perform Actions
```
Error: forbidden: User "system:serviceaccount:default:app-sa" cannot create resource "pods"
```

**Diagnosis Steps:**
```bash
# Check service account
kubectl get sa app-sa -n default

# Check associated roles
kubectl describe sa app-sa -n default

# Test permissions
kubectl auth can-i create pods --as=system:serviceaccount:default:app-sa
```

**Solutions:**
1. **Create Service Account with Proper RBAC:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: default

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: app-role
rules:
- apiGroups: [""]
  resources: ["pods", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: app-sa
  namespace: default
roleRef:
  kind: Role
  name: app-role
  apiGroup: rbac.authorization.k8s.io
```

## 📊 Monitoring and Logging Issues

### Metrics Collection Problems

#### Issue: Prometheus Cannot Scrape Metrics
```
Error: context deadline exceeded while scraping target
```

**Diagnosis Steps:**
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Visit http://localhost:9090/targets

# Check network policies
kubectl get networkpolicies -n monitoring

# Test connectivity
kubectl exec -n monitoring prometheus-pod -- wget -qO- http://app-service:8080/metrics
```

**Solutions:**
1. **Configure Service Monitor:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
    timeout: 10s
```

2. **Add Prometheus Annotations:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  # ... service spec
```

### Log Aggregation Issues

#### Issue: Logs Not Appearing in CloudWatch
```
Error: No log streams found for log group
```

**Diagnosis Steps:**
```bash
# Check Fluent Bit DaemonSet
kubectl get daemonset aws-for-fluent-bit -n amazon-cloudwatch

# Check Fluent Bit logs
kubectl logs -n amazon-cloudwatch daemonset/aws-for-fluent-bit

# Verify IAM permissions
aws logs describe-log-groups --log-group-name-prefix "/aws/containerinsights/"
```

**Solutions:**
1. **Install AWS for Fluent Bit:**
```bash
# Create namespace
kubectl create namespace amazon-cloudwatch

# Apply Fluent Bit configuration
curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml | \
sed 's/{{cluster_name}}/my-cluster/g' | \
kubectl apply -f -
```

2. **Configure Custom Log Groups:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: amazon-cloudwatch
data:
  fluent-bit.conf: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        multiline.parser  docker, cri
        Tag               kube.*
        Refresh_Interval  5
        Mem_Buf_Limit     50MB
        Skip_Long_Lines   On
        Skip_Empty_Lines  On

    [OUTPUT]
        Name                cloudwatch_logs
        Match               kube.*
        region              us-west-2
        log_group_name      /aws/containerinsights/my-cluster/application
        log_stream_prefix   ${hostname}-
        auto_create_group   true
```

## 🔄 GitOps and CI/CD Issues

### ArgoCD Sync Failures

#### Issue: Application Stuck in Progressing State
```
Status: Progressing
Message: one or more objects failed to apply
```

**Diagnosis Steps:**
```bash
# Check ArgoCD application status
argocd app get APPNAME

# Review sync logs
argocd app logs APPNAME

# Check application events
kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'
```

**Solutions:**
1. **Fix Resource Conflicts:**
```bash
# Refresh application
argocd app sync APPNAME --force

# Delete stuck resources
kubectl delete pod PODNAME -n NAMESPACE --force --grace-period=0

# Reset application state
argocd app sync APPNAME --replace
```

2. **Configure Sync Policy:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - PruneLast=true
    - RespectIgnoreDifferences=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m0s
```

### GitHub Actions Pipeline Failures

#### Issue: Terraform Plan/Apply Failures
```
Error: Error acquiring the state lock
```

**Diagnosis Steps:**
```bash
# Check Terraform state lock
terraform force-unlock LOCK_ID

# Verify S3 backend configuration
aws s3 ls s3://terraform-state-bucket/

# Check DynamoDB lock table
aws dynamodb describe-table --table-name terraform-locks
```

**Solutions:**
1. **Implement Proper State Management:**
```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "eks/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    
    # Enable versioning for state recovery
    versioning = true
  }
}
```

2. **Add Retry Logic to Pipeline:**
```yaml
- name: Terraform Apply
  run: |
    # Retry logic for state lock conflicts
    for i in {1..3}; do
      terraform apply -auto-approve && break
      echo "Attempt $i failed, retrying in 30 seconds..."
      sleep 30
    done
```

## 🎯 Performance Issues

### High CPU/Memory Usage

#### Issue: Node Resource Exhaustion
```
Node Condition: MemoryPressure=True, DiskPressure=True
```

**Diagnosis Steps:**
```bash
# Check node resource usage
kubectl top nodes

# Identify resource-heavy pods
kubectl top pods --all-namespaces --sort-by=cpu
kubectl top pods --all-namespaces --sort-by=memory

# Check system resource usage
kubectl describe node NODE_NAME | grep -A 10 "Allocated resources"
```

**Solutions:**
1. **Implement Resource Quotas:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "4"
```

2. **Configure Horizontal Pod Autoscaler:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Storage Performance Issues

#### Issue: Slow PVC Mount Times
```
Warning: FailedMount: MountVolume.WaitForAttach failed
```

**Diagnosis Steps:**
```bash
# Check EBS CSI driver
kubectl get pods -n kube-system -l app=ebs-csi-controller

# Check volume attachment status
kubectl describe pvc PVC_NAME -n NAMESPACE

# Review EBS volume status
aws ec2 describe-volumes --volume-ids vol-12345678
```

**Solutions:**
1. **Optimize Storage Class:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "250"
  fsType: ext4
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

2. **Pre-provision Volumes:**
```bash
# Create volumes in advance for critical workloads
aws ec2 create-volume \
  --size 100 \
  --volume-type gp3 \
  --iops 3000 \
  --throughput 250 \
  --availability-zone us-west-2a \
  --encrypted
```

## 🚨 Emergency Procedures

### Cluster Recovery

#### Critical Node Failure
```bash
#!/bin/bash
# Emergency node recovery procedure

# 1. Cordon the failing node
kubectl cordon NODE_NAME

# 2. Drain the node safely
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data --force

# 3. Terminate the instance (will be replaced by ASG)
aws ec2 terminate-instances --instance-ids i-1234567890abcdef0

# 4. Monitor new node joining
kubectl get nodes -w

# 5. Verify pod rescheduling
kubectl get pods --all-namespaces -o wide | grep NODE_NAME
```

#### Control Plane Issues
```bash
# Check control plane health
aws eks describe-cluster --name CLUSTER_NAME --query 'cluster.status'

# Verify API server accessibility
kubectl get --raw='/healthz'

# Check cluster logs
aws logs filter-log-events \
  --log-group-name /aws/eks/CLUSTER_NAME/cluster \
  --start-time $(date -d '1 hour ago' +%s)000
```

### Disaster Recovery

#### Backup and Restore Procedures
```bash
#!/bin/bash
# Comprehensive backup script

# 1. Backup etcd (if using self-managed)
kubectl get all --all-namespaces -o yaml > cluster-backup.yaml

# 2. Backup persistent volumes
kubectl get pv,pvc --all-namespaces -o yaml > storage-backup.yaml

# 3. Backup configuration
kubectl get configmaps,secrets --all-namespaces -o yaml > config-backup.yaml

# 4. Upload to S3
aws s3 cp cluster-backup.yaml s3://disaster-recovery-bucket/$(date +%Y-%m-%d)/
aws s3 cp storage-backup.yaml s3://disaster-recovery-bucket/$(date +%Y-%m-%d)/
aws s3 cp config-backup.yaml s3://disaster-recovery-bucket/$(date +%Y-%m-%d)/
```

## 📋 Troubleshooting Checklist

### Pre-Deployment Checklist
- [ ] AWS credentials configured correctly
- [ ] Required IAM permissions granted
- [ ] VPC and subnet configuration validated
- [ ] Security groups configured properly
- [ ] KMS keys created and accessible
- [ ] Terraform state backend configured

### Post-Deployment Checklist
- [ ] All nodes joined the cluster successfully
- [ ] Core DNS is functioning
- [ ] Load balancer controller installed
- [ ] Cluster autoscaler operational
- [ ] Monitoring stack deployed and collecting metrics
- [ ] Logging configured and functioning
- [ ] Network policies applied
- [ ] RBAC configured correctly

### Ongoing Maintenance Checklist
- [ ] Regular security updates applied
- [ ] Resource usage monitored
- [ ] Backup procedures tested
- [ ] Disaster recovery plan validated
- [ ] Performance baselines established
- [ ] Alert thresholds configured appropriately

## 🔗 Useful Commands and Scripts

### Quick Diagnostics
```bash
# Cluster health overview
kubectl get nodes,pods --all-namespaces | head -20

# Resource usage summary
kubectl top nodes && kubectl top pods --all-namespaces | head -10

# Recent events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10

# Network connectivity test
kubectl run test-pod --image=busybox --restart=Never --rm -it -- sh
```

### Log Analysis
```bash
# Search for errors in pod logs
kubectl logs -l app=myapp --all-containers=true | grep -i error

# Monitor real-time logs
kubectl logs -f deployment/myapp -n production

# Export logs for analysis
kubectl logs deployment/myapp -n production --since=1h > app-logs.txt
```

### Performance Profiling
```bash
# CPU profiling
kubectl exec -it POD_NAME -- top -b -n1

# Memory analysis
kubectl exec -it POD_NAME -- free -h

# Network statistics
kubectl exec -it POD_NAME -- netstat -tuln
```

Remember: Always test troubleshooting procedures in non-production environments first, and maintain detailed documentation of all changes made during incident resolution.

---

## 📚 Additional Resources

- [EKS Troubleshooting Guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [Kubernetes Debugging Guide](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [AWS Support Center](https://console.aws.amazon.com/support/)
- [EKS Best Practices Guides](https://aws.github.io/aws-eks-best-practices/)

**🔧 Happy Troubleshooting!**
