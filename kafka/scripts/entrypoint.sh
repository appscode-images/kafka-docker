#!/bin/bash

# Final Configuration Path, kafka start will use this configuration
final_config="/opt/kafka/config/server.properties"
# KubeDB operator empty directory
kafka_config_dir="/opt/kafka/config/kafkaconfig"
operator_config="/opt/kafka/config/kafkaconfig/config.properties"
# KubeDB operator configuration files
temp_operator_config="/opt/kafka/config/temp-config/config.properties"
temp_ssl_config="/opt/kafka/config/temp-config/ssl.properties"
temp_clientauth_config="/opt/kafka/config/temp-config/clientauth.properties"
# Kafka KRaft configuration files
controller_config="/opt/kafka/config/kraft/controller.properties"
broker_config="/opt/kafka/config/kraft/broker.properties"
server_config="/opt/kafka/config/kraft/server.properties"
# KubeDB Custom configuration files
server_custom_config="/opt/kafka/config/custom-config/server.properties"
broker_custom_config="/opt/kafka/config/custom-config/broker.properties"
controller_custom_config="/opt/kafka/config/custom-config/controller.properties"
custom_log4j_config="/opt/kafka/config/custom-config/log4j.properties"
custom_tools_log4j_config="/opt/kafka/config/custom-config/tools-log4j.properties"
# Utility variables
kafka_broker_max_id=1000

# For debug purpose
print_bootstrap_config() {
  echo "--------------- Bootstrap configurations ------------------"
  cat $1
  echo "------------------------------------------------------------"
}
# This function deletes the meta.properties for a given node ID and the metadata log directory.
# It creates log direcory and metadata log directory if they do not exist.
# Arguments:
#   NODE_ID: ID of the node whose metadata is to be deleted
# Returns:
#   None
delete_cluster_metadata() {

  NODE_ID=$1
  # Create or update the log directory for specific node
  modified_log_dirs=()
  echo "Enter for metadata deleting node $NODE_ID"
  IFS=','
  for log_dir in $log_dirs; do
    if [[ ! -d "$log_dir/$NODE_ID" ]]; then
      mkdir -p "$log_dir/$NODE_ID"
      echo "Created kafka data directory at $log_dir/$NODE_ID"
    else [ -e "$log_dir/$NODE_ID/meta.properties" ]
      echo "Deleting old metadata..."
      rm -rf "$log_dir/$NODE_ID/meta.properties"
    fi
    modified_log_dirs+=("$log_dir/$NODE_ID")
  done
  log_dirs=$(IFS=','; echo "${modified_log_dirs[*]}")
  echo "Modified log_dirs: $log_dirs"
  # Create or update the metadata log directory
  if [[ ! -d "$metadata_log_dir" ]]; then
    mkdir -p $metadata_log_dir
    echo "Created kafka metadata directory at $metadata_log_dir"
  else [ -e "$metadata_log_dir/meta.properties" ]
     rm -rf "$metadata_log_dir/meta.properties"
  fi
  # Delete previously configured controller.quorum.voters file
  if [ -e "$metadata_log_dir/__cluster_metadata-0/quorum-state" ] ; then
     rm -rf "$metadata_log_dir/__cluster_metadata-0/quorum-state"
  fi
  # Add or replace cluster_id to metadata_log_dir/cluster_id
  echo "$KAFKA_CLUSTER_ID" > "$metadata_log_dir/cluster_id"
}

# Function to update the advertised listeners by modifying BROKER:// listeners adding the hostname prefix
update_advertised_listeners() {
  # Use tr to replace commas with newlines and read into an array
  readarray -t elements < <(echo "$advertised_listeners" | tr ',' '\n')
  # Prefix to append to each element
  prefix=$HOSTNAME
  # Loop through the array and modify elements
  modified_elements=()
  for element in "${elements[@]}"; do
        # Check if the element starts with the excluded prefix
        if [[ "$element" == "BROKER://"* ]]; then
          modified_elements+=("${element/\/\//\/\/$prefix.}")
        else
          modified_elements+=("$element")  # Skip modification
        fi
  done
  # Join the modified elements into a string using commas as delimiters
  output_string=$(IFS=','; echo "${modified_elements[*]}")
  advertised_listeners=$output_string
  # Print the modified string
  echo "Modified advertised_listeners: $advertised_listeners"
}
# This script copies the temporary operator configuration file to the operator configuration file
cp $temp_operator_config $operator_config
# If a temporary SSL configuration file exists, it concatenates the contents of the temporary SSL configuration file to operator configuration file.
if [[ -f $temp_ssl_config ]]; then
  cat $temp_ssl_config $operator_config > config.properties.updated
  mv config.properties.updated $operator_config
  cp $temp_ssl_config /opt/kafka/config
fi
# and merges the custom configuration files based on the process roles specified in the operator configuration file.
# The merged configuration file is saved in the Kafka configuration directory and move the file to operator configuration.
roles=$(grep process.roles $operator_config | cut -d'=' -f 2-)
if [[ $roles = "controller" ]]; then
  /opt/kafka/config/merge_custom_config.sh $controller_custom_config $operator_config $kafka_config_dir/config.properties.merged
