# Bare Kubernetes on AWS (Terraform + Ansible)

This project contains **Terraform** code to provision infrastructure on AWS and **Ansible** playbooks to automatically deploy a bare basic Kubernetes cluster on the created instances.

I use my own personal domain and free dns.he.net with dynamic dns record for whole cluster services via HE.net DynDNS API.

You can use your own domain and dns provider with same principles.

_NOTICE_: Our demo environment assumes that we install all services for the bare cluster, otherwise we will not be able to deploy the infrastructure via terraform succesfully. If we install it in a virtual OrbStack - the CNI in the cluster is already based on flannel and, for example, network policies will not work as expected.

## Overview

1. **Infrastructure (Terraform)**:
   - Provisions EC2 instances for Control Plane and Worker nodes.
   - Configures AWS Firewall Security Groups.
   - Generates an ansible `inventory` file automatically.

2. **Configuration (Ansible)**:
   - **Node Preparation**: Installs dependencies, configures kernel modules, sysctl, containerd.
   - **Control Plane Initialization**:
     - Initalize cluster.
     - Installs Calico CNI.
     - Installs basic CRDs (Traefik, Cert-Manager, ArgoCD).
   - **Worker Join**:  Joins worker nodes to the cluster.
   - **Finalization**: Reboots all nodes.
   - **Basic Apps**:   Installs basic apps (KeyCloak, Vault).
   - Automates SSL certificates via Certbot from Lets Encrypt for basic and other apps.

## Prerequisites

- **Terraform** (>= 1.0)
- **Ansible** (>= 2.9)
- **AWS CLI** configured (or access keys available)

---

## 1. Infrastructure Setup (Terraform)

Navigate to the project directory.

### Configuration

Create a `terraform.tfvars` file (use `terraform.tfvars.default` as a template) to configure your specific settings:

You can use one micro and one medium instances for deploy one application for testing purposes, but it will not be enough for proper work.

_NOTICE_: You can use t3.large instance type for control plane and worker nodes as they use lots of memory

_WARNING_: Basic AWS account have a 8 vCPU limit. So you can use only 1 control plane node and 3 worker nodes without any fails from terraform side. If you want nore nodes - You can raise AWS request for 16 vCPUs extension.

```hcl
access_key   = "YOUR_AWS_ACCESS_KEY"
secret_key   = "YOUR_AWS_SECRET_KEY"
vpc_id       = "vpc-xxxxxxxx"  # Existing VPC ID
region       = "eu-north-1"    # Target Region
cp_count     = 1               # Number of Control Plane nodes
cp_type      = "t3.large"      # Control Plane instance type
worker_count = 2               # Number of Worker nodes - 2 with 20Gb storage is okay for our infrastructure
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

#### Init K8s cluster

Run the `main.yml` playbook with the required variables in command line

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
- k8s-control       - Initialize K8s cluster and control planes, install Calico CNI and basic CRDs (Traefik, Cert-Manager, MetalLB, ArgoCD).
- k8s-workers       - Install K8s to worker nodes and apply local-path-provisioner for K8 PVC claims.
- k8s-apps          - Install basic required apps to cluster - KeyCloak, Vault. Store generated passwords to password_$(service).txt
- k8s-nginx         - Nginx and CertBot configuration

```bash
ansible-playbook -i inventory main.yml \
  -e "cp_dns_name=cp.example.com" \
  -e "he_net_password=your_he_password" \
  -e "ext_domain=your.domain.com" \
  --tags="k8s-apps"
```

#### 1. Install basic Nginx for KeyCloak and Vault

For public access from terraform you need to install Nginx as proxy for KeyCloak and Vault as prerequrements. Currently we use control plane node as bastion host for all access and proxying. Nginx for basic KeyCloak and Vault services with LetsEncrypt based SSL triggered from k8s-apps role

#### 2. KeyCloak preparation

- Ansible will create random password for KeyCloak root user and save it to password_keycloak.txt file.
  And you can use it to login to KeyCloak web UI.
  Also admin-cli client secret will be created and saved to password_keycloak_secret.txt file - You need update terraform variables for keycloak password and adminc-cli secret for deploy all infra.

  _NOTICE_: In case of manual re-installation You will need to create secrets manually via this script (it use internal svc.cluster.local url by default) before changing anything for admin user in master realm.

  ```bash
  ./set-keycloak.sh -u admin -p <admin_password> -k <keycloak_url>
  ```

#### 3. Vault unseal

- Vault is unsealed for our testing purposes via patching values file in k8s-apps role. You should _DISABLE_ this steps in real world, and unseal it manually and save api token and keys to your infra repo manually.

#### 4. Install infra

- Use your repo with infra to deploy all stuff to cluster. For example you can use my repo with infra: <https://github.com/mturnaviotov/k8s-infra> - this repo contains all the necessary stuff to deploy all the applications to the cluster.

#### 5. Install Nginx for all applications

When all applications are deployed, they should be resolved via internal ${service}.${namespace}.svc.cluster.local before nginx will work with upstreams. You can test it via `kubectl exec -it -n <namespace> <pod-name> -- curl -I <service>.<namespace>.svc.cluster.local` from any node from cluster.
You also should provide cname for all applications in your dns provider and domain to point to control plane node as it will be your proxy before cert-bot can achieve certificates for your apps.

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

## Some useful commands

```bash
# Disk pressure disable toleration
for i in `kubectl get nodes | awk '{print $1}' | grep -v NAME`; do kubectl taint nodes $i node.kubernetes.io/disk-pressure-; done

# Delete failed pods
kubectl delete pods --field-selector 'status.phase==Failed' -A
```
