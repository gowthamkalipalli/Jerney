# ============================================================================
# GCP Application Load Balancer (ALB) Configuration for Jerney
# ============================================================================
# This file contains all resources needed to create a production-ready
# Application Load Balancer (Layer 7) for the Jerney application.
#
# DEPLOYMENT ORDER:
# 1. Apply Kubernetes service first (jerney-frontend-alb-service.yaml)
# 2. Run: terraform plan
# 3. Run: terraform apply
# ============================================================================

# ============================================================================
# NETWORK ENDPOINT GROUP (NEG) - Discovers Kubernetes Pods
# ============================================================================
# NEG automatically discovers and registers Kubernetes pods as backend targets
resource "google_compute_network_endpoint_group" "jerney_neg" {
  name                  = "jerney-frontend-neg"
  namespace_name        = "jerney"
  network_endpoint_type = "GKE_VM_IP_PORT"
  
  # Reference to your GKE cluster network and subnetwork
  network    = data.google_compute_network.default.id
  subnetwork = data.google_compute_subnetwork.default.id
  
  # Zone where the NEG will operate
  location = var.gke_zone
  
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [network_endpoint_type]
  }

  depends_on = [
    kubernetes_service.jerney_frontend_alb,
    data.google_container_cluster.jerney
  ]

  tags = ["gke-node", "jerney"]
}

