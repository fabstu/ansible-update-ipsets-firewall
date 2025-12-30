#!/usr/bin/env python3
"""
Dynamic Ansible inventory script that reads from Terraform output.
"""

import json
import os
import subprocess
import sys


def get_terraform_output():
    """Get terraform output as JSON."""
    # Get the directory where this script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # Terraform files are in the parent directory
    terraform_dir = os.path.dirname(script_dir)
    
    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            capture_output=True,
            text=True,
            check=True,
            cwd=terraform_dir
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"Error running terraform output: {e}\n")
        return {}
    except json.JSONDecodeError as e:
        sys.stderr.write(f"Error parsing terraform output: {e}\n")
        return {}


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        tf_output = get_terraform_output()
        
        droplet_ip = tf_output.get("droplet_ip", {}).get("value", "")
        droplet_name = tf_output.get("droplet_name", {}).get("value", "linux-droplet")
        
        inventory = {
            "linux_servers": {
                "hosts": [droplet_name],
            },
            "_meta": {
                "hostvars": {
                    droplet_name: {
                        "ansible_host": droplet_ip,
                        "ansible_user": "root",
                        "ansible_ssh_private_key_file": "~/.ssh/digitalocean-terraform",
                        "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes"
                    }
                }
            }
        }
        
        print(json.dumps(inventory, indent=2))
    
    elif len(sys.argv) == 2 and sys.argv[1] == "--host":
        # Return empty dict for host-specific vars (all vars in _meta)
        print(json.dumps({}))
    
    else:
        print(json.dumps({}))


if __name__ == "__main__":
    main()
