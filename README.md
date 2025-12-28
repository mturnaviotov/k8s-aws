# Kubernetes on AWS (Terraform + Ansible)

This project contains **Terraform** code to provision infrastructure on AWS and **Ansible** playbooks to automatically deploy a Kubernetes cluster (Kubeadm) on the created instances.

## Overview

1. **Infrastructure (Terraform)**:
   - Provisions EC2 instances for Control Plane and Worker nodes.
   - Configures Security Groups.
   - Generates an ansible `inventory` file automatically.

2. **Configuration (Ansible)**:
   - **Node Preparation**: Installs dependencies, configures kernel modules, sysctl, containerd.
   - **Control Plane Initialization**:
     - Runs `kubeadm init`.
     - Sets up `kubectl` for the user.
     - Installs Flannel CNI.
     - Installs basic CRDs (Traefik, Cert-Manager, ArgoCD).
     - Configures Nginx as a reverse proxy for services.
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

Create a `terraform.tfvars` file (or use `terraform.tfvars.default` as a template) to configure your specific settings:

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

### Usage

Run the `k8.yml` playbook with the necessary variables:

```bash
ansible-playbook -i inventory k8.yml \
  -e "cp_dns_name=cp.example.com" \
  -e "he_net_password=your_he_password" \
  -e "ext_domain=your.domain.com"
```

### Variables

| Variable | Description |
| --- | --- |
| `cp_dns_name` | DNS name for the Control Plane (API Server). |
| `he_net_password` | Password for dynamic DNS update (he.net) - optional if script enabled, you can replace it with your own script. Control plane node will be updated with this script at the node restart to update DNS name via he.net API server. |
| `ext_domain` | External domain for Nginx/SSL external/public usage (e.g., `test.example.com`). |

---

## File Structure

- **Terraform**:
  - `main.tf`: Main infrastructure definition (EC2, SG).
  - `settings.tf`: Provider and variable definitions.
  - `inventory.tpl`: Template for generating the Ansible inventory.

- **Ansible**:
  - `k8.yml`: Main playbook.
  - `inventory`: Generated inventory file from terraform .
  - `nginx.tpl`: Nginx configuration template for external/public usage.
