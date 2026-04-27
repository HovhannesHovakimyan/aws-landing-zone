#!/bin/bash
set -euo pipefail

# Bootstraps GitHub Actions OIDC in specified AWS accounts.
# Creates:
# 1) IAM OIDC identity provider for token.actions.githubusercontent.com
# 2) IAM role GitHubAction-Terraform-Role trusted by this repository
# 3) AdministratorAccess attachment to the role
#
# Scope:
#   This script is intended for AWS Landing Zone / AWS Organizations style
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
# Input format:
#   Comma-separated AWS account names passed through flags.
#
# Supported combinations:
#   1) --include "ACCOUNT_NAME_1,ACCOUNT_NAME_2,..."
#   2) --all
#   3) --all --exclude "ACCOUNT_NAME_X,..."
#
# Invalid combinations:
#   1) --include with --exclude
#   2) --all with --include
#
# Usage:
#   ./bootstrap-github-oidc.sh --include "ACCOUNT_NAME_1,ACCOUNT_NAME_2,..." --sso-session SESSION_NAME
#   ./bootstrap-github-oidc.sh --all --sso-session SESSION_NAME
#   ./bootstrap-github-oidc.sh --all --exclude "ACCOUNT_NAME_X,..." --sso-session SESSION_NAME
#
# Examples:
#   ./bootstrap-github-oidc.sh --include "hhmycompany, CloudTrail administrator" --sso-session my-sso-session
#   ./bootstrap-github-oidc.sh --all --sso-session my-sso-session
#   ./bootstrap-github-oidc.sh --all --exclude "Aggregator account" --sso-session my-sso-session
#
# Optional env vars:
#   GITHUB_REPO       GitHub repository URL or owner/repo for trust policy.
#                     Example: https://github.com/org/repo or org/repo
#   SSO_ROLE_NAME      SSO role to request in each account.
#                      Default: AWSAdministratorAccess
#   SSO_USE_DEVICE_CODE Use device-code login flow for aws sso login.
#                      Default: true

ROLE_NAME="GitHubAction-Terraform-Role"
REPO_INPUT="${GITHUB_REPO:-}"
REPO=""
OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_HOST="token.actions.githubusercontent.com"
OIDC_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
SSO_SESSION_NAME=""
SSO_ROLE_NAME="${SSO_ROLE_NAME:-AWSAdministratorAccess}"
SSO_USE_DEVICE_CODE="${SSO_USE_DEVICE_CODE:-true}"
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
  echo "Usage: $0 --include \"ACCOUNT_NAME_1,ACCOUNT_NAME_2,...\" --sso-session NAME [--repo-url URL]"
  echo "       $0 --all [--exclude \"ACCOUNT_NAME_X,...\"] --sso-session NAME [--repo-url URL]"
  echo ""
  echo "Scope:"
  echo "  Intended for AWS Landing Zone / AWS Organizations environments using AWS SSO sessions."
  echo "  Standalone AWS accounts may require a different authentication/bootstrap flow."
  echo ""
  echo "Flags:"
  echo "  --include, -i     Comma-separated AWS account names to bootstrap."
  echo "  --all, -a         Bootstrap all accounts assigned to the current SSO session."
  echo "  --exclude, -x     Optional. Comma-separated AWS account names to skip when using --all."
  echo "  --sso-session, -s Required. SSO session name to use or create."
  echo "  --repo-url, -r    Optional. GitHub repository URL or owner/repo for trust policy."
  echo "  --use-device-code Use AWS CLI device-code login flow (recommended)."
  echo "  --auth-code-flow  Use AWS CLI auth-code login flow (browser localhost callback)."
  echo "  --no-browser      Pass --no-browser to aws sso login."
  echo "  --help, -h        Show this help message."
  echo ""
  echo "Rules:"
  echo "  --include cannot be used with --exclude."
  echo "  --all cannot be used with --include."
  echo ""
  echo "Authentication behavior:"
  echo "  If the session exists and has a valid cache, the script continues non-interactively."
  echo "  Otherwise the script starts interactive first-time setup/login for that session."
}

