# ============================================================================
# Terraform Variables for GCP ALB Configuration
# ============================================================================
# These variables define the configuration for your GCP Application Load Balancer
# Fill in these values in terraform.tfvars before running terraform apply

# ============================================================================
# GCP Project Configuration
# ============================================================================

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = ""  # e.g., "jerney-prod-12345"
}

variable "gcp_region" {
  description = "GCP Region for resources"
  type        = string
  default     = "us-central1"  # Change to your region
}

# ============================================================================
# GKE Cluster Configuration
# ============================================================================

variable "gke_cluster_name" {
  description = "Name of the existing GKE cluster"
  type        = string
  default     = "jerney-gke"  # Update with your cluster name
}

variable "gke_zone" {
  description = "Zone where GKE cluster is located"
  type        = string
  default     = "us-central1-a"  # Update with your zone
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "gcp_network_name" {
  description = "Name of the GCP VPC network where ALB will operate"
  type        = string
  default     = "default"  # Change if using custom VPC
}

variable "gcp_subnetwork_name" {
  description = "Name of the GCP subnetwork for NEG"
  type        = string
  default     = "default"  # Change if using custom subnetwork
}

# ============================================================================
# Application Configuration
# ============================================================================

variable "app_domain" {
  description = "Domain name for your Jerney application (used for SSL certificate and DNS)"
  type        = string
  default     = ""  # REQUIRED: Set this! e.g., "jerney.example.com"
  
  validation {
    condition     = var.app_domain != ""
    error_message = "app_domain must be set to your application domain"
  }
}

# ============================================================================
# ALB Configuration
# ============================================================================

variable "alb_health_check_interval" {
  description = "How often ALB checks if pods are healthy (seconds)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.alb_health_check_interval >= 1 && var.alb_health_check_interval <= 300
    error_message = "Health check interval must be between 1 and 300 seconds"
  }
}

variable "alb_health_check_timeout" {
  description = "Timeout for health check response (seconds)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.alb_health_check_timeout >= 1 && var.alb_health_check_timeout <= 300
    error_message = "Health check timeout must be between 1 and 300 seconds"
  }
}

variable "alb_healthy_threshold" {
  description = "Number of successful health checks before marking pod as HEALTHY"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alb_healthy_threshold >= 1 && var.alb_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 1 and 10"
  }
}

variable "alb_unhealthy_threshold" {
  description = "Number of failed health checks before marking pod as UNHEALTHY"
  type        = number
  default     = 3
  
  validation {
    condition     = var.alb_unhealthy_threshold >= 1 && var.alb_unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 1 and 10"
  }
}

variable "alb_backend_port" {
  description = "Port on which frontend pods listen"
  type        = number
  default     = 8080
  
  validation {
    condition     = var.alb_backend_port >= 1 && var.alb_backend_port <= 65535
    error_message = "Backend port must be between 1 and 65535"
  }
}

variable "alb_max_rate_per_endpoint" {
  description = "Maximum requests per second that each pod can handle"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.alb_max_rate_per_endpoint > 0
    error_message = "Max rate per endpoint must be greater than 0"
  }
}

variable "alb_session_affinity_ttl" {
  description = "How long to maintain sticky sessions (seconds)"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.alb_session_affinity_ttl >= 0 && var.alb_session_affinity_ttl <= 86400
    error_message = "Session affinity TTL must be between 0 and 86400 seconds"
  }
}

variable "alb_connection_draining_timeout" {
  description = "Time to wait for in-flight requests before stopping pod (seconds)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.alb_connection_draining_timeout >= 0 && var.alb_connection_draining_timeout <= 3600
    error_message = "Connection draining timeout must be between 0 and 3600 seconds"
  }
}

# ============================================================================
# Cloud Armor Configuration
# ============================================================================

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor for DDoS protection"
  type        = bool
  default     = true
}

variable "rate_limit_requests_per_minute" {
  description = "Number of requests allowed per minute per IP"
  type        = number
  default     = 60000
}

variable "rate_limit_ban_duration_minutes" {
  description = "How long to ban an IP that exceeds rate limit (minutes)"
  type        = number
  default     = 10
}

# ============================================================================
# Logging Configuration
# ============================================================================

variable "enable_alb_logging" {
  description = "Enable ALB access logging"
  type        = bool
  default     = true
}

variable "alb_logging_sample_rate" {
  description = "Percentage of requests to log (0-1, where 1 = 100%)"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.alb_logging_sample_rate >= 0 && var.alb_logging_sample_rate <= 1
    error_message = "Sample rate must be between 0 and 1"
  }
}

# ============================================================================
# SSL/TLS Configuration
# ============================================================================

variable "enable_https" {
  description = "Enable HTTPS (requires valid domain for certificate)"
  type        = bool
  default     = true
}

variable "http_to_https_redirect" {
  description = "Automatically redirect HTTP to HTTPS"
  type        = bool
  default     = true
}

# ============================================================================
# Tags and Labels
# ============================================================================

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "application_name" {
  description = "Application name for labeling resources"
  type        = string
  default     = "jerney"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Jerney"
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}

# ============================================================================
# DNS Configuration (Optional but Recommended)
# ============================================================================

variable "managed_dns_zone" {
  description = "GCP Cloud DNS zone name (optional, for automated DNS updates)"
  type        = string
  default     = ""  # Leave empty if managing DNS manually
}

# ============================================================================
# Monitoring and Alerting
# ============================================================================

variable "create_monitoring_dashboard" {
  description = "Create a Grafana/Cloud Monitoring dashboard for ALB metrics"
  type        = bool
  default     = true
}

variable "enable_error_alerts" {
  description = "Create alerts for high error rates"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "Alert if error rate exceeds this percentage (0-100)"
  type        = number
  default     = 5
}

variable "enable_latency_alerts" {
  description = "Create alerts for high latency"
  type        = bool
  default     = true
}

variable "latency_threshold_ms" {
  description = "Alert if p95 latency exceeds this milliseconds"
  type        = number
  default     = 1000
}

# ============================================================================
# Scheduled Actions (Optional)
# ============================================================================

variable "maintenance_window_start_time" {
  description = "Start time for maintenance window (UTC, e.g., '02:00')"
  type        = string
  default     = "02:00"
}

variable "maintenance_window_duration_hours" {
  description = "Duration of maintenance window in hours"
  type        = number
  default     = 2
}
