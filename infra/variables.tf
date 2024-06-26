
variable "gcp_key"{

}

variable "gcp_project"{

}

variable "gcp_region"{
    
}

variable "bucket_path"{

}

variable "gcp_vpc" {
  type = list(
    object({
      name                  =  string
      routing_mode          = string
      subnet_name_1         = string
      subnet_1_cidr         = string
      subnet_name_2         = string
      subnet_2_cidr         = string
      subnet_1_custom_route = string
      instance_size         = number
      instance_type         = string
      image_address         = string
      allowed_ports         = list(number)
      instance_zone         = string
      private_ip_address    = string
      db_username           = string
      database_name         = string
      sql_database_name     = string
      connector_ipv4        = string
      cloud_function_service_account_email = string
      topic_name = string
      bucket_name = string
      bucket_source = string
      cloud_function_name = string
      cloud_function_entypoint = string
      cloud_function_version = string
      distribution_policy_zones = list(string)
      max_replica = number
      min_replica = number
      cool_down_period = number 
    })
  )
}
