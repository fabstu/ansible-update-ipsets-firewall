.PHONY: init plan apply destroy ssh output

# Terraform commands
init:
	terraform init

plan:
	terraform plan -var-file=digitalocean.tfvars

apply:
	terraform apply -var-file=digitalocean.tfvars

destroy:
	terraform destroy -var-file=digitalocean.tfvars

# SSH connect to the droplet
ssh:
	ssh -i ~/.ssh/digitalocean-terraform -o IdentitiesOnly=yes root@$$(terraform output -raw droplet_ip)

# Show all outputs
output:
	terraform output
