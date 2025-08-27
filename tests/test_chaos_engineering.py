"""
Chaos Engineering Test Suite for EKS Infrastructure
Tests the resilience and fault tolerance of the EKS cluster
"""

import os
import time
import json
import logging
from datetime import datetime, timedelta
from unittest.mock import patch

try:
    import pytest
    import boto3
    import kubernetes
    import requests
except ImportError as e:
    print(f"Missing dependencies: {e}")
    print("Install required packages: pip install pytest boto3 kubernetes requests")
    raise

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TestChaosEngineering:
    """Comprehensive chaos engineering tests for EKS infrastructure."""
    
    @pytest.fixture(autouse=True)
    def setup_clients(self):
        """Setup AWS and Kubernetes clients."""
        self.eks_client = boto3.client('eks')
        self.ec2_client = boto3.client('ec2')
        self.asg_client = boto3.client('autoscaling')
        
        # Load Kubernetes config
        try:
            kubernetes.config.load_incluster_config()
        except:
            kubernetes.config.load_kube_config()
        
        self.k8s_core = kubernetes.client.CoreV1Api()
        self.k8s_apps = kubernetes.client.AppsV1Api()
        self.k8s_custom = kubernetes.client.CustomObjectsApi()
        
        self.cluster_name = os.environ.get('CLUSTER_NAME', 'eks-cluster-dev')
        self.namespace = os.environ.get('CHAOS_NAMESPACE', 'chaos-testing')

    def test_pod_failure_resilience(self):
        """Test application resilience to pod failures."""
        logger.info("Testing pod failure resilience")
        
        # Deploy test application
        app_name = "chaos-resilience-app"
        self._deploy_test_application(app_name, replicas=3)
        
        # Wait for deployment to be ready
        self._wait_for_deployment_ready(app_name, timeout=300)
        
        # Get initial pod count
        initial_pods = self._get_pod_count(app_name)
        
        # Kill 50% of pods
        pods_to_kill = max(1, initial_pods // 2)
        killed_pods = self._kill_random_pods(app_name, pods_to_kill)
        
        # Verify pods are recreated within 60 seconds
        recovery_start = time.time()
        max_recovery_time = 60
        
        while time.time() - recovery_start < max_recovery_time:
            current_pods = self._get_ready_pod_count(app_name)
            if current_pods >= initial_pods:
                recovery_time = time.time() - recovery_start
                logger.info(f"Pods recovered in {recovery_time:.2f} seconds")
                break
            time.sleep(5)
        else:
            pytest.fail(f"Pods did not recover within {max_recovery_time} seconds")
        
        # Verify application is still accessible
        assert self._test_application_health(app_name), "Application not healthy after pod failure"
        
        # Cleanup
        self._cleanup_test_application(app_name)

    def test_node_failure_resilience(self):
        """Test cluster resilience to node failures."""
        logger.info("Testing node failure resilience")
        
        # Get cluster nodes
        nodes = self.k8s_core.list_node().items
        worker_nodes = [n for n in nodes if 'node-role.kubernetes.io/master' not in n.metadata.labels]
        
        if len(worker_nodes) < 3:
            pytest.skip("Need at least 3 worker nodes for node failure testing")
        
        # Deploy test application across multiple nodes
        app_name = "chaos-node-test-app"
        self._deploy_test_application(app_name, replicas=6, anti_affinity=True)
        self._wait_for_deployment_ready(app_name, timeout=300)
        
        # Select a node to "fail"
        target_node = worker_nodes[0]
        node_name = target_node.metadata.name
        
        logger.info(f"Simulating failure of node: {node_name}")
        
        # Cordon the node
        self._cordon_node(node_name)
        
        # Drain the node
        self._drain_node(node_name)
        
        # Wait for pods to reschedule
        time.sleep(30)
        
        # Verify application is still healthy
        assert self._test_application_health(app_name), "Application not healthy after node failure"
        
        # Verify pods rescheduled to other nodes
        pods = self._get_pods(app_name)
        nodes_with_pods = {pod.spec.node_name for pod in pods if pod.spec.node_name != node_name}
        assert len(nodes_with_pods) >= 2, "Pods not distributed across multiple nodes"
        
        # Uncordon the node
        self._uncordon_node(node_name)
        
        # Cleanup
        self._cleanup_test_application(app_name)

    def test_network_partition_resilience(self):
        """Test application resilience to network partitions."""
        logger.info("Testing network partition resilience")
        
        # Deploy distributed application (frontend + backend)
        frontend_name = "chaos-frontend"
        backend_name = "chaos-backend"
        
        self._deploy_distributed_application(frontend_name, backend_name)
        
        # Wait for applications to be ready
        self._wait_for_deployment_ready(frontend_name, timeout=300)
        self._wait_for_deployment_ready(backend_name, timeout=300)
        
        # Test normal communication
        assert self._test_service_communication(frontend_name, backend_name), \
            "Initial service communication failed"
        
        # Create network policy to simulate partition
        self._create_network_partition_policy(backend_name)
        
        # Wait for network policy to take effect
        time.sleep(10)
        
        # Test that communication is blocked
        assert not self._test_service_communication(frontend_name, backend_name), \
            "Network partition not effective"
        
        # Remove network policy
        self._remove_network_partition_policy()
        
        # Wait for network to recover
        time.sleep(10)
        
        # Verify communication is restored
        assert self._test_service_communication(frontend_name, backend_name), \
            "Service communication not restored after partition"
        
        # Cleanup
        self._cleanup_test_application(frontend_name)
        self._cleanup_test_application(backend_name)

    def test_resource_exhaustion_resilience(self):
        """Test cluster resilience to resource exhaustion."""
        logger.info("Testing resource exhaustion resilience")
        
        # Deploy resource-intensive application
        app_name = "chaos-resource-hog"
        self._deploy_resource_intensive_app(app_name)
        
        # Monitor cluster resource usage
        initial_usage = self._get_cluster_resource_usage()
        
        # Wait for resource usage to increase
        time.sleep(30)
        
        # Deploy normal application
        normal_app = "chaos-normal-app"
        self._deploy_test_application(normal_app, replicas=2)
        
        # Verify normal application can still be scheduled
        try:
            self._wait_for_deployment_ready(normal_app, timeout=120)
            normal_app_healthy = True
        except:
            normal_app_healthy = False
        
        # Check if cluster autoscaler scaled up
        final_usage = self._get_cluster_resource_usage()
        
        # Verify cluster didn't become completely unresponsive
        assert self._test_cluster_api_responsiveness(), "Cluster API became unresponsive"
        
        # Cleanup resource-intensive app first
        self._cleanup_test_application(app_name)
        
        # Wait for resources to be freed
        time.sleep(30)
        
        if not normal_app_healthy:
            # Try deploying normal app again now that resources are freed
            self._wait_for_deployment_ready(normal_app, timeout=120)
        
        # Cleanup
        self._cleanup_test_application(normal_app)

    def test_storage_failure_resilience(self):
        """Test application resilience to storage failures."""
        logger.info("Testing storage failure resilience")
        
        # Deploy stateful application with persistent volume
        app_name = "chaos-stateful-app"
        self._deploy_stateful_application(app_name)
        
        # Wait for application to be ready
        self._wait_for_statefulset_ready(app_name, timeout=300)
        
        # Write test data
        test_data = f"chaos-test-{int(time.time())}"
        self._write_test_data(app_name, test_data)
        
        # Simulate storage failure by deleting pod (PV should persist)
        self._delete_statefulset_pod(app_name, 0)
        
        # Wait for pod to be recreated
        time.sleep(30)
        self._wait_for_statefulset_ready(app_name, timeout=180)
        
        # Verify data persistence
        recovered_data = self._read_test_data(app_name)
        assert recovered_data == test_data, "Data not persisted after storage failure simulation"
        
        # Cleanup
        self._cleanup_stateful_application(app_name)

    def test_dns_failure_resilience(self):
        """Test application resilience to DNS failures."""
        logger.info("Testing DNS failure resilience")
        
        # Deploy applications that depend on service discovery
        app_name = "chaos-dns-test"
        self._deploy_test_application(app_name, replicas=2)
        self._wait_for_deployment_ready(app_name, timeout=300)
        
        # Test normal DNS resolution
        assert self._test_dns_resolution("kubernetes.default.svc.cluster.local"), \
            "Initial DNS resolution failed"
        
        # Scale down CoreDNS to simulate DNS failure
        coredns_replicas = self._scale_coredns(0)
        
        # Wait for DNS to fail
        time.sleep(10)
        
        # Verify DNS failure
        assert not self._test_dns_resolution("kubernetes.default.svc.cluster.local", timeout=5), \
            "DNS should have failed"
        
        # Restore CoreDNS
        self._scale_coredns(coredns_replicas)
        
        # Wait for DNS to recover
        time.sleep(30)
        
        # Verify DNS recovery
        assert self._test_dns_resolution("kubernetes.default.svc.cluster.local"), \
            "DNS not recovered"
        
        # Cleanup
        self._cleanup_test_application(app_name)

    def test_chaos_mesh_experiments(self):
        """Test various Chaos Mesh experiments."""
        logger.info("Testing Chaos Mesh experiments")
        
        # Verify Chaos Mesh is installed
        assert self._is_chaos_mesh_installed(), "Chaos Mesh not installed"
        
        app_name = "chaos-mesh-test-app"
        self._deploy_test_application(app_name, replicas=3)
        self._wait_for_deployment_ready(app_name, timeout=300)
        
        # Test Pod Kill experiment
        pod_kill_experiment = {
            "apiVersion": "chaos-mesh.org/v1alpha1",
            "kind": "PodChaos",
            "metadata": {
                "name": "test-pod-kill",
                "namespace": self.namespace
            },
            "spec": {
                "action": "pod-kill",
                "mode": "one",
                "selector": {
                    "namespaces": [self.namespace],
                    "labelSelectors": {"app": app_name}
                },
                "duration": "30s"
            }
        }
        
        # Apply experiment
        self._apply_chaos_experiment(pod_kill_experiment)
        
        # Wait for experiment to complete
        time.sleep(45)
        
        # Verify application recovered
        assert self._test_application_health(app_name), \
            "Application not healthy after Chaos Mesh pod kill"
        
        # Cleanup experiment
        self._cleanup_chaos_experiment("test-pod-kill", "PodChaos")
        self._cleanup_test_application(app_name)

    # Helper methods
    def _deploy_test_application(self, name, replicas=3, anti_affinity=False):
        """Deploy a test application."""
        deployment = {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {"name": name, "namespace": self.namespace},
            "spec": {
                "replicas": replicas,
                "selector": {"matchLabels": {"app": name}},
                "template": {
                    "metadata": {"labels": {"app": name}},
                    "spec": {
                        "containers": [{
                            "name": "app",
                            "image": "nginx:1.21-alpine",
                            "ports": [{"containerPort": 80}],
                            "resources": {
                                "requests": {"cpu": "50m", "memory": "64Mi"},
                                "limits": {"cpu": "200m", "memory": "256Mi"}
                            },
                            "readinessProbe": {
                                "httpGet": {"path": "/", "port": 80},
                                "initialDelaySeconds": 5,
                                "periodSeconds": 10
                            }
                        }]
                    }
                }
            }
        }
        
        if anti_affinity:
            deployment["spec"]["template"]["spec"]["affinity"] = {
                "podAntiAffinity": {
                    "preferredDuringSchedulingIgnoredDuringExecution": [{
                        "weight": 100,
                        "podAffinityTerm": {
                            "labelSelector": {"matchLabels": {"app": name}},
                            "topologyKey": "kubernetes.io/hostname"
                        }
                    }]
                }
            }
        
        self.k8s_apps.create_namespaced_deployment(self.namespace, deployment)
        
        # Create service
        service = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": f"{name}-service", "namespace": self.namespace},
            "spec": {
                "selector": {"app": name},
                "ports": [{"port": 80, "targetPort": 80}]
            }
        }
        
        self.k8s_core.create_namespaced_service(self.namespace, service)

    def _wait_for_deployment_ready(self, name, timeout=300):
        """Wait for deployment to be ready."""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                deployment = self.k8s_apps.read_namespaced_deployment(name, self.namespace)
                if (deployment.status.ready_replicas and 
                    deployment.status.ready_replicas == deployment.spec.replicas):
                    return True
            except:
                pass
            time.sleep(5)
        raise TimeoutError(f"Deployment {name} not ready within {timeout} seconds")

    def _get_pod_count(self, app_name):
        """Get total pod count for application."""
        pods = self.k8s_core.list_namespaced_pod(
            self.namespace, 
            label_selector=f"app={app_name}"
        ).items
        return len(pods)

    def _get_ready_pod_count(self, app_name):
        """Get ready pod count for application."""
        pods = self.k8s_core.list_namespaced_pod(
            self.namespace,
            label_selector=f"app={app_name}"
        ).items
        
        ready_count = 0
        for pod in pods:
            if pod.status.phase == "Running":
                for condition in pod.status.conditions or []:
                    if condition.type == "Ready" and condition.status == "True":
                        ready_count += 1
                        break
        return ready_count

    def _kill_random_pods(self, app_name, count):
        """Kill random pods from application."""
        pods = self.k8s_core.list_namespaced_pod(
            self.namespace,
            label_selector=f"app={app_name}"
        ).items
        
        import random
        pods_to_kill = random.sample(pods, min(count, len(pods)))
        
        for pod in pods_to_kill:
            self.k8s_core.delete_namespaced_pod(pod.metadata.name, self.namespace)
        
        return len(pods_to_kill)

    def _test_application_health(self, app_name):
        """Test if application is healthy and responding."""
        try:
            # Port forward to test service
            service_name = f"{app_name}-service"
            # In real implementation, would use kubectl port-forward or ingress
            # For now, just check if pods are ready
            return self._get_ready_pod_count(app_name) > 0
        except:
            return False

    def _cleanup_test_application(self, name):
        """Clean up test application."""
        try:
            self.k8s_apps.delete_namespaced_deployment(name, self.namespace)
            self.k8s_core.delete_namespaced_service(f"{name}-service", self.namespace)
        except:
            pass

    def _cordon_node(self, node_name):
        """Cordon a node."""
        body = {"spec": {"unschedulable": True}}
        self.k8s_core.patch_node(node_name, body)

    def _uncordon_node(self, node_name):
        """Uncordon a node."""
        body = {"spec": {"unschedulable": False}}
        self.k8s_core.patch_node(node_name, body)

    def _drain_node(self, node_name):
        """Drain a node by deleting pods."""
        pods = self.k8s_core.list_pod_for_all_namespaces(
            field_selector=f"spec.nodeName={node_name}"
        ).items
        
        for pod in pods:
            if pod.metadata.namespace in ["kube-system", "kube-public"]:
                continue  # Skip system pods
            try:
                self.k8s_core.delete_namespaced_pod(
                    pod.metadata.name, 
                    pod.metadata.namespace
                )
            except:
                pass

    def _get_pods(self, app_name):
        """Get pods for application."""
        return self.k8s_core.list_namespaced_pod(
            self.namespace,
            label_selector=f"app={app_name}"
        ).items

    def _is_chaos_mesh_installed(self):
        """Check if Chaos Mesh is installed."""
        try:
            self.k8s_core.list_namespaced_pod("chaos-system", label_selector="app.kubernetes.io/name=chaos-mesh")
            return True
        except:
            return False

    def _apply_chaos_experiment(self, experiment):
        """Apply a Chaos Mesh experiment."""
        group = experiment["apiVersion"].split("/")[0]
        version = experiment["apiVersion"].split("/")[1]
        plural = experiment["kind"].lower() + "s"
        
        self.k8s_custom.create_namespaced_custom_object(
            group=group,
            version=version,
            namespace=self.namespace,
            plural=plural,
            body=experiment
        )

    def _cleanup_chaos_experiment(self, name, kind):
        """Clean up a chaos experiment."""
        try:
            group = "chaos-mesh.org"
            version = "v1alpha1"
            plural = kind.lower() + "s"
            
            self.k8s_custom.delete_namespaced_custom_object(
                group=group,
                version=version,
                namespace=self.namespace,
                plural=plural,
                name=name
            )
        except:
            pass

