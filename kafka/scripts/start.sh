#!/bin/bash

final_config="$1"
export KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID:-4L6g3nShT-eMCtK--X86sw}
storage_args=("--cluster-id" "$KAFKA_CLUSTER_ID" "--config" "$final_config" "--ignore-formatted")

echo "Formatting storage"
kafka-storage.sh format "${storage_args[@]}"
echo "Starting Kafka Server"
exec kafka-server-start.sh "$final_config"
