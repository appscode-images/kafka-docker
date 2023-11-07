#!/bin/bash

# Set the directory where the Kafka Connect configuration files are located
connect_config_dir="/opt/kafka/config"
connect_standalone_config="/opt/kafka/config/connect-standalone.properties"
connect_distributed_config="/opt/kafka/config/connect-distributed.properties"

# Set the directory where the Kafka Connect Default configuration files are located 
# Created by Kafka Connect Operator
default_connect_config_dir="/opt/kafka/config/connect-default-config"
default_connect_standalone_config="/opt/kafka/config/connect-default-config/connect-standalone.properties"
default_connect_distributed_config="/opt/kafka/config/connect-default-config/connect-distributed.properties"

# Set the directory where the Kafka Connect Custom configuration files are located 
# Created by User using Kubernetes Secret (Connect .spec.configSecret)
custom_connect_config_dir="/opt/kafka/config/connect-custom-config"
custom_connect_standalone_config="/opt/kafka/config/connect-custom-config/connect-standalone.properties"
custom_connect_distributed_config="/opt/kafka/config/connect-custom-config/connect-distributed.properties"

# Merge the Custom and Default Kafka Connect configuration files where the Custom configuration file takes precedence
if [[ $KAFKA_CONNECT_MODE = "standalone" ]]; then
  /opt/kafka/scripts/merge_custom_config.sh $custom_connect_standalone_config $default_connect_standalone_config $connect_config_dir/connect-standalone.properties.merged
else [[ $KAFKA_CONNECT_MODE = "distributed" ]]
  /opt/kafka/scripts/merge_custom_config.sh $custom_connect_distributed_config $default_connect_distributed_config $connect_config_dir/connect-distributed.properties.merged
fi


# This function reads a configuration file and updates the values of the properties in another file.
# If the property already exists in the file, it updates the value. If it is commented out, it uncomments it and updates the value.
# If the property does not exist in the file, it adds the property and its value to the end of the file.
# Parameters:
# $1 - The path to the configuration file to read from.
# $2 - The path to the file to update the properties in.
# Returns: None
function update_configuration() {

    readarray config_array < "$1"

    for config in "${config_array[@]}"; do

        config_property=`echo $config | cut -d = -f1`
        config_value=`echo $config | cut -d = -f2-`

        if grep "^$config_property=" "$2"; then
            sed -i "s|^$config_property=.*|$config_property=$config_value|g" "$2"
        elif grep "^#$config_property=" "$2"; then
            sed -i "s|^#$config_property=.*|$config_property=$config_value|g" "$2"
        else
            echo "$config_property=$config_value" >> "$2"
        fi
    done

}


# This script starts Kafka Connect in either standalone or distributed mode based on the value of KAFKA_CONNECT_MODE environment variable.
# If KAFKA_CONNECT_MODE is set to "standalone", 
# - It updates the configuration with the values from $default_connect_standalone_config and $connect_standalone_config variables
# - Starts Kafka Connect in standalone mode using connect-standalone.sh script.
# If KAFKA_CONNECT_MODE is set to "distributed",
# - It updates the configuration with the values from $default_connect_distributed_config and $connect_distributed_config variables
# - Starts Kafka Connect in distributed mode using connect-distributed.sh script.
if [[ $KAFKA_CONNECT_MODE = "standalone" ]]; then

    update_configuration $default_connect_standalone_config $connect_standalone_config

    echo "Starting Kafka Connect in Standalone mode"
    exec connect-standalone.sh $connect_standalone_config
else [[ $KAFKA_CONNECT_MODE = "distributed" ]]

    update_configuration $default_connect_distributed_config $connect_distributed_config

    echo "Starting Kafka Connect in Distributed mode"
    exec connect-distributed.sh $connect_distributed_config
fi