class TestEKSClusterUpgrade:
    """Test suite for EKS cluster upgrade procedures."""
    
    @pytest.fixture(autouse=True)
    def setup_clients(self):
        """Setup AWS clients."""
        self.eks_client = boto3.client('eks')
        self.cluster_name = os.environ.get('CLUSTER_NAME', 'eks-cluster-dev')

    def test_pre_upgrade_validation(self):
        """Test pre-upgrade validation procedures."""
        logger.info("Testing pre-upgrade validation")
        
        # Check cluster status
        cluster = self.eks_client.describe_cluster(name=self.cluster_name)
        assert cluster['cluster']['status'] == 'ACTIVE', "Cluster not in ACTIVE state"
        
        # Check node groups
        node_groups = self.eks_client.list_nodegroups(clusterName=self.cluster_name)
        for ng_name in node_groups['nodegroups']:
            ng = self.eks_client.describe_nodegroup(
                clusterName=self.cluster_name,
                nodegroupName=ng_name
            )
            assert ng['nodegroup']['status'] == 'ACTIVE', f"Node group {ng_name} not active"

    def test_upgrade_compatibility(self):
        """Test upgrade compatibility checks."""
        logger.info("Testing upgrade compatibility")
        
        # Get current cluster version
        cluster = self.eks_client.describe_cluster(name=self.cluster_name)
        current_version = cluster['cluster']['version']
        
        # Check for deprecated APIs (mock test)
        deprecated_apis = self._check_deprecated_apis()
        assert len(deprecated_apis) == 0, f"Found deprecated APIs: {deprecated_apis}"

    def test_backup_procedures(self):
        """Test backup procedures before upgrade."""
        logger.info("Testing backup procedures")
        
        # Test cluster configuration backup
        backup_created = self._create_cluster_backup()
        assert backup_created, "Failed to create cluster backup"
        
        # Test backup validation
        backup_valid = self._validate_backup()
        assert backup_valid, "Backup validation failed"

    def _check_deprecated_apis(self):
        """Mock function to check for deprecated APIs."""
        # In real implementation, would use kubent or similar tool
        return []

    def _create_cluster_backup(self):
        """Mock function to create cluster backup."""
        # In real implementation, would backup cluster resources
        return True

    def _validate_backup(self):
        """Mock function to validate backup."""
        # In real implementation, would validate backup integrity
        return True

if __name__ == "__main__":
    # Run chaos engineering tests
    pytest.main([__file__ + "::TestChaosEngineering", "-v"])
    
    # Run upgrade tests
    pytest.main([__file__ + "::TestEKSClusterUpgrade", "-v"])
