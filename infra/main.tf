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

  metadata_startup_script = "${file("./startup.sh")}"

  metadata = {
    db-host     = google_sql_database_instance.instance[count.index].first_ip_address
    db-username = var.gcp_vpc[count.index].db_username
    db-password = random_password.password.result
    db-name = var.gcp_vpc[count.index].database_name
  }
  # Some changes require full VM restarts
  # consider disabling this flag in production
  #   depending on your needs
  zone = var.gcp_vpc[count.index].instance_zone
  allow_stopping_for_update = true

  service_account {
    email  = google_service_account.logging.email
    scopes = ["cloud-platform"]
  }

  depends_on = [google_service_account.logging]

   tags = ["webapp-firewall"]

}


resource "google_compute_global_address" "compute_address" {
  count = length(var.gcp_vpc)
  provider     = google-beta
  project      = google_compute_network.vpc[count.index].project
  name         = "globel-address-${count.index}"
  ip_version   = "IPV4"
  address_type = "INTERNAL"
  purpose = "VPC_PEERING"
  network      = google_compute_network.vpc[count.index].id
  prefix_length = 20
}
# [END compute_internal_ip_private_access]

# [START compute_forwarding_rule_private_access]
resource "google_service_networking_connection" "private_vpc_connection" {
  count = length(var.gcp_vpc)
  provider = google-beta
  network                 = google_compute_network.vpc[count.index].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.compute_address[count.index].name]
  depends_on = [ 
    google_compute_network.vpc[0],
    google_compute_global_address.compute_address[0] 
    ]
  deletion_policy = "ABANDON"
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "instance" {
  provider = google-beta
  count = length(var.gcp_vpc)
  name             = var.gcp_vpc[count.index].sql_database_name
  region           = "us-central1"
  database_version = "POSTGRES_15"
  deletion_protection = false
  depends_on = [google_service_networking_connection.private_vpc_connection[0]]
  
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc[count.index].id
      enable_private_path_for_google_cloud_services = true
    }
    disk_size = 100
    disk_type = "PD_SSD"
    availability_type = "REGIONAL"
  }
  

}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}
resource "google_sql_database" "database" {
  count = length(var.gcp_vpc)
  name     = var.gcp_vpc[count.index].database_name
  instance = google_sql_database_instance.instance[count.index].name
}

resource "google_sql_user" "users" {
  count = length(var.gcp_vpc)
  name     = var.gcp_vpc[count.index].db_username
  instance = google_sql_database_instance.instance[count.index].name
  password = random_password.password.result
}


resource "google_dns_record_set" "a" {
  count        = length(var.gcp_vpc)
  name         = "abhishekforce.me."
  managed_zone = "abhishekforce" # Replace with your actual managed zone name
  type         = "A"
  ttl          = 300

  rrdatas = ["${google_compute_instance.webapp_instance[0].network_interface.0.access_config.0.nat_ip}"]

  depends_on = [google_compute_instance.webapp_instance[0]]
}

resource "google_service_account" "logging" {
  account_id   = "logging-service-account"
  display_name = "Logging Service Account"
  description  = "This service account is used for logging."
}


resource "google_project_iam_member" "member1" {
  count = length(var.gcp_vpc)
  project     = google_compute_network.vpc[count.index].project
  role    = "roles/logging.admin"
  member  = "serviceAccount:${google_service_account.logging.email}"
}

resource "google_project_iam_member" "member2" {
  count = length(var.gcp_vpc)
  project     = google_compute_network.vpc[count.index].project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.logging.email}"
}

resource "google_project_iam_binding" "pubsub_publisher" {
  count   = length(var.gcp_vpc)
  project = google_compute_network.vpc[count.index].project
  role    = "roles/pubsub.publisher"
  members = [
    "serviceAccount:${google_service_account.logging.email}"
  ]
}

resource "google_pubsub_topic" "email" {
  name = "verify_email"

  labels = {
  purpose = "email_verification"
}

  message_retention_duration = "604800s"
}

resource "random_string" "string-generator" {
  length           = 16
  special          = false
}

resource "google_storage_bucket" "email-bucket" {
  name     = "bucket-3fa85f64-5717-4562-b3fc-2c963f66afa6-1629479812345"
  location = "US"
  force_destroy = true

}

resource "google_storage_bucket_object" "archive" {
  name   = "email-server.zip"
  bucket = google_storage_bucket.email-bucket.name
  source = "C:\\Users\\abhis\\OneDrive\\Documents\\prep\\email-server.zip"
}




resource "google_cloudfunctions2_function" "email-server" {
  count = length(var.gcp_vpc)
  name        = "run-email-server"
  location    = "us-east1"
  description = "a new function"

  build_config {
    runtime     = "nodejs16"
    entry_point = "consumeUserMessage" # Set the entry point
 
    source {
      storage_source {
        bucket = google_storage_bucket.email-bucket.name
        object = google_storage_bucket_object.archive.name
      }
    }
  }
  
  service_config {
    max_instance_count = 3
    min_instance_count = 2
    available_memory   = "256M"
    timeout_seconds    = 60
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = var.gcp_vpc[count.index].cloud_function_service_account_email
    environment_variables = {
        DB_PASSWORD = random_password.password.result
        DB_NAME = var.gcp_vpc[count.index].database_name
        DB_USERNAME = var.gcp_vpc[count.index].db_username
        DB_HOST = google_sql_database_instance.instance[count.index].first_ip_address
    }
    vpc_connector = google_vpc_access_connector.connector[0].name
    vpc_connector_egress_settings  = "PRIVATE_RANGES_ONLY"

  }

  event_trigger {
    trigger_region = "us-east1"
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.email.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  

}



resource "google_vpc_access_connector" "connector" {
  count = length(var.gcp_vpc)
  name          = "connector-${count.index}"
  network       = google_compute_network.vpc[count.index].id
  machine_type  = "e2-standard-4"
  min_instances = 2
  max_instances = 3
  ip_cidr_range = var.gcp_vpc[count.index].connector_ipv4

  depends_on = [
    google_compute_network.vpc[0]
  ]
}




