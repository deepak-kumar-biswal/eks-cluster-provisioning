#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════
# ENHANCED SYSTEM NODE BOOTSTRAP SCRIPT
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Enable detailed logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting enhanced system node bootstrap process..."

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

# Update system packages
yum update -y

# Install essential packages
yum install -y \
    htop \
    iotop \
    sysstat \
    tcpdump \
    strace \
    lsof \
    curl \
    wget \
    unzip \
    jq \
    awscli \
    amazon-cloudwatch-agent

# ─────────────────────────────────────────────────────────────────────────────
# KERNEL PARAMETER OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

cat <<EOF >> /etc/sysctl.conf
# Network performance optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_wmem = 4096 87380 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_congestion_control = bbr

# File descriptor limits
fs.file-max = 2097152

# Memory management
vm.max_map_count = 262144
vm.swappiness = 1

# Network security
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
EOF

sysctl -p

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM LIMITS OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

cat <<EOF >> /etc/security/limits.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER/CONTAINERD OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

# Configure containerd
mkdir -p /etc/containerd
cat <<EOF > /etc/containerd/config.toml
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
          endpoint = ["https://registry-1.docker.io"]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."public.ecr.aws"]
          endpoint = ["https://public.ecr.aws"]
EOF

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH AGENT CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "EKS/SystemNodes",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_iowait",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent",
          "inodes_free"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "diskio": {
        "measurement": [
          "io_time",
          "read_bytes",
          "write_bytes",
          "reads",
          "writes"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait"
        ],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [
          "swap_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/eks/system-nodes/messages",
            "log_stream_name": "{instance_id}/messages"
          },
          {
            "file_path": "/var/log/secure",
            "log_group_name": "/aws/eks/system-nodes/secure",
            "log_stream_name": "{instance_id}/secure"
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/aws/eks/system-nodes/user-data",
            "log_stream_name": "{instance_id}/user-data"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY HARDENING
# ─────────────────────────────────────────────────────────────────────────────

# Disable unnecessary services
systemctl disable postfix
systemctl stop postfix

# Configure SSH security (if SSH is needed)
if systemctl is-active --quiet sshd; then
  sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  systemctl reload sshd
fi

# Set up log rotation for container logs
cat <<EOF > /etc/logrotate.d/docker-container
/var/lib/docker/containers/*/*.log {
  rotate 5
  daily
  compress
  size=10M
  missingok
  delaycompress
  copytruncate
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# DISK OPTIMIZATION
# ─────────────────────────────────────────────────────────────────────────────

# Extend root filesystem if needed
resize2fs /dev/xvda1 2>/dev/null || true

# Set up dedicated directories for Kubernetes
mkdir -p /var/lib/kubelet
mkdir -p /var/lib/docker
mkdir -p /var/log/pods

# ─────────────────────────────────────────────────────────────────────────────
# INSTALL ADDITIONAL MONITORING TOOLS
# ─────────────────────────────────────────────────────────────────────────────

# Install node_exporter for Prometheus monitoring
wget -O /tmp/node_exporter.tar.gz \
  https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz

tar -xzf /tmp/node_exporter.tar.gz -C /tmp
mv /tmp/node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
rm -rf /tmp/node_exporter*

# Create node_exporter user
useradd --no-create-home --shell /bin/false node_exporter

# Create systemd service for node_exporter
cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.processes \
    --collector.interrupts \
    --no-collector.arp \
    --no-collector.bcache \
    --no-collector.bonding \
    --no-collector.conntrack \
    --no-collector.edac \
    --no-collector.entropy \
    --no-collector.filefd \
    --no-collector.hwmon \
    --no-collector.infiniband \
    --no-collector.ipvs \
    --no-collector.mdadm \
    --no-collector.netclass \
    --no-collector.netstat \
    --no-collector.sockstat \
    --no-collector.timex \
    --no-collector.vmstat \
    --no-collector.wifi \
    --no-collector.zfs

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# ─────────────────────────────────────────────────────────────────────────────
# FINAL SETUP
# ─────────────────────────────────────────────────────────────────────────────

# Create a script for runtime monitoring
cat <<EOF > /usr/local/bin/node-health-check.sh
#!/bin/bash
# Node health check script

TIMESTAMP=\$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=\$(hostname)

# Check disk space
DISK_USAGE=\$(df / | awk 'NR==2 {print \$5}' | sed 's/%//')
if [ \$DISK_USAGE -gt 80 ]; then
    echo "[\$TIMESTAMP] WARNING: High disk usage on \$HOSTNAME: \$DISK_USAGE%" >> /var/log/node-health.log
fi

# Check memory usage
MEM_USAGE=\$(free | awk 'NR==2{printf "%.0f", \$3/\$2*100}')
if [ \$MEM_USAGE -gt 80 ]; then
    echo "[\$TIMESTAMP] WARNING: High memory usage on \$HOSTNAME: \$MEM_USAGE%" >> /var/log/node-health.log
fi

# Check load average
LOAD_AVG=\$(uptime | awk -F'load average:' '{ print \$2 }' | cut -d',' -f1 | sed 's/^ *//')
CPU_COUNT=\$(nproc)
LOAD_THRESHOLD=\$(echo "\$CPU_COUNT * 0.8" | bc -l)
if (( \$(echo "\$LOAD_AVG > \$LOAD_THRESHOLD" | bc -l) )); then
    echo "[\$TIMESTAMP] WARNING: High load average on \$HOSTNAME: \$LOAD_AVG" >> /var/log/node-health.log
fi
EOF

chmod +x /usr/local/bin/node-health-check.sh

# Add cron job for health check
echo "*/5 * * * * root /usr/local/bin/node-health-check.sh" >> /etc/crontab

# Set hostname tag for easier identification
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Name,Value="eks-system-node-$INSTANCE_ID" --region $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')

echo "System node bootstrap completed successfully at $(date)"

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource NodeGroup --region ${AWS::Region} 2>/dev/null || true
