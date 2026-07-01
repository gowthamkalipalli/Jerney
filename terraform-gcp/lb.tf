#############################################
# Reserve a Global Static IP for the GKE Ingress
#############################################

resource "google_compute_global_address" "jerney_lb_ip" {
  name = "jerney-lb-ip"
}

#############################################
# Output the reserved IP
#############################################

output "load_balancer_ip" {
  description = "Global Static IP for GKE Ingress"
  value       = google_compute_global_address.jerney_lb_ip.address
}
