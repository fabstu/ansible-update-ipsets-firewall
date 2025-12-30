variable "region" {
  type    = string
  default = "fra1"
}

variable "droplet_name" {
  type    = string
  default = "linux-droplet"
}

variable "droplet_size" {
  type    = string
  default = "s-1vcpu-1gb" # Basic droplet: 1 vCPU, 1GB RAM
}

variable "droplet_image" {
  type    = string
  default = "ubuntu-24-04-x64" # Ubuntu 24.04 LTS
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/digitalocean-terraform.pub"
  description = "Path to your SSH public key"
}

variable "ssh_private_key_path" {
  type        = string
  default     = "~/.ssh/digitalocean-terraform"
  description = "Path to your SSH private key (for SSH config)"
}

# Use your existing SSH public key
resource "digitalocean_ssh_key" "droplet_key" {
  name       = "${var.droplet_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Create the DigitalOcean Droplet
resource "digitalocean_droplet" "linux" {
  name     = var.droplet_name
  region   = var.region
  size     = var.droplet_size
  image    = var.droplet_image
  ssh_keys = [digitalocean_ssh_key.droplet_key.fingerprint]

  tags = ["linux", "terraform"]
}

# Generate SSH config file
resource "local_file" "ssh_config" {
  filename = "${path.module}/ssh_config"
  content  = <<-EOT
    # SSH config for ${var.droplet_name}
    # Add this to your ~/.ssh/config or use: ssh -F ssh_config ${var.droplet_name}
    
    Host ${var.droplet_name}
        HostName ${digitalocean_droplet.linux.ipv4_address}
        User root
        IdentityFile ${pathexpand(var.ssh_private_key_path)}
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
  EOT
}

# Output the droplet information
output "droplet_ip" {
  description = "The public IP address of the droplet"
  value       = digitalocean_droplet.linux.ipv4_address
}

output "droplet_id" {
  description = "The ID of the droplet"
  value       = digitalocean_droplet.linux.id
}

output "droplet_name" {
  description = "The name of the droplet"
  value       = digitalocean_droplet.linux.name
}

output "ssh_command" {
  description = "SSH command to connect to the droplet"
  value       = "ssh root@${digitalocean_droplet.linux.ipv4_address}"
}

output "ssh_config_path" {
  description = "Path to the generated SSH config file"
  value       = local_file.ssh_config.filename
}
