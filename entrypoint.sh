#!/bin/bash

operator_config="/opt/kafka/config/kafkaconfig/config.properties"
ssl_config="/opt/kafka/config/kafkaconfig/ssl.properties"
temp_operator_config="/opt/kafka/config/temp-config/config.properties"
temp_ssl_config="/opt/kafka/config/temp-config/ssl.properties"
temp_clientauth_config="/opt/kafka/config/temp-config/clientauth.properties"
controller_config="/opt/kafka/config/kraft/controller.properties"
broker_config="/opt/kafka/config/kraft/broker.properties"
server_config="/opt/kafka/config/kraft/server.properties"
custom_config_dir="/opt/kafka/config/custom-config"

merge_custom_config() {

    # Merge the custom config with the default config
    echo "Merging custom config with default config"

    MASTER_FILE="/opt/kafka/config/custom-config/config.properties"
    SLAVE_FILE=$operator_config
    OUTPUT_FILE="/opt/kafka/config/kafkaconfig/config.properties.merged"

    if [[ ! -d "$custom_config_dir" ]]; then
      echo "No custom configuration found"
      return
    fi
    #ignore the following properties while merging
    arr=("process.roles", "cluster.id", "node.id", "controller.quorum.voters",
    "control.plane.listener.name", "listeners", "advertised.listeners")
    # Delete the output file if exists
    if [ -e $OUTPUT_FILE ] ; then
        rm -rf "$OUTPUT_FILE"
    fi
    # Ensure files exist before attempting to merge
    if [ ! -e $MASTER_FILE ] ; then
        echo 'Unable to merge property files: MASTER_FILE doesn''t exist'
        return
    fi
    if [ ! -e $SLAVE_FILE ] ; then
        echo 'Unable to merge property files: SLAVE_FILE doesn''t exist'
        return
    fi
    # Read property files into arrays
    readarray MASTER_FILE_A < "$MASTER_FILE"
    readarray SLAVE_FILE_A < "$SLAVE_FILE"
    # Regex strings to check for values and
    COMMENT_LINE_REGEX="[#*]"
    HAS_VALUE_REGEX="[*=*]"
    declare -A ALL_PROPERTIES
    # All the master file property names and values will be preserved
    for MASTER_FILE_LINE in "${MASTER_FILE_A[@]}"; do
        MASTER_PROPERTY_NAME=`echo $MASTER_FILE_LINE | cut -d = -f1`
        if [[ $(echo ${arr[@]} | fgrep -w $MASTER_PROPERTY_NAME) ]]; then
            continue
        else
            # Only attempt to get the property value if it exists
            if [[ $MASTER_FILE_LINE =~ $HAS_VALUE_REGEX ]]; then
                MASTER_PROPERTY_VALUE=`echo $MASTER_FILE_LINE | cut -d = -f2-`
            else
                MASTER_PROPERTY_VALUE=''
            fi
            # Ignore the line if it begins with the # symbol as it is a comment
            if ! [[ $MASTER_PROPERTY_NAME =~ $COMMENT_LINE_REGEX ]]; then
                ALL_PROPERTIES[$MASTER_PROPERTY_NAME]=$MASTER_PROPERTY_VALUE
            fi
        fi
    done
    # Properties that are in the slave but not the master will be preserved
    for SLAVE_FILE_LINE in "${SLAVE_FILE_A[@]}"; do
        SLAVE_PROPERTY_NAME=`echo $SLAVE_FILE_LINE | cut -d = -f1`
        # Only attempt to get the property value if it exists
        if [[ $SLAVE_FILE_LINE =~ $HAS_VALUE_REGEX ]]; then
            SLAVE_PROPERTY_VALUE=`echo $SLAVE_FILE_LINE | cut -d = -f2-`
        else
            SLAVE_PROPERTY_VALUE=''
        fi
        # If a slave property exists in the master, the master's value will be used preserved
        if [ ! ${ALL_PROPERTIES[$SLAVE_PROPERTY_NAME]+_ } ]; then
            # If the line begins with a # symbol it is a comment line and should be ignored
            if ! [[ $SLAVE_PROPERTY_NAME =~ $COMMENT_LINE_REGEX ]]; then
                ALL_PROPERTIES[$SLAVE_PROPERTY_NAME]=$SLAVE_PROPERTY_VALUE
            fi
        fi
    done

    for KEY in "${!ALL_PROPERTIES[@]}"; do
        echo "$KEY=${ALL_PROPERTIES[$KEY]}" >> "$OUTPUT_FILE"
    done
    # move merge file to kafkaconfig directory
    mv "$OUTPUT_FILE" "$operator_config"

    echo "Merged custom config with default config"
}



cp $temp_operator_config $operator_config
merge_custom_config

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

delete_cluster_metadata() {
  NODE_ID=$1
  echo "Enter for metadata deleting node $NODE_ID"
  if [[ ! -d "$log_dirs/$NODE_ID" ]]; then
    mkdir -p "$log_dirs"/"$NODE_ID"
    echo "Created kafka data directory at "$log_dirs"/$NODE_ID"
  else
    echo "Deleting old metadata..."
    rm -rf $log_dirs/$NODE_ID/meta.properties
  fi

  if [[ -d "$metadata_log_dir/__cluster_metadata-0" ]]; then
     rm -rf $metadata_log_dir/meta.properties
  fi

  if [[ ! -f "$log_dirs/cluster_id" ]]; then
      echo "$CLUSTER_ID" > "$log_dirs"/cluster_id
  else
      CLUSTER_ID=$(cat "$log_dirs"/cluster_id)
  fi

}

AUTHFILE="/opt/kafka/config/kafka_server_jaas.conf"
sed -i "s/\<KAFKA_USER\>/"$KAFKA_USER"/g" $AUTHFILE
sed -i "s/\<KAFKA_PASSWORD\>/"$KAFKA_PASSWORD"/g" $AUTHFILE
export KAFKA_OPTS="$KAFKA_OPTS -Djava.security.auth.login.config=$AUTHFILE"

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
  ID=$(( ID + CONTROLLER_NODE_COUNT ))
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