# ============================================================================
# HEALTH CHECK - Determines Pod Health Status
# ============================================================================
# ALB uses this to determine which pods are healthy and can receive traffic
resource "google_compute_health_check" "jerney_health_check" {
  name                = "jerney-alb-health-check"
  description         = "Health check for Jerney ALB backend"
  check_interval_sec  = 10        # Check every 10 seconds
  timeout_sec         = 5         # Wait 5 seconds for response
  healthy_threshold   = 2         # 2 consecutive successful checks = HEALTHY
  unhealthy_threshold = 3         # 3 consecutive failed checks = UNHEALTHY

  http_health_check {
    port               = 8080                    # Frontend pod port
    request_path       = "/"                     # Health check endpoint
    proxy_header       = "NONE"                  # Don't add proxy headers
    port_specification = "USE_FIXED_PORT"       # Always use port 8080
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# BACKEND SERVICE - Routes Traffic to NEG
# ============================================================================
# Backend service defines how traffic should be distributed to the NEG
resource "google_compute_backend_service" "jerney_backend" {
  name                    = "jerney-backend-service"
  protocol                = "HTTP"              # ALB protocol
  load_balancing_scheme   = "EXTERNAL"          # External ALB
  health_checks           = [google_compute_health_check.jerney_health_check.id]
  session_affinity        = "CLIENT_IP"         # Sticky sessions
  affinity_cookie_ttl_sec = 3600                # Cookie valid for 1 hour
  
  # Enable connection draining
  connection_draining_timeout_sec = 30

  # Define backend (NEG)
  backend {
    group           = google_compute_network_endpoint_group.jerney_neg.id
    balancing_mode  = "RATE"                    # Distribute by request rate
    max_rate_per_endpoint = 1000                # Max 1000 req/sec per pod
  }

  # Logging configuration
  log_config {
    enable      = true
    sample_rate = 1.0                           # Log all requests (1.0 = 100%)
  }

  # Timeout for backend connections
  timeout_sec = 30

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_compute_health_check.jerney_health_check,
    google_compute_network_endpoint_group.jerney_neg
  ]
}

# ============================================================================
# URL MAP - Defines Routing Rules
# ============================================================================
# URL map defines how requests should be routed to different backends
resource "google_compute_url_map" "jerney_url_map" {
  name              = "jerney-url-map"
  description       = "URL map for Jerney application"
  default_service   = google_compute_backend_service.jerney_backend.id

  # Optional: Add host-based routing if needed
  host_rule {
    hosts        = [var.app_domain]
    path_matcher = "jerney-paths"
  }

  # Define path-based routing (all paths go to same backend for now)
  path_matcher {
    name            = "jerney-paths"
    default_service = google_compute_backend_service.jerney_backend.id

    # Route all paths to backend
    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_service.jerney_backend.id
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# SSL/TLS CERTIFICATE - Managed by Google
# ============================================================================
# Google automatically provisions and renews SSL certificates
resource "google_compute_managed_ssl_certificate" "jerney_cert" {
  name        = "jerney-ssl-cert"
  description = "Managed SSL certificate for Jerney"

  managed {
    domains = [var.app_domain]  # e.g., jerney.example.com
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# HTTPS REDIRECT URL MAP
# ============================================================================
# Automatically redirect HTTP requests to HTTPS
resource "google_compute_url_map" "jerney_https_redirect" {
  name        = "jerney-https-redirect"
  description = "Redirect HTTP to HTTPS"

  default_url_redirect {
    https_redirect         = true              # Redirect to HTTPS
    redirect_response_code = "301"             # Permanent redirect
    strip_query            = false             # Keep query parameters
  }
}

# ============================================================================
# TARGET PROXIES - Forward Requests to URL Map
# ============================================================================

# HTTP Target Proxy (handles HTTP requests and redirects to HTTPS)
resource "google_compute_target_http_proxy" "jerney_http_proxy" {
  name            = "jerney-http-proxy"
  url_map         = google_compute_url_map.jerney_https_redirect.id
  proxy_bind      = false
}

# HTTPS Target Proxy (handles HTTPS requests)
resource "google_compute_target_https_proxy" "jerney_https_proxy" {
  name            = "jerney-https-proxy"
  url_map         = google_compute_url_map.jerney_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.jerney_cert.id]

  depends_on = [google_compute_managed_ssl_certificate.jerney_cert]
}

# ============================================================================
# STATIC IP ADDRESS - External IP for ALB
# ============================================================================
# Reserve a static IP that won't change
resource "google_compute_address" "jerney_ip" {
  name              = "jerney-alb-ip"
  description       = "Static external IP for Jerney ALB"
  address_type      = "EXTERNAL"
  network_tier      = "PREMIUM"               # Premium tier for better performance
  ip_version        = "IPV4"

  lifecycle {
    prevent_destroy = true                    # Prevent accidental deletion
  }
}

# ============================================================================
# FORWARDING RULES - Route Traffic from Public Internet to ALB
# ============================================================================

# HTTP Forwarding Rule (port 80)
resource "google_compute_global_forwarding_rule" "jerney_http_rule" {
  name                  = "jerney-http-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.jerney_http_proxy.id
  ip_address            = google_compute_address.jerney_ip.id
}

# HTTPS Forwarding Rule (port 443)
resource "google_compute_global_forwarding_rule" "jerney_https_rule" {
  name                  = "jerney-https-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.jerney_https_proxy.id
  ip_address            = google_compute_address.jerney_ip.id
  
  depends_on = [google_compute_target_https_proxy.jerney_https_proxy]
}

# ============================================================================
# FIREWALL RULES - Allow ALB Health Checks
# ============================================================================
# Allow Google's health check IPs to reach your pods
resource "google_compute_firewall" "jerney_alb_health_check" {
  name          = "jerney-alb-health-check"
  network       = data.google_compute_network.default.name
  direction     = "INGRESS"
  priority      = 1000
  
  allow {
    protocol = "tcp"
    ports    = ["8080"]  # Frontend pod port
  }

  # Google's health check IP ranges
  source_ranges = [
    "35.191.0.0/16",      # Google Cloud health checks
    "130.211.0.0/22"      # Google Cloud health checks
  ]

  target_tags = ["gke-node"]  # Apply to GKE nodes
  target_networks = [data.google_compute_network.default.name]

  lifecycle {
    create_before_destroy = true
  }
}

# Allow traffic from ALB to pods
resource "google_compute_firewall" "jerney_alb_to_pods" {
  name          = "jerney-alb-to-pods"
  network       = data.google_compute_network.default.name
  direction     = "INGRESS"
  priority      = 1001

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  # Allow from ALB (typically 0.0.0.0/0 for internal GCP routing)
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# CLOUD ARMOR SECURITY POLICY
# ============================================================================
# DDoS protection and basic WAF rules

resource "google_compute_security_policy" "jerney_security_policy" {
  name        = "jerney-alb-policy"
  description = "Cloud Armor security policy for Jerney ALB"

  # Default rule: allow all traffic
  rules {
    action      = "allow"
    priority    = "2147483647"
    description = "Default rule - allow all"
    match {
      versioned_expr = "EXPR_V1"
    }
  }

  # Rate limiting rule
  rules {
    action      = "rate_based_ban"
    priority    = "1000"
    description = "Rate limit excessive requests"
    match {
      versioned_expr = "EXPR_V1"
    }
    rate_limit_options {
      conform_action           = "allow"                        # Allow within limit
      exceed_action            = "deny(429)"                    # Block with 429 error
      rate_limit_threshold_count = 1000                         # 1000 requests
      rate_limit_threshold_interval_sec = 60                    # Per 60 seconds
      ban_threshold_count              = 10000                  # Ban after 10000 requests
      ban_threshold_interval_sec       = 600                    # Ban for 10 minutes
    }
  }

  # Block SQL injection attempts
  rules {
    action      = "deny(403)"
    priority    = "900"
    description = "Block SQL injection"
    match {
      versioned_expr = "EXPR_V1"
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
  }

  # Block XSS attempts
  rules {
    action      = "deny(403)"
    priority    = "800"
    description = "Block XSS"
    match {
      versioned_expr = "EXPR_V1"
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Attach security policy to backend service
resource "google_compute_backend_service_security_policy_binding" "jerney_binding" {
  backend_service = google_compute_backend_service.jerney_backend.id
  security_policy = google_compute_security_policy.jerney_security_policy.id
}

# ============================================================================
# DATA SOURCES - Reference Existing GCP Resources
# ============================================================================

# Reference to existing GCP network
data "google_compute_network" "default" {
  name = var.gcp_network_name
}

# Reference to existing GCP subnetwork
data "google_compute_subnetwork" "default" {
  name   = var.gcp_subnetwork_name
  region = var.gcp_region
}

# Reference to existing GKE cluster
data "google_container_cluster" "jerney" {
  name     = var.gke_cluster_name
  location = var.gke_zone
}

# ============================================================================
# OUTPUTS - Export Important Values
# ============================================================================

output "alb_ip_address" {
  description = "External IP address of the ALB"
  value       = google_compute_address.jerney_ip.address
  sensitive   = false
}

output "alb_https_url" {
  description = "HTTPS URL for accessing Jerney through ALB"
  value       = "https://${var.app_domain}"
  sensitive   = false
}

output "alb_http_url" {
  description = "HTTP URL (will redirect to HTTPS)"
  value       = "http://${var.app_domain}"
  sensitive   = false
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = google_compute_backend_service.jerney_backend.name
  sensitive   = false
}

output "neg_self_link" {
  description = "Self link of the Network Endpoint Group"
  value       = google_compute_network_endpoint_group.jerney_neg.self_link
  sensitive   = false
}

output "health_check_name" {
  description = "Name of the health check"
  value       = google_compute_health_check.jerney_health_check.name
  sensitive   = false
}

output "security_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = google_compute_security_policy.jerney_security_policy.name
  sensitive   = false
}
