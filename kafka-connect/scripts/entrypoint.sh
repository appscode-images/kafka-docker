#!/bin/bash

# Set the directory where the Kafka Connect configuration files are located
connect_config_dir="/opt/kafka/config"
connect_standalone_config="/opt/kafka/config/connect-standalone.properties"
connect_distributed_config="/opt/kafka/config/connect-distributed.properties"
# Set the directory where the Kafka Connect Operator configuration files are located 
# Created by Kafka Connect Operator
operator_connect_config_dir="/opt/kafka/config/connect-operator-config"
operator_connect_config="/opt/kafka/config/connect-operator-config/config.properties"
# Set the directory where the Kafka Connect Custom configuration files are located 
# Created by User using Kubernetes Secret (Connect .spec.configSecret)
custom_connect_config_dir="/opt/kafka/config/connect-custom-config"
custom_connect_config="/opt/kafka/config/connect-custom-config/config.properties"
# Set kafka connect temporary configuration file
temp_operator_connect_config="/opt/kafka/config/temp-operator-config.properties"
temp_custom_connect_config="/opt/kafka/config/temp-custom-config.properties"


#-----------------------------------------------Functions--------------------------------------------------------------------#

# Removes comments and empty lines from a file.
# Sorts the file in alphabetical order.
# Arguments -> A properties file
function remove_comments_and_sort() {
  sed -i '/^#/d;/^$/d' $1
  sort -o $1 $1
}
# This function updates the value of 'rest.advertised.host.name' in a given file.
# It appends the hostname to the value of 'rest.advertised.host.name' property.
# Parameters:
#   - $1: The path of the file to be updated.
function update_advertised_host_name() {
    value=$(echo "$(grep "^rest.advertised.host.name=" "$1")" | cut -d'=' -f2-)
    new_value="${HOSTNAME}.$value"
    sed -i "s|^rest.advertised.host.name=.*|rest.advertised.host.name=$new_value|" "$1"
}


#-----------------------------------------------Kafka Connect Basic Authentication--------------------------------------------------------------------#

# Check if KAFKA_CONNECT_USER and KAFKA_CONNECT_PASSWORD have values
# If both variables are set, it creates a file named connect-credentials.properties in the /var/private/basic-auth directory
# and writes the value of KAFKA_CONNECT_USER as the key and KAFKA_CONNECT_PASSWORD as the value in the file.
# It also sets the KAFKA_OPTS environment variable to include the path to the kafka_connect_jaas.conf file.
# This file is used for Java authentication and is located in the /opt/kafka/config directory.
if [[ -n "$KAFKA_CONNECT_USER" && -n "$KAFKA_CONNECT_PASSWORD" ]]; then
    echo "$KAFKA_CONNECT_USER=$KAFKA_CONNECT_PASSWORD" > /var/private/basic-auth/connect-credentials.properties
    export KAFKA_OPTS="-Djava.security.auth.login.config=/opt/kafka/config/kafka_connect_jaas.conf"
fi

#-----------------------------------------------Mode Based Configuration and Run Kafka Connect Server-------------------------------------------------#


# Copy the operator and custom configuration file to a temporary file
if [ -e $operator_connect_config ] ; then
    cp $operator_connect_config $temp_operator_connect_config
fi
if [ -e $custom_connect_config ] ; then
    cp $custom_connect_config $temp_custom_connect_config
fi

# This script starts Kafka Connect in either standalone or distributed mode based on the value of KAFKA_CONNECT_MODE environment variable.
# For both modes, it does the following:
# - For distributed mode, it updates the value of 'rest.advertised.host.name' in the temporary configuration file(user can override it with custom configuration).
# - It merges the default configuration file with the custom configuration file if custom configuration exist.
# - It merges the mode-specific connect configuration with the values from (operator + custom configuration)
# - It sorts and removes comments from the configuration file
# - Starts Kafka Connect using the updated configuration file with mode-specific script(ex. connect-standalone.sh, connect-distributed.sh)
if [[ $KAFKA_CONNECT_MODE = "standalone" ]]; then
    /opt/kafka/scripts/merge_config_properties.sh $temp_custom_connect_config $temp_operator_connect_config $connect_config_dir/connect-standalone.properties.merged
    /opt/kafka/scripts/merge_config_properties.sh $temp_operator_connect_config $connect_standalone_config $connect_config_dir/connect-standalone.properties.merged
    remove_comments_and_sort $connect_standalone_config
    
    echo "Starting Kafka Connect in Standalone mode"
    exec connect-standalone.sh $connect_standalone_config
else [[ $KAFKA_CONNECT_MODE = "distributed" ]]
    update_advertised_host_name $temp_operator_connect_config
    /opt/kafka/scripts/merge_config_properties.sh  $temp_custom_connect_config $temp_operator_connect_config $connect_config_dir/connect-distributed.properties.merged
    /opt/kafka/scripts/merge_config_properties.sh  $temp_operator_connect_config $connect_distributed_config $connect_config_dir/connect-distributed.properties.merged
    remove_comments_and_sort $connect_distributed_config
    
    echo "Starting Kafka Connect in Distributed mode"
    exec connect-distributed.sh $connect_distributed_config
fi