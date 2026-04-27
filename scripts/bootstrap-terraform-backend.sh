#!/bin/bash
set -euo pipefail

# Provisions Terraform state S3 buckets in selected AWS accounts.
#
# What it does per account:
# 1) Creates bucket: terraform-<account-name>-<account-id> with Object Lock enabled
# 2) Enables versioning (implicitly enabled by Object Lock; also set explicitly)
# 3) Enables default encryption (AES256)
# 4) Enables S3 Block Public Access
# 5) Enforces bucket owner object ownership
# 6) Applies resource tags
#
# Note: Object Lock must be enabled at bucket creation time and cannot be added
# to an existing bucket. If a bucket already exists without Object Lock, the
# script will warn and skip recreation. Delete the bucket manually and re-run
# to get a new bucket with Object Lock enabled.
#
# Scope:
#   Intended for AWS Landing Zone / AWS Organizations style
#   multi-account environments that use AWS IAM Identity Center (AWS SSO)
#   with a shared SSO session.
#
# Auth model:
#   The script requires --sso-session on every run.
#   If the named SSO session is already configured and cached, the script uses
#   the cached token non-interactively.
#
#   If the named SSO session is not configured yet, or no valid cached token
#   exists, the script falls back to interactive first-time authentication:
#
#     1) prompt for SSO start URL and SSO region
#     2) write [sso-session <name>] to ~/.aws/config
#     3) aws sso login --sso-session <name>
#
#   If no SSO region is provided during first-time setup, the script defaults
#   it to us-east-1.
#
# Supported account-selection combinations:
#   1) --include "ACCOUNT_NAME_1,ACCOUNT_NAME_2,..."
#   2) --all
#   3) --all --exclude "ACCOUNT_NAME_X,..."
#
# Invalid combinations:
#   1) --include with --exclude
#   2) --all with --include
#
# Usage:
#   ./bootstrap-terraform-backend.sh --include "Network-hub" --sso-session my-sso-session
#   ./bootstrap-terraform-backend.sh --all --sso-session my-sso-session
#   ./bootstrap-terraform-backend.sh --all --exclude "Sandbox" --sso-session my-sso-session
#
# Optional env vars:
#   SSO_ROLE_NAME       SSO role to request in each account.
#                       Default: AWSAdministratorAccess
#   SSO_USE_DEVICE_CODE Use device-code login flow for aws sso login.
#                       Default: true
#   TF_STATE_BUCKET_REGION
#                       Bucket region. Default: us-east-1
#   TAG_ENVIRONMENT     Tag value for Environment. Default: network-hub
#   TAG_MANAGED_BY      Tag value for ManagedBy. Default: bootstrap-script
#   TAG_PROJECT         Tag value for Project. Default: aws-landing-zone

SSO_SESSION_NAME=""
SSO_ROLE_NAME="${SSO_ROLE_NAME:-AWSAdministratorAccess}"
SSO_USE_DEVICE_CODE="${SSO_USE_DEVICE_CODE:-true}"
SSO_NO_BROWSER="false"

BUCKET_REGION="${TF_STATE_BUCKET_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_OUTPUT_DIR="${SCRIPT_DIR}/../terraform"

TAG_ENVIRONMENT="${TAG_ENVIRONMENT:-network-hub}"
TAG_MANAGED_BY="${TAG_MANAGED_BY:-bootstrap-script}"
TAG_PROJECT="${TAG_PROJECT:-aws-landing-zone}"

TAG_ARGS=(
  "Key=Environment,Value=${TAG_ENVIRONMENT}"
  "Key=ManagedBy,Value=${TAG_MANAGED_BY}"
  "Key=Project,Value=${TAG_PROJECT}"
)

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI is required."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required."
  exit 1
fi

