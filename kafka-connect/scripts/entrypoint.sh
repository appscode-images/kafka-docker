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
# Set kafka connect temporary configuration file
temp_config_file="/opt/kafka/config/temp.properties"

# Function: merge_config
# Description: Merges two configuration property files with the precedence given to the first file.
# Parameters:
#   - master_file: Path to the master configuration file.
#   - slave_file: Path to the slave configuration file.
#   - output_file: Path to the output file where the merged configuration will be stored.
# Move the merged configuration file to the slave file.
function merge_config() {
    master_file=$1
    slave_file=$2
    output_file=$3
    # Ensure files exist before attempting to merge
    # return if $master_file doesn't exist
    # return if $slave_file doesn't exist
    # Delete the previous output file if exists
    if [ ! -e $master_file ] ; then
        return
    elif [ ! -e $slave_file ] ; then
        echo 'Unable to merge custom configuration property files: $slave_file doesn''t exist'
        return
    else [ -e $output_file ]
        rm -rf "$output_file"
    fi

    echo "Merging custom config with default config"
    # This awk command reads two input files, $master_file and $slave_file, and processes the lines in a key-value format.
    # It removes leading and trailing whitespace from the keys and values, and stores unique key-value pairs in an associative array.
    # The resulting key-value pairs are then printed to the $output_file.
    awk -F'=' '
    !/^[[:space:]]*(#|$)/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);
        if (!seen[$1]++) {
        a[$1] = $0;
        }
    }
    END {
        for (key in a) {
            print a[key];
        }
    }
    ' "$master_file" "$slave_file" > "$output_file"

    mv "$output_file" "$slave_file"
}
# Removes comments and empty lines from a file.
# Sorts the file in alphabetical order.
# Arguments -> A properties file
function remove_comments_and_sort() {
  sed -i '/^#/d;/^$/d' $1
  sort -o $1 $1
}
# This function updates the value of 'rest.advertised.host.name' in a given file.
# Parameters:
#   - $1: The path of the file to be updated.
function update_advertised_host_name() {
    value=$(echo "$(grep "^rest.advertised.host.name=" "$1")" | cut -d'=' -f2-)
    new_value="${HOSTNAME}.$value"
    sed -i "s|^rest.advertised.host.name=.*|rest.advertised.host.name=$new_value|" "$1"
}

#-----------------------------------------------Mode Based Configuration and Run Kafka Connect Server-------------------------------------------------#

# Copy the default configuration file to a temporary file
cp $default_connect_config $temp_config_file
# This script starts Kafka Connect in either standalone or distributed mode based on the value of KAFKA_CONNECT_MODE environment variable.
# For both modes, it does the following:
# - For distributed mode, it updates the value of 'rest.advertised.host.name' in the temporary configuration file(user can override it with custom configuration).
# - It merges the default configuration file with the custom configuration file if custom configuration exist.
# - It merges the connect configuration with the values from (operator + custom configuration) and mode-specific configuration files.
# - It sorts and removes comments from the configuration file
# - Starts Kafka Connect using the updated configuration file with mode-specific script(ex. connect-standalone.sh, connect-distributed.sh)
if [[ $KAFKA_CONNECT_MODE = "standalone" ]]; then
    merge_config $custom_connect_config $temp_config_file $connect_config_dir/connect-standalone.properties.merged
    merge_config $temp_config_file $connect_standalone_config $connect_config_dir/connect-standalone.properties.merged
    remove_comments_and_sort $connect_standalone_config
    echo "Starting Kafka Connect in Standalone mode"
    exec connect-standalone.sh $connect_standalone_config
else [[ $KAFKA_CONNECT_MODE = "distributed" ]]
    update_advertised_host_name $temp_config_file
    merge_config $custom_connect_config $temp_config_file $connect_config_dir/connect-distributed.properties.merged
    merge_config $temp_config_file $connect_distributed_config $connect_config_dir/connect-distributed.properties.merged
    remove_comments_and_sort $connect_distributed_config
    echo "Starting Kafka Connect in Distributed mode"
    exec connect-distributed.sh $connect_distributed_config
fi