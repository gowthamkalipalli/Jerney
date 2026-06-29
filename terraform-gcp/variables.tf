variable "gcp_project_id" {
  description = "GCP project ID to deploy resources"
  type        = string
}

variable "gcp_region" {
  description = "GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the GKE Autopilot cluster"
  type        = string
  default     = "jerney-gke"
}

variable "vpc_cidr" {
  description = "CIDR block for the GCP subnet"
  type        = string
  default     = "10.0.0.0/16"
}
