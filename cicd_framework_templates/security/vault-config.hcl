# HashiCorp Vault Configuration Template
# Production-ready configuration with security best practices

# Storage backend configuration
storage "consul" {
  address = "consul.service.consul:8500"
  path    = "vault/"
  
  # Consul ACL token for Vault
  token = "vault-consul-token"
  
  # TLS configuration for Consul communication
  scheme = "https"
  tls_ca_file = "/vault/tls/consul-ca.pem"
  tls_cert_file = "/vault/tls/consul-client.pem"
  tls_key_file = "/vault/tls/consul-client-key.pem"
  tls_skip_verify = false
}

# Alternative: Integrated storage (Raft)
# storage "raft" {
#   path = "/vault/data"
#   node_id = "vault-node-1"
#   
#   retry_join {
#     leader_api_addr = "https://vault-0.vault-internal:8200"
#   }
#   retry_join {
#     leader_api_addr = "https://vault-1.vault-internal:8200"
#   }
#   retry_join {
#     leader_api_addr = "https://vault-2.vault-internal:8200"
#   }
# }

# Listener configuration
listener "tcp" {
  address = "0.0.0.0:8200"
  
  # TLS configuration
  tls_cert_file = "/vault/tls/vault-server.pem"
  tls_key_file = "/vault/tls/vault-server-key.pem"
  tls_client_ca_file = "/vault/tls/vault-ca.pem"
  
  # Security headers
  tls_min_version = "tls12"
  tls_cipher_suites = "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
  
  # Disable HTTP/2 for security
  tls_disable_client_certs = false
  tls_require_and_verify_client_cert = false
}

# Cluster configuration for HA
cluster_addr = "https://vault.service.consul:8201"
api_addr = "https://vault.service.consul:8200"

# Seal configuration (Auto-unseal with cloud KMS)
seal "awskms" {
  region = "us-west-2"
  kms_key_id = "vault-unseal-key-id"
  endpoint = "https://kms.us-west-2.amazonaws.com"
}

# Alternative: Azure Key Vault seal
# seal "azurekeyvault" {
#   tenant_id = "azure-tenant-id"
#   client_id = "azure-client-id"
#   client_secret = "azure-client-secret"
#   vault_name = "vault-key-vault"
#   key_name = "vault-unseal-key"
# }

# Alternative: Google Cloud KMS seal
# seal "gcpckms" {
#   project = "gcp-project-id"
#   region = "global"
#   key_ring = "vault-keyring"
#   crypto_key = "vault-key"
# }

# UI configuration
ui = true

# Logging configuration
log_level = "INFO"
log_format = "json"

# Disable mlock for containers (use with caution)
disable_mlock = false

# Default lease TTL
default_lease_ttl = "768h"
max_lease_ttl = "8760h"

# Plugin directory
plugin_directory = "/vault/plugins"

# Telemetry configuration
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
  
  # StatsD configuration
  statsd_address = "statsd.service.consul:8125"
  
  # Circonus configuration
  # circonus_api_token = "circonus-api-token"
  # circonus_api_app = "vault"
  # circonus_api_url = "https://api.circonus.com/v2"
  # circonus_submission_interval = "10s"
  # circonus_submission_url = "https://trap.noit.circonus.net/module/httptrap/check-id/secret"
}

# Entropy augmentation (for additional randomness)
entropy "seal" {
  mode = "augmentation"
}

# Performance and caching
cache_size = "32000"

# Disable clustering for single-node deployments
# disable_clustering = true

# Raw storage endpoint (disable in production)
raw_storage_endpoint = false

# Introspection endpoint (disable in production)
introspection_endpoint = false

# Disable printing of vault configuration
disable_printable_check = true

