# Create VPC
resource "google_compute_network" "gcp_vpc" {
  name                    = "my-vpc"
  routing_mode            = "REGIONAL"
  auto_create_subnetworks = false
}

# Create Subnets
resource "google_compute_subnetwork" "webapp_subnet" {
  name          = "webapp"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.gcp_vpc.id
}

resource "google_compute_subnetwork" "db_subnet" {
  name          = "db"
  ip_cidr_range = "10.0.2.0/24"
  network       = google_compute_network.gcp_vpc.id
}

# Create Route for Internet Gateway
resource "google_compute_route" "internet_route" {
  name                  = "internet-route"
  network               = google_compute_network.gcp_vpc.name
  dest_range            = "0.0.0.0/0"
  next_hop_gateway      = "default-internet-gateway"
}