#!/usr/bin/env python3

"""
CI/CD Framework Troubleshooting Utility
Comprehensive diagnostic and troubleshooting tool for CI/CD infrastructure
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

import requests
import yaml
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/cicd-troubleshoot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class TroubleshootingTool:
    """Main troubleshooting class"""
    
    def __init__(self):
        """Initialize the troubleshooting tool"""
        try:
            # Initialize Kubernetes client
            try:
                config.load_incluster_config()
                logger.info("Loaded in-cluster Kubernetes configuration")
            except:
                config.load_kube_config()
                logger.info("Loaded local Kubernetes configuration")
            
            self.k8s_apps_v1 = client.AppsV1Api()
            self.k8s_core_v1 = client.CoreV1Api()
            self.k8s_networking_v1 = client.NetworkingV1Api()
            self.k8s_events = client.EventsV1Api()
            
        except Exception as e:
            logger.error(f"Failed to initialize Kubernetes client: {e}")
            sys.exit(1)
    
    def diagnose_deployment_issues(self, namespace: str, deployment_name: str) -> Dict:
        """Diagnose deployment-related issues"""
        issues = []
        recommendations = []
        
        try:
            # Get deployment
            deployment = self.k8s_apps_v1.read_namespaced_deployment(
                name=deployment_name, namespace=namespace
            )
            
            # Check deployment status
            spec_replicas = deployment.spec.replicas or 0
            ready_replicas = deployment.status.ready_replicas or 0
            available_replicas = deployment.status.available_replicas or 0
            
            if ready_replicas < spec_replicas:
                issues.append(f"Deployment has {ready_replicas}/{spec_replicas} ready replicas")
                
                # Get pods for this deployment
                pods = self.k8s_core_v1.list_namespaced_pod(
                    namespace=namespace,
                    label_selector=f"app={deployment_name}"
                )
                
                for pod in pods.items:
                    pod_issues = self._diagnose_pod_issues(pod)
                    issues.extend(pod_issues)
            
            # Check deployment conditions
            if deployment.status.conditions:
                for condition in deployment.status.conditions:
                    if condition.status == 'False':
                        issues.append(f"Deployment condition {condition.type}: {condition.message}")
            
            # Check resource requests and limits
            container = deployment.spec.template.spec.containers[0]
            if not container.resources or not container.resources.requests:
                recommendations.append("Consider setting resource requests for better scheduling")
            
            if not container.resources or not container.resources.limits:
                recommendations.append("Consider setting resource limits to prevent resource exhaustion")
            
        except ApiException as e:
            issues.append(f"Failed to get deployment info: {e}")
        
        return {
            'deployment': deployment_name,
            'namespace': namespace,
            'issues': issues,
            'recommendations': recommendations
        }
    
    def _diagnose_pod_issues(self, pod) -> List[str]:
        """Diagnose issues with a specific pod"""
        issues = []
        
        # Check pod phase
        if pod.status.phase == 'Failed':
            issues.append(f"Pod {pod.metadata.name} is in Failed state")
        elif pod.status.phase == 'Pending':
            issues.append(f"Pod {pod.metadata.name} is stuck in Pending state")
        
        # Check container statuses
        if pod.status.container_statuses:
            for container_status in pod.status.container_statuses:
                if not container_status.ready:
                    issues.append(f"Container {container_status.name} in pod {pod.metadata.name} is not ready")
                
                if container_status.restart_count > 5:
                    issues.append(f"Container {container_status.name} has high restart count: {container_status.restart_count}")
                
                # Check container state
                if container_status.state.waiting:
                    reason = container_status.state.waiting.reason
                    message = container_status.state.waiting.message
                    issues.append(f"Container {container_status.name} waiting: {reason} - {message}")
                
                if container_status.state.terminated:
                    reason = container_status.state.terminated.reason
                    exit_code = container_status.state.terminated.exit_code
                    issues.append(f"Container {container_status.name} terminated: {reason} (exit code: {exit_code})")
        
        return issues
    
    def diagnose_network_issues(self, namespace: str, service_name: str) -> Dict:
        """Diagnose network connectivity issues"""
        issues = []
        recommendations = []
        
        try:
            # Get service
            service = self.k8s_core_v1.read_namespaced_service(
                name=service_name, namespace=namespace
            )
            
            # Check if service has endpoints
            try:
                endpoints = self.k8s_core_v1.read_namespaced_endpoints(
                    name=service_name, namespace=namespace
                )
                
                if not endpoints.subsets or not any(subset.addresses for subset in endpoints.subsets):
                    issues.append(f"Service {service_name} has no endpoints")
                    recommendations.append("Check if pods matching the service selector are running and ready")
            
            except ApiException:
                issues.append(f"No endpoints found for service {service_name}")
            
            # Check service selector
            if not service.spec.selector:
                issues.append(f"Service {service_name} has no selector")
            
            # Check ingress if exists
            try:
                ingresses = self.k8s_networking_v1.list_namespaced_ingress(namespace=namespace)
                for ingress in ingresses.items:
                    if ingress.spec.rules:
                        for rule in ingress.spec.rules:
                            if rule.http and rule.http.paths:
                                for path in rule.http.paths:
                                    if (path.backend.service and 
                                        path.backend.service.name == service_name):
                                        # Check ingress status
                                        if not ingress.status.load_balancer.ingress:
                                            issues.append(f"Ingress {ingress.metadata.name} has no load balancer IP")
            
            except ApiException:
                pass  # Ingress might not exist
        
        except ApiException as e:
            issues.append(f"Failed to get service info: {e}")
        
        return {
            'service': service_name,
            'namespace': namespace,
            'issues': issues,
            'recommendations': recommendations
        }
    
    def diagnose_storage_issues(self, namespace: str) -> Dict:
        """Diagnose persistent volume and storage issues"""
        issues = []
        recommendations = []
        
        try:
            # Check PVCs
            pvcs = self.k8s_core_v1.list_namespaced_persistent_volume_claim(namespace=namespace)
            
            for pvc in pvcs.items:
                if pvc.status.phase != 'Bound':
                    issues.append(f"PVC {pvc.metadata.name} is in {pvc.status.phase} state")
                
                # Check storage usage (if metrics available)
                # This would require metrics server integration
                
        except ApiException as e:
            issues.append(f"Failed to check storage: {e}")
        
        return {
            'namespace': namespace,
            'issues': issues,
            'recommendations': recommendations
        }
    
    def check_resource_constraints(self, namespace: str) -> Dict:
        """Check for resource constraints and quotas"""
        issues = []
        recommendations = []
        
        try:
            # Check resource quotas
            quotas = self.k8s_core_v1.list_namespaced_resource_quota(namespace=namespace)
            
            for quota in quotas.items:
                if quota.status.hard and quota.status.used:
                    for resource, hard_limit in quota.status.hard.items():
                        used = quota.status.used.get(resource, '0')
                        
                        # Calculate usage percentage
                        try:
                            if resource.endswith('.cpu'):
                                hard_val = self._parse_cpu(hard_limit)
                                used_val = self._parse_cpu(used)
                            elif resource.endswith('.memory'):
                                hard_val = self._parse_memory(hard_limit)
                                used_val = self._parse_memory(used)
                            else:
                                hard_val = int(hard_limit)
                                used_val = int(used)
                            
                            usage_percent = (used_val / hard_val) * 100 if hard_val > 0 else 0
                            
                            if usage_percent > 90:
                                issues.append(f"Resource quota {resource} is {usage_percent:.1f}% used")
                            elif usage_percent > 80:
                                recommendations.append(f"Resource quota {resource} is {usage_percent:.1f}% used - consider monitoring")
                        
                        except (ValueError, ZeroDivisionError):
                            pass
            
            # Check limit ranges
            limit_ranges = self.k8s_core_v1.list_namespaced_limit_range(namespace=namespace)
            
            for limit_range in limit_ranges.items:
                # Check if pods are hitting limits
                pods = self.k8s_core_v1.list_namespaced_pod(namespace=namespace)
                
                for pod in pods.items:
                    if pod.status.container_statuses:
                        for container_status in pod.status.container_statuses:
                            if (container_status.state.terminated and 
                                container_status.state.terminated.reason == 'OOMKilled'):
                                issues.append(f"Container {container_status.name} in pod {pod.metadata.name} was OOMKilled")
                                recommendations.append("Consider increasing memory limits or optimizing application memory usage")
        
        except ApiException as e:
            issues.append(f"Failed to check resource constraints: {e}")
        
        return {
            'namespace': namespace,
            'issues': issues,
            'recommendations': recommendations
        }
    
    def get_recent_events(self, namespace: str, hours: int = 1) -> List[Dict]:
        """Get recent events that might indicate issues"""
        events = []
        
        try:
            # Get events from the last hour
            cutoff_time = datetime.now() - timedelta(hours=hours)
            
            k8s_events = self.k8s_core_v1.list_namespaced_event(namespace=namespace)
            
            for event in k8s_events.items:
                if event.last_timestamp and event.last_timestamp > cutoff_time:
                    events.append({
                        'type': event.type,
                        'reason': event.reason,
                        'message': event.message,
                        'object': f"{event.involved_object.kind}/{event.involved_object.name}",
                        'timestamp': event.last_timestamp.isoformat()
                    })
        
        except ApiException as e:
            logger.error(f"Failed to get events: {e}")
        
        return sorted(events, key=lambda x: x['timestamp'], reverse=True)
    
    def check_external_dependencies(self, dependencies: List[Dict]) -> Dict:
        """Check external service dependencies"""
        issues = []
        
        for dep in dependencies:
            try:
                url = dep['url']
                timeout = dep.get('timeout', 10)
                expected_status = dep.get('expected_status', 200)
                
                response = requests.get(url, timeout=timeout)
                
                if response.status_code != expected_status:
                    issues.append({
                        'service': dep['name'],
                        'issue': f"HTTP {response.status_code}, expected {expected_status}",
                        'url': url
                    })
            
            except requests.RequestException as e:
                issues.append({
                    'service': dep['name'],
                    'issue': f"Connection failed: {e}",
                    'url': dep['url']
                })
        
        return {'external_dependencies': issues}
    
    def run_connectivity_tests(self, namespace: str, service_name: str) -> Dict:
        """Run connectivity tests from within the cluster"""
        results = []
        
        try:
            # Create a test pod for connectivity testing
            test_pod_manifest = {
                'apiVersion': 'v1',
                'kind': 'Pod',
                'metadata': {
                    'name': 'connectivity-test',
                    'namespace': namespace
                },
                'spec': {
                    'containers': [{
                        'name': 'test',
                        'image': 'busybox:latest',
                        'command': ['sleep', '300'],
                        'resources': {
                            'requests': {'cpu': '10m', 'memory': '16Mi'},
                            'limits': {'cpu': '50m', 'memory': '32Mi'}
                        }
                    }],
                    'restartPolicy': 'Never'
                }
            }
            
            # Create test pod
            self.k8s_core_v1.create_namespaced_pod(
                namespace=namespace,
                body=test_pod_manifest
            )
            
            # Wait for pod to be ready
            time.sleep(10)
            
            # Test DNS resolution
            dns_test = self._exec_in_pod(
                namespace, 'connectivity-test', 
                ['nslookup', service_name]
            )
            results.append({
                'test': 'DNS Resolution',
                'result': 'PASS' if dns_test['exit_code'] == 0 else 'FAIL',
                'output': dns_test['output']
            })
            
            # Test service connectivity
            service_test = self._exec_in_pod(
                namespace, 'connectivity-test',
                ['wget', '-q', '-O-', f'http://{service_name}', '--timeout=5']
            )
            results.append({
                'test': 'Service Connectivity',
                'result': 'PASS' if service_test['exit_code'] == 0 else 'FAIL',
                'output': service_test['output']
            })
            
            # Cleanup test pod
            self.k8s_core_v1.delete_namespaced_pod(
                name='connectivity-test',
                namespace=namespace
            )
        
        except Exception as e:
            results.append({
                'test': 'Connectivity Test Setup',
                'result': 'FAIL',
                'output': str(e)
            })
        
        return {'connectivity_tests': results}
    
    def _exec_in_pod(self, namespace: str, pod_name: str, command: List[str]) -> Dict:
        """Execute command in pod and return result"""
        try:
            from kubernetes.stream import stream
            
            response = stream(
                self.k8s_core_v1.connect_get_namespaced_pod_exec,
                pod_name,
                namespace,
                command=command,
                stderr=True,
                stdin=False,
                stdout=True,
                tty=False
            )
            
            return {
                'exit_code': 0,
                'output': response
            }
        
        except Exception as e:
            return {
                'exit_code': 1,
                'output': str(e)
            }
    
    def _parse_cpu(self, cpu_str: str) -> float:
        """Parse CPU string to cores"""
        if not cpu_str:
            return 0.0
        if cpu_str.endswith('m'):
            return float(cpu_str[:-1]) / 1000
        return float(cpu_str)
    
    def _parse_memory(self, memory_str: str) -> int:
        """Parse memory string to bytes"""
        if not memory_str:
            return 0
        
        units = {'Ki': 1024, 'Mi': 1024**2, 'Gi': 1024**3, 'Ti': 1024**4}
        for unit, multiplier in units.items():
            if memory_str.endswith(unit):
                return int(float(memory_str[:-2]) * multiplier)
        
        return int(memory_str)
    
    def generate_troubleshooting_report(self, namespace: str, deployment_name: str = None) -> Dict:
        """Generate comprehensive troubleshooting report"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'namespace': namespace,
            'deployment': deployment_name
        }
        
        # Deployment-specific diagnostics
        if deployment_name:
            report['deployment_issues'] = self.diagnose_deployment_issues(namespace, deployment_name)
            report['network_issues'] = self.diagnose_network_issues(namespace, deployment_name)
            report['connectivity_tests'] = self.run_connectivity_tests(namespace, deployment_name)
        
        # General namespace diagnostics
        report['storage_issues'] = self.diagnose_storage_issues(namespace)
        report['resource_constraints'] = self.check_resource_constraints(namespace)
        report['recent_events'] = self.get_recent_events(namespace, hours=2)
        
        # External dependencies (if configured)
        external_deps = [
            {'name': 'Database', 'url': 'http://postgres:5432'},
            {'name': 'Redis', 'url': 'http://redis:6379'},
            {'name': 'External API', 'url': 'https://api.example.com/health'}
        ]
        report['external_dependencies'] = self.check_external_dependencies(external_deps)
        
        return report


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='CI/CD Framework Troubleshooting Tool')
    parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    parser.add_argument('--deployment', '-d', help='Specific deployment to troubleshoot')
    parser.add_argument('--output', '-o', help='Output file for troubleshooting report')
    parser.add_argument('--format', choices=['json', 'yaml'], default='json', help='Output format')
    
    args = parser.parse_args()
    
    try:
        tool = TroubleshootingTool()
        
        # Generate troubleshooting report
        report = tool.generate_troubleshooting_report(args.namespace, args.deployment)
        
        # Format output
        if args.format == 'yaml':
            output = yaml.dump(report, default_flow_style=False)
        else:
            output = json.dumps(report, indent=2)
        
        # Save or print report
        if args.output:
            with open(args.output, 'w') as f:
                f.write(output)
            logger.info(f"Troubleshooting report saved to {args.output}")
        else:
            print(output)
        
        # Print summary
        total_issues = 0
        if 'deployment_issues' in report:
            total_issues += len(report['deployment_issues'].get('issues', []))
        if 'network_issues' in report:
            total_issues += len(report['network_issues'].get('issues', []))
        if 'storage_issues' in report:
            total_issues += len(report['storage_issues'].get('issues', []))
        if 'resource_constraints' in report:
            total_issues += len(report['resource_constraints'].get('issues', []))
        
        logger.info(f"Troubleshooting completed. Found {total_issues} issues.")
        
        return 0 if total_issues == 0 else 1
    
    except Exception as e:
        logger.error(f"Troubleshooting failed: {e}")
        return 1


if __name__ == '__main__':
    exit(main())

