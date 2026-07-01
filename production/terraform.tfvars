# ============================================================================
# Terraform Values File for GCP ALB Configuration
# ============================================================================
# IMPORTANT: Update these values with your actual production settings
# This file should NOT be committed to version control if it contains secrets
# 
# Usage: terraform apply -var-file="terraform.tfvars"
# Or set environment variables: TF_VAR_app_domain="jerney.example.com"
# ============================================================================

# ============================================================================
# REQUIRED: GCP Project Configuration
# ============================================================================

gcp_project_id = "your-gcp-project-id"  # CHANGE THIS: e.g., "jerney-prod-12345"
gcp_region     = "us-central1"          # CHANGE THIS: Match your GKE region
gke_zone       = "us-central1-a"        # CHANGE THIS: Match your GKE zone

# ============================================================================
# REQUIRED: GKE Cluster Configuration
# ============================================================================

gke_cluster_name = "jerney-gke"         # CHANGE THIS: Your cluster name
gcp_network_name = "default"            # CHANGE THIS: If using custom VPC
gcp_subnetwork_name = "default"         # CHANGE THIS: If using custom subnetwork

# ============================================================================
# REQUIRED: Application Domain
# ============================================================================
# This must be a valid domain that you own and can update DNS for
# Google will automatically provision an SSL certificate for this domain

app_domain = "jerney.example.com"       # CHANGE THIS: Your actual domain!

# ============================================================================
# ALB Health Check Configuration
# ============================================================================
# These settings determine how ALB monitors pod health

alb_health_check_interval = 10          # Check every 10 seconds
alb_health_check_timeout  = 5           # Wait 5 seconds for response
alb_healthy_threshold     = 2           # 2 successful checks = HEALTHY
alb_unhealthy_threshold   = 3           # 3 failed checks = UNHEALTHY

# ============================================================================
# ALB Backend Configuration
# ============================================================================
# These settings control how traffic is distributed to pods

alb_backend_port           = 8080       # Frontend pod port
alb_max_rate_per_endpoint  = 1000       # Max 1000 req/sec per pod
alb_session_affinity_ttl   = 3600       # Sticky sessions for 1 hour
alb_connection_draining_timeout = 30    # Wait 30 seconds before stopping pod

# ============================================================================
# Cloud Armor (DDoS Protection)
# ============================================================================

enable_cloud_armor = true

# Rate limiting: Block IPs that exceed this rate
rate_limit_requests_per_minute = 60000  # 1000 requests per second per IP
rate_limit_ban_duration_minutes = 10    # Ban for 10 minutes

# ============================================================================
# Logging Configuration
# ============================================================================

enable_alb_logging      = true
alb_logging_sample_rate = 1.0           # Log all requests (1.0 = 100%)

# ============================================================================
# SSL/TLS Configuration
# ============================================================================

enable_https             = true         # Enable HTTPS
http_to_https_redirect   = true         # Redirect HTTP → HTTPS

# ============================================================================
# Environment and Tags
# ============================================================================

environment      = "production"         # CHANGE THIS: staging/production
application_name = "jerney"

tags = {
  Project     = "Jerney"
  ManagedBy   = "Terraform"
  Environment = "production"
  Owner       = "DevOps Team"
  CostCenter  = "Engineering"
}

# ============================================================================
# DNS Configuration (Optional)
# ============================================================================
# Leave empty to manage DNS manually, or set to your Cloud DNS zone

managed_dns_zone = ""                   # OPTIONAL: e.g., "jerney-zone"

# ============================================================================
# Monitoring and Alerting
# ============================================================================

create_monitoring_dashboard = true

# Error rate alerts
enable_error_alerts      = true
error_rate_threshold     = 5            # Alert if > 5% errors

# Latency alerts
enable_latency_alerts    = true
latency_threshold_ms     = 1000         # Alert if p95 latency > 1000ms

# ============================================================================
# Maintenance Window (Optional)
# ============================================================================

maintenance_window_start_time    = "02:00"   # 2 AM UTC
maintenance_window_duration_hours = 2        # 2 hour window
