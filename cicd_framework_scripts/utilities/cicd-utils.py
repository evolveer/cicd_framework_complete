#!/usr/bin/env python3

"""
CI/CD Framework Utility Script
Comprehensive utility for common CI/CD operations and maintenance tasks
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
import yaml
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import requests
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/cicd-utils.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


class CICDUtils:
    """Main utility class for CI/CD operations"""
    
    def __init__(self):
        """Initialize the utility with Kubernetes configuration"""
        try:
            # Try to load in-cluster config first, then local config
            try:
                config.load_incluster_config()
                logger.info("Loaded in-cluster Kubernetes configuration")
            except:
                config.load_kube_config()
                logger.info("Loaded local Kubernetes configuration")
            
            self.k8s_apps_v1 = client.AppsV1Api()
            self.k8s_core_v1 = client.CoreV1Api()
            self.k8s_networking_v1 = client.NetworkingV1Api()
            
        except Exception as e:
            logger.error(f"Failed to initialize Kubernetes client: {e}")
            sys.exit(1)
    
    def get_deployment_status(self, namespace: str, deployment_name: Optional[str] = None) -> Dict:
        """Get deployment status for a namespace or specific deployment"""
        try:
            if deployment_name:
                deployments = [self.k8s_apps_v1.read_namespaced_deployment(
                    name=deployment_name, namespace=namespace
                )]
            else:
                deployments = self.k8s_apps_v1.list_namespaced_deployment(
                    namespace=namespace
                ).items
            
            status_info = []
            for deployment in deployments:
                status = {
                    'name': deployment.metadata.name,
                    'namespace': deployment.metadata.namespace,
                    'replicas': deployment.spec.replicas,
                    'ready_replicas': deployment.status.ready_replicas or 0,
                    'available_replicas': deployment.status.available_replicas or 0,
                    'image': deployment.spec.template.spec.containers[0].image,
                    'creation_timestamp': deployment.metadata.creation_timestamp.isoformat(),
                    'labels': deployment.metadata.labels or {}
                }
                
                # Calculate health status
                if status['ready_replicas'] == status['replicas']:
                    status['health'] = 'Healthy'
                elif status['ready_replicas'] > 0:
                    status['health'] = 'Degraded'
                else:
                    status['health'] = 'Unhealthy'
                
                status_info.append(status)
            
            return {'deployments': status_info}
            
        except ApiException as e:
            logger.error(f"Kubernetes API error: {e}")
            return {'error': str(e)}
    
    def scale_deployment(self, namespace: str, deployment_name: str, replicas: int) -> bool:
        """Scale a deployment to specified number of replicas"""
        try:
            # Get current deployment
            deployment = self.k8s_apps_v1.read_namespaced_deployment(
                name=deployment_name, namespace=namespace
            )
            
            # Update replica count
            deployment.spec.replicas = replicas
            
            # Apply the update
            self.k8s_apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=deployment
            )
            
            logger.info(f"Scaled deployment {deployment_name} to {replicas} replicas")
            return True
            
        except ApiException as e:
            logger.error(f"Failed to scale deployment: {e}")
            return False
    
    def restart_deployment(self, namespace: str, deployment_name: str) -> bool:
        """Restart a deployment by updating its restart annotation"""
        try:
            # Get current deployment
            deployment = self.k8s_apps_v1.read_namespaced_deployment(
                name=deployment_name, namespace=namespace
            )
            
            # Add restart annotation
            if not deployment.spec.template.metadata.annotations:
                deployment.spec.template.metadata.annotations = {}
            
            deployment.spec.template.metadata.annotations['kubectl.kubernetes.io/restartedAt'] = \
                datetime.now().isoformat()
            
            # Apply the update
            self.k8s_apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=deployment
            )
            
            logger.info(f"Restarted deployment {deployment_name}")
            return True
            
        except ApiException as e:
            logger.error(f"Failed to restart deployment: {e}")
            return False
    
    def get_pod_logs(self, namespace: str, pod_name: str, container: Optional[str] = None, 
                     lines: int = 100, follow: bool = False) -> str:
        """Get logs from a pod"""
        try:
            logs = self.k8s_core_v1.read_namespaced_pod_log(
                name=pod_name,
                namespace=namespace,
                container=container,
                tail_lines=lines,
                follow=follow
            )
            return logs
            
        except ApiException as e:
            logger.error(f"Failed to get pod logs: {e}")
            return f"Error: {e}"
    
    def cleanup_old_resources(self, namespace: str, days: int = 7) -> Dict:
        """Clean up old resources (completed jobs, failed pods, etc.)"""
        cleanup_results = {
            'jobs_deleted': 0,
            'pods_deleted': 0,
            'errors': []
        }
        
        cutoff_date = datetime.now() - timedelta(days=days)
        
        try:
            # Clean up completed jobs
            jobs = client.BatchV1Api().list_namespaced_job(namespace=namespace)
            for job in jobs.items:
                if (job.status.completion_time and 
                    job.status.completion_time < cutoff_date):
                    try:
                        client.BatchV1Api().delete_namespaced_job(
                            name=job.metadata.name,
                            namespace=namespace,
                            propagation_policy='Background'
                        )
                        cleanup_results['jobs_deleted'] += 1
                        logger.info(f"Deleted old job: {job.metadata.name}")
                    except Exception as e:
                        cleanup_results['errors'].append(f"Failed to delete job {job.metadata.name}: {e}")
            
            # Clean up failed/succeeded pods
            pods = self.k8s_core_v1.list_namespaced_pod(namespace=namespace)
            for pod in pods.items:
                if (pod.status.phase in ['Succeeded', 'Failed'] and
                    pod.metadata.creation_timestamp < cutoff_date):
                    try:
                        self.k8s_core_v1.delete_namespaced_pod(
                            name=pod.metadata.name,
                            namespace=namespace
                        )
                        cleanup_results['pods_deleted'] += 1
                        logger.info(f"Deleted old pod: {pod.metadata.name}")
                    except Exception as e:
                        cleanup_results['errors'].append(f"Failed to delete pod {pod.metadata.name}: {e}")
            
        except ApiException as e:
            cleanup_results['errors'].append(f"API error during cleanup: {e}")
        
        return cleanup_results
    
    def check_resource_usage(self, namespace: str) -> Dict:
        """Check resource usage for a namespace"""
        try:
            # Get pods in namespace
            pods = self.k8s_core_v1.list_namespaced_pod(namespace=namespace)
            
            total_cpu_requests = 0
            total_memory_requests = 0
            total_cpu_limits = 0
            total_memory_limits = 0
            pod_count = len(pods.items)
            
            for pod in pods.items:
                if pod.status.phase == 'Running':
                    for container in pod.spec.containers:
                        if container.resources.requests:
                            cpu_req = container.resources.requests.get('cpu', '0')
                            mem_req = container.resources.requests.get('memory', '0')
                            total_cpu_requests += self._parse_cpu(cpu_req)
                            total_memory_requests += self._parse_memory(mem_req)
                        
                        if container.resources.limits:
                            cpu_limit = container.resources.limits.get('cpu', '0')
                            mem_limit = container.resources.limits.get('memory', '0')
                            total_cpu_limits += self._parse_cpu(cpu_limit)
                            total_memory_limits += self._parse_memory(mem_limit)
            
            return {
                'namespace': namespace,
                'pod_count': pod_count,
                'cpu_requests': f"{total_cpu_requests}m",
                'memory_requests': f"{total_memory_requests}Mi",
                'cpu_limits': f"{total_cpu_limits}m",
                'memory_limits': f"{total_memory_limits}Mi"
            }
            
        except ApiException as e:
            logger.error(f"Failed to check resource usage: {e}")
            return {'error': str(e)}
    
    def _parse_cpu(self, cpu_str: str) -> int:
        """Parse CPU string to millicores"""
        if not cpu_str or cpu_str == '0':
            return 0
        if cpu_str.endswith('m'):
            return int(cpu_str[:-1])
        return int(float(cpu_str) * 1000)
    
    def _parse_memory(self, memory_str: str) -> int:
        """Parse memory string to MiB"""
        if not memory_str or memory_str == '0':
            return 0
        
        units = {'Ki': 1/1024, 'Mi': 1, 'Gi': 1024, 'Ti': 1024*1024}
        for unit, multiplier in units.items():
            if memory_str.endswith(unit):
                return int(float(memory_str[:-2]) * multiplier)
        
        # Assume bytes if no unit
        return int(memory_str) // (1024 * 1024)
    
    def generate_deployment_report(self, namespaces: List[str]) -> Dict:
        """Generate comprehensive deployment report"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'namespaces': {}
        }
        
        for namespace in namespaces:
            try:
                deployment_status = self.get_deployment_status(namespace)
                resource_usage = self.check_resource_usage(namespace)
                
                report['namespaces'][namespace] = {
                    'deployments': deployment_status.get('deployments', []),
                    'resource_usage': resource_usage
                }
                
            except Exception as e:
                report['namespaces'][namespace] = {'error': str(e)}
        
        return report
    
    def backup_namespace_configs(self, namespace: str, backup_dir: str) -> bool:
        """Backup all configurations in a namespace"""
        try:
            backup_path = Path(backup_dir) / f"{namespace}-backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
            backup_path.mkdir(parents=True, exist_ok=True)
            
            # Backup deployments
            deployments = self.k8s_apps_v1.list_namespaced_deployment(namespace=namespace)
            for deployment in deployments.items:
                with open(backup_path / f"deployment-{deployment.metadata.name}.yaml", 'w') as f:
                    yaml.dump(client.ApiClient().sanitize_for_serialization(deployment), f)
            
            # Backup services
            services = self.k8s_core_v1.list_namespaced_service(namespace=namespace)
            for service in services.items:
                with open(backup_path / f"service-{service.metadata.name}.yaml", 'w') as f:
                    yaml.dump(client.ApiClient().sanitize_for_serialization(service), f)
            
            # Backup configmaps
            configmaps = self.k8s_core_v1.list_namespaced_config_map(namespace=namespace)
            for cm in configmaps.items:
                with open(backup_path / f"configmap-{cm.metadata.name}.yaml", 'w') as f:
                    yaml.dump(client.ApiClient().sanitize_for_serialization(cm), f)
            
            # Backup secrets (metadata only, not data)
            secrets = self.k8s_core_v1.list_namespaced_secret(namespace=namespace)
            for secret in secrets.items:
                secret_copy = client.ApiClient().sanitize_for_serialization(secret)
                secret_copy['data'] = {}  # Remove sensitive data
                with open(backup_path / f"secret-{secret.metadata.name}.yaml", 'w') as f:
                    yaml.dump(secret_copy, f)
            
            logger.info(f"Backup completed for namespace {namespace} in {backup_path}")
            return True
            
        except Exception as e:
            logger.error(f"Backup failed: {e}")
            return False


