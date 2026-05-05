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
