# AWS Landing Zone Bootstrap

Use this repository after AWS Control Tower and your landing zone foundation are already enabled.

The workflow order is:

1. Enable AWS Control Tower and complete landing zone foundation setup.
2. Use this repository to bootstrap these two things across one or more AWS accounts:
  - Terraform backend S3 buckets for remote state
  - GitHub Actions OIDC trust and deployment role

It is designed for AWS Organizations style environments using AWS IAM Identity Center (AWS SSO).

## AWS Control Tower and Landing Zone Foundation (step by step guide)

Use this runbook when setting up the foundation environment for hhmycompany in us-east-1.

### Project Context

- Organization: hhmycompany
- Region: us-east-1
- Management account: hhmycompany (management-admin)
- Networking hub account: Network-hub (network-hub-admin)
- Security accounts: CloudTrail administrator (Audit), Aggregator account (Logging)

### Phase 1: Prerequisites

1. Confirm administrator access to the AWS Management account.
2. Prepare four unique email addresses that are not used by existing AWS accounts:
  - Management email (existing)
  - Log archive email (new)
  - Audit email (new)
  - Network-hub email (new)

### Phase 2: Deploy Control Tower

1. Sign in to the AWS Management account.
2. Set the console region to US East (N. Virginia), us-east-1.
3. Open Control Tower and choose Set up landing zone.
4. In Pricing and regions:
  - Set Home Region to us-east-1.
  - Set Region deny guardrail to Disabled for initial setup flexibility.
5. In Organizational Units:
  - Keep foundational OU as Security.
  - Rename Sandbox OU to Infrastructure.
6. In Shared Accounts:
  - Log archive account name: Aggregator account.
  - Audit account name: CloudTrail administrator.
  - Provide the corresponding new email addresses.
7. Review settings, acknowledge required permissions, and start landing zone setup.
8. Wait approximately 30 to 45 minutes until the landing zone status is Enabled.

### Phase 3: Provision the Networking Account

1. In Control Tower, open Account Factory.
2. Choose Enroll account.
3. Enter account details:
  - Account email: network-hub email.
  - Display name: Network-hub.
4. Enter Identity Center user details for the primary operator.
5. Set organizational unit to Infrastructure.
6. Submit enrollment and wait until status changes from Enrolling to Enrolled.

### Phase 4: Configure CLI and SSO Profile

1. Accept the AWS IAM Identity Center invitation email and complete password setup.
2. In IAM Identity Center, assign the operator to the Network-hub account with AdministratorAccess.
3. Configure local SSO profile:
  - Run `aws configure sso`.
  - SSO region: us-east-1.
  - Select account: Network-hub.
  - Profile name: network-hub-admin.

### Phase 5: Validate Access

Run this command and confirm the returned account is the Network-hub account:

   aws sts get-caller-identity --profile network-hub-admin

## Terraform Backend and OIDC Bootstrap Scripts

- `scripts/bootstrap-terraform-backend.sh`
  - Creates or updates a Terraform state S3 bucket per account and generates matching Terraform files
  - **Recommended usage:** run this script for the Network-hub account only; spoke accounts should reuse the same Network-hub bucket with manually created Terraform files
  - Applies S3 hardening (versioning, encryption, public access block, ownership controls)
  - Applies bucket tags
  - Generates Terraform files per account in `terraform/<account-name>/`

- `scripts/bootstrap-github-oidc.sh`
  - Creates GitHub OIDC identity provider in target accounts
  - Creates/updates `GitHubAction-Terraform-Role`
  - Attaches `AdministratorAccess` to the role
  - Applies tags to IAM resources

## Prerequisites (Fresh Computer)

You need the following tools installed:

- Git
- AWS CLI v2
- Python 3
- Terraform (recommended: latest stable)

### macOS (Homebrew)

