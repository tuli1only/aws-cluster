#!/usr/bin/env bash
# Friendly wrapper around Terraform.  Usage:  ./scripts/tf.sh <a|b> <command>
#   commands: check | init | fmt | validate | plan | apply | destroy
# Each unit gets its own state file in ./state/ (keep these safe, see README).
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "Usage: $0 <a|b> <check|init|fmt|validate|plan|apply|destroy>"; exit 1; }
[[ $# -eq 2 ]] || usage

case "$1" in
  a) NAME="unit-a-black" ;;
  b) NAME="unit-b-red" ;;
  *) usage ;;
esac
CMD="$2"
VARS="environments/${NAME}.tfvars"
STATE="state/${NAME}.tfstate"
mkdir -p state

need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING: $1 (see README step 1)"; return 1; }; }

show_account() {
  echo "AWS identity you are logged in as:"
  aws sts get-caller-identity --output table
  echo "Unit selected: ${NAME}"
}

confirm() {
  show_account
  read -r -p "Is this the RIGHT AWS account for ${NAME}? Type yes to continue: " ans
  [[ "$ans" == "yes" ]] || { echo "Cancelled."; exit 1; }
}

case "$CMD" in
  check)
    ok=0
    need terraform || ok=1
    need aws       || ok=1
    need kubectl   || ok=1
    [[ $ok -eq 0 ]] && { echo "All tools found."; terraform version | head -1; aws --version; show_account; }
    exit $ok ;;
  init)     terraform init ;;
  fmt)      terraform fmt ;;
  validate) terraform validate ;;
  plan)     confirm; terraform plan    -var-file="$VARS" -state="$STATE" ;;
  apply)    confirm; terraform apply   -var-file="$VARS" -state="$STATE" ;;
  destroy)  confirm; terraform destroy -var-file="$VARS" -state="$STATE" ;;
  *) usage ;;
esac
