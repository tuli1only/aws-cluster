#!/usr/bin/env bash
# Friendly wrapper around Terraform.   Usage:  ./scripts/tf.sh <a|b> <command>
#   commands: check | init | fmt | validate | plan | apply | destroy | output
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "Usage: $0 <a|b> <check|init|fmt|validate|plan|apply|destroy|output>"; exit 1; }
[[ $# -eq 2 ]] || usage

case "$1" in
  a) NAME="unit-a-black" ;;
  b) NAME="unit-b-red" ;;
  *) usage ;;
esac
CMD="$2"
ENV_DIR="environments/${NAME}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING: $1 (see README step 1)"; return 1; }; }

show_account() {
  echo "AWS identity you are logged in as:"
  aws sts get-caller-identity --output table
  echo "Environment selected: ${NAME}"
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
    if [[ $ok -eq 0 ]]; then echo "All tools found."; terraform version | head -1; aws --version; show_account; fi
    exit $ok ;;
  init)     terraform -chdir="$ENV_DIR" init ;;
  fmt)      terraform fmt -recursive ;;
  validate) terraform -chdir="$ENV_DIR" validate ;;
  plan)     confirm; terraform -chdir="$ENV_DIR" plan ;;
  apply)    confirm; terraform -chdir="$ENV_DIR" apply ;;
  destroy)  confirm; terraform -chdir="$ENV_DIR" destroy ;;
  output)   terraform -chdir="$ENV_DIR" output ;;
  *) usage ;;
esac
