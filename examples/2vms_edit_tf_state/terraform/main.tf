# yaklass-test

terraform {
    required_providers {
        vkcs = {
            source  = "vk-cs/vkcs"
            version = "~> 0.7.1"
        }
    }
}

// ---- NETWORKING NEUTRON -----------------

resource "vkcs_networking_network" "app" {
  name        = "app-tf-example"
  description = "Application network"
  sdn = "neutron"
}

resource "vkcs_networking_subnet" "app" {
  name       = "app-tf-example"
  network_id = vkcs_networking_network.app.id
  cidr       = "192.168.199.0/24"
  sdn = "neutron"
}

resource "vkcs_networking_router" "router" {
  name = "router-tf-example"
  # Connect router to Internet
  external_network_id = data.vkcs_networking_network.extnet.id
  tags                = ["tf-example"]
  sdn = "neutron"
}

resource "vkcs_networking_router_interface" "app" {
  router_id = vkcs_networking_router.router.id
  subnet_id = vkcs_networking_subnet.app.id
  sdn = "neutron"
}

// ---------- NETWORKING SPRUT ------

resource "vkcs_networking_network" "app_sprut" {
  name        = "app-tf-example-sprut"
//  description = "Application network"
  sdn = "sprut"
}

resource "vkcs_networking_subnet" "app_sprut" {
  name       = "app-tf-example-sprut"
  network_id = vkcs_networking_network.app_sprut.id
  cidr       = "192.168.199.0/24"
  sdn = "sprut"
}

resource "vkcs_networking_router" "router_sprut" {
  name = "router-tf-example-sprut"
  # Connect router to Internet
  external_network_id = data.vkcs_networking_network.internet.id
  tags                = ["tf-example"]
  sdn = "sprut"
}

data "vkcs_networking_network" "internet" {
  name = "internet"
  sdn = "sprut"
}

resource "vkcs_networking_router_interface" "app_sprut" {
  router_id = vkcs_networking_router.router_sprut.id
  subnet_id = vkcs_networking_subnet.app_sprut.id
  sdn = "sprut"
}

// --------------------------------


data "vkcs_images_image" "debian" {
  # Both arguments are required to search an actual image provided by VKCS.
  visibility = "public"
  default    = true
  # Use properties to distinguish between available images.
  properties = {
    mcs_os_distro  = "debian"
    mcs_os_version = "10.1"
  }
}

// -----------------VIRTUAL MACHINE------------------

resource "vkcs_compute_instance" "basic" {
  count = var.instance_count # Add this line, define `instance_count` in your variables.tf

  name = "${var.instance_name_prefix}-${count.index}" # Modify this line
  # AZ and flavor are mandatory
  availability_zone = "GZ1"
  flavor_name       = "Basic-1-2-20"
  # Use block_device to specify instance disk to get full control
  # of it in the future
  block_device {
    source_type      = "image"
    uuid             = data.vkcs_images_image.debian.id
    destination_type = "volume"
    volume_size      = 10
  //  volume_type      = "ceph-ssd"
    # Must be set to delete volume after instance deletion
    # Otherwise you get "orphaned" volume with terraform
    delete_on_termination = true
  }

  network {
    uuid = vkcs_networking_network.app_sprut.id
  }

  # ensure it is attached to a router before creating of the instance
  depends_on = [
    vkcs_networking_router_interface.app_sprut
  ]
}

variable "instance_count" {
  description = "The number of instances to create."
  type        = number
  default = 2
}

variable "instance_name_prefix" {
  description = "Prefix for the instance names."
  type        = string
  default = "yaklass-private"
}

data "vkcs_networking_network" "extnet" {
  name = "ext-net"
  sdn = "neutron"
}
