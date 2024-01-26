#!/bin/bash

# The following is a reference.
# https://zenn.dev/smartround_dev/articles/5e20fa7223f0fd

set -euo pipefail

function usage() {
  cat <<EOF
Usage: [TF_SKIP_INIT=boolean ] $0 [-help] <env> <command> [args]
  env          : environment [stg/prd/...]
  command      : terraform command [plan/apply/state/...]
  args         : subcommand [e.g. state "mv"] and terraform command options (see : terraform <command> -help)
  TF_SKIP_INIT : skip "terraform init"
EOF
}

if [ "$1" = '-h' ] || [ "$1" = '-help' ] ; then
  usage
  exit 0
fi

if [ $# -lt 2 ] ; then
  echo -e "[ERROR] Invalid parameters\n"
  usage
  exit 128
fi

TF_ENV=$1
TF_COMMAND=$2
TF_ARGS=${@:3}

if [ "${TF_SKIP_INIT-false}" = true ] ; then
  echo "[INFO] Skip init..."
else
  if [ "${TF_COMMAND}" = 'init' ] ; then
    # shellcheck disable=SC2086
    terraform init \
      -backend-config="${TF_ENV}.tfbackend" \
      -reconfigure \
      ${TF_ARGS} # When ./terraform.sh <env> init [args] is executed, [args] are interpreted as being specified for init, and expanded here
    exit 0 # Exit here when ./terraform.sh <env> init is executed
  else
    terraform init \
      -backend-config="${TF_ENV}.tfbackend" \
      -reconfigure # To hide the prompt: Do you want to copy existing state to the new backend?
  fi
fi

case $TF_COMMAND in
  apply | console | destroy | import | plan | refresh)
    # shellcheck disable=SC2086
    # Using "${TF_ARGS}" is recommended but it throws an error when multiple arguments are specified so we remove the double quotes
    terraform "${TF_COMMAND}" -var-file="${TF_ENV}.tfvars" ${TF_ARGS};;
  *)
    # shellcheck disable=SC2086
    terraform "${TF_COMMAND}" ${TF_ARGS};;
esac