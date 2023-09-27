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
kafka_controller_max_id=1000

delete_cluster_metadata() {
  NODE_ID=$1
  echo "Enter for metadata deleting node $NODE_ID"
  if [[ ! -d "$log_dirs/$NODE_ID" ]]; then
    sudo mkdir -p "$log_dirs"/"$NODE_ID"
    echo "Created kafka data directory at "$log_dirs"/$NODE_ID"
  else
    echo "Deleting old metadata..."
    sudo rm -rf $log_dirs/$NODE_ID/meta.properties
  fi
  if [[ ! -d "$metadata_log_dir" ]]; then
    sudo mkdir -p $metadata_log_dir
    echo "Created kafka metadata directory at $metadata_log_dir"
  fi

  # Give log_dirs access for kafka user
  sudo chown -R kafka:kafka "$log_dirs"/"$NODE_ID"
  # Give metadata_log_dirs acces for kafka user
  sudo chown -R kafka:kafka "$metadata_log_dir"

  if [ -e "$metadata_log_dir/meta.properties" ]; then
     sudo rm -rf $metadata_log_dir/meta.properties
  fi
  # Delete previously configured controller.quorum.voters file
  if [ -e "$metadata_log_dir/__cluster_metadata-0/quorum-state" ] ; then
     sudo rm -rf "$metadata_log_dir/__cluster_metadata-0/quorum-state"
  fi
  # Add or replace cluster_id to log_dirs/cluster_id
  sudo sh -c "echo '$CLUSTER_ID' > '$log_dirs'/cluster_id"
  # No required password line remove from -> /etc/sudoers files
  sudo sed -i '$d' /etc/sudoers
}

update_advertised_listeners() {
  # Use tr to replace commas with newlines and read into an array
  readarray -t elements < <(echo "$advertised_listeners" | tr ',' '\n')

  # Prefix to append to each element
  prefix=$HOSTNAME

  # Loop through the array and modify elements
  modified_elements=()
  for element in "${elements[@]}"; do
        # Check if the element starts with the excluded prefix
        if [[ "$element" == "INTERNAL://"* || "$element" == "EXTERNAL://"* ]]; then
            modified_elements+=("$element")  # Skip modification
        else
            modified_elements+=("${element/\/\//\/\/$prefix.}")
        fi
  done

  # Join the modified elements into a string using commas as delimiters
  output_string=$(IFS=','; echo "${modified_elements[*]}")
  advertised_listeners=$output_string

  # Print the modified string
  echo "Modified advertised_listeners: $advertised_listeners"

}


# merge custom config files with default ones
cp $temp_operator_config $operator_config
roles=$(grep process.roles $operator_config | cut -d'=' -f 2-)
if [[ $roles = "controller" ]]; then
  /opt/kafka/config/merge_custom_config.sh $controller_config_file $operator_config $kafkaconfig_dir/config.properties.merged
elif [[ $roles = "broker" ]]; then
  /opt/kafka/config/merge_custom_config.sh $broker_config_file $operator_config $kafkaconfig_dir/config.properties.merged
else [[ $roles = "controller,broker" ]]
  /opt/kafka/config/merge_custom_config.sh $server_config_file $operator_config $kafkaconfig_dir/config.properties.merged
fi

if [[ -f $temp_ssl_config ]]; then
  cat $temp_ssl_config $operator_config > config.properties.updated
  mv config.properties.updated $operator_config
  cp $temp_ssl_config /opt/kafka/config
fi

if [[ -f $temp_clientauth_config ]]; then
  cp $temp_clientauth_config /opt/kafka/config
fi

if [[ $KAFKA_PASSWORD != "" ]]; then
  CLIENTAUTHFILE="/opt/kafka/config/clientauth.properties"
  sed -i "s/\<KAFKA_USER\>/"$KAFKA_USER"/g" $CLIENTAUTHFILE
  sed -i "s/\<KAFKA_PASSWORD\>/"$KAFKA_PASSWORD"/g" $CLIENTAUTHFILE
fi

while IFS='=' read -r key value
do
    key=$(echo $key | tr '.' '_')
    eval ${key}=\${value}
done < "$operator_config"

CLUSTER_ID=${cluster_id}
ID=${HOSTNAME##*-}
NODE=$(echo $HOSTNAME | rev | cut -d- -f1 --complement | rev )
CONTROLLER_NODE_COUNT=${controller_count}

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


if [[ $process_roles = "controller" ]]; then

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

  kafka-storage.sh format -t "$CLUSTER_ID" -c /opt/kafka/config/kraft/controller.properties --ignore-formatted

  echo "Starting Kafka Server"
  exec kafka-server-start.sh /opt/kafka/config/kraft/controller.properties

elif [[ $process_roles = "broker" ]]; then
  ID=$(( ID + kafka_controller_max_id ))
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

  kafka-storage.sh format -t $CLUSTER_ID -c $server_config --ignore-formatted
  echo "Starting Kafka Server"
  exec kafka-server-start.sh $server_config
fi
