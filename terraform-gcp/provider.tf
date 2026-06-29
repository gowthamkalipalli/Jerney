terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state (recommended for teams)
  # backend "gcs" {
  #   bucket  = "jerney-terraform-state"
  #   prefix  = "gke/state"
  # }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
