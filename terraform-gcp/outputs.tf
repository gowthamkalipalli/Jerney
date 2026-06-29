output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.gke.name
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.gke.endpoint
}

output "cluster_certificate_authority" {
  description = "GKE cluster CA certificate (base64)"
  value       = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "vpc_id" {
  description = "VPC Network ID"
  value       = google_compute_network.vpc.id
}

output "region" {
  description = "GCP region"
  value       = var.gcp_region
}

# Use this command to configure kubectl after apply:
# gcloud container clusters get-credentials <cluster_name> --region <region> --project <project_id>
