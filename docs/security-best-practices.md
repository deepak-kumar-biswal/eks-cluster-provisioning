# 🔒 Security Best Practices for Enterprise EKS

## Overview

This document outlines comprehensive security best practices for deploying and managing Amazon EKS clusters at enterprise scale. These practices align with industry standards including AWS Well-Architected Framework, CIS Kubernetes Benchmark, and compliance frameworks like SOC2, ISO27001, and PCI-DSS.

## 🛡️ Security Framework

### Defense in Depth Strategy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Infrastructure Security                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                            Platform Security                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                           Application Security                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                              Data Security                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🏗️ Infrastructure Security

### VPC and Network Security

#### Network Isolation

```hcl
# Private subnet configuration
resource "aws_subnet" "private" {
  for_each          = var.private_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.available.names[each.key]
  
  # Critical: Disable public IP assignment
  map_public_ip_on_launch = false
  
  tags = {
    Name                              = "${var.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Security group for EKS cluster
resource "aws_security_group" "cluster" {
  name_prefix = "${var.name}-cluster-"
  vpc_id      = aws_vpc.main.id

  # Restrict ingress to necessary sources only
  ingress {
    description = "HTTPS from trusted networks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.trusted_networks
  }

  # Allow outbound for cluster communication
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-cluster-sg"
  }
}
```

#### Network Policies

```yaml
# Default deny-all network policy
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

---
# Allow specific application communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web-frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: api-backend
    ports:
    - protocol: TCP
      port: 8080
```

### Endpoint Security

```hcl
# EKS cluster endpoint configuration
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    # Security best practice: Disable public endpoint for production
    endpoint_private_access = true
    endpoint_public_access  = var.environment == "prod" ? false : true
    
    # Restrict public endpoint access to trusted CIDRs
    public_access_cidrs = var.environment == "prod" ? [] : var.trusted_cidrs
    
    subnet_ids = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.cluster.id]
  }
}
```

## 🔐 Identity and Access Management

### IAM Roles and Service Accounts

#### Principle of Least Privilege

```yaml
# Example: EBS CSI Driver Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ebs-csi-controller-sa
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/EBS-CSI-Role
---
# IAM role with minimal required permissions
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSnapshot",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyVolume",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeVolumes"
      ],
      "Resource": "*"
    }
  ]
}
```

#### RBAC Implementation

```yaml
# Namespace-specific developer role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: development
subjects:
- kind: User
  name: developer-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

### Multi-Factor Authentication

```yaml
# Example: Enforce MFA for cluster access
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
```

## 🛡️ Runtime Security

### Pod Security Standards

#### Implementation Strategy

```yaml
# Namespace with Pod Security Standards
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # Enforce restricted security profile
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/enforce-version: latest

---
# Example secure pod specification
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: production
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:1.21-alpine
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
        - ALL
    resources:
      limits:
        cpu: "200m"
        memory: "256Mi"
      requests:
        cpu: "100m"
        memory: "128Mi"
    volumeMounts:
    - name: tmp
      mountPath: /tmp
      readOnly: false
    - name: var-run
      mountPath: /var/run
      readOnly: false
  volumes:
  - name: tmp
    emptyDir: {}
  - name: var-run
    emptyDir: {}
```

### Container Security

#### Image Security Best Practices

```yaml
# Secure container image practices
spec:
  containers:
  - name: app
    # Use specific version tags, not 'latest'
    image: nginx:1.21.6-alpine@sha256:specific-hash
    
    # Security context
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 65534  # nobody user
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE  # Only if needed
    
    # Resource limits
    resources:
      limits:
        cpu: "500m"
        memory: "512Mi"
        ephemeral-storage: "1Gi"
      requests:
        cpu: "100m"
        memory: "128Mi"
        ephemeral-storage: "100Mi"
```

#### Image Scanning Integration

```yaml
# Trivy scanner DaemonSet for runtime scanning
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: trivy-scanner
  namespace: security-system
spec:
  selector:
    matchLabels:
      app: trivy-scanner
  template:
    metadata:
      labels:
        app: trivy-scanner
    spec:
      hostPID: true
      containers:
      - name: trivy
        image: aquasec/trivy:0.45.1
        command: ["/bin/sh"]
        args: ["-c", "trivy fs --security-checks vuln,config /host --format json > /tmp/scan-results.json"]
        volumeMounts:
        - name: host-root
          mountPath: /host
          readOnly: true
        - name: scan-results
          mountPath: /tmp
      volumes:
      - name: host-root
        hostPath:
          path: /
      - name: scan-results
        emptyDir: {}