1. Install Homebrew (if missing):
   - `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
2. Install required tools:
   - `brew install git awscli python terraform`
3. Verify:
   - `git --version`
   - `aws --version`
   - `python3 --version`
   - `terraform version`

### Ubuntu/Debian

1. Install required tools:
   - `sudo apt update`
   - `sudo apt install -y git awscli python3 python3-pip`
2. Install Terraform from HashiCorp packages (recommended) or from your package manager.
3. Verify versions as above.

### Windows

Use winget (PowerShell):

- `winget install Git.Git`
- `winget install Amazon.AWSCLI`
- `winget install Python.Python.3`
- `winget install Hashicorp.Terraform`

Then verify in a new terminal:

- `git --version`
- `aws --version`
- `python --version`
- `terraform version`

## Clone and Enter the Repository

- `git clone <your-repo-url>`
- `cd aws-landing-zone`

## AWS Access Requirements

You must have access to AWS accounts through IAM Identity Center and permission to:

- Create and configure S3 buckets
- Create and manage IAM OIDC providers
- Create and manage IAM roles and policy attachments

Default role requested by scripts:

- `AWSAdministratorAccess`

You can override it with:

- `SSO_ROLE_NAME=<RoleName>`

## GitHub Actions ORG_ARN Prerequisite

Set `ORG_ARN` in GitHub repository Variables or Secrets to the organization ARN of the same account where the workflow assumes `AWS_OIDC_ROLE_ARN`.

Fetch the correct value from the target account context:

1. Verify caller account:
  - `aws sts get-caller-identity --profile network-hub-admin`
2. Get organization ARN:
  - `aws organizations describe-organization --profile network-hub-admin --query 'Organization.Arn' --output text`

Expected ARN shape:

- `arn:aws:organizations::<management-account-id>:organization/o-xxxxxxxxxx`

Do not use these as `ORG_ARN`:

- Root ARN (for example: `arn:aws:organizations::<id>:root/o-xxxx/r-xxxx`)
- Account ARN (for example: `arn:aws:organizations::<id>:account/o-xxxx/<account-id>`)

## Step 1: Bootstrap Terraform Backend Buckets

Run this script **for the Network-hub account only**:

- `./scripts/bootstrap-terraform-backend.sh --include "Network-hub" --sso-session my-sso-session`

The script can target multiple accounts if needed, but in most cases this is not recommended:

- `./scripts/bootstrap-terraform-backend.sh --all --sso-session my-sso-session`
- `./scripts/bootstrap-terraform-backend.sh --all --exclude "Sandbox" --sso-session my-sso-session`

What happens:

- An S3 bucket is created in the Network-hub account for Terraform state
- Bucket name format: `terraform-network-hub-<account-id>`
- Terraform files are generated in: `terraform/network-hub/`
- AWS provider version in generated Terraform: `~> 6.0`

For spoke accounts (Aggregator, Audit, etc.), **do not run this script**. Instead, manually create the Terraform files for each spoke under `terraform/<stack-name>/`, pointing their `backend.tf` to the same Network-hub bucket with a unique state key (for example `terraform-aggregator-account.tfstate`).

Default output location:

- `terraform/` at the repository root (one level above `scripts/`)

## Step 2: Bootstrap GitHub OIDC Role

Run:

- `./scripts/bootstrap-github-oidc.sh --include "Network-hub" --sso-session my-sso-session --repo-url https://github.com/<owner>/<repo>`

Or all accounts:

- `./scripts/bootstrap-github-oidc.sh --all --sso-session my-sso-session --repo-url <owner>/<repo>`

This creates/updates:

- OIDC provider for `token.actions.githubusercontent.com`
- IAM role `GitHubAction-Terraform-Role`
- Trust policy for `repo:<owner>/<repo>:*`

## Tags and Defaults

Both scripts support default tags through environment variables:

- `TAG_ENVIRONMENT` (default: `network-hub`)
- `TAG_MANAGED_BY` (default: `bootstrap-script`)
- `TAG_PROJECT` (default: `aws-landing-zone`)

Example:

- `TAG_ENVIRONMENT=prod TAG_PROJECT=landing-zone ./scripts/bootstrap-terraform-backend.sh --include "Network-hub" --sso-session my-sso-session`

Note: bucket tagging uses `put-bucket-tagging`, which replaces the bucket tag set with the specified tags.

## Optional Environment Variables

Terraform backend script:

- `SSO_ROLE_NAME` (default: `AWSAdministratorAccess`)
- `SSO_USE_DEVICE_CODE` (default: `true`)
- `TF_STATE_BUCKET_REGION` (default: `us-east-1`)
- `TAG_ENVIRONMENT`, `TAG_MANAGED_BY`, `TAG_PROJECT`

GitHub OIDC script:

- `GITHUB_REPO` (optional if `--repo-url` is provided)
- `SSO_ROLE_NAME` (default: `AWSAdministratorAccess`)
- `SSO_USE_DEVICE_CODE` (default: `true`)
- `TAG_ENVIRONMENT`, `TAG_MANAGED_BY`, `TAG_PROJECT`

## Using Generated Terraform

After backend bootstrap, each account folder under `terraform/` contains:

- `backend.tf`
- `versions.tf`
- `providers.tf`

Typical workflow per account folder:

1. `cd terraform/<account-name>`
2. Add your Terraform resources (.tf files)
3. `terraform init`
4. `terraform plan`
5. `terraform apply`

