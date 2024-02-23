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

resource "google_compute_firewall" "allow_http" {
  count   = length(var.gcp_vpc)
  name    = "${var.gcp_vpc[count.index].subnet_1_custom_route}-fw"
  network = google_compute_network.vpc[count.index].id

  allow {
    protocol = "tcp"
    ports    = var.gcp_vpc[count.index].allowed_ports  // Your application listens to port 8000
  }
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["webapp-firewall"]
}

resource "google_compute_firewall" "deny_ssh" {
  count   = length(var.gcp_vpc)
  name    = "${var.gcp_vpc[count.index].subnet_1_custom_route}-fk"
  network = google_compute_network.vpc[count.index].id

  deny {
    protocol = "tcp"
    ports    = ["22"]  
  }
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "webapp_instance" {
  count = length(var.gcp_vpc)
  provider = google
  name = "compute-instance-${count.index}"
  machine_type = "e2-medium"
  network_interface {
    network = google_compute_network.vpc[count.index].id
    subnetwork  = google_compute_subnetwork.webapp_subnet[count.index].id
    access_config{

    }
  }

  boot_disk {
    initialize_params {
      size  = var.gcp_vpc[count.index].instance_size
      type  = var.gcp_vpc[count.index].instance_type
      image = var.gcp_vpc[count.index].image_address
    }
  }
  # Some changes require full VM restarts
  # consider disabling this flag in production
  #   depending on your needs
  zone = var.gcp_vpc[count.index].instance_zone
  allow_stopping_for_update = true

   tags = ["webapp-firewall"]

}