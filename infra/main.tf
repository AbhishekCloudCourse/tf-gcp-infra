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
  priority = 900

  deny {
    protocol = "tcp"
    ports    = var.gcp_vpc[count.index].allowed_ports  // Your application listens to port 8000
  }
  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["webapp-firewall"]
}

resource "google_compute_firewall" "allow_http_lb" {
  count   = length(var.gcp_vpc)
  name    = "${var.gcp_vpc[count.index].subnet_1_custom_route}-fw-lb"
  network = google_compute_network.vpc[count.index].id
  priority = 500

  allow {
    protocol = "tcp"
    ports    = var.gcp_vpc[count.index].allowed_ports  // Your application listens to port 8000
  }
  direction = "INGRESS"
  source_ranges = ["35.191.0.0/16","130.211.0.0/22"]
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

data "google_project" "current" {
}

locals {
  cloud_vm_service_account = "service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"
}
resource "google_kms_crypto_key_iam_binding" "vm_crypto_key_binding" {
  crypto_key_id = google_kms_crypto_key.ce_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members = [
    "serviceAccount:${local.cloud_vm_service_account}",
  ]
}



resource "google_compute_instance_template" "webapp_template" {
  count = length(var.gcp_vpc)
  name         = "compute-instance-template-${count.index}"
  machine_type = "e2-medium"

  disk {
    source_image = var.gcp_vpc[count.index].image_address
    disk_size_gb = var.gcp_vpc[count.index].instance_size
    boot = true 
    disk_type = var.gcp_vpc[count.index].instance_type
     disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.ce_key.id
    }
  }

   metadata_startup_script = "${file("./startup.sh")}"

  network_interface {
    network = google_compute_network.vpc[count.index].id
    subnetwork  = google_compute_subnetwork.webapp_subnet[count.index].id
    access_config{

    }
  }

  # To avoid embedding secret keys or user credentials in the instances, Google recommends that you use custom service accounts with the following access scopes.
    service_account {
    email  = google_service_account.logging.email
    scopes = ["cloud-platform"]
  }

    metadata = {
    db-host     = google_sql_database_instance.instance[count.index].first_ip_address
    db-username = var.gcp_vpc[count.index].db_username
    db-password = random_password.password.result
    db-name = var.gcp_vpc[count.index].database_name
    topic-name = var.gcp_vpc[count.index].topic_name
  }

  depends_on = [google_service_account.logging]
  tags = ["webapp-firewall"]

}

resource "google_compute_region_instance_group_manager" "instance_group_manager" {
  count = length(var.gcp_vpc)
  name                      = "webapp-group-manager-${count.index}"
  region                    = var.gcp_region
  distribution_policy_zones = var.gcp_vpc[count.index].distribution_policy_zones
  base_instance_name        = "webappinstance"
  version {
    name = "app-server-canary"
    instance_template = google_compute_instance_template.webapp_template[0].id
  }

  named_port {
    name = "http-connect"
    port = 8000
  }

  auto_healing_policies {
     health_check = google_compute_health_check.autohealing.id
     initial_delay_sec = "60"
  }
}


resource "google_compute_region_autoscaler" "autoscaler"{
  count = length(var.gcp_vpc)
  name   = "my-region-autoscaler"
  region = var.gcp_region
  target = google_compute_region_instance_group_manager.instance_group_manager[0].id

  autoscaling_policy {
    max_replicas    = var.gcp_vpc[count.index].max_replica
    min_replicas    = var.gcp_vpc[count.index].min_replica
    cooldown_period = 60

    cpu_utilization {
      target = 0.05
    }
  }
}

resource "google_compute_health_check" "autohealing" {
  name                = "autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds

  http_health_check {
    request_path = "/healthz"
    port         = "8000"
  }
}

resource "google_compute_managed_ssl_certificate" "lb_certificate" {
  provider = google-beta
  name     = "loadbalancer-ssl-certificate"

  managed {
    domains = ["abhishekforce.me"]
  }
}


module "gce-lb-http" {
  count = length(var.gcp_vpc)
  source            = "GoogleCloudPlatform/lb-http/google"
  version           = "~> 9.0"
  project           =  var.gcp_project
  name              = "group-http-lb"
  target_tags       = [google_compute_network.vpc[count.index].name]
   ssl               = true
  managed_ssl_certificate_domains = [
    "abhishekforce.me"
  ]
 
  backends = {
    default = {
      port                            = 8000
      protocol                        = "HTTP"
      port_name                       = "http-connect"
      timeout_sec                     = 10
      enable_cdn                      = false


      health_check = {
        request_path        = "/healthz"
        port                = "8000"
      }

      log_config = {
        enable = true
        sample_rate = 1.0
      }

      groups = [
        {
          # Each node pool instance group should be added to the backend.
          group                        = google_compute_region_instance_group_manager.instance_group_manager[0].instance_group
        },
      ]

      iap_config = {
        enable               = false
      }
    }
  }
}