## Troubleshooting

- If prompted for SSO details, follow the interactive setup/login flow.
- If a bucket name conflict happens, verify account name/account ID mapping and rerun.
- If role resolution fails, ensure your SSO user can assume the configured role in target accounts.
- If scripts are not executable:
  - `chmod +x scripts/bootstrap-terraform-backend.sh scripts/bootstrap-github-oidc.sh`

## Security Notes

- The OIDC bootstrap currently attaches `AdministratorAccess` to the GitHub role.
- For production, replace with least-privilege policies aligned to your Terraform scope.

## Quick Start (After Foundation Setup)

Only run these commands after completing the foundation phases above.

1. `git clone <your-repo-url>`
2. `cd aws-landing-zone`
3. `chmod +x scripts/bootstrap-terraform-backend.sh scripts/bootstrap-github-oidc.sh`
4. `./scripts/bootstrap-terraform-backend.sh --include "Network-hub" --sso-session my-sso-session`
5. `./scripts/bootstrap-github-oidc.sh --include "Network-hub" --sso-session my-sso-session --repo-url <owner>/<repo>`

---

# Hub-and-Spoke Network Architecture

This section documents the Transit Gateway (TGW) hub-and-spoke network topology that enables secure, low-latency connectivity across AWS accounts in the landing zone.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Network Hub Account                      │
│                      (082787299790)                         │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ VPC: 10.0.0.0/16                                       │ │
│  │  ├─ Subnets: 10.0.1.0/24, 10.0.2.0/24 (nat/shared)    │ │
│  │  └─ NAT Gateways for outbound traffic                  │ │
│  │                                                         │ │
│  │ ┌─────────────────────────────────────────────────────┤ │
│  │ │ Transit Gateway (TGW): tgw-0bce03b7b87987017       │ │
│  │ │  • Default route table association: DISABLED        │ │
│  │ │  • Default route table propagation: DISABLED        │ │
│  │ │  • Explicit route table: tgw-rtb-0c6f5fd1cd16fd084 │ │
│  │ │  • Shared with AWS Organization via RAM             │ │
│  │ └─────────────────────────────────────────────────────┤ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
              │                               │
              │ TGW Attachment                │ TGW Attachment
              │ (Propagated)                  │ (Propagated)
              │                               │
    ┌─────────▼──────────┐        ┌──────────▼──────────┐
    │ Aggregator Spoke   │        │   Audit Spoke       │
    │ Account            │        │   Account           │
    │ (334296258026)     │        │   (612827969911)    │
    │                    │        │                    │
    │ VPC: 10.1.0.0/16  │        │ VPC: 10.2.0.0/16   │
    │ ┌────────────────┐ │        │ ┌────────────────┐ │
    │ │ App Subnets:   │ │        │ │ App Subnets:   │ │
    │ │ 10.1.1.0/24    │ │        │ │ 10.2.1.0/24    │ │
    │ │ 10.1.2.0/24    │ │        │ │ 10.2.2.0/24    │ │
    │ │                │ │        │ │                │ │
    │ │ IGW Routes to  │ │        │ │ IGW Routes to  │ │
    │ │ SSM endpoints  │ │        │ │ SSM endpoints  │ │
    │ │                │ │        │ │                │ │
    │ │ Test EC2:      │ │        │ │ Test EC2:      │ │
    │ │ i-0de98346...  │ │        │ │ i-0781987e...  │ │
    │ │ 10.1.1.249     │ │        │ │ 10.2.1.169     │ │
    │ └────────────────┘ │        │ └────────────────┘ │
    └────────────────────┘        └────────────────────┘
```

## Account Structure

| Account Name | Account ID | Purpose | Profile | Terraform Stack |
|---|---|---|---|---|
| Network Hub | 082787299790 | Transit Gateway hub, RAM sharing, shared services | `network-hub-admin` | `terraform/network-hub/` |
| Aggregator | 334296258026 | Spoke 1 (aggregator/logging workloads) | `aggregator-admin` | `terraform/aggregator-account/` |
| Audit | 612827969911 | Spoke 2 (audit/compliance workloads) | `audit-admin` | `terraform/audit-account/` |

## Directory Structure

```
terraform/
├── network-hub/
│   ├── main.tf (VPC, core resources)
│   ├── transit-gateway.tf (TGW definition, explicit route tables)
│   ├── spoke-routing.tf (TGW attachment associations & propagations)
│   ├── spoke-attachment-tags.tf (Tags TGW attachments from hub account)
│   ├── ram-resource-share.tf (Shares TGW with AWS Organization)
│   ├── providers.tf (AWS provider configuration)
│   ├── backend.tf (S3 remote state configuration)
│   ├── versions.tf (Terraform & provider versions)
│   ├── variables.tf (Input variables)
│   ├── outputs.tf (Exports TGW IDs for spoke remote state)
│   └── outputs.tf
│
├── aggregator-account/
│   ├── main.tf (VPC, subnets, route tables)
│   ├── test-instance.tf (Test EC2, IGW, app subnet routing)
│   ├── providers.tf
│   ├── backend.tf
│   ├── versions.tf
│   ├── variables.tf
│   └── outputs.tf (Exports instance ID, IPs, subnet IDs)
│
└── audit-account/
    ├── main.tf (VPC, subnets, route tables)
    ├── test-instance.tf (Test EC2, IGW, app subnet routing)
    ├── providers.tf
    ├── backend.tf
    ├── versions.tf
    ├── variables.tf
    └── outputs.tf

