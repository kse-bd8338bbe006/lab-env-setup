# Terraform external data source for managing Multipass VMs.
# Called by Terraform via data "external" - receives VM params as JSON on stdin,
# returns VM info (name, ip, release, state) as JSON on stdout.
# If a VM with the given name already exists, returns its info without creating a new one.

import os
import sys
import json
import subprocess
import tempfile
import time
import random

def log(msg):
    with open("multipass.log", "a") as f:
        f.write("%s\n" % msg)

def find_vm(name):
    """Check if a VM with this name already exists and return its info."""
    cmd = ["multipass", "list", "--format=json"]
    out = subprocess.check_output(cmd)
    vms = json.loads(out)
    for vm in vms["list"]:
        if vm["name"] == name:
            return {
                "name": name,
                "ip": vm["ipv4"][0],
                "release": vm["release"],
                "state": vm["state"]
            }
    return None

def create_vm(name, cpu, mem, disk, data, image, network_name=None, mac_address=None):
    """Create a new Multipass VM with the given resources and cloud-init config."""
    # Write cloud-init data to a temp file (multipass needs a file path)
    temp = tempfile.NamedTemporaryFile(delete=False)
    with open(temp.name, "w") as f:
        f.write(data)
    cmd = ["multipass", "launch",
            "--name", name,
            "--cpus", cpu,
            "--disk", disk,
            "--memory", mem,
            "--timeout", "1800",
            "--cloud-init", temp.name]
    # Add a second network interface for static IP (bridge101 on macOS)
    if network_name and mac_address:
        cmd += ["--network", "name=%s,mode=manual,mac=%s" % (network_name, mac_address)]
    elif network_name:
        cmd += ["--network", "name=%s,mode=manual" % network_name]
    cmd.append(image)
    res = subprocess.check_output(cmd)
    log("%s: %s" %(cmd, res))
    os.remove(temp.name)
    return find_vm(name)

# Read VM parameters from stdin (passed by Terraform)
inp = json.loads(sys.stdin.read())
name = inp["name"]
mem = inp["mem"]
disk = inp["disk"]
cpu = inp["cpu"]
data = inp["init"]
image = inp.get("image", "22.04")
network_name = inp.get("network_name", "")
mac_address = inp.get("mac_address", "")

# Only create the VM if it doesn't already exist (idempotent)
res = find_vm(name)
if not res:
    # Random delay to avoid race conditions when Terraform creates multiple VMs in parallel
    time.sleep(random.randrange(1, 10))
    res = create_vm(name, cpu, mem, disk, data, image, network_name, mac_address)

# Return VM info as JSON to Terraform
print(json.dumps(res))