usage() {
  echo "Usage: $0 --include \"ACCOUNT_NAME_1,ACCOUNT_NAME_2,...\" --sso-session NAME [--bucket-region REGION]"
  echo "       $0 --all [--exclude \"ACCOUNT_NAME_X,...\"] --sso-session NAME [--bucket-region REGION]"
  echo ""
  echo "Flags:"
  echo "  --include, -i       Comma-separated AWS account names to target."
  echo "  --all, -a           Target all accounts assigned to the current SSO session."
  echo "  --exclude, -x       Optional. Comma-separated AWS account names to skip when using --all."
  echo "  --sso-session, -s   Required. SSO session name to use or create."
  echo "  --bucket-region     Optional. Bucket region. Default: us-east-1."
  echo "  --terraform-dir     Optional. Output dir for generated Terraform files."
  echo "                      Default: ../terraform (relative to script directory)."
  echo "  --use-device-code   Use AWS CLI device-code login flow (recommended)."
  echo "  --auth-code-flow    Use AWS CLI auth-code login flow (browser localhost callback)."
  echo "  --no-browser        Pass --no-browser to aws sso login."
  echo "  --help, -h          Show this help message."
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

contains_in_array() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

parse_account_names_csv() {
  local csv="$1"
  local raw_names
  IFS=',' read -r -a raw_names <<< "$csv"
  local raw_name account_name
  for raw_name in "${raw_names[@]}"; do
    account_name="$(trim "$raw_name")"
    if [[ -n "$account_name" ]]; then
      printf '%s\n' "$account_name"
    fi
  done
}

get_sso_session_field() {
  local session_name="$1"
  local field_name="$2"
  awk -v session="$session_name" -v field="$field_name" '
    $0 == "[sso-session " session "]" { in_block = 1; next }
    /^\[/ { if (in_block) exit; in_block = 0 }
    in_block && $1 == field && $2 == "=" {
      $1 = ""
      $2 = ""
      sub(/^[ \t]+/, "")
      print
      exit
    }
  ' ~/.aws/config 2>/dev/null
}

get_cached_sso_access_token() {
  local start_url="$1"
  local region="$2"
  python3 - "$start_url" "$region" <<'PY'
import datetime
import glob
import json
import os
import sys

start_url = sys.argv[1]
region = sys.argv[2]
cache_dir = os.path.expanduser("~/.aws/sso/cache")
now = datetime.datetime.now(datetime.timezone.utc)

def parse_expiry(value: str):
    if not value:
        return None
    value = value.replace("Z", "+00:00")
    try:
        return datetime.datetime.fromisoformat(value)
    except ValueError:
        return None

for path in sorted(glob.glob(os.path.join(cache_dir, "*.json"))):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        continue

    if data.get("startUrl") != start_url:
        continue
    if data.get("region") != region:
        continue

    expires_at = parse_expiry(data.get("expiresAt"))
    if expires_at is None or expires_at <= now:
        continue

    token = data.get("accessToken")
    if token:
        print(token)
        sys.exit(0)

sys.exit(1)
PY
}

ensure_sso_session_authenticated() {
  local start_url region

  start_url="$(get_sso_session_field "$SSO_SESSION_NAME" sso_start_url)"
  region="$(get_sso_session_field "$SSO_SESSION_NAME" sso_region)"

  if [[ -z "$start_url" || -z "$region" ]]; then
    echo "SSO session '$SSO_SESSION_NAME' is not configured yet."
    echo "Starting interactive first-time setup for session '$SSO_SESSION_NAME'."

    read -r -p "SSO start URL: " start_url
    if [[ -z "$start_url" ]]; then
      echo "ERROR: SSO start URL is required."
      return 1
    fi

    read -r -p "SSO region [us-east-1]: " region
    region="${region:-us-east-1}"

    mkdir -p ~/.aws
    touch ~/.aws/config
    {
      if [[ -s ~/.aws/config ]]; then
        printf '\n'
      fi
      printf '[sso-session %s]\n' "$SSO_SESSION_NAME"
      printf 'sso_start_url = %s\n' "$start_url"
      printf 'sso_region = %s\n' "$region"
      printf 'sso_registration_scopes = sso:account:access\n'
    } >> ~/.aws/config

    start_url="$(get_sso_session_field "$SSO_SESSION_NAME" sso_start_url)"
    region="$(get_sso_session_field "$SSO_SESSION_NAME" sso_region)"
    if [[ -z "$start_url" || -z "$region" ]]; then
      echo "ERROR: SSO session '$SSO_SESSION_NAME' was not configured in ~/.aws/config."
      return 1
    fi
  fi

  SSO_START_URL="$start_url"
  SSO_REGION="$region"

  if SSO_ACCESS_TOKEN="$(get_cached_sso_access_token "$SSO_START_URL" "$SSO_REGION")"; then
    return 0
  fi

  echo "No valid cached SSO token found for session '$SSO_SESSION_NAME'."
  local login_args=(sso login --sso-session "$SSO_SESSION_NAME")

  if [[ "$SSO_USE_DEVICE_CODE" == "true" ]]; then
    login_args+=(--use-device-code)
  fi

  if [[ "$SSO_NO_BROWSER" == "true" ]]; then
    login_args+=(--no-browser)
  fi

  echo "Starting interactive login: aws ${login_args[*]}"
  aws "${login_args[@]}"

  if ! SSO_ACCESS_TOKEN="$(get_cached_sso_access_token "$SSO_START_URL" "$SSO_REGION")"; then
    echo "ERROR: Unable to find a valid cached SSO token after login for session '$SSO_SESSION_NAME'."
    return 1
  fi
}

sso_cli() {
  AWS_PAGER="" aws --region "$SSO_REGION" --no-cli-pager sso "$@" --access-token "$SSO_ACCESS_TOKEN"
}

target_aws_cli() {
  local access_key_id="$1"
  local secret_access_key="$2"
  local session_token="$3"
  shift 3
  AWS_ACCESS_KEY_ID="$access_key_id" \
  AWS_SECRET_ACCESS_KEY="$secret_access_key" \
  AWS_SESSION_TOKEN="$session_token" \
  AWS_PAGER="" aws --no-cli-pager "$@"
}

list_accounts_table() {
  sso_cli list-accounts --no-paginate --query 'accountList[].[accountName,accountId,emailAddress]' --output text
}

resolve_role_name() {
  local account_id="$1"
  local roles_output
  roles_output="$(sso_cli list-account-roles --account-id "$account_id" --no-paginate --query 'roleList[].roleName' --output text 2>/dev/null || true)"

  if [[ -z "$roles_output" ]]; then
    echo ""
    return 0
  fi

  local role_names=()
  local role_name
  for role_name in $roles_output; do
    role_names+=("$role_name")
  done

  if contains_in_array "$SSO_ROLE_NAME" "${role_names[@]}"; then
    echo "$SSO_ROLE_NAME"
    return 0
  fi

  if [[ ${#role_names[@]} -eq 1 ]]; then
    echo "${role_names[0]}"
    return 0
  fi

  echo ""
}

ensure_bucket_baseline() {
  local access_key_id="$1"
  local secret_access_key="$2"
  local session_token="$3"
  local account_id="$4"
  local account_name="$5"

  local account_name_sanitized
  account_name_sanitized="$(sanitize_dirname "$account_name")"
  local bucket_name="terraform-${account_name_sanitized}-${account_id}"
  local create_ok="false"

  if target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api head-bucket --bucket "$bucket_name" >/dev/null 2>&1; then
    echo "Bucket already exists: $bucket_name"
    if ! target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api get-object-lock-configuration --bucket "$bucket_name" >/dev/null 2>&1; then
      echo "WARNING: Bucket '$bucket_name' exists but does NOT have Object Lock enabled."
      echo "         Object Lock can only be enabled at bucket creation time."
      echo "         To enable it: delete the bucket manually, then re-run this script."
    fi
    create_ok="true"
  else
    echo "Creating bucket: $bucket_name (region: $BUCKET_REGION)"
    if [[ "$BUCKET_REGION" == "us-east-1" ]]; then
      if target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api create-bucket \
        --bucket "$bucket_name" \
        --object-lock-enabled-for-bucket >/dev/null 2>&1; then
        create_ok="true"
      fi
    else
      if target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api create-bucket \
        --bucket "$bucket_name" \
        --create-bucket-configuration "LocationConstraint=$BUCKET_REGION" \
        --region "$BUCKET_REGION" \
        --object-lock-enabled-for-bucket >/dev/null 2>&1; then
        create_ok="true"
      fi
    fi
  fi

  if [[ "$create_ok" != "true" ]]; then
    echo "ERROR: Could not create or access bucket '$bucket_name'."
    echo "The name may already be taken globally by another AWS account."
    return 1
  fi

  echo "Applying baseline settings to $bucket_name..."

  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api put-bucket-versioning \
    --bucket "$bucket_name" \
    --versioning-configuration Status=Enabled >/dev/null

  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api put-public-access-block \
    --bucket "$bucket_name" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null

  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api put-bucket-encryption \
    --bucket "$bucket_name" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null

  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api put-bucket-ownership-controls \
    --bucket "$bucket_name" \
    --ownership-controls Rules=[{ObjectOwnership=BucketOwnerEnforced}] >/dev/null

  echo "Applying tags to bucket..."
  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" s3api put-bucket-tagging \
    --bucket "$bucket_name" \
    --tagging 'TagSet=[{Key=Environment,Value='"${TAG_ENVIRONMENT}"'},{Key=ManagedBy,Value='"${TAG_MANAGED_BY}"'},{Key=Project,Value='"${TAG_PROJECT}"'}]' >/dev/null

  echo "Bucket ready: $bucket_name"
  echo ""
}

sanitize_dirname() {
  local name="$1"
  echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\{2,\}/-/g' | sed 's/^-//;s/-$//'
}

generate_terraform_files() {
  local account_name="$1"
  local account_id="$2"
  local dir_name
  dir_name="$(sanitize_dirname "$account_name")"
  local output_dir="${TERRAFORM_OUTPUT_DIR}/${dir_name}"
  local bucket_name="terraform-${dir_name}-${account_id}"
  local state_key="terraform-${dir_name}.tfstate"

  # Infer environment from account name
  local environment="production"
  if [[ "$account_name" =~ [Dd]ev|[Dd]evelopment ]]; then
    environment="development"
  elif [[ "$account_name" =~ [Ss]taging|[Ss]tage ]]; then
    environment="staging"
  elif [[ "$account_name" =~ [Tt]est|[Qq]a ]]; then
    environment="testing"
  elif [[ "$account_name" =~ [Ss]andbox ]]; then
    environment="sandbox"
  fi

  mkdir -p "$output_dir"

  cat > "${output_dir}/backend.tf" <<EOF
terraform {
  backend "s3" {
    bucket                = "${bucket_name}"
    key                   = "${state_key}"
    region                = "${BUCKET_REGION}"
    encrypt               = true
    use_s3_native_locking = true
  }
}
EOF

  cat > "${output_dir}/versions.tf" <<EOF
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
EOF

  cat > "${output_dir}/providers.tf" <<EOF
provider "aws" {
  region = "${BUCKET_REGION}"

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = "${environment}"
      AccountName = "${account_name}"
      AccountId   = "${account_id}"
    }
  }
}
EOF

  echo "Terraform files generated: ${output_dir}/"
  echo ""
}

INCLUDE_CSV=""
EXCLUDE_CSV=""
USE_ALL="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include|-i)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --include requires a comma-separated value."
        usage
        exit 1
      fi
      INCLUDE_CSV="$1"
      ;;
    --all|-a)
      USE_ALL="true"
      ;;
    --exclude|-x)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --exclude requires a comma-separated value."
        usage
        exit 1
      fi
      EXCLUDE_CSV="$1"
      ;;
    --sso-session|-s)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --sso-session requires a value."
        usage
        exit 1
      fi
      SSO_SESSION_NAME="$1"
      ;;
    --bucket-region)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --bucket-region requires a value."
        usage
        exit 1
      fi
      BUCKET_REGION="$1"
      ;;
    --terraform-dir)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --terraform-dir requires a value."
        usage
        exit 1
      fi
      TERRAFORM_OUTPUT_DIR="$1"
      ;;
    --use-device-code)
      SSO_USE_DEVICE_CODE="true"
      ;;
    --auth-code-flow)
      SSO_USE_DEVICE_CODE="false"
      ;;
    --no-browser)
      SSO_NO_BROWSER="true"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$USE_ALL" == "true" && -n "$INCLUDE_CSV" ]]; then
  echo "ERROR: --all cannot be used together with --include."
  usage
  exit 1
