# Bare Kubernetes on AWS (Terraform + Ansible)

This project contains **Terraform** code to provision infrastructure on AWS and **Ansible** playbooks to automatically deploy a bare basic Kubernetes cluster on the created instances.

I use my own personal domain and free dns.he.net with dynamic dns record for whole cluster services via HE.net DynDNS API.

You can use your own domain and dns provider with same principles.

_-NOTICE-_ Our demo environment assumes that we install all services for the bare cluster,
_-NOTICE-_ otherwise we will not be able to deploy the infrastructure via terraform succesfully.
_-NOTICE-_ If we install it in a virtual OrbStack - the CNI in the cluster is already based on flannel and,
_-NOTICE-_ for example, network policies will not work as expected.

## Overview

1. **Infrastructure (Terraform)**:
   - Provisions EC2 instances for Control Plane and Worker nodes.
   - Configures AWS Firewall Security Groups.
   - Generates an ansible `inventory` file automatically.

2. **Configuration (Ansible)**:
   - **Node Preparation**: Installs dependencies, configures kernel modules, sysctl, containerd.
   - **Control Plane Initialization**:
     - Initalize cluster.
     - Installs Flannel CNI.
     - Installs basic CRDs (Traefik, Cert-Manager, ArgoCD).
     - Automates SSL certificates via Certbot from Lets Encrypt.
   - **Worker Join**:  Joins worker nodes to the cluster.
   - **Finalization**: Reboots all nodes.
   - **Basic Apps**:   Installs basic apps (KeyCloak, Vault).

## Prerequisites

- **Terraform** (>= 1.0)
- **Ansible** (>= 2.9)
- **AWS CLI** configured (or access keys available)

---

## 1. Infrastructure Setup (Terraform)

Navigate to the project directory.

### Configuration

Create a `terraform.tfvars` file (use `terraform.tfvars.default` as a template) to configure your specific settings:

TODO: Currently only 1 control plane node is supported.

You can use one micro and one medium instances for deploy one application for testing purposes, but it will not be enough for proper work.

_WARNING_: You can use t3.large instance type for control plane and worker nodes as they use lots of memory.

_WARNING_: Basic AWS account have a 8 vCPU limit. So you can use only 1 control plane node and 3 worker nodes without any fails from terraform side. This is NOT enought to serve all provided applications, so for more efficiency you can request 16 vCPU via AWS console.

```hcl
access_key   = "YOUR_AWS_ACCESS_KEY"
secret_key   = "YOUR_AWS_SECRET_KEY"
vpc_id       = "vpc-xxxxxxxx"  # Existing VPC ID
region       = "eu-north-1"    # Target Region
cp_count     = 1               # Number of Control Plane nodes # currently supported only 1 control plane node
cp_type      = "t3.large"      # Control Plane instance type
worker_count = 3               # Number of Worker nodes
worker_type  = "t3.large"      # Worker instance type
```

### Provisioning

Initialize Terraform:

```bash
terraform init
```

Review the plan:

```bash
terraform plan
```

Apply the changes to create infrastructure:

```bash
terraform apply # --auto-approve
```

After a successful run, Terraform will generate an `inventory` file in the project directory containing the IP addresses of the created servers.

---

## 2. Cluster Configuration (Ansible)

Once the infrastructure is ready and the `inventory` file is generated, you can proceed with Ansible.

### Requirements

- SSH access to the target nodes (configured via the key pair used in Terraform).
- The `inventory` file present in the directory.

### Setup basic cluster

#### 0. Run the `main.yml` playbook with the required variables in comman line

I use free dns.he.net with dynamic dns record for whole cluster services via HE.net api and my private domain.
Role based variables you can find in role/${name}/defaults.

```bash
ansible-playbook -i inventory main.yml \
  -e "cp_dns_name=cp.your.domain.com" \
  -e "he_net_password=your_dyndns_record_he_password" \
  -e "ext_domain=your.domain.com"
```

You can use partial configuration via tags if you need, or in case of re-run after network issues, or if you need to update something. You can find available tags at the main.yaml in roles, and use as in this example.

- k8s-prerequisites - Install K8s prerequisites to all nodes.
- k8s-control       - Install K8s control plane to control plane nodes, Flannel and basic CRDs (Traefik, Cert-Manager, MetalLB,ArgoCD).
- k8s-workers       - Install K8s to worker nodes.
- k8s-apps          - Install basic apps to cluster - KeyCloak, Vault.

```bash
ansible-playbook -i inventory main.yml \
  -e "cp_dns_name=cp.example.com" \
  -e "he_net_password=your_he_password" \
  -e "ext_domain=your.domain.com"
  --tags="k8s-apps"
```

#### 1. Install basic Nginx for KeyCloak and Vault

For public access from terraform you need to install Nginx as proxy for KeyCloak and Vault as prerequrements. Currently we use control plane node as bastion host for all access and proxying.

```bash
ansible-playbook -i inventory nginx.yml -e "ext_domain=your.domain.com" --tags=nginx_basics
```

#### 2. KeyCloak preparation

- Go to the web UI for KeyCloak (<https://keycloak.your.domain.com> in case of cname record for keycloak.your.domain.com pointing to control plane node) with provided via text file password.
- Go to clients -> choose 'admin-cli'.
- Enable client authentication, save.
- Go to credentials tab and copy client secret to terraform.vars in your infra repo.

#### 3. Vault unseal

- Go to the web UI for Vault (<https://vault.your.domain.com> in case of cname record for vault.your.domain.com pointing to control plane node) and unseal it via web interface.
- Save api token and keys to your infra repo.

#### 4. Install infra

- Use your repo with infra to deploy all stuff to cluster. For example you can use my repo with infra: <https://github.com/mturnaviotov/k8s-infra> - this repo contains all the necessary stuff to deploy all the applications to the cluster.

#### 5. Install Nginx for all applications

When all applications are deployed, they should be resolved via internal ${service}.${namespace}.svc.cluster.local before nginx will work with upstreams. You can test it via `kubectl exec -it -n <namespace> <pod-name> -- curl -I <service>.<namespace>.svc.cluster.local` from any node from cluster.
You also should provide cname for all applications in your dns provider and domain to point to control plane node as it will be your proxy.

```bash
ansible-playbook -i inventory nginx.yml -e "ext_domain=your.domain.com"
```

### Variables

| Variable | Description |
| --- | --- |
| `cp_dns_name` | DNS name for the Control Plane (API Server). |
| `he_net_password` | Password for dynamic DNS update (he.net) - optional if script enabled, you can replace it with your own script. Control plane node will be updated with this script at the node restart to update DNS name via he.net API server. |
| `ext_domain` | External domain for Nginx/SSL external/public usage (e.g., `your.domain.com`). |

## File Structure

- **Terraform**:
  - `main.tf`: Main infrastructure definition (EC2, SG).
  - `settings.tf`: Provider and variable definitions.
  - `inventory.tpl`: Template for generating the Ansible inventory.

- **Ansible**:
  - `main.yml`: Main playbook.
  - `inventory`: Generated inventory file from terraform .
  - `nginx.tpl`: Nginx configuration template for external/public usage.
