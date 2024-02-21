# Create VPC
resource "google_compute_network" "vpc" {
  count = length(var.gcp_vpc)
  name = var.gcp_vpc[count.index].name
  routing_mode = var.gcp_vpc[count.index].routing_mode
  delete_default_routes_on_create = true
  auto_create_subnetworks = false
}

# Create Subnets
resource "google_compute_subnetwork" "webapp_subnet" {
    count = length(var.gcp_vpc)
    name = var.gcp_vpc[count.index].subnet_name_1
    ip_cidr_range = var.gcp_vpc[count.index].subnet_1_cidr
    network = google_compute_network.vpc[count.index].id 
    region = var.gcp_region
}

resource "google_compute_subnetwork" "db_subnet" {
   count = length(var.gcp_vpc)
   name = var.gcp_vpc[count.index].subnet_name_2
   ip_cidr_range = var.gcp_vpc[count.index].subnet_2_cidr
   network = google_compute_network.vpc[count.index].id 
   region = var.gcp_region
}

# Create Route for Internet Gatewa
resource "google_compute_route" "internet_route" {
    count = length(var.gcp_vpc)
    name = var.gcp_vpc[count.index].subnet_1_custom_route
    network = google_compute_network.vpc[count.index].id
    dest_range = "0.0.0.0/0"
    next_hop_gateway = "default-internet-gateway"
}