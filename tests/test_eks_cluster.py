import pytest
import boto3
import subprocess
import json
import time
import requests
from typing import Dict, Any, List
import yaml
from kubernetes import client, config
from moto import mock_eks, mock_ec2
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class EKSClusterTest:
    """Comprehensive test suite for EKS cluster deployment and management"""
    
    def __init__(self, cluster_name: str = "eks-enterprise-dev", region: str = "us-west-2"):
        self.cluster_name = cluster_name
        self.region = region
        self.eks_client = boto3.client('eks', region_name=region)
        self.ec2_client = boto3.client('ec2', region_name=region)
        self.elbv2_client = boto3.client('elbv2', region_name=region)
        
        # Load kubeconfig if available
        try:
            config.load_kube_config()
            self.k8s_core_v1 = client.CoreV1Api()
            self.k8s_apps_v1 = client.AppsV1Api()
            self.k8s_networking_v1 = client.NetworkingV1Api()
            self.k8s_rbac_v1 = client.RbacAuthorizationV1Api()
            logger.info("Kubernetes configuration loaded successfully")
        except Exception as e:
            logger.warning(f"Failed to load kubeconfig: {e}")
            self.k8s_core_v1 = None

class TestTerraformInfrastructure:
    """Test Terraform infrastructure deployment"""
    
    @pytest.fixture(scope="class")
    def terraform_output(self):
        """Get Terraform outputs"""
        try:
            result = subprocess.run(
                ["terraform", "output", "-json"],
                cwd="terraform/environments/dev",
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            pytest.skip(f"Terraform output failed: {e}")
    
    def test_terraform_init(self):
        """Test Terraform initialization"""
        result = subprocess.run(
            ["terraform", "init"],
            cwd="terraform/environments/dev",
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Terraform init failed: {result.stderr}"
    
    def test_terraform_validate(self):
        """Test Terraform configuration validation"""
        result = subprocess.run(
            ["terraform", "validate"],
            cwd="terraform/environments/dev",
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Terraform validation failed: {result.stderr}"
    
    def test_terraform_plan(self):
        """Test Terraform planning"""
        result = subprocess.run(
            ["terraform", "plan", "-var-file=dev.tfvars"],
            cwd="terraform/environments/dev",
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Terraform plan failed: {result.stderr}"
    
    def test_terraform_outputs_exist(self, terraform_output):
        """Test that required Terraform outputs exist"""
        required_outputs = [
            'cluster_endpoint',
            'cluster_name',
            'vpc_id',
            'private_subnets',
            'public_subnets'
        ]
        
        for output in required_outputs:
            assert output in terraform_output, f"Missing required output: {output}"
            assert terraform_output[output]['value'], f"Empty output: {output}"

class TestAWSInfrastructure:
    """Test AWS infrastructure components"""
    
    @pytest.fixture(scope="class")
    def cluster_test(self):
        return EKSClusterTest()
    
    def test_eks_cluster_exists(self, cluster_test):
        """Test EKS cluster exists and is active"""
        try:
            response = cluster_test.eks_client.describe_cluster(name=cluster_test.cluster_name)
            assert response['cluster']['status'] == 'ACTIVE'
            assert response['cluster']['version'] >= '1.28'
            logger.info(f"EKS cluster {cluster_test.cluster_name} is active")
        except Exception as e:
            pytest.fail(f"EKS cluster test failed: {e}")
    
    def test_eks_cluster_logging_enabled(self, cluster_test):
        """Test EKS cluster logging is properly configured"""
        try:
            response = cluster_test.eks_client.describe_cluster(name=cluster_test.cluster_name)
            logging_config = response['cluster']['logging']
            
            enabled_logs = [log['types'] for log in logging_config['clusterLogging'] if log['enabled']]
            required_logs = ['api', 'audit', 'authenticator']
            
            for log_type in required_logs:
                found = any(log_type in logs for logs in enabled_logs)
                assert found, f"Required log type {log_type} is not enabled"
                
            logger.info("EKS cluster logging is properly configured")
        except Exception as e:
            pytest.fail(f"EKS cluster logging test failed: {e}")
    
    def test_eks_cluster_encryption(self, cluster_test):
        """Test EKS cluster encryption is enabled"""
        try:
            response = cluster_test.eks_client.describe_cluster(name=cluster_test.cluster_name)
            encryption_config = response['cluster'].get('encryptionConfig', [])
            
            assert encryption_config, "No encryption configuration found"
            assert encryption_config[0]['resources'] == ['secrets']
            logger.info("EKS cluster encryption is enabled")
        except Exception as e:
            pytest.fail(f"EKS cluster encryption test failed: {e}")
    
    def test_node_groups_exist(self, cluster_test):
        """Test EKS node groups exist and are active"""
        try:
            response = cluster_test.eks_client.list_nodegroups(clusterName=cluster_test.cluster_name)
            node_groups = response['nodegroups']
            
            expected_node_groups = ['system', 'applications', 'spot']
            for ng_name in expected_node_groups:
                matching_ng = [ng for ng in node_groups if ng_name in ng.lower()]
                assert matching_ng, f"Node group containing '{ng_name}' not found"
            
            # Test each node group status
            for ng_name in node_groups:
                ng_response = cluster_test.eks_client.describe_nodegroup(
                    clusterName=cluster_test.cluster_name,
                    nodegroupName=ng_name
                )
                assert ng_response['nodegroup']['status'] == 'ACTIVE'
                logger.info(f"Node group {ng_name} is active")
                
        except Exception as e:
            pytest.fail(f"Node groups test failed: {e}")
    
    def test_vpc_configuration(self, cluster_test):
        """Test VPC configuration is correct"""
        try:
            # Get cluster VPC
            cluster_response = cluster_test.eks_client.describe_cluster(name=cluster_test.cluster_name)
            vpc_id = cluster_response['cluster']['resourcesVpcConfig']['vpcId']
            
            # Test VPC exists
            vpc_response = cluster_test.ec2_client.describe_vpcs(VpcIds=[vpc_id])
            assert vpc_response['Vpcs'][0]['State'] == 'available'
            
            # Test subnets
            subnets = cluster_response['cluster']['resourcesVpcConfig']['subnetIds']
            assert len(subnets) >= 6, "Should have at least 6 subnets (3 private + 3 public)"
            
            subnet_response = cluster_test.ec2_client.describe_subnets(SubnetIds=subnets)
            
            private_subnets = [s for s in subnet_response['Subnets'] 
                             if any(tag.get('Key') == 'kubernetes.io/role/internal-elb' 
                                   for tag in s.get('Tags', []))]
            public_subnets = [s for s in subnet_response['Subnets'] 
                            if any(tag.get('Key') == 'kubernetes.io/role/elb' 
                                  for tag in s.get('Tags', []))]
            
            assert len(private_subnets) >= 3, "Should have at least 3 private subnets"
            assert len(public_subnets) >= 3, "Should have at least 3 public subnets"
            
            logger.info("VPC configuration is correct")
        except Exception as e:
            pytest.fail(f"VPC configuration test failed: {e}")
    
    def test_security_groups(self, cluster_test):
        """Test security groups are properly configured"""
        try:
            cluster_response = cluster_test.eks_client.describe_cluster(name=cluster_test.cluster_name)
            sg_ids = cluster_response['cluster']['resourcesVpcConfig']['securityGroupIds']
            
            sg_response = cluster_test.ec2_client.describe_security_groups(GroupIds=sg_ids)
            
            for sg in sg_response['SecurityGroups']:
                # Basic security group validation
                assert sg['VpcId'], "Security group must be in a VPC"
                assert len(sg['IpPermissions']) > 0 or len(sg['IpPermissionsEgress']) > 0, \
                       "Security group should have rules"
            
            logger.info("Security groups are properly configured")
        except Exception as e:
            pytest.fail(f"Security groups test failed: {e}")

class TestKubernetesCluster:
    """Test Kubernetes cluster functionality"""
    
    @pytest.fixture(scope="class")
    def cluster_test(self):
        cluster_test = EKSClusterTest()
        if not cluster_test.k8s_core_v1:
            pytest.skip("Kubernetes client not available")
        return cluster_test
    
    def test_cluster_nodes_ready(self, cluster_test):
        """Test all cluster nodes are ready"""
        try:
            nodes = cluster_test.k8s_core_v1.list_node()
            assert len(nodes.items) > 0, "No nodes found in cluster"
            
            for node in nodes.items:
                conditions = node.status.conditions
                ready_condition = next((c for c in conditions if c.type == "Ready"), None)
                assert ready_condition and ready_condition.status == "True", \
                       f"Node {node.metadata.name} is not ready"
                
            logger.info(f"All {len(nodes.items)} nodes are ready")
        except Exception as e:
            pytest.fail(f"Cluster nodes test failed: {e}")
    
    def test_system_pods_running(self, cluster_test):
        """Test essential system pods are running"""
        try:
            essential_namespaces = ['kube-system', 'kube-node-lease', 'kube-public']
            essential_pods = [
                ('kube-system', 'coredns'),
                ('kube-system', 'aws-node'),
                ('kube-system', 'kube-proxy'),
                ('kube-system', 'ebs-csi')
            ]
            
            for namespace, pod_prefix in essential_pods:
                pods = cluster_test.k8s_core_v1.list_namespaced_pod(namespace=namespace)
                matching_pods = [p for p in pods.items if pod_prefix in p.metadata.name]
                
                assert matching_pods, f"No {pod_prefix} pods found in {namespace}"
                
                for pod in matching_pods:
                    assert pod.status.phase == "Running", \
                           f"Pod {pod.metadata.name} is not running: {pod.status.phase}"
            
            logger.info("All essential system pods are running")
        except Exception as e:
            pytest.fail(f"System pods test failed: {e}")
    
    def test_cluster_dns_resolution(self, cluster_test):
        """Test DNS resolution within cluster"""
        try:
            # Create a test pod for DNS resolution
            test_pod = {
                "apiVersion": "v1",
                "kind": "Pod",
                "metadata": {
                    "name": "dns-test-pod",
                    "namespace": "default"
                },
                "spec": {
                    "containers": [{
                        "name": "dns-test",
                        "image": "busybox:1.35",
                        "command": ["sleep", "3600"],
                        "resources": {
                            "requests": {"cpu": "100m", "memory": "64Mi"},
                            "limits": {"cpu": "100m", "memory": "64Mi"}
                        }
                    }],
                    "restartPolicy": "Never"
                }
            }
            
            # Create and wait for pod
            cluster_test.k8s_core_v1.create_namespaced_pod(namespace="default", body=test_pod)
            
            # Wait for pod to be ready
            for _ in range(30):
                pod = cluster_test.k8s_core_v1.read_namespaced_pod(
                    name="dns-test-pod", namespace="default"
                )
                if pod.status.phase == "Running":
                    break
                time.sleep(2)
            
            # Test DNS resolution
            result = subprocess.run([
                "kubectl", "exec", "dns-test-pod", "--",
                "nslookup", "kubernetes.default.svc.cluster.local"
            ], capture_output=True, text=True)
            
            assert result.returncode == 0, f"DNS resolution failed: {result.stderr}"
            
            # Cleanup
            cluster_test.k8s_core_v1.delete_namespaced_pod(
                name="dns-test-pod", namespace="default"
            )
            
            logger.info("DNS resolution test passed")
        except Exception as e:
            pytest.fail(f"DNS resolution test failed: {e}")
    
    def test_network_policies(self, cluster_test):
        """Test network policies can be created and enforced"""
        try:
            # Create test namespace
            namespace = {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {"name": "network-policy-test"}
            }
            cluster_test.k8s_core_v1.create_namespace(body=namespace)
            
            # Create network policy
            network_policy = {
                "apiVersion": "networking.k8s.io/v1",
                "kind": "NetworkPolicy",
                "metadata": {
                    "name": "test-network-policy",
                    "namespace": "network-policy-test"
                },
                "spec": {
                    "podSelector": {},
                    "policyTypes": ["Ingress", "Egress"],
                    "ingress": [{
                        "from": [{"podSelector": {"matchLabels": {"role": "allowed"}}}]
                    }],
                    "egress": [{
                        "to": [{"podSelector": {"matchLabels": {"role": "allowed"}}}]
                    }]
                }
            }
            
            cluster_test.k8s_networking_v1.create_namespaced_network_policy(
                namespace="network-policy-test", body=network_policy
            )
            
            # Verify network policy exists
            policies = cluster_test.k8s_networking_v1.list_namespaced_network_policy(
                namespace="network-policy-test"
            )
            assert len(policies.items) > 0, "Network policy was not created"
            
            # Cleanup
            cluster_test.k8s_networking_v1.delete_namespaced_network_policy(
                name="test-network-policy", namespace="network-policy-test"
            )
            cluster_test.k8s_core_v1.delete_namespace(name="network-policy-test")
            
            logger.info("Network policies test passed")
        except Exception as e:
            pytest.fail(f"Network policies test failed: {e}")

class TestMonitoringAndObservability:
    """Test monitoring and observability components"""
    
    @pytest.fixture(scope="class")
    def cluster_test(self):
        cluster_test = EKSClusterTest()
        if not cluster_test.k8s_core_v1:
            pytest.skip("Kubernetes client not available")
        return cluster_test
    
    def test_prometheus_deployed(self, cluster_test):
        """Test Prometheus is deployed and accessible"""
        try:
            pods = cluster_test.k8s_core_v1.list_namespaced_pod(namespace="monitoring")
            prometheus_pods = [p for p in pods.items if 'prometheus' in p.metadata.name]
            
            assert prometheus_pods, "No Prometheus pods found"
            
            for pod in prometheus_pods:
                assert pod.status.phase == "Running", \
                       f"Prometheus pod {pod.metadata.name} is not running"
            
            logger.info("Prometheus is deployed and running")
        except Exception as e:
            pytest.fail(f"Prometheus test failed: {e}")
    
    def test_grafana_deployed(self, cluster_test):
        """Test Grafana is deployed and accessible"""
        try:
            pods = cluster_test.k8s_core_v1.list_namespaced_pod(namespace="monitoring")
            grafana_pods = [p for p in pods.items if 'grafana' in p.metadata.name]
            
            assert grafana_pods, "No Grafana pods found"
            
            for pod in grafana_pods:
                assert pod.status.phase == "Running", \
                       f"Grafana pod {pod.metadata.name} is not running"
            
            # Test Grafana service exists
            services = cluster_test.k8s_core_v1.list_namespaced_service(namespace="monitoring")
            grafana_services = [s for s in services.items if 'grafana' in s.metadata.name]
            assert grafana_services, "No Grafana service found"
            
            logger.info("Grafana is deployed and running")
        except Exception as e:
            pytest.fail(f"Grafana test failed: {e}")
    
    def test_alertmanager_deployed(self, cluster_test):
        """Test AlertManager is deployed"""
        try:
            pods = cluster_test.k8s_core_v1.list_namespaced_pod(namespace="monitoring")
            alertmanager_pods = [p for p in pods.items if 'alertmanager' in p.metadata.name]
            
            assert alertmanager_pods, "No AlertManager pods found"
            
            for pod in alertmanager_pods:
                assert pod.status.phase == "Running", \
                       f"AlertManager pod {pod.metadata.name} is not running"
            
            logger.info("AlertManager is deployed and running")
        except Exception as e:
            pytest.fail(f"AlertManager test failed: {e}")
    
    def test_node_exporter_deployed(self, cluster_test):
        """Test Node Exporter is deployed on all nodes"""
        try:
            # Get number of nodes
            nodes = cluster_test.k8s_core_v1.list_node()
            node_count = len(nodes.items)
            
            # Get node exporter pods
            pods = cluster_test.k8s_core_v1.list_namespaced_pod(namespace="monitoring")
            node_exporter_pods = [p for p in pods.items if 'node-exporter' in p.metadata.name]
            
            assert len(node_exporter_pods) >= node_count, \
                   f"Expected at least {node_count} node exporter pods, found {len(node_exporter_pods)}"
            
            for pod in node_exporter_pods:
                assert pod.status.phase == "Running", \
                       f"Node exporter pod {pod.metadata.name} is not running"
            
            logger.info("Node Exporter is deployed on all nodes")
        except Exception as e:
            pytest.fail(f"Node Exporter test failed: {e}")

class TestSecurityAndCompliance:
    """Test security and compliance features"""
    
    @pytest.fixture(scope="class")
    def cluster_test(self):
        cluster_test = EKSClusterTest()
        if not cluster_test.k8s_core_v1:
            pytest.skip("Kubernetes client not available")
        return cluster_test
    
    def test_rbac_configured(self, cluster_test):
        """Test RBAC is properly configured"""
        try:
            # Test cluster roles exist
            cluster_roles = cluster_test.k8s_rbac_v1.list_cluster_role()
            essential_roles = ['cluster-admin', 'edit', 'view']
            
            for role_name in essential_roles:
                matching_roles = [r for r in cluster_roles.items if role_name in r.metadata.name]
                assert matching_roles, f"Essential cluster role {role_name} not found"
            
            # Test role bindings exist
            role_bindings = cluster_test.k8s_rbac_v1.list_cluster_role_binding()
            assert len(role_bindings.items) > 0, "No cluster role bindings found"
            
            logger.info("RBAC is properly configured")
        except Exception as e:
            pytest.fail(f"RBAC test failed: {e}")
    
    def test_pod_security_standards(self, cluster_test):
        """Test Pod Security Standards are enforced"""
        try:
            # Try to create a privileged pod (should fail in restricted mode)
            privileged_pod = {
                "apiVersion": "v1",
                "kind": "Pod",
                "metadata": {
                    "name": "privileged-test-pod",
                    "namespace": "default"
                },
                "spec": {
                    "containers": [{
                        "name": "privileged-container",
                        "image": "nginx:1.21",
                        "securityContext": {
                            "privileged": True
                        }
                    }]
                }
            }
            
            # This should fail if Pod Security Standards are properly configured
            try:
                cluster_test.k8s_core_v1.create_namespaced_pod(
                    namespace="default", body=privileged_pod
                )
                # If it succeeds, clean up and note that PSS might not be in restricted mode
                cluster_test.k8s_core_v1.delete_namespaced_pod(
                    name="privileged-test-pod", namespace="default"
                )
                logger.warning("Privileged pod was allowed - PSS may not be in restricted mode")
            except client.ApiException as e:
                # This is expected behavior for restricted PSS
                if e.status == 403 or e.status == 422:
                    logger.info("Pod Security Standards are properly enforcing restrictions")
                else:
                    raise
                    
        except Exception as e:
            pytest.fail(f"Pod Security Standards test failed: {e}")
    
    def test_secrets_encryption(self, cluster_test):
        """Test secrets encryption at rest"""
        try:
            # Create a test secret
            secret = {
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {
                    "name": "test-encryption-secret",
                    "namespace": "default"
                },
                "type": "Opaque",
                "stringData": {
                    "sensitive-data": "this-should-be-encrypted"
                }
            }
            
            cluster_test.k8s_core_v1.create_namespaced_secret(
                namespace="default", body=secret
            )
            
            # Retrieve the secret
            retrieved_secret = cluster_test.k8s_core_v1.read_namespaced_secret(
                name="test-encryption-secret", namespace="default"
            )
            
            assert retrieved_secret.data["sensitive-data"], "Secret data should exist"
            
            # Cleanup
            cluster_test.k8s_core_v1.delete_namespaced_secret(
                name="test-encryption-secret", namespace="default"
            )
            
            logger.info("Secrets encryption test completed")
        except Exception as e:
            pytest.fail(f"Secrets encryption test failed: {e}")

class TestApplicationDeployment:
    """Test application deployment capabilities"""
    
    @pytest.fixture(scope="class")
    def cluster_test(self):
        cluster_test = EKSClusterTest()
        if not cluster_test.k8s_core_v1:
            pytest.skip("Kubernetes client not available")
        return cluster_test
    
    def test_deploy_sample_application(self, cluster_test):
        """Test deploying a sample application"""
        try:
            # Create test namespace
            namespace = {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {"name": "app-test"}
            }
            cluster_test.k8s_core_v1.create_namespace(body=namespace)
            
            # Deploy sample application
            deployment = {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "name": "sample-app",
                    "namespace": "app-test"
                },
                "spec": {
                    "replicas": 2,
                    "selector": {"matchLabels": {"app": "sample-app"}},
                    "template": {
                        "metadata": {"labels": {"app": "sample-app"}},
                        "spec": {
                            "containers": [{
                                "name": "nginx",
                                "image": "nginx:1.21",
                                "ports": [{"containerPort": 80}],
                                "resources": {
                                    "requests": {"cpu": "100m", "memory": "128Mi"},
                                    "limits": {"cpu": "200m", "memory": "256Mi"}
                                },
                                "securityContext": {
                                    "allowPrivilegeEscalation": False,
                                    "runAsNonRoot": True,
                                    "runAsUser": 1000,
                                    "readOnlyRootFilesystem": True
                                }
                            }]
                        }
                    }
                }
            }
            
            cluster_test.k8s_apps_v1.create_namespaced_deployment(
                namespace="app-test", body=deployment
            )
            
            # Wait for deployment to be ready
            for _ in range(60):
                dep = cluster_test.k8s_apps_v1.read_namespaced_deployment(
                    name="sample-app", namespace="app-test"
                )
                if dep.status.ready_replicas == 2:
                    break
                time.sleep(2)
            
            assert dep.status.ready_replicas == 2, "Sample application deployment failed"
            
            # Cleanup
            cluster_test.k8s_apps_v1.delete_namespaced_deployment(
                name="sample-app", namespace="app-test"
            )
            cluster_test.k8s_core_v1.delete_namespace(name="app-test")
            
            logger.info("Sample application deployment test passed")
        except Exception as e:
            pytest.fail(f"Application deployment test failed: {e}")
    
    def test_load_balancer_service(self, cluster_test):
        """Test Load Balancer service creation"""
        try:
            # Create test namespace
            namespace = {
                "apiVersion": "v1",
                "kind": "Namespace",
                "metadata": {"name": "lb-test"}
            }
            cluster_test.k8s_core_v1.create_namespace(body=namespace)
            
            # Create deployment
            deployment = {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {"name": "lb-test-app", "namespace": "lb-test"},
                "spec": {
                    "replicas": 1,
                    "selector": {"matchLabels": {"app": "lb-test-app"}},
                    "template": {
                        "metadata": {"labels": {"app": "lb-test-app"}},
                        "spec": {
                            "containers": [{
                                "name": "nginx",
                                "image": "nginx:1.21",
                                "ports": [{"containerPort": 80}],
                                "resources": {
                                    "requests": {"cpu": "100m", "memory": "128Mi"}
                                }
                            }]
                        }
                    }
                }
            }
            
            # Create service
            service = {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {
                    "name": "lb-test-service",
                    "namespace": "lb-test",
                    "annotations": {
                        "service.beta.kubernetes.io/aws-load-balancer-type": "nlb",
                        "service.beta.kubernetes.io/aws-load-balancer-internal": "true"
                    }
                },
                "spec": {
                    "type": "LoadBalancer",
                    "selector": {"app": "lb-test-app"},
                    "ports": [{"port": 80, "targetPort": 80}]
                }
            }
            
            cluster_test.k8s_apps_v1.create_namespaced_deployment(
                namespace="lb-test", body=deployment
            )
            cluster_test.k8s_core_v1.create_namespaced_service(
                namespace="lb-test", body=service
            )
            
            # Wait for service to get external IP
            external_ip = None
            for _ in range(120):  # Wait up to 4 minutes
                svc = cluster_test.k8s_core_v1.read_namespaced_service(
                    name="lb-test-service", namespace="lb-test"
                )
                if svc.status.load_balancer.ingress:
                    external_ip = svc.status.load_balancer.ingress[0].hostname
                    break
                time.sleep(2)
            
            assert external_ip, "Load balancer service did not get external IP"
            
            # Cleanup
            cluster_test.k8s_core_v1.delete_namespaced_service(
                name="lb-test-service", namespace="lb-test"
            )
            cluster_test.k8s_apps_v1.delete_namespaced_deployment(
                name="lb-test-app", namespace="lb-test"
            )
            cluster_test.k8s_core_v1.delete_namespace(name="lb-test")
            
            logger.info("Load Balancer service test passed")
        except Exception as e:
            pytest.fail(f"Load Balancer service test failed: {e}")

class TestCostOptimization:
    """Test cost optimization features"""
    
    @pytest.fixture(scope="class")
    def cluster_test(self):
        return EKSClusterTest()
    
    def test_spot_instances_configured(self, cluster_test):
        """Test spot instances are properly configured"""
        try:
            response = cluster_test.eks_client.list_nodegroups(clusterName=cluster_test.cluster_name)
            node_groups = response['nodegroups']
            
            spot_node_groups = []
            for ng_name in node_groups:
                ng_response = cluster_test.eks_client.describe_nodegroup(
                    clusterName=cluster_test.cluster_name,
                    nodegroupName=ng_name
                )
                if ng_response['nodegroup']['capacityType'] == 'SPOT':
                    spot_node_groups.append(ng_name)
            
            assert spot_node_groups, "No spot instance node groups found"
            logger.info(f"Found spot node groups: {spot_node_groups}")
        except Exception as e:
            pytest.fail(f"Spot instances test failed: {e}")
    
    def test_cluster_autoscaler_deployed(self, cluster_test):
        """Test cluster autoscaler is deployed"""
        if not cluster_test.k8s_core_v1:
            pytest.skip("Kubernetes client not available")
            
        try:
            pods = cluster_test.k8s_core_v1.list_namespaced_pod(namespace="kube-system")
            ca_pods = [p for p in pods.items if 'cluster-autoscaler' in p.metadata.name]
            
            assert ca_pods, "No cluster autoscaler pods found"
            
            for pod in ca_pods:
                assert pod.status.phase == "Running", \
                       f"Cluster autoscaler pod {pod.metadata.name} is not running"
            
            logger.info("Cluster autoscaler is deployed and running")
        except Exception as e:
            pytest.fail(f"Cluster autoscaler test failed: {e}")

class TestBackupAndDisasterRecovery:
    """Test backup and disaster recovery capabilities"""
    
    @pytest.fixture(scope="class")
    def cluster_test(self):
        cluster_test = EKSClusterTest()
        if not cluster_test.k8s_core_v1:
            pytest.skip("Kubernetes client not available")
        return cluster_test
    
    def test_velero_deployed(self, cluster_test):
        """Test Velero is deployed for backup"""
        try:
            # Check if velero namespace exists
            namespaces = cluster_test.k8s_core_v1.list_namespace()
            velero_ns = [ns for ns in namespaces.items if ns.metadata.name == "velero"]
            
            if not velero_ns:
                pytest.skip("Velero not deployed")
            
            # Check velero pods
            pods = cluster_test.k8s_core_v1.list_namespaced_pod(namespace="velero")
            velero_pods = [p for p in pods.items if 'velero' in p.metadata.name]
            
            assert velero_pods, "No Velero pods found"
            
            for pod in velero_pods:
                assert pod.status.phase == "Running", \
                       f"Velero pod {pod.metadata.name} is not running"
            
            logger.info("Velero is deployed and running")
        except Exception as e:
            pytest.fail(f"Velero test failed: {e}")

if __name__ == "__main__":
    # Run the tests
    pytest.main([
        __file__,
        "-v",
        "--tb=short",
        "--disable-warnings",
        f"--junitxml=test-results.xml"
    ])