resource "random_string" "keyring_id" {
  length = 8
  special = false
}

resource "random_string" "crypto_key_ce" {
  length = 8
  special = false
}

resource "random_string" "crypto_key_bucket" {
  length = 8
  special = false
}

resource "random_string" "crypto_key_sql" {
  length = 8
  special = false
}

resource "google_kms_key_ring" "keyring" {
  name     = "keyring-${random_string.keyring_id.result}"
  location = "us-east1"
  project = var.gcp_project
}


resource "google_kms_crypto_key" "ce_key" {
  name            = "crypto-key-ce-${random_string.crypto_key_ce.result}"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "2592000s"

  depends_on = [google_kms_key_ring.keyring]

}

resource "google_kms_crypto_key" "bucket_key" {
  name            = "crypto-key-bucket-${random_string.crypto_key_bucket.result}"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "2592000s"
  depends_on = [google_kms_key_ring.keyring]
}

resource "google_kms_crypto_key" "sql_key" {
  name            = "crypto-key-sql${random_string.crypto_key_sql.result}"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "2592000s"
  depends_on = [google_kms_key_ring.keyring]
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

resource "google_project_service_identity" "gcp_sa_cloud_sql" {
  provider   = google-beta
  service    = "sqladmin.googleapis.com"
  depends_on = [google_kms_key_ring.keyring]
}


resource "google_kms_crypto_key_iam_binding" "crypto_key_binding" {
  provider      = google
  crypto_key_id = google_kms_crypto_key.sql_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members = [
    "serviceAccount:${google_project_service_identity.gcp_sa_cloud_sql.email}",
  ]
}



resource "google_sql_database_instance" "instance" {
  provider = google-beta
  count = length(var.gcp_vpc)
  name             = var.gcp_vpc[count.index].sql_database_name
  region           = "us-east1"
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

   encryption_key_name = google_kms_crypto_key.sql_key.id

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

  rrdatas = [module.gce-lb-http[0].external_ip]

  depends_on = [module.gce-lb-http]
}

resource "google_dns_record_set" "spf" {
  count        = length(var.gcp_vpc)
  name         = "abhishekforce.me."
  managed_zone = "abhishekforce" # Replace with your actual managed zone name
  type         = "TXT"
  ttl          = 300

  rrdatas = ["\"v=spf1 include:sendgrid.net -all\""]
}

resource "google_dns_record_set" "s1_domainkey" {
  name         = "s1._domainkey.abhishekforce.me."
  managed_zone = "abhishekforce"
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["s1.domainkey.u43038719.wl220.sendgrid.net."]
}

resource "google_dns_record_set" "s2_domainkey" {
  name         = "s2._domainkey.abhishekforce.me."
  managed_zone = "abhishekforce"
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["s2.domainkey.u43038719.wl220.sendgrid.net."]
}

resource "google_dns_record_set" "s3_domainkey" {
  name         = "em4258.abhishekforce.me."
  managed_zone = "abhishekforce"
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["u43038719.wl220.sendgrid.net."]
}

resource "google_dns_record_set" "spf2" {
  name         = "_dmarc.abhishekforce.me."
  managed_zone = "abhishekforce"
  type         = "TXT"
  ttl          = 300

  rrdatas = ["v=DMARC1; p=none;"]
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
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
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


locals {
  cloud_storage_service_account = "service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_binding" "crypto_key_bucket_iam" {
  crypto_key_id = google_kms_crypto_key.bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${local.cloud_storage_service_account}"
  ]
}
resource "google_storage_bucket" "email-bucket" {
  name     = "bucket-3fa85f64-5717-4562-b3fc-2c963f66afa6-1629479812345"
  location = "us-east1"
  force_destroy = true
  # encryption {
  #    default_kms_key_name = google_kms_crypto_key.bucket_key.id
  # }
  
}


resource "google_storage_bucket_object" "archive" {
  name   = "email-server.zip"
  bucket = google_storage_bucket.email-bucket.name
  source = var.bucket_path
}




resource "google_cloudfunctions2_function" "email-server" {
  count = length(var.gcp_vpc)
  name        = var.gcp_vpc[count.index].cloud_function_name
  location    = var.gcp_region
  description = "a new function"

  build_config {
    runtime     = var.gcp_vpc[count.index].cloud_function_version
    entry_point = var.gcp_vpc[count.index].cloud_function_entypoint # Set the entry point
 
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
    trigger_region = var.gcp_region
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