elif [[ $roles = "broker" ]]; then
  /opt/kafka/config/merge_custom_config.sh $broker_custom_config $operator_config $kafka_config_dir/config.properties.merged
else [[ $roles = "controller,broker" ]]
  /opt/kafka/config/merge_custom_config.sh $server_custom_config $operator_config $kafka_config_dir/config.properties.merged
fi

# If a file named $temp_clientauth_config exists, it copies the file to /opt/kafka/config directory.
if [[ -f $temp_clientauth_config ]]; then
  cp $temp_clientauth_config /opt/kafka/config
fi

# If KAFKA_PASSWORD is not empty,
# replace the placeholders <KAFKA_USER> and <KAFKA_PASSWORD> in clientauth.properties and operator_config files
if [[ $KAFKA_PASSWORD != "" ]]; then
  CLIENTAUTHFILE="/opt/kafka/config/clientauth.properties"
  sed -i "s/\<KAFKA_USER\>/"$KAFKA_USER"/g" $CLIENTAUTHFILE
  sed -i "s/\<KAFKA_PASSWORD\>/"$KAFKA_PASSWORD"/g" $CLIENTAUTHFILE
  
  sed -i "s/KAFKA_USER\>/"$KAFKA_USER"/g" $operator_config
  sed -i "s/\<KAFKA_PASSWORD\>/"$KAFKA_PASSWORD"/g" $operator_config
fi

# Reads operator configuration file line by line and sets the values of the keys as environment variables.
# The keys in the configuration file are separated from their values by an equal sign (=).
# The script replaces dots (.) in the keys with underscores (_) to make them valid environment variable names.
while IFS='=' read -r key value
do
    key=$(echo "$key" | sed -e 's/\./_/g' -e 's/-/___/g')
    eval ${key}=\${value}
done < "$operator_config"

# Set the value of KAFKA_CLUSTER_ID and ID
export KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID:-$cluster_id}
ID=${HOSTNAME##*-}

if [[ -n $advertised_listeners ]]; then
  old_advertised_listeners=$advertised_listeners
  update_advertised_listeners
  # Print the modified string
  echo "Updating advertised_listeners to: $advertised_listeners"
  # Use sed to replace the line containing "advertised.listeners" with the updated one
  sed -i "s|$old_advertised_listeners|$advertised_listeners|" "$operator_config"
fi

# Removes comments and empty lines from a file.
# Arguments -> A properties file
function remove_comments_and_sort() {
  sed -i '/^#/d;/^$/d' "$1"
  sort -o "$1" "$1"
}

# It starts the Kafka server with the specified configuration.
# For three different process_roles(broker, controller and combined),
# it deletes the cluster metadata,
# sets the node ID, updates the log directories,
# and formats the storage using kafka-storage script before starting the Kafka server.
old_log_dirs="$log_dirs"
if [[ "$process_roles" = "controller" ]]; then
  ID=$(( ID + kafka_broker_max_id ))
  delete_cluster_metadata $ID
  echo "node.id=$ID" >> "$operator_config"
  sed -i "s|"^log.dirs=$old_log_dirs"|"log.dirs=$log_dirs"|" "$operator_config"
  cat $operator_config $controller_config | awk -F= '!seen[$1]++' > "$controller_config.updated"
  mv "$controller_config.updated" "$final_config"
elif [[ "$process_roles" = "broker" ]]; then
  delete_cluster_metadata $ID
  echo "node.id=$ID" >> "$operator_config"
  sed -i "s|"^log.dirs=$old_log_dirs"|"log.dirs=$log_dirs"|" "$operator_config"
  cat "$operator_config" "$broker_config" | awk -F'=' '!seen[$1]++' > "$broker_config.updated"
  mv "$broker_config.updated" "$final_config"
else [[ "$process_roles" = "controller,broker" ]]
  delete_cluster_metadata "$ID"
  echo "node.id=$ID" >> "$operator_config"
  sed -i "s|"^log.dirs=$old_log_dirs"|"log.dirs=$log_dirs"|" "$operator_config"
  cat "$operator_config" "$server_config" | awk -F'=' '!seen[$1]++' > "$server_config.updated"
  mv "$server_config.updated" "$final_config"
fi

remove_comments_and_sort "$final_config"

# Keeping this for backward compatibility
if grep -Eqi '^sasl\.enabled\.mechanisms=.*plain.*' "$final_config"; then
  AUTHFILE="/opt/kafka/config/kafka_server_jaas.conf"
  sed -i "s/KAFKA_USER\>/"$KAFKA_USER"/g" $AUTHFILE
  sed -i "s/\<KAFKA_PASSWORD\>/"$KAFKA_PASSWORD"/g" $AUTHFILE
  export KAFKA_OPTS="$KAFKA_OPTS -Djava.security.auth.login.config=$AUTHFILE"
fi
# If user has provided custom log4j configuration, it will be used
if [[ -f "$custom_log4j_config" ]]; then
  cp "$custom_log4j_config" /opt/kafka/config
fi
# If user has provided custom tools-log4j configuration, it will be used
if [[ -f "$custom_tools_log4j_config" ]]; then
  cp "$custom_tools_log4j_config" /opt/kafka/config
fi

/opt/kafka/config/launch.sh "$final_config"