.github/workflows/
├── terraform-spoke-template.yml (Reusable workflow for all spoke deployments)
├── terraform-aggregator-account.yml (Wrapper calling reusable template)
└── terraform-audit-account.yml (Wrapper calling reusable template)
```

## AWS CLI Profile Configuration

Set up SSO profiles in `~/.aws/config`:

```
[sso-session my-sso-session]
sso_start_url = https://d-90660ad893.awsapps.com/start/
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile network-hub-admin]
sso_session = my-sso-session
sso_account_id = 082787299790
sso_role_name = AWSAdministratorAccess
region = us-east-1

[profile aggregator-admin]
sso_session = my-sso-session
sso_account_id = 334296258026
sso_role_name = AWSAdministratorAccess
region = us-east-1

[profile audit-admin]
sso_session = my-sso-session
sso_account_id = 612827969911
sso_role_name = AWSAdministratorAccess
region = us-east-1
```

**Install Session Manager Plugin (required for SSM access):**

```bash
# macOS
brew install --cask session-manager-plugin

# Ubuntu/Debian
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

## Network Routing

### Transit Gateway Routes

The TGW explicitly routes between spokes using a dedicated route table (`tgw-rtb-0c6f5fd1cd16fd084`):

| Destination | Target | Origin | Status |
|---|---|---|---|
| 10.1.0.0/16 | Aggregator attachment | Propagation | Active |
| 10.2.0.0/16 | Audit attachment | Propagation | Active |
| 10.0.0.0/8 | TGW (RFC1918 via TGW) | Manual route | Active |
| 172.16.0.0/12 | TGW (RFC1918 via TGW) | Manual route | Active |
| 192.168.0.0/16 | TGW (RFC1918 via TGW) | Manual route | Active |

### Spoke Subnet Routing

Each spoke's app subnet route table includes:

| Destination | Target | Purpose |
|---|---|---|
| 10.0.0.0/8 | TGW | Reach other spokes & hub via RFC1918 |
| 172.16.0.0/12 | TGW | Reach RFC1918 networks |
| 192.168.0.0/16 | TGW | Reach RFC1918 networks |
| 0.0.0.0/0 | IGW | Internet access (required for SSM agent to reach AWS endpoints) |

## Access Patterns

### Option 1: AWS Systems Manager (Recommended for headless instances)

```bash
# From aggregator spoke
aws ssm start-session --target i-0de98346eb255410d --region us-east-1 --profile aggregator-admin

# From audit spoke
aws ssm start-session --target i-0781987e5832fded0 --region us-east-1 --profile audit-admin

# From SSM session, test connectivity
ping 10.1.1.249  # Ping the other spoke
```

### Option 2: SSH (Requires EC2 Instance Connect or SSH key management)

```bash
# Get instance public IP
aws ec2 describe-instances --instance-ids i-0de98346eb255410d \
  --region us-east-1 --profile aggregator-admin \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

# Connect via SSH
ssh -i ~/.ssh/id_rsa ec2-user@44.213.89.38

# Test connectivity to audit spoke
ping -c 5 10.2.1.169
```

### Option 3: EC2 Instance Connect (Temporary SSH key generation)

```bash
# Generate temporary SSH access
aws ec2-instance-connect send-ssh-public-key \
  --instance-id i-0de98346eb255410d \
  --instance-os-user ec2-user \
  --region us-east-1 \
  --profile aggregator-admin \
  --ssh-public-key "$(cat ~/.ssh/id_rsa.pub)"
```

## Connectivity Validation

### Verify TGW Routes

