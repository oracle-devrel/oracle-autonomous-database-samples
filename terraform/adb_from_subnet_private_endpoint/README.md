# Terraform — Oracle Autonomous Database with Private Endpoint

Creates a VCN, a private subnet, a Network Security Group, and an Autonomous Database (ADB) with a private endpoint. The ADB is only accessible from within the VCN.

## Files

| File | Description |
|---|---|
| `main.tf` | ADB resource with private endpoint configuration |
| `vcn.tf` | VCN, internet gateway, route table, and private subnet |
| `nsg.tf` | Network Security Group with rules for DB and HTTP traffic |
| `variables.tf` | All configurable parameters |
| `outputs.tf` | Values exported after apply |
| `versions.tf` | Terraform and provider version requirements |
| `provider.tf` | OCI provider configuration |
| `terraform.tfvars` | Your actual values |

## Architecture

```
VCN (10.0.0.0/16)
└── Private Subnet (10.0.1.0/24)
    ├── NSG
    │   ├── Ingress: port 1521-1522 (SQL*Net) from VCN
    │   ├── Ingress: port 443 (HTTPS) from VCN
    │   └── Egress: all traffic allowed
    └── ADB (private endpoint)
        └── No public IP — accessible only from within the VCN
```

## Quick Start

```bash
# 1. Edit terraform.tfvars with your real values
#    (tenancy_ocid, user_ocid, fingerprint, compartment_ocid, etc.)

# 2. Initialize Terraform
terraform init

# 3. Review the plan before applying
terraform plan

# 4. Create all resources
terraform apply
```

## NSG Rules

| Direction | Protocol | Port | Source/Destination | Purpose |
|---|---|---|---|---|
| Ingress | TCP | 1521-1522 | VCN CIDR | SQL*Net database connections |
| Ingress | TCP | 443 | VCN CIDR | HTTPS — Database Actions and APEX |
| Egress | All | All | 0.0.0.0/0 | Outbound traffic |