```

## 🔒 Data Security

### Encryption at Rest

#### EKS Secrets Encryption

```hcl
# KMS key for EKS secrets encryption
resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.cluster.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.name}-eks-secrets"
    Purpose     = "EKS Secrets Encryption"
    Environment = var.environment
  }
}

# EKS cluster with encryption
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }
}
```

### Secrets Management

#### External Secrets Operator

```yaml
# External Secrets Operator for AWS Secrets Manager integration
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secretsmanager
  namespace: production
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa

---
# External Secret resource
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: app-secrets
    creationPolicy: Owner
  data:
  - secretKey: database-password
    remoteRef:
      key: prod/app/database
      property: password
```

### Data in Transit

#### TLS Configuration

```yaml
# Ingress with TLS termination
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-app-ingress
  namespace: production
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-2017-01
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  ingressClassName: alb
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls-secret
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

## 🔍 Security Monitoring and Auditing

### Audit Logging

#### EKS Audit Log Configuration

```hcl
resource "aws_eks_cluster" "main" {
  # ... other configuration ...

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

# CloudWatch Log Group with retention
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = {
    Name        = "${var.cluster_name}-logs"
    Environment = var.environment
  }
}
```

#### Falco for Runtime Security Monitoring

```yaml
# Falco deployment for runtime security
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: falco
  namespace: security-system
spec:
  selector:
    matchLabels:
      app: falco
  template:
    metadata:
      labels:
        app: falco
    spec:
      serviceAccountName: falco
      hostNetwork: true
      hostPID: true
      containers:
      - name: falco
        image: falcosecurity/falco:0.36.2
        args:
          - /usr/bin/falco
          - --k8s-audit-endpoint=http://localhost:8765/k8s-audit
          - --k8s-audit
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-proc
          mountPath: /host/proc
          readOnly: true
        - name: host-boot
          mountPath: /host/boot
          readOnly: true
        - name: host-lib-modules
          mountPath: /host/lib/modules
          readOnly: true
        - name: host-usr
          mountPath: /host/usr
          readOnly: true
        - name: host-etc
          mountPath: /host/etc
          readOnly: true
      volumes:
      - name: host-proc
        hostPath:
          path: /proc
      - name: host-boot
        hostPath:
          path: /boot
      - name: host-lib-modules
        hostPath:
          path: /lib/modules
      - name: host-usr
        hostPath:
          path: /usr
      - name: host-etc
        hostPath:
          path: /etc
```

### Security Alerts

```yaml
# Prometheus rules for security alerts
groups:
- name: security-alerts
  rules:
  - alert: PrivilegedPodDetected
    expr: kube_pod_spec_containers_privileged > 0
    for: 0m
    labels:
      severity: critical
      category: security
    annotations:
      summary: "Privileged pod detected"
      description: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is running in privileged mode"

  - alert: UnauthorizedAPIAccess
    expr: increase(apiserver_audit_total{verb!~"get|list|watch"}[10m]) > 100
    for: 0m
    labels:
      severity: warning
      category: security
    annotations:
      summary: "High number of unauthorized API access attempts"
      description: "Detected {{ $value }} unauthorized API access attempts"

  - alert: SuspiciousNetworkActivity
    expr: increase(container_network_receive_errors_total[5m]) > 50
    for: 2m
    labels:
      severity: warning
      category: security
    annotations:
      summary: "Suspicious network activity detected"
      description: "High network errors in pod {{ $labels.namespace }}/{{ $labels.pod }}"
```

## 🧪 Security Testing

### Automated Security Scanning

```yaml
# Security scanning pipeline
name: Security Scan
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    # Container image scanning
    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'

    # Infrastructure scanning
    - name: Run tfsec
      uses: aquasecurity/tfsec-sarif-action@master
      with:
        sarif_file: tfsec.sarif

    # Kubernetes manifest scanning
    - name: Run kubesec
      run: |
        curl -sSX POST \
          --data-binary @deployment.yaml \
          https://v2.kubesec.io/scan \
          | jq .

    # SAST scanning
    - name: Run CodeQL Analysis
      uses: github/codeql-action/analyze@v2
      with:
        languages: python, terraform
```

### Penetration Testing

#### Kube-hunter for Kubernetes Security Assessment

```yaml
# Kube-hunter job for security assessment
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-hunter
  namespace: security-system
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: kube-hunter
        image: aquasec/kube-hunter:0.6.8
        command: ["kube-hunter"]
        args: ["--pod", "--quick", "--report=json"]
        volumeMounts:
        - name: output
          mountPath: /tmp/kube-hunter
      volumes:
      - name: output
        emptyDir: {}
```

## 📋 Security Compliance

### CIS Kubernetes Benchmark

