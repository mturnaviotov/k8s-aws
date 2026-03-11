# Kubernetes on AWS (Terraform + Ansible)

This project contains **Terraform** code to provision infrastructure on AWS and **Ansible** playbooks to automatically deploy a Kubernetes cluster (Kubeadm) on the created instances.

## Overview

1. **Infrastructure (Terraform)**:
   - Provisions EC2 instances for Control Plane and Worker nodes.
   - Configures AWS Firewall Security Groups.
   - Generates an ansible `inventory` file automatically.

2. **Configuration (Ansible)**:
   - **Node Preparation**: Installs dependencies, configures kernel modules, sysctl, containerd.
   - **Control Plane Initialization**:
     - Runs `kubeadm init`.
     - Sets up `kubectl` for the user.
     - Installs Flannel CNI.
     - Installs basic CRDs (Traefik, Cert-Manager, ArgoCD).
     - Automates SSL certificates via Certbot.
   - **Worker Join**: Joins worker nodes to the cluster.
   - **Finalization**: Reboots all nodes.

## prerequisites

- **Terraform** (>= 1.0)
- **Ansible** (>= 2.9)
- **AWS CLI** configured (or access keys available).

---

## 1. Infrastructure Setup (Terraform)

Navigate to the project directory.

### Configuration

Create a `terraform.tfvars` file (use `terraform.tfvars.default` as a template) to configure your specific settings:

```hcl
access_key   = "YOUR_AWS_ACCESS_KEY"
secret_key   = "YOUR_AWS_SECRET_KEY"
vpc_id       = "vpc-xxxxxxxx"        # Existing VPC ID
region       = "eu-north-1"          # Target Region
cp_count     = 1                     # Number of Control Plane nodes # currently supported only 1 control plane node
cp_type      = "t3.medium"           # Control Plane instance type
worker_count = 2                     # Number of Worker nodes
worker_type  = "t3.medium"           # Worker instance type
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
Role based variables you can find in role/${name}/defaults

```bash
ansible-playbook -i inventory main.yml \
  -e "cp_dns_name=cp.example.com" \
  -e "he_net_password=your_he_password" \
  -e "ext_domain=your.domain.com"
```

You can use partial configuration via tags if you need. You can find available tags at the main.yaml in roles, and use as in this example

```
ansible-playbook -i inventory main.yml \
  -e "cp_dns_name=cp.example.com" \
  -e "he_net_password=your_he_password" \
  -e "ext_domain=your.domain.com"
  --tags="k8s-apps"
```

#### 1. Install basic Nginx for KeyCloak and Vault as prerequrements for terraform based infrastructure deploy

```
ansible-playbook -i inventory nginx.yml -e "ext_domain=your.domain.com" --tags=nginx_basics
```

#### 2. KeyCloak preparation

- Go to the web UI for KeyCloak with provided via text file password
- go to clients -> choose 'admin-cli'
- enable client authentication, save
- go to credentials tab and copy client secret to terraform.vars in your infra repo

#### 3. Vault unseal

- Go to the web UI for Vault and unseal it via web interface
- save api token and keys to your infra repo

#### 4. Install infra

- Use your repo with infra to deploy all stuff to cluster

#### 5. Install Nginx for all applications

All of them should be resolved via internal ${service}.${namespace}.svc.cluster.local before nginx will work with upstreams

```
ansible-playbook -i inventory nginx.yml -e "ext_domain=your.domain.com" --tags=nginx_all
```

### Variables

| Variable | Description |
| --- | --- |
| `cp_dns_name` | DNS name for the Control Plane (API Server). |
| `he_net_password` | Password for dynamic DNS update (he.net) - optional if script enabled, you can replace it with your own script. Control plane node will be updated with this script at the node restart to update DNS name via he.net API server. |
| `ext_domain` | External domain for Nginx/SSL external/public usage (e.g., `your.domain.com`). |

---

## File Structure

- **Terraform**:
  - `main.tf`: Main infrastructure definition (EC2, SG).
  - `settings.tf`: Provider and variable definitions.
  - `inventory.tpl`: Template for generating the Ansible inventory.

- **Ansible**:
  - `main.yml`: Main playbook.
  - `inventory`: Generated inventory file from terraform .
  - `nginx.tpl`: Nginx configuration template for external/public usage.