normalize_repo_identifier() {
  local input="$1"
  input="$(trim "$input")"

  if [[ -z "$input" ]]; then
    return 1
  fi

  # Accept https://github.com/owner/repo(.git), git@github.com:owner/repo(.git), or owner/repo.
  if [[ "$input" =~ ^https://github\.com/([^/]+)/(.+)(\.git)?/?$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.*}"
    return 0
  fi

  if [[ "$input" =~ ^git@github\.com:([^/]+)/(.+)(\.git)?$ ]]; then
    printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.*}"
    return 0
  fi

  if [[ "$input" =~ ^[^/]+/[^/]+$ ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  return 1
}

ensure_repo_identifier() {
  if [[ -z "$REPO_INPUT" ]]; then
    read -r -p "GitHub repository URL (or owner/repo): " REPO_INPUT
  fi

  if ! REPO="$(normalize_repo_identifier "$REPO_INPUT")"; then
    echo "ERROR: Invalid GitHub repository value '$REPO_INPUT'."
    echo "Use https://github.com/<owner>/<repo> or <owner>/<repo>."
    return 1
  fi
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

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
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

INCLUDE_CSV=""
EXCLUDE_CSV=""
USE_ALL="false"
SSO_NO_BROWSER="false"

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
    --repo-url|-r)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --repo-url requires a value."
        usage
        exit 1
      fi
      REPO_INPUT="$1"
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
  exit 1
fi

if ! ensure_repo_identifier; then
  exit 1
fi

if ! ensure_sso_session_authenticated; then
  exit 1
fi

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
  echo "ERROR: No accounts left to bootstrap after applying --exclude."
  exit 1
fi

echo "AWS Accounts to bootstrap:"
for account_name in "${ACCOUNT_NAMES[@]}"; do
  echo "  - $account_name"
done

if [[ ${#EXCLUDE_NAMES[@]:-0} -gt 0 ]]; then
  echo "Excluded accounts:"
  for account_name in "${EXCLUDE_NAMES[@]}"; do
    echo "  - $account_name"
  done
fi
echo ""

bootstrap_account() {
  local wanted_account_name="$1"
  local matched_account_id=""
  local matched_account_name=""
  local matched_account_email=""
  local account_name account_id account_email

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
    return 1
  fi

  local selected_role_name
  selected_role_name="$(resolve_role_name "$matched_account_id")"
  if [[ -z "$selected_role_name" ]]; then
    echo "ERROR: Could not resolve an SSO role for '$matched_account_name' (${matched_account_id})."
    echo "Requested role: ${SSO_ROLE_NAME}"
    return 1
  fi

  local role_credentials
  role_credentials="$(sso_cli get-role-credentials --account-id "$matched_account_id" --role-name "$selected_role_name" --query 'roleCredentials.[accessKeyId,secretAccessKey,sessionToken]' --output text 2>/dev/null || true)"
  if [[ -z "$role_credentials" ]]; then
    echo "ERROR: Could not retrieve SSO role credentials for '$matched_account_name' (${matched_account_id}) using role '$selected_role_name'."
    return 1
  fi

  local access_key_id secret_access_key session_token
  IFS=$'\t' read -r access_key_id secret_access_key session_token <<< "$role_credentials"

  local current_account_id
  current_account_id="$(target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  if [[ -z "$current_account_id" ]]; then
    echo "ERROR: Unable to access account '$matched_account_name' with retrieved SSO credentials."
    return 1
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Input Name: ${wanted_account_name}"
  echo "AWS Account: ${matched_account_name} (${current_account_id})"
  echo "Account Email: ${matched_account_email}"
  echo "SSO Role: ${selected_role_name}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local oidc_provider_arn
  oidc_provider_arn="arn:aws:iam::${current_account_id}:oidc-provider/${OIDC_HOST}"

  if target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam get-open-id-connect-provider --open-id-connect-provider-arn "$oidc_provider_arn" >/dev/null 2>&1; then
    echo "OIDC provider already exists: ${oidc_provider_arn}"
  else
    echo "Creating OIDC provider: ${OIDC_URL}"
    target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam create-open-id-connect-provider \
      --url "$OIDC_URL" \
      --client-id-list "sts.amazonaws.com" \
      --thumbprint-list "$OIDC_THUMBPRINT" >/dev/null
    echo "OIDC provider created: ${oidc_provider_arn}"
  fi

  echo "Applying tags to OIDC provider..."
  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam tag-open-id-connect-provider \
    --open-id-connect-provider-arn "$oidc_provider_arn" \
    --tags "${TAG_ARGS[@]}" >/dev/null

  local trust_doc_file
  trust_doc_file="$(mktemp)"
  cat > "$trust_doc_file" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_HOST}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_HOST}:sub": "repo:${REPO}:*"
        }
      }
    }
  ]
}
JSON

  if target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    echo "Role already exists: ${ROLE_NAME}"
  else
    echo "Creating role: ${ROLE_NAME}"
    target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "file://${trust_doc_file}" \
      --tags "${TAG_ARGS[@]}" >/dev/null
    echo "Role created: ${ROLE_NAME}"
  fi

  echo "Applying tags to role..."
  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam tag-role \
    --role-name "$ROLE_NAME" \
    --tags "${TAG_ARGS[@]}" >/dev/null

  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "file://${trust_doc_file}" >/dev/null

  echo "Ensuring AdministratorAccess is attached..."
  target_aws_cli "$access_key_id" "$secret_access_key" "$session_token" iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" >/dev/null

  rm -f "$trust_doc_file"

  local role_arn
  role_arn="arn:aws:iam::${current_account_id}:role/${ROLE_NAME}"
  echo "Bootstrap complete for ${matched_account_name} (${current_account_id})"
  echo "Role ARN: ${role_arn}"
  echo ""
}

echo "Bootstrapping GitHub Actions OIDC role..."
echo ""

FAILED_ACCOUNTS=()
for account_name in "${ACCOUNT_NAMES[@]}"; do
  if ! bootstrap_account "$account_name"; then
    FAILED_ACCOUNTS+=("$account_name")
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Bootstrap Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total accounts processed: ${#ACCOUNT_NAMES[@]}"

if [[ ${#FAILED_ACCOUNTS[@]} -eq 0 ]]; then
  echo "Status: All accounts bootstrapped successfully ✓"
  exit 0
else
  echo "Status: ${#FAILED_ACCOUNTS[@]} account(s) failed:"
  for account_name in "${FAILED_ACCOUNTS[@]}"; do
    echo "  ✗ $account_name"
  done
  exit 1
fi
