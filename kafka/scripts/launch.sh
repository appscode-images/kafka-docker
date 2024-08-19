#!/bin/bash

final_config="$1"
export KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID:-4L6g3nShT-eMCtK--X86sw}

declare -A scram_sha_256
declare -A scram_sha_512
storage_args=("--cluster-id" "$KAFKA_CLUSTER_ID" "--config" "$final_config" "--ignore-formatted")
sparse_scram_credentials() {
  local -n scram="$1"
  local pat="$2"
  grep -E "$pat" "$final_config" | while IFS= read -r line; do
    username=$(echo "$line" | awk -F 'username=' '{print $2}' | awk -F ' ' '{print $1}' | sed 's/[";]//g')
    password=$(echo "$line" | awk -F 'password=' '{print $2}' | awk -F ' ' '{print $1}' | sed 's/[";]//g')
    scram["$username"]="$password"
  done
}
add_scram_storage_args() {
  local -n scram="$1"
  local algo="$2"
  for username in "${!scram[@]}"; do
      storage_args+=("--add-scram" "$algo=[name=$username,password=${scram[$username]}]")
  done
}
sparse_scram_credentials scram_sha_256 "listener\.[^ ]*\.scram-sha-256\.sasl\.jaas\.config"
add_scram_storage_args scram_sha_256 "SCRAM-SHA-256"
sparse_scram_credentials scram_sha_512 "listener\.[^ ]*\.scram-sha-512\.sasl\.jaas\.config"
add_scram_storage_args scram_sha_512 "SCRAM-SHA-512"

echo "Formatting storage"
kafka-storage.sh format "${storage_args[@]}"

echo "Starting Kafka Server"
exec kafka-server-start.sh "$final_config"