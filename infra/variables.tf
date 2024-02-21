
variable "gcp_key"{

}

variable "gcp_project"{

}

variable "gcp_region"{
    
}

variable "gcp_vpc" {
  type = list(
    object({
      name                  = string
      routing_mode          = string
      subnet_name_1         = string
      subnet_1_cidr         = string
      subnet_name_2         = string
      subnet_2_cidr         = string
      subnet_1_custom_route = string
    })
  )
}
