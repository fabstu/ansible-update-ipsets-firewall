.PHONY: init plan apply destroy ssh output ansible-ping ansible-docker ansible-ufw ansible-firehol ansible-test echo-server http-server firewall-status firewall-update firewall-disable firewall-enable firewall-test

# Variables
SSH_CMD = ssh $(1) -i ~/.ssh/digitalocean-terraform -o IdentitiesOnly=yes root@$$(terraform output -raw droplet_ip)

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
	$(call SSH_CMD)

# Show all outputs
output:
	terraform output

# Ansible commands
ansible-ping:
	cd ansible && ansible all -m ping

ansible-docker:
	cd ansible && ansible-playbook playbooks/setup-docker.yml

ansible-ufw:
	cd ansible && ansible-playbook playbooks/setup-ufw.yml

ansible-firehol:
	cd ansible && ansible-playbook playbooks/setup-firehol-ipsets.yml

ansible-test:
	cd ansible && ansible all -m shell -a "docker --version && docker compose version"

# Run HTTP echo server on the remote server (blocking - Ctrl+C to stop)
echo-server:
	$(call SSH_CMD,-tt) \
		'docker run --rm -it -p 8080:80 ealen/echo-server:latest'

# Run simple HTTP server with static page on the remote server (blocking - Ctrl+C to stop)
http-server:
	$(call SSH_CMD,-tt) \
		'docker run --rm -it -p 80:80 nginx:alpine sh -c "echo \"<html><body><h1>Hello from Docker!</h1><p>This is a static page served by nginx.</p></body></html>\" > /usr/share/nginx/html/index.html && nginx -g \"daemon off;\""'

# Firewall commands
firewall-status:
	@echo "=== DOCKER-USER chain rules ==="
	@$(call SSH_CMD) \
		'iptables -L DOCKER-USER -n -v 2>/dev/null || echo "DOCKER-USER chain not found"'
	@echo ""
	@echo "=== Loaded ipsets ==="
	@$(call SSH_CMD) \
		'ipset list -n 2>/dev/null | while read name; do count=$$(ipset list "$$name" 2>/dev/null | grep -c "^[0-9]" || echo 0); echo "$$name: $$count entries"; done'
	@echo ""
	@echo "=== Blocklist files ==="
	@$(call SSH_CMD) \
		'ls -la /etc/firehol/ipsets/*.netset /etc/firehol/ipsets/*.ipset 2>/dev/null || echo "No ipset files found"'

firewall-update:
	@echo "Downloading/updating blocklists..."
	@$(call SSH_CMD) \
		'systemctl start update-ipsets.service && systemctl status --no-pager update-ipsets.service || true'
	@echo ""
	@echo "Restoring ipsets in firewall..."
	@$(call SSH_CMD) \
		'systemctl start firehol-ipsets-restore.service && systemctl status --no-pager firehol-ipsets-restore.service || true'
	@echo ""
	@echo "Verifying services completed successfully..."
	@$(call SSH_CMD) \
		'systemctl is-failed update-ipsets.service firehol-ipsets-restore.service --quiet && echo "ERROR: One or more services failed!" && exit 1 || echo "All services completed successfully."'

firewall-disable:
	@echo "Disabling firewall blocklists..."
	@echo ""
	@echo "1. Stopping update timer..."
	@$(call SSH_CMD) \
		'systemctl stop update-ipsets.timer 2>/dev/null || true; systemctl disable update-ipsets.timer 2>/dev/null || true'
	@echo "   ✓ Timer stopped"
	@echo ""
	@echo "2. Disabling restore service at boot..."
	@$(call SSH_CMD) \
		'systemctl disable firehol-ipsets-restore.service 2>/dev/null || true'
	@echo "   ✓ Service disabled"
	@echo ""
	@echo "3. Flushing DOCKER-USER iptables rules..."
	@$(call SSH_CMD) \
		'iptables -F DOCKER-USER 2>/dev/null || true; iptables -A DOCKER-USER -j RETURN 2>/dev/null || true'
	@echo "   ✓ DOCKER-USER chain flushed"
	@echo ""
	@echo "4. Destroying ipsets..."
	@$(call SSH_CMD) \
		'ipset list -n 2>/dev/null | while read name; do ipset destroy "$$name" 2>/dev/null || true; done'
	@echo "   ✓ Ipsets destroyed"
	@echo ""
	@echo "Blocklists disabled. Run 'make firewall-enable' to re-enable."

firewall-enable:
	@echo "Enabling firewall blocklists..."
	@echo ""
	@echo "1. Enabling restore service at boot..."
	@$(call SSH_CMD) \
		'systemctl enable firehol-ipsets-restore.service'
	@echo "   ✓ Service enabled"
	@echo ""
	@echo "2. Enabling and starting update timer..."
	@$(call SSH_CMD) \
		'systemctl enable update-ipsets.timer && systemctl start update-ipsets.timer'
	@echo "   ✓ Timer enabled and started"
	@echo ""
	@echo "3. Running update and restore..."
	@$(MAKE) firewall-update

firewall-test:
	@echo "Testing firewall by temporarily adding your IP to a test blocklist..."
	@echo "This will add your IP, try to curl, then remove it."
	@echo ""
	@MY_IP=$$(curl -s ifconfig.me); \
	SERVER_IP=$$(terraform output -raw droplet_ip); \
	echo "Your IP: $$MY_IP"; \
	echo "Server IP: $$SERVER_IP"; \
	echo ""; \
	echo "1. First, verify you CAN access the server (should work):"; \
	curl -s --connect-timeout 5 "http://$$SERVER_IP:80/" >/dev/null && echo "   ✓ Connection successful" || echo "   ✗ Connection failed (is http-server running?)"; \
	echo ""; \
	echo "2. Adding your IP to test blocklist..."; \
	$(call SSH_CMD) \
		"ipset create test_block hash:ip -exist && ipset add test_block $$MY_IP -exist && iptables -C DOCKER-USER -m set --match-set test_block src -j DROP 2>/dev/null || iptables -I DOCKER-USER 1 -m set --match-set test_block src -j DROP"; \
	echo ""; \
	echo "3. Testing connection (should FAIL/timeout):"; \
	curl -s --connect-timeout 5 "http://$$SERVER_IP:80/" >/dev/null && echo "   ✗ Connection still works (firewall not blocking!)" || echo "   ✓ Connection blocked (firewall working!)"; \
	echo ""; \
	echo "4. Removing your IP from test blocklist..."; \
	$(call SSH_CMD) \
		"iptables -D DOCKER-USER -m set --match-set test_block src -j DROP 2>/dev/null; ipset destroy test_block 2>/dev/null"; \
	echo ""; \
	echo "5. Verifying connection restored (should work):"; \
	curl -s --connect-timeout 5 "http://$$SERVER_IP:80/" >/dev/null && echo "   ✓ Connection restored" || echo "   ✗ Connection still blocked (cleanup may have failed)"
