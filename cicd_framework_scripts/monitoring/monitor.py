#!/usr/bin/env python3

"""
CI/CD Framework Monitoring and Alerting Tool
Comprehensive monitoring solution with alerting capabilities
"""

import argparse
import json
import logging
import os
import smtplib
import time
from datetime import datetime, timedelta
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart
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
        logging.FileHandler('/var/log/cicd-monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class AlertManager:
    """Handle different types of alerts"""
    
    def __init__(self, config_data: Dict):
        self.config = config_data
        self.smtp_config = config_data.get('smtp', {})
        self.slack_config = config_data.get('slack', {})
        self.webhook_config = config_data.get('webhook', {})
    
    def send_email_alert(self, subject: str, message: str, recipients: List[str]) -> bool:
        """Send email alert"""
        try:
            if not self.smtp_config.get('enabled', False):
                return False
            
            msg = MimeMultipart()
            msg['From'] = self.smtp_config['from']
            msg['To'] = ', '.join(recipients)
            msg['Subject'] = subject
            
            msg.attach(MimeText(message, 'html'))
            
            server = smtplib.SMTP(self.smtp_config['host'], self.smtp_config['port'])
            if self.smtp_config.get('tls', False):
                server.starttls()
            if self.smtp_config.get('username'):
                server.login(self.smtp_config['username'], self.smtp_config['password'])
            
            server.send_message(msg)
            server.quit()
            
            logger.info(f"Email alert sent to {recipients}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send email alert: {e}")
            return False
    
    def send_slack_alert(self, message: str, channel: str = None) -> bool:
        """Send Slack alert"""
        try:
            if not self.slack_config.get('enabled', False):
                return False
            
            webhook_url = self.slack_config['webhook_url']
            channel = channel or self.slack_config.get('default_channel', '#alerts')
            
            payload = {
                'channel': channel,
                'username': 'CI/CD Monitor',
                'text': message,
                'icon_emoji': ':warning:'
            }
            
            response = requests.post(webhook_url, json=payload, timeout=10)
            response.raise_for_status()
            
            logger.info(f"Slack alert sent to {channel}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send Slack alert: {e}")
            return False
    
    def send_webhook_alert(self, alert_data: Dict) -> bool:
        """Send webhook alert"""
        try:
            if not self.webhook_config.get('enabled', False):
                return False
            
            webhook_url = self.webhook_config['url']
            headers = self.webhook_config.get('headers', {})
            
            response = requests.post(webhook_url, json=alert_data, headers=headers, timeout=10)
            response.raise_for_status()
            
            logger.info("Webhook alert sent successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send webhook alert: {e}")
            return False


class CICDMonitor:
    """Main monitoring class"""
    
    def __init__(self, config_file: str):
        """Initialize monitor with configuration"""
        self.config = self._load_config(config_file)
        self.alert_manager = AlertManager(self.config.get('alerts', {}))
        
        # Initialize Kubernetes client
        try:
            try:
                config.load_incluster_config()
            except:
                config.load_kube_config()
            
            self.k8s_apps_v1 = client.AppsV1Api()
            self.k8s_core_v1 = client.CoreV1Api()
            self.k8s_metrics = client.CustomObjectsApi()
            
        except Exception as e:
            logger.error(f"Failed to initialize Kubernetes client: {e}")
            raise
    
    def _load_config(self, config_file: str) -> Dict:
        """Load configuration from file"""
        try:
            with open(config_file, 'r') as f:
                if config_file.endswith('.yaml') or config_file.endswith('.yml'):
                    return yaml.safe_load(f)
                else:
                    return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config file {config_file}: {e}")
            raise
    
    def check_deployment_health(self, namespace: str) -> List[Dict]:
        """Check health of all deployments in namespace"""
        issues = []
        
        try:
            deployments = self.k8s_apps_v1.list_namespaced_deployment(namespace=namespace)
            
            for deployment in deployments.items:
                name = deployment.metadata.name
                spec_replicas = deployment.spec.replicas or 0
                ready_replicas = deployment.status.ready_replicas or 0
                available_replicas = deployment.status.available_replicas or 0
                
                # Check if deployment is unhealthy
                if ready_replicas < spec_replicas:
                    issues.append({
                        'type': 'deployment_unhealthy',
                        'severity': 'critical' if ready_replicas == 0 else 'warning',
                        'resource': f"{namespace}/{name}",
                        'message': f"Deployment {name} has {ready_replicas}/{spec_replicas} ready replicas",
                        'timestamp': datetime.now().isoformat()
                    })
                
                # Check for old deployments
                creation_time = deployment.metadata.creation_timestamp
                age = datetime.now(creation_time.tzinfo) - creation_time
                max_age_days = self.config.get('thresholds', {}).get('max_deployment_age_days', 90)
                
                if age.days > max_age_days:
                    issues.append({
                        'type': 'deployment_old',
                        'severity': 'info',
                        'resource': f"{namespace}/{name}",
                        'message': f"Deployment {name} is {age.days} days old",
                        'timestamp': datetime.now().isoformat()
                    })
        
        except ApiException as e:
            logger.error(f"Failed to check deployment health: {e}")
            issues.append({
                'type': 'api_error',
                'severity': 'critical',
                'resource': f"namespace/{namespace}",
                'message': f"Failed to access Kubernetes API: {e}",
                'timestamp': datetime.now().isoformat()
            })
        
        return issues
    
    def check_pod_health(self, namespace: str) -> List[Dict]:
        """Check health of pods in namespace"""
        issues = []
        
        try:
            pods = self.k8s_core_v1.list_namespaced_pod(namespace=namespace)
            
            for pod in pods.items:
                name = pod.metadata.name
                phase = pod.status.phase
                
                # Check for failed pods
                if phase == 'Failed':
                    issues.append({
                        'type': 'pod_failed',
                        'severity': 'critical',
                        'resource': f"{namespace}/{name}",
                        'message': f"Pod {name} is in Failed state",
                        'timestamp': datetime.now().isoformat()
                    })
                
                # Check for pending pods
                elif phase == 'Pending':
                    creation_time = pod.metadata.creation_timestamp
                    age = datetime.now(creation_time.tzinfo) - creation_time
                    
                    if age.total_seconds() > 300:  # 5 minutes
                        issues.append({
                            'type': 'pod_pending',
                            'severity': 'warning',
                            'resource': f"{namespace}/{name}",
                            'message': f"Pod {name} has been pending for {age}",
                            'timestamp': datetime.now().isoformat()
                        })
                
                # Check container restart counts
                if pod.status.container_statuses:
                    for container_status in pod.status.container_statuses:
                        restart_count = container_status.restart_count
                        max_restarts = self.config.get('thresholds', {}).get('max_container_restarts', 5)
                        
                        if restart_count > max_restarts:
                            issues.append({
                                'type': 'high_restart_count',
                                'severity': 'warning',
                                'resource': f"{namespace}/{name}/{container_status.name}",
                                'message': f"Container {container_status.name} has restarted {restart_count} times",
                                'timestamp': datetime.now().isoformat()
                            })
        
        except ApiException as e:
            logger.error(f"Failed to check pod health: {e}")
            issues.append({
                'type': 'api_error',
                'severity': 'critical',
                'resource': f"namespace/{namespace}",
                'message': f"Failed to access Kubernetes API: {e}",
                'timestamp': datetime.now().isoformat()
            })
        
        return issues
    
    def check_resource_usage(self, namespace: str) -> List[Dict]:
        """Check resource usage and quotas"""
        issues = []
        
        try:
            # Check resource quotas
            quotas = self.k8s_core_v1.list_namespaced_resource_quota(namespace=namespace)
            
            for quota in quotas.items:
                if quota.status.hard and quota.status.used:
                    for resource, hard_limit in quota.status.hard.items():
                        used = quota.status.used.get(resource, '0')
                        
                        # Convert to comparable values
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
                            issues.append({
                                'type': 'resource_quota_high',
                                'severity': 'critical' if usage_percent > 95 else 'warning',
                                'resource': f"{namespace}/{quota.metadata.name}/{resource}",
                                'message': f"Resource quota {resource} is {usage_percent:.1f}% used ({used}/{hard_limit})",
                                'timestamp': datetime.now().isoformat()
                            })
        
        except ApiException as e:
            logger.error(f"Failed to check resource usage: {e}")
        
        return issues
    
    def check_external_services(self) -> List[Dict]:
        """Check external service health"""
        issues = []
        
        external_services = self.config.get('external_services', [])
        
        for service in external_services:
            try:
                url = service['url']
                timeout = service.get('timeout', 10)
                expected_status = service.get('expected_status', 200)
                
                response = requests.get(url, timeout=timeout)
                
                if response.status_code != expected_status:
                    issues.append({
                        'type': 'external_service_unhealthy',
                        'severity': 'critical',
                        'resource': service['name'],
                        'message': f"Service {service['name']} returned status {response.status_code}, expected {expected_status}",
                        'timestamp': datetime.now().isoformat()
                    })
            
            except requests.RequestException as e:
                issues.append({
                    'type': 'external_service_unreachable',
                    'severity': 'critical',
                    'resource': service['name'],
                    'message': f"Service {service['name']} is unreachable: {e}",
                    'timestamp': datetime.now().isoformat()
                })
        
        return issues
    
    def check_certificate_expiry(self, namespace: str) -> List[Dict]:
        """Check TLS certificate expiry"""
        issues = []
        
        try:
            secrets = self.k8s_core_v1.list_namespaced_secret(namespace=namespace)
            
            for secret in secrets.items:
                if secret.type == 'kubernetes.io/tls' and secret.data:
                    cert_data = secret.data.get('tls.crt')
                    if cert_data:
                        # This would require additional certificate parsing
                        # For now, we'll just check if the secret exists
                        pass
        
        except ApiException as e:
            logger.error(f"Failed to check certificates: {e}")
        
        return issues
    
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
    
    def run_health_checks(self, namespaces: List[str]) -> Dict:
        """Run all health checks"""
        all_issues = []
        
        for namespace in namespaces:
            logger.info(f"Checking health for namespace: {namespace}")
            
            # Run various health checks
            all_issues.extend(self.check_deployment_health(namespace))
            all_issues.extend(self.check_pod_health(namespace))
            all_issues.extend(self.check_resource_usage(namespace))
            all_issues.extend(self.check_certificate_expiry(namespace))
        
        # Check external services
        all_issues.extend(self.check_external_services())
        
        # Group issues by severity
        issues_by_severity = {
            'critical': [i for i in all_issues if i['severity'] == 'critical'],
            'warning': [i for i in all_issues if i['severity'] == 'warning'],
            'info': [i for i in all_issues if i['severity'] == 'info']
        }
        
        return {
            'timestamp': datetime.now().isoformat(),
            'total_issues': len(all_issues),
            'issues_by_severity': issues_by_severity,
            'all_issues': all_issues
        }
    
    def send_alerts(self, health_report: Dict) -> None:
        """Send alerts based on health report"""
        critical_issues = health_report['issues_by_severity']['critical']
        warning_issues = health_report['issues_by_severity']['warning']
        
        if critical_issues:
            # Send critical alerts
            message = self._format_alert_message(critical_issues, 'CRITICAL')
            
            # Email alert
            if self.config.get('alerts', {}).get('email', {}).get('critical', False):
                recipients = self.config['alerts']['email']['recipients']
                self.alert_manager.send_email_alert(
                    'CRITICAL: CI/CD Infrastructure Issues',
                    message,
                    recipients
                )
            
            # Slack alert
            if self.config.get('alerts', {}).get('slack', {}).get('critical', False):
                self.alert_manager.send_slack_alert(message)
            
            # Webhook alert
            if self.config.get('alerts', {}).get('webhook', {}).get('critical', False):
                self.alert_manager.send_webhook_alert({
                    'severity': 'critical',
                    'issues': critical_issues,
                    'timestamp': health_report['timestamp']
                })
        
        if warning_issues and self.config.get('alerts', {}).get('send_warnings', True):
            # Send warning alerts (less frequently)
            message = self._format_alert_message(warning_issues, 'WARNING')
            
            if self.config.get('alerts', {}).get('slack', {}).get('warning', False):
                self.alert_manager.send_slack_alert(message)
    
    def _format_alert_message(self, issues: List[Dict], severity: str) -> str:
        """Format alert message"""
        message = f"🚨 {severity} CI/CD Infrastructure Alert\n\n"
        message += f"Found {len(issues)} {severity.lower()} issues:\n\n"
        
        for issue in issues[:10]:  # Limit to first 10 issues
            message += f"• {issue['type']}: {issue['message']}\n"
            message += f"  Resource: {issue['resource']}\n"
            message += f"  Time: {issue['timestamp']}\n\n"
        
        if len(issues) > 10:
            message += f"... and {len(issues) - 10} more issues\n"
        
        return message


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='CI/CD Framework Monitor')
    parser.add_argument('--config', '-c', required=True, help='Configuration file path')
    parser.add_argument('--namespaces', '-n', nargs='+', required=True, help='Namespaces to monitor')
    parser.add_argument('--once', action='store_true', help='Run once and exit')
    parser.add_argument('--interval', '-i', type=int, default=300, help='Check interval in seconds')
    parser.add_argument('--output', '-o', help='Output file for health report')
    
    args = parser.parse_args()
    
    try:
        monitor = CICDMonitor(args.config)
        
        if args.once:
            # Run once
            health_report = monitor.run_health_checks(args.namespaces)
            
            if args.output:
                with open(args.output, 'w') as f:
                    json.dump(health_report, f, indent=2)
                logger.info(f"Health report saved to {args.output}")
            else:
                print(json.dumps(health_report, indent=2))
            
            monitor.send_alerts(health_report)
        
        else:
            # Run continuously
            logger.info(f"Starting continuous monitoring with {args.interval}s interval")
            
            while True:
                try:
                    health_report = monitor.run_health_checks(args.namespaces)
                    monitor.send_alerts(health_report)
                    
                    if args.output:
                        with open(args.output, 'w') as f:
                            json.dump(health_report, f, indent=2)
                    
                    logger.info(f"Health check completed. Found {health_report['total_issues']} issues.")
                    
                except Exception as e:
                    logger.error(f"Health check failed: {e}")
                
                time.sleep(args.interval)
    
    except KeyboardInterrupt:
        logger.info("Monitoring stopped by user")
    except Exception as e:
        logger.error(f"Monitor failed: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    exit(main())