```bash
# Check TGW route table
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-0c6f5fd1cd16fd084 \
  --region us-east-1 \
  --profile network-hub-admin \
  --filters "Name=state,Values=active"

# Check TGW attachment associations
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id tgw-rtb-0c6f5fd1cd16fd084 \
  --region us-east-1 \
  --profile network-hub-admin
```

### Test Spoke-to-Spoke Connectivity

From aggregator instance:
```bash
ping -c 5 10.2.1.169  # Audit spoke instance
```

From audit instance:
```bash
ping -c 5 10.1.1.249  # Aggregator spoke instance
```

**Expected result:** 5/5 packets transmitted and received, 0% loss, latency ~0.5ms

## Onboarding a New Spoke Account

### Prerequisites
1. AWS account exists and is part of the organization
2. Account added to RAM resource share for TGW access
3. AWS CLI profile created for the new spoke account

### Steps

1. **Create spoke account Terraform stack:**

   ```bash
   # Copy aggregator-account template
   cp -r terraform/aggregator-account terraform/new-spoke-account
   ```

2. **Update variables:**

   Edit `terraform/new-spoke-account/variables.tf`:
   ```hcl
   variable "account_name" {
     default = "new-spoke-account"
   }
   
   variable "vpc_name" {
     default = "new-spoke-vpc"
   }
   ```

3. **Update providers:**

   Edit `terraform/new-spoke-account/providers.tf`:
   ```hcl
   provider "aws" {
     alias   = "spoke"
     profile = "new-spoke-admin"  # Your new profile name
     # ... rest of config
   }
   ```

4. **Create GitHub Actions workflow:**

   Copy `.github/workflows/terraform-aggregator-account.yml` and update:
   ```yaml
   - name: Terrafor New Spoke
     uses: ./.github/workflows/terraform-spoke-template.yml
     with:
       spoke_name: "new-spoke-account"
       working_directory: "terraform/new-spoke-account"
       # ... other inputs
   ```

5. **Add TGW attachment to hub routing:**

   Update `terraform/network-hub/spoke-routing.tf` with new attachment association/propagation (repeat pattern from existing spokes)

6. **Deploy:**

   ```bash
   cd terraform/new-spoke-account
   terraform init
   terraform plan
   terraform apply
   ```

7. **Validate connectivity:**

   ```bash
   # From new spoke instance, ping existing spokes
   ping 10.1.1.249  # Aggregator
   ping 10.2.1.169  # Audit
   ```

## Development & Maintenance

### Terraform Workflow

Always run `terraform fmt` before committing:

```bash
terraform fmt -recursive terraform/
```

Typical development flow:

```bash
# 1. Make changes to .tf files
# 2. Format
terraform fmt -recursive terraform/

# 3. Plan specific stack
cd terraform/<stack-name>
terraform plan -out=tfplan

# 4. Review plan, then apply
terraform apply tfplan

# 5. Commit and push
git add .
git commit -m "fix: describe your change"
git push origin <branch-name>

# 6. Create PR for review
# 7. Merge to main (triggers GitHub Actions apply)
```

### CI/CD Workflow

GitHub Actions workflows trigger on:
- **PR events** (feature branches): `terraform plan` only (no apply)
- **Merge to main**: `terraform plan` + approval gate + `terraform apply`

Workflows require:
- `id-token: write` permission for OIDC authentication
- Secrets for each spoke account's IAM role ARN

### Troubleshooting

**Instance not appearing in SSM Fleet Manager:**
- Ensure IAM role has `AmazonSSMManagedInstanceCore` policy
- Ensure instance has outbound internet access (IGW + default route)
- Wait 1-2 minutes for SSM agent to register

**TGW attachment not propagating routes:**
- Verify attachment is in the correct TGW route table (not default)
- Check route table association/propagation status via AWS Console or CLI
- Verify network ACLs allow traffic on TGW attachment subnets

**Terraform state lock errors:**
- Check S3 bucket for stale lock files: `aws s3 ls s3://terraform-network-hub-082787299790/`
- If needed, force unlock (use with caution): `terraform force-unlock <LOCK_ID>`

**OIDC Token Errors in GitHub Actions:**
- Verify workflows have `permissions: { id-token: write, contents: read }`
- Verify IAM role trust policy includes GitHub OIDC provider
- Check secrets contain correct role ARNs for each account

## Next Steps

- [ ] Add VPC Flow Logs for traffic analysis
- [ ] Enable AWS Config for compliance monitoring
- [ ] Deploy private subnets with NAT Gateways
- [ ] Implement DNS resolution (Route 53 Private Hosted Zones)
- [ ] Add shared services VPC for logging, security tools
- [ ] Configure GuardDuty and Security Hub
- [ ] Tag resources for cost allocation and chargeback

---
