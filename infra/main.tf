# Create VPC
resourc "google_compute_network" "gcp_vpc" {
  name                    = "my-vpc"
  routing_mode            = var.gcp_route_mode
  delete_default_routes_on_create = true
  auto_create_subnetworks = false
}

# Create Subnets
resource "google_compute_subnetwork" "webapp_subnet" {
  name          = "webapp"
  ip_cidr_range = var.subnet_1_cidr
  network       = google_compute_network.gcp_vpc.id
}

resource "google_compute_subnetwork" "db_subnet" {
  name          = "db"
  ip_cidr_range = var.subnet_2_cidr
  network       = google_compute_network.gcp_vpc.id
}

# Create Route for Internet Gateway
resource "google_compute_route" "internet_route" {
  name                  = "internet-route"
  network               = google_compute_network.gcp_vpc.name
  dest_range            = "0.0.0.0/0"
  next_hop_gateway      = "default-internet-gateway"
}