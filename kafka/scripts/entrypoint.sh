#!/bin/bash

kafkaconfig_dir="/opt/kafka/config/kafkaconfig"
operator_config="/opt/kafka/config/kafkaconfig/config.properties"
ssl_config="/opt/kafka/config/kafkaconfig/ssl.properties"
temp_operator_config="/opt/kafka/config/temp-config/config.properties"
temp_ssl_config="/opt/kafka/config/temp-config/ssl.properties"
temp_clientauth_config="/opt/kafka/config/temp-config/clientauth.properties"
controller_config="/opt/kafka/config/kraft/controller.properties"
broker_config="/opt/kafka/config/kraft/broker.properties"
server_config="/opt/kafka/config/kraft/server.properties"
server_config_file="/opt/kafka/config/custom-config/server.properties"
broker_config_file="/opt/kafka/config/custom-config/broker.properties"
controller_config_file="/opt/kafka/config/custom-config/controller.properties"
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
  echo "Enter for metadata deleting node $NODE_ID"
  if [[ ! -d "$log_dirs/$NODE_ID" ]]; then
    mkdir -p "$log_dirs/$NODE_ID"
    echo "Created kafka data directory at "$log_dirs"/$NODE_ID"
  else [ -e "$log_dirs/$NODE_ID/meta.properties" ]
    echo "Deleting old metadata..."
    rm -rf "$log_dirs/$NODE_ID/meta.properties"
  fi

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
  # Add or replace cluster_id to log_dirs/cluster_id
  echo $CLUSTER_ID > "$log_dirs/cluster_id"
}

# Function to update the advertised listeners by modifying BROKER:// and CC:// listeners adding the hostname prefix
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
# and merges the custom configuration files based on the process roles specified in the operator configuration file. 
# The merged configuration file is saved in the Kafka configuration directory and move the file to operator configuration.
cp $temp_operator_config $operator_config
roles=$(grep process.roles $operator_config | cut -d'=' -f 2-)
if [[ $roles = "controller" ]]; then
  /opt/kafka/config/merge_custom_config.sh $controller_config_file $operator_config $kafkaconfig_dir/config.properties.merged
elif [[ $roles = "broker" ]]; then
  /opt/kafka/config/merge_custom_config.sh $broker_config_file $operator_config $kafkaconfig_dir/config.properties.merged
else [[ $roles = "controller,broker" ]]
  /opt/kafka/config/merge_custom_config.sh $server_config_file $operator_config $kafkaconfig_dir/config.properties.merged
fi

# If a temporary SSL configuration file exists, it concatenates the contents of the temporary SSL configuration file to operator configuration file.
if [[ -f $temp_ssl_config ]]; then
  cat $temp_ssl_config $operator_config > config.properties.updated
  mv config.properties.updated $operator_config
  cp $temp_ssl_config /opt/kafka/config
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
  
  sed -i "s/\<KAFKA_USER\>/"$KAFKA_USER"/g" $operator_config
  sed -i "s/\<KAFKA_PASSWORD\>/"$KAFKA_PASSWORD"/g" $operator_config
fi

# Reads operator configuration file line by line and sets the values of the keys as environment variables.
# The keys in the configuration file are separated from their values by an equal sign (=).
# The script replaces dots (.) in the keys with underscores (_) to make them valid environment variable names.
while IFS='=' read -r key value
do
    key=$(echo $key | tr '.' '_')
    eval ${key}=\${value}
done < "$operator_config"

# Set the value of CLUSTER_ID, ID and NODE environment variables.
CLUSTER_ID=${cluster_id}
ID=${HOSTNAME##*-}
NODE=$(echo $HOSTNAME | rev | cut -d- -f1 --complement | rev )

AUTHFILE="/opt/kafka/config/kafka_server_jaas.conf"
sed -i "s/\<KAFKA_USER\>/"$KAFKA_USER"/g" $AUTHFILE
sed -i "s/\<KAFKA_PASSWORD\>/"$KAFKA_PASSWORD"/g" $AUTHFILE
export KAFKA_OPTS="$KAFKA_OPTS -Djava.security.auth.login.config=$AUTHFILE"

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
  sed -i '/^#/d;/^$/d' $1
  sort -o $1 $1
}

# It starts the Kafka server with the specified configuration.
# For three different process_roles(broker, controller and combined),
# it deletes the cluster metadata,
# sets the node ID, updates the log directories,
# and formats the storage using kafka-storage script before starting the Kafka server.
if [[ $process_roles = "controller" ]]; then
  ID=$(( ID + kafka_broker_max_id ))
  delete_cluster_metadata $ID

  echo "node.id=$ID" >> /opt/kafka/config/kafkaconfig/config.properties

  sed -e "s+^log.dirs=.*+log.dirs=$log_dirs/$ID+" \
  /opt/kafka/config/kafkaconfig/config.properties > config.properties.updated
  mv config.properties.updated /opt/kafka/config/kafkaconfig/config.properties

  cat /opt/kafka/config/kafkaconfig/config.properties /opt/kafka/config/kraft/controller.properties | awk -F= '!seen[$1]++' > controller.properties.updated
  mv controller.properties.updated /opt/kafka/config/kraft/controller.properties

  if [[ -f "$ssl_config" ]]; then
      cat $ssl_config $controller_config | awk -F'=' '!seen[$1]++' > controller.properties.updated
      mv controller.properties.updated $controller_config
  fi

  remove_comments_and_sort $controller_config

  echo "Formatting controller properties"
  kafka-storage.sh format -t "$CLUSTER_ID" -c /opt/kafka/config/kraft/controller.properties --ignore-formatted
  echo "Starting Kafka Server"
  exec kafka-server-start.sh /opt/kafka/config/kraft/controller.properties

elif [[ $process_roles = "broker" ]]; then

  delete_cluster_metadata $ID

  echo "node.id=$ID" >> $operator_config

  sed -e "s+^log.dirs=.*+log.dirs=$log_dirs/$ID+" \
  $operator_config > $operator_config.updated
  mv $operator_config.updated $operator_config

  cat $operator_config $broker_config | awk -F'=' '!seen[$1]++' > $broker_config.updated
  mv $broker_config.updated $broker_config

  if [[ -f "$ssl_config" ]]; then
      cat $ssl_config $broker_config | awk -F'=' '!seen[$1]++' > $broker_config.updated
      mv $broker_config.updated $broker_config
  fi

  remove_comments_and_sort $broker_config

  echo "Formatting broker properties"
  kafka-storage.sh format -t $CLUSTER_ID -c $broker_config --ignore-formatted
  echo "Starting Kafka Server"
  exec kafka-server-start.sh $broker_config

else [[ $process_roles = "controller,broker" ]]

  delete_cluster_metadata $ID

  echo "node.id=$ID" >> $operator_config
  sed -e "s+^log.dirs=.*+log.dirs=$log_dirs/$ID+" \
  $operator_config > $operator_config.updated
  mv $operator_config.updated $operator_config

  cat $operator_config $server_config | awk -F'=' '!seen[$1]++' > $server_config.updated
  mv $server_config.updated $server_config

  if [[ -f "$ssl_config" ]]; then
      cat $ssl_config $server_config | awk -F'=' '!seen[$1]++' > $server_config.updated
      mv $server_config.updated $server_config
  fi

  remove_comments_and_sort $server_config

  echo "Formatting server properties"
  kafka-storage.sh format -t $CLUSTER_ID -c $server_config --ignore-formatted
  echo "Starting Kafka Server"
  exec kafka-server-start.sh $server_config
fi