def main():
    """Main function to handle command line arguments"""
    parser = argparse.ArgumentParser(description='CI/CD Framework Utility Script')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Status command
    status_parser = subparsers.add_parser('status', help='Get deployment status')
    status_parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    status_parser.add_argument('--deployment', '-d', help='Specific deployment name')
    
    # Scale command
    scale_parser = subparsers.add_parser('scale', help='Scale deployment')
    scale_parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    scale_parser.add_argument('--deployment', '-d', required=True, help='Deployment name')
    scale_parser.add_argument('--replicas', '-r', type=int, required=True, help='Number of replicas')
    
    # Restart command
    restart_parser = subparsers.add_parser('restart', help='Restart deployment')
    restart_parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    restart_parser.add_argument('--deployment', '-d', required=True, help='Deployment name')
    
    # Logs command
    logs_parser = subparsers.add_parser('logs', help='Get pod logs')
    logs_parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    logs_parser.add_argument('--pod', '-p', required=True, help='Pod name')
    logs_parser.add_argument('--container', '-c', help='Container name')
    logs_parser.add_argument('--lines', '-l', type=int, default=100, help='Number of lines')
    
    # Cleanup command
    cleanup_parser = subparsers.add_parser('cleanup', help='Clean up old resources')
    cleanup_parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    cleanup_parser.add_argument('--days', type=int, default=7, help='Age threshold in days')
    
    # Resource usage command
    resources_parser = subparsers.add_parser('resources', help='Check resource usage')
    resources_parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    
    # Report command
    report_parser = subparsers.add_parser('report', help='Generate deployment report')
    report_parser.add_argument('--namespaces', '-n', nargs='+', required=True, help='Namespaces to include')
    report_parser.add_argument('--output', '-o', help='Output file path')
    
    # Backup command
    backup_parser = subparsers.add_parser('backup', help='Backup namespace configurations')
    backup_parser.add_argument('--namespace', '-n', required=True, help='Kubernetes namespace')
    backup_parser.add_argument('--output-dir', '-o', required=True, help='Backup output directory')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    utils = CICDUtils()
    
    try:
        if args.command == 'status':
            result = utils.get_deployment_status(args.namespace, args.deployment)
            print(json.dumps(result, indent=2))
        
        elif args.command == 'scale':
            success = utils.scale_deployment(args.namespace, args.deployment, args.replicas)
            print(f"Scale operation {'succeeded' if success else 'failed'}")
        
        elif args.command == 'restart':
            success = utils.restart_deployment(args.namespace, args.deployment)
            print(f"Restart operation {'succeeded' if success else 'failed'}")
        
        elif args.command == 'logs':
            logs = utils.get_pod_logs(args.namespace, args.pod, args.container, args.lines)
            print(logs)
        
        elif args.command == 'cleanup':
            result = utils.cleanup_old_resources(args.namespace, args.days)
            print(json.dumps(result, indent=2))
        
        elif args.command == 'resources':
            result = utils.check_resource_usage(args.namespace)
            print(json.dumps(result, indent=2))
        
        elif args.command == 'report':
            result = utils.generate_deployment_report(args.namespaces)
            if args.output:
                with open(args.output, 'w') as f:
                    json.dump(result, f, indent=2)
                print(f"Report saved to {args.output}")
            else:
                print(json.dumps(result, indent=2))
        
        elif args.command == 'backup':
            success = utils.backup_namespace_configs(args.namespace, args.output_dir)
            print(f"Backup operation {'succeeded' if success else 'failed'}")
    
    except Exception as e:
        logger.error(f"Command failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()