fi

if [[ -n "$INCLUDE_CSV" && -n "$EXCLUDE_CSV" ]]; then
  echo "ERROR: --include and --exclude cannot be used together."
  echo "Use --include by itself, or use --all with --exclude."
  usage
  exit 1
fi

if [[ "$USE_ALL" != "true" && -z "$INCLUDE_CSV" ]]; then
  echo "ERROR: Either --include or --all is required."
  usage
  exit 1
fi

if [[ -z "$SSO_SESSION_NAME" ]]; then
  echo "ERROR: --sso-session is required."
  usage
  exit 1
fi

if ! ensure_sso_session_authenticated; then
  exit 1
fi

ACCOUNT_NAMES=()
if [[ "$USE_ALL" == "true" ]]; then
  while IFS=$'\t' read -r account_name _account_id _account_email; do
    account_name="$(trim "$account_name")"
    if [[ -n "$account_name" ]] && ! contains_in_array "$account_name" "${ACCOUNT_NAMES[@]-}"; then
      ACCOUNT_NAMES+=("$account_name")
    fi
  done < <(list_accounts_table)
else
  while IFS= read -r account_name; do
    if [[ -n "$account_name" ]] && ! contains_in_array "$account_name" "${ACCOUNT_NAMES[@]-}"; then
      ACCOUNT_NAMES+=("$account_name")
    fi
  done < <(parse_account_names_csv "$INCLUDE_CSV")
