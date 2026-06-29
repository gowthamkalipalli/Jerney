# ==============================================================
# Jerney GKE Cluster - Autopilot Mode
# ==============================================================

# ---- VPC Network ----
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

# ---- Subnet with Secondary Ranges for GKE ----
resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.cluster_name}-subnet"
  ip_cidr_range            = "10.0.0.0/20" # Node IP range
  region                   = var.gcp_region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  # Secondary ranges for GKE pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# ---- Cloud NAT & Router (Private Nodes Internet Access) ----
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ---- GKE Autopilot Cluster ----
resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.gcp_region

  # Autopilot Mode — Google manages node provisioning, scaling, security, etc.
  enable_autopilot = true

  # Networking
  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # IP Allocation Policy for Secondary Ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Security: Private nodes with public master endpoint access (matches EKS configuration)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Release Channel for automatic upgrades
  release_channel {
    channel = "REGULAR"
  }

  # Deletion protection disabled for easy teardown (development environment setting)
  deletion_protection = false
}
