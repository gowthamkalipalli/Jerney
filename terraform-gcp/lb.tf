resource "google_compute_global_address" "lb_static_ip" {
  name = "app-lb-static-ip"
}

resource "google_compute_health_check" "lb_health_check" {
  name               = "app-lb-health-check"
  check_interval_sec = 5
  timeout_sec        = 5

  http_health_check {
    port         = 80 # Replace with your app's actual port
    request_path = "/health" 
  }
}

resource "google_compute_backend_service" "lb_backend" {
  name                  = "app-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  connection_draining_timeout_sec = 300 # 5 minutes graceful draining

  health_checks = [google_compute_health_check.lb_health_check.id]

  backend {
    # Replace with the reference to your existing running instance group
    group = "https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/zones/YOUR_ZONE/instanceGroups/YOUR_EXISTING_GROUP"
  }
}

# URL Map routes requests to the backend service
resource "google_compute_url_map" "lb_url_map" {
  name            = "app-url-map"
  default_service = google_compute_backend_service.lb_backend.id
}

# HTTP Target Proxy maps the URL map to incoming requests
resource "google_compute_target_http_proxy" "lb_http_proxy" {
  name    = "app-http-proxy"
  url_map = google_compute_url_map.lb_url_map.id
}

resource "google_compute_global_forwarding_rule" "lb_forwarding_rule" {
  name                  = "app-forwarding-rule"
  ip_address            = google_compute_global_address.lb_static_ip.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.lb_http_proxy.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_firewall" "allow_lb_health_checks" {
  name    = "allow-lb-health-checks"
  network = "YOUR_EXISTING_VPC_NAME" # Specify your running network

  allow {
    protocol = "tcp"
    ports    = ["80"] # The port your app listens on
  }

  # These exact CIDRs are mandatory for GCP Layer 7 LBs
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["your-existing-vm-network-tag"]
}