fi

if [[ ${#ACCOUNT_NAMES[@]} -eq 0 ]]; then
  if [[ "$USE_ALL" == "true" ]]; then
    echo "ERROR: No AWS accounts were returned for SSO session '$SSO_SESSION_NAME'."
  else
    echo "ERROR: No valid account names provided in --include."
  fi
  exit 1
fi

EXCLUDE_NAMES=()
if [[ -n "$EXCLUDE_CSV" ]]; then
  while IFS= read -r account_name; do
    if [[ -n "$account_name" ]] && ! contains_in_array "$account_name" "${EXCLUDE_NAMES[@]-}"; then
      EXCLUDE_NAMES+=("$account_name")
    fi
  done < <(parse_account_names_csv "$EXCLUDE_CSV")
fi

if [[ "$USE_ALL" == "true" ]]; then
  FILTERED_ACCOUNT_NAMES=()
  for account_name in "${ACCOUNT_NAMES[@]}"; do
    if ! contains_in_array "$account_name" "${EXCLUDE_NAMES[@]-}"; then
      FILTERED_ACCOUNT_NAMES+=("$account_name")
    fi
  done
  ACCOUNT_NAMES=("${FILTERED_ACCOUNT_NAMES[@]}")
fi

if [[ ${#ACCOUNT_NAMES[@]} -eq 0 ]]; then
  echo "ERROR: No accounts left after applying --exclude."
  exit 1
fi

echo "AWS Accounts to process:"
for account_name in "${ACCOUNT_NAMES[@]}"; do
  echo "  - $account_name"
done

echo "Bucket naming: terraform-<account-name>-<account-id>"
echo "Bucket region: $BUCKET_REGION"
echo ""

FAILED_ACCOUNTS=()
CREATED_BUCKETS=()
GENERATED_TERRAFORM_DIRS=()

for wanted_account_name in "${ACCOUNT_NAMES[@]}"; do
  matched_account_id=""
  matched_account_name=""
  matched_account_email=""

  while IFS=$'\t' read -r account_name account_id account_email; do
    if [[ "$account_name" == "$wanted_account_name" ]]; then
      matched_account_name="$account_name"
      matched_account_id="$account_id"
      matched_account_email="$account_email"
      break
    fi
  done < <(list_accounts_table)

  if [[ -z "$matched_account_id" ]]; then
    echo "ERROR: Account '$wanted_account_name' is not assigned to the current SSO session."
    FAILED_ACCOUNTS+=("$wanted_account_name")
    continue
  fi

  selected_role_name="$(resolve_role_name "$matched_account_id")"
  if [[ -z "$selected_role_name" ]]; then
    echo "ERROR: Could not resolve an SSO role for '$matched_account_name' (${matched_account_id})."
    FAILED_ACCOUNTS+=("$matched_account_name")
    continue
  fi

  role_credentials="$(sso_cli get-role-credentials --account-id "$matched_account_id" --role-name "$selected_role_name" --query 'roleCredentials.[accessKeyId,secretAccessKey,sessionToken]' --output text 2>/dev/null || true)"
  if [[ -z "$role_credentials" ]]; then
    echo "ERROR: Could not retrieve credentials for '$matched_account_name' (${matched_account_id})."
    FAILED_ACCOUNTS+=("$matched_account_name")
    continue
  fi

  IFS=$'\t' read -r access_key_id secret_access_key session_token <<< "$role_credentials"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "AWS Account: ${matched_account_name} (${matched_account_id})"
  echo "Account Email: ${matched_account_email}"
  echo "SSO Role: ${selected_role_name}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if ensure_bucket_baseline "$access_key_id" "$secret_access_key" "$session_token" "$matched_account_id" "$matched_account_name"; then
    sanitized_name="$(sanitize_dirname "$matched_account_name")"
    CREATED_BUCKETS+=("terraform-${sanitized_name}-${matched_account_id}")
    generate_terraform_files "$matched_account_name" "$matched_account_id"
    GENERATED_TERRAFORM_DIRS+=("${TERRAFORM_OUTPUT_DIR}/${sanitized_name}")
  else
    FAILED_ACCOUNTS+=("$matched_account_name")
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Provisioning Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total accounts processed: ${#ACCOUNT_NAMES[@]}"

if [[ ${#CREATED_BUCKETS[@]} -gt 0 ]]; then
  echo "Buckets ready:"
  for bucket in "${CREATED_BUCKETS[@]}"; do
    echo "  - $bucket"
  done
fi

if [[ ${#GENERATED_TERRAFORM_DIRS[@]} -gt 0 ]]; then
  echo "Terraform configs generated:"
  for dir in "${GENERATED_TERRAFORM_DIRS[@]}"; do
    echo "  - ${dir}/{backend.tf,versions.tf,providers.tf}"
  done
fi

if [[ ${#FAILED_ACCOUNTS[@]} -eq 0 ]]; then
  echo "Status: All target accounts processed successfully ✓"
  exit 0
else
  echo "Status: ${#FAILED_ACCOUNTS[@]} account(s) failed:"
  for account_name in "${FAILED_ACCOUNTS[@]}"; do
    echo "  ✗ $account_name"
  done
  exit 1
fi