```yaml
# kube-bench for CIS compliance checking
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench
  namespace: security-system
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:0.6.15
        command: ["kube-bench"]
        args: ["--benchmark", "eks-1.0.1", "--json"]
        volumeMounts:
        - name: var-lib-etcd
          mountPath: /var/lib/etcd
          readOnly: true
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
          readOnly: true
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
        - name: usr-bin
          mountPath: /usr/local/mount-from-host/bin
          readOnly: true
      volumes:
      - name: var-lib-etcd
        hostPath:
          path: "/var/lib/etcd"
      - name: var-lib-kubelet
        hostPath:
          path: "/var/lib/kubelet"
      - name: etc-kubernetes
        hostPath:
          path: "/etc/kubernetes"
      - name: usr-bin
        hostPath:
          path: "/usr/bin"
```

### SOC2 Compliance Checklist

#### Access Controls
- [ ] Multi-factor authentication enforced
- [ ] Role-based access control implemented
- [ ] Principle of least privilege applied
- [ ] Regular access reviews conducted

#### Data Protection
- [ ] Encryption at rest implemented
- [ ] Encryption in transit enforced
- [ ] Key management procedures defined
- [ ] Data classification implemented

#### Monitoring and Logging
- [ ] Comprehensive audit logging enabled
- [ ] Real-time security monitoring active
- [ ] Log retention policies defined
- [ ] Alert response procedures documented

#### Incident Response
- [ ] Incident response plan documented
- [ ] Security team contact information maintained
- [ ] Escalation procedures defined
- [ ] Regular incident response drills conducted

## 🎯 Security Metrics and KPIs

### Key Security Metrics

1. **Mean Time to Detection (MTTD)**
   - Target: < 15 minutes for critical security events
   - Measurement: Time from security event to alert

2. **Mean Time to Response (MTTR)**
   - Target: < 1 hour for critical security incidents
   - Measurement: Time from alert to initial response

3. **Security Vulnerability Remediation Time**
   - Target: Critical vulnerabilities patched within 24 hours
   - Measurement: Time from vulnerability discovery to patch deployment

4. **Compliance Score**
   - Target: > 95% compliance with security policies
   - Measurement: Automated compliance checks and manual assessments

### Security Dashboard Metrics

```yaml
# Grafana dashboard for security metrics
dashboard:
  title: "Security Metrics Dashboard"
  panels:
  - title: "Security Events"
    targets:
    - expr: rate(security_events_total[5m])
  
  - title: "Failed Authentication Attempts"
    targets:
    - expr: increase(authentication_failures_total[1h])
  
  - title: "Policy Violations"
    targets:
    - expr: increase(policy_violations_total[1h])
  
  - title: "Vulnerability Scan Results"
    targets:
    - expr: vulnerability_scan_critical_count
    - expr: vulnerability_scan_high_count
    - expr: vulnerability_scan_medium_count
```

## 🚀 Continuous Security Improvement

### Security Review Process

1. **Weekly Security Reviews**
   - Review security alerts and incidents
   - Analyze security metrics and trends
   - Update security policies as needed

2. **Monthly Vulnerability Assessments**
   - Comprehensive security scans
   - Penetration testing results review
   - Security control effectiveness evaluation

3. **Quarterly Security Architecture Reviews**
   - Review security architecture changes
   - Assess new threat landscape
   - Update security strategy and roadmap

### Security Training and Awareness

- **Developer Security Training**: Secure coding practices, OWASP Top 10
- **Operations Security Training**: Infrastructure security, incident response
- **Security Champions Program**: Dedicated security advocates in each team
- **Regular Security Briefings**: Threat intelligence and security updates

---

## 📚 Security Resources

### Industry Standards and Frameworks
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [AWS Security Best Practices](https://aws.amazon.com/security/security-resources/)

### Security Tools
- [Falco](https://falco.org/) - Runtime security monitoring
- [Trivy](https://github.com/aquasecurity/trivy) - Vulnerability scanner
- [kube-bench](https://github.com/aquasecurity/kube-bench) - CIS compliance checker
- [kube-hunter](https://github.com/aquasecurity/kube-hunter) - Penetration testing tool

### Compliance Resources
- [SOC2 Security Requirements](https://www.aicpa.org/interestareas/frc/assuranceadvisoryservices/aicpasoc2report.html)
- [ISO 27001 Standards](https://www.iso.org/isoiec-27001-information-security.html)
- [PCI DSS Requirements](https://www.pcisecuritystandards.org/pci_security/)

Remember: Security is not a destination but a continuous journey. Regular reviews, updates, and improvements are essential for maintaining a strong security posture.

---

**🔒 Stay Secure, Stay Vigilant!**
