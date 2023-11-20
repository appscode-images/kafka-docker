#!/bin/bash

# Set the directory where the Kafka Connect configuration files are located
connect_config_dir="/opt/kafka/config"
connect_standalone_config="/opt/kafka/config/connect-standalone.properties"
connect_distributed_config="/opt/kafka/config/connect-distributed.properties"
# Set the directory where the Kafka Connect Default configuration files are located 
# Created by Kafka Connect Operator
default_connect_config_dir="/opt/kafka/config/connect-default-config"
default_connect_config="/opt/kafka/config/connect-default-config/config.properties"
# Set the directory where the Kafka Connect Custom configuration files are located 
# Created by User using Kubernetes Secret (Connect .spec.configSecret)
custom_connect_config_dir="/opt/kafka/config/connect-custom-config"
custom_connect_config="/opt/kafka/config/connect-custom-config/config.properties"
# Merge the Custom and Default Kafka Connect configuration files where the Custom configuration file takes precedence
if [[ $KAFKA_CONNECT_MODE = "standalone" ]]; then
  /opt/kafka/scripts/merge_custom_config.sh $custom_connect_config $default_connect_config $connect_config_dir/connect-standalone.properties.merged
else [[ $KAFKA_CONNECT_MODE = "distributed" ]]
  /opt/kafka/scripts/merge_custom_config.sh $custom_connect_config $default_connect_config $connect_config_dir/connect-distributed.properties.merged
fi
# This function reads a configuration file and updates the values of the properties in another file.
# If the property already exists in the file, it updates the value. If it is commented out, it uncomments it and updates the value.
# If the property does not exist in the file, it adds the property and its value to the end of the file.
# If the property is rest.advertised.host.name, it appends the hostname to the value as prefix.
# Parameters:
# $1 - The path to the configuration file to read from.
# $2 - The path to the file to update the properties in.
# Returns: None
function update_configuration() {
    readarray config_array < "$1"
    for config in "${config_array[@]}"; do
        # It uses the cut command to split the string at the "=" character and assign the property to the "config_property" variable
        # and the value to the "config_value" variable.
        config_property=`echo $config | cut -d = -f1`
        config_value=`echo $config | cut -d = -f2-`
        # This code block checks if the config_property is "rest.advertised.host.name".
        # If it is, it appends the hostname to the value as prefix.
        # It adds to communicate with the members of the Kafka Connect cluster(distributed).
        if [[ $config_property = "rest.advertised.host.name" ]]; then
            config_value=$HOSTNAME.$config_value
        fi
        # This code block checks if a given configuration property exists in a file. If it does, it replaces the value with a new one. 
        # If it doesn't, it adds the property and its value to the file.
        if grep "^$config_property=" "$2"; then
            sed -i "s|^$config_property=.*|$config_property=$config_value|g" "$2"
        elif grep "^#$config_property=" "$2"; then
            sed -i "s|^#$config_property=.*|$config_property=$config_value|g" "$2"
        else
            echo "$config_property=$config_value" >> "$2"
        fi
    done
}
# Removes comments and empty lines from a file.
# Sorts the file in alphabetical order.
# Arguments -> A properties file
function remove_comments_and_sort() {
  sed -i '/^#/d;/^$/d' $1
  sort -o $1 $1
}
# This script starts Kafka Connect in either standalone or distributed mode based on the value of KAFKA_CONNECT_MODE environment variable.
# For both modes, it does the following:
# - It updates the configuration with the values from default configuration and mode-specific configuration files.
# - It sorts and removes comments from the configuration file
# - Starts Kafka Connect using the updated configuration file with mode-specific script(ex. connect-standalone.sh, connect-distributed.sh)
if [[ $KAFKA_CONNECT_MODE = "standalone" ]]; then
    update_configuration $default_connect_config $connect_standalone_config
    remove_comments_and_sort $connect_standalone_config
    echo "Starting Kafka Connect in Standalone mode"
    exec connect-standalone.sh $connect_standalone_config
else [[ $KAFKA_CONNECT_MODE = "distributed" ]]
    update_configuration $default_connect_config $connect_distributed_config
    remove_comments_and_sort $connect_distributed_config
    echo "Starting Kafka Connect in Distributed mode"
    exec connect-distributed.sh $connect_distributed_config
fi