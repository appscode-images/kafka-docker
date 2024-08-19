#!/bin/bash

# Regular expression to match any line that contains only whitespace characters
WHITESPACE_REGEX='^[[:space:]]*$'
# Regular expression to match any line that starts with a comment character
COMMENT_LINE_REGEX="[#*]"
# Regular expression to match any line that contains a key-value pair
HAS_VALUE_REGEX="[*=*]"
# This script merges two configuration files into a single output file.
# The first file is considered the master file and the second file is the slave file.
# The output is written to the specified output file.
master_file="$1"
slave_file="$2"
output_file="$3"

#ignore the following properties while merging
forbidden_configs=("process.roles" "node.id" "controller.quorum.voters" "advertised.listeners")
# preserve the following properties while merging for listener, and listener.security.protocol.map
reserved_protocol=("broker" "controller" "local")
# Ensure files exist before attempting to merge
# Exit if $master_file doesn't exist
# Exit if $slave_file doesn't exist
# Delete the previous output file if exists
if [ ! -e "$master_file" ] ; then
    exit
elif [ ! -e "$slave_file" ] ; then
    echo "Unable to merge custom configuration property files: $slave_file doesn't exist"
    exit
else [ -e "$output_file" ]
    rm -rf "$output_file"
fi
echo "Merging configs"

# Read property files into arrays
readarray master_file_a < "$master_file"
readarray slave_file_a < "$slave_file"
# This script declares an associative array named "all_properties".
declare -A all_properties

# Preserve the all slave valid configuration properties
for slave_file_line in "${slave_file_a[@]}"; do
    slave_property_name=$(echo "$slave_file_line" | cut -d = -f1 | tr -d '[:space:]')
    # If it contains whitespace or comment, the loop continues to the next iteration.
    if [[ "$slave_property_name" =~ $WHITESPACE_REGEX || "$slave_property_name" =~ $COMMENT_LINE_REGEX ]]; then
      continue
    fi
    # Only attempt to get the property value if it exists
    if [[ "$slave_file_line" =~ $HAS_VALUE_REGEX ]]; then
      slave_property_value=$(echo "$slave_file_line" | cut -d = -f2-)
      all_properties["$slave_property_name"]="$slave_property_value"
    fi
done
# The script loops through each line of the master file and extracts the property name and value.
# Ignore forbidden_configs if master contains them
# Replace the slave property value with master property value if it exists except 'listeners', and 'listener.security.protocol.map'
# We will preserve the slave properties for 'listeners', and 'listener.security.protocol.map' and merge with master properties if new protocol is exist
for master_file_line in "${master_file_a[@]}"; do
    # This line of code extracts the property name from a line in a file and removes any whitespace characters.
    master_property_name=$(echo "$master_file_line" | cut -d = -f1 | tr -d '[:space:]')
    # If it contains whitespace or comment, the loop continues to the next iteration.
    if [[ "$master_property_name" =~ $WHITESPACE_REGEX || "$master_property_name" =~ $COMMENT_LINE_REGEX ]]; then
        continue
    fi
    if printf "%s\n" "${forbidden_configs[@]}" | grep -Fxq "$master_property_name"; then
        continue
    fi
    # Only attempt to get the property value if it exists
    if [[ "$master_file_line" =~ $HAS_VALUE_REGEX ]]; then
        master_property_value=$(echo "$master_file_line" | cut -d = -f2-)
    else
        master_property_value=''
    fi
    if [[ "$master_property_name" == "listeners" || "$master_property_name" == "listener.security.protocol.map" ]]; then
      IFS=','
      for element in $master_property_value; do
          IFS=':'
          read -r  property _ <<< "$(echo "$element" | tr '[:upper:]' '[:lower:]')"
          if ! printf "%s\n" "${reserved_protocol[@]}" | grep -Fxq "$property"; then
              all_properties["$master_property_name"]="${all_properties["$master_property_name"]},${element}"
          fi
      done
    elif [[ "$master_property_name" =~ ^[^=]+\.advertised\.listeners$ ]]; then
      IFS=',' read -r -a adv_listener <<< "$master_property_value"
      id="${HOSTNAME##*-}"
      length="${#adv_listener[@]}"
      if [ "$length" -le "$id" ]; then
        echo "WARN: $master_property_name is not set for broker id = $id, continuing without setting it"
        continue
      fi
      all_properties["advertised.listeners"]="${all_properties["advertised.listeners"]},${adv_listener[${id}]}"
    else
      all_properties["$master_property_name"]="$master_property_value"
    fi
done

for key in "${!all_properties[@]}"; do
    echo "$key=${all_properties[$key]}" >> "$output_file"
done
# move merged file to slave file
mv "$output_file" "$slave_file"
echo "Merged custom config or env with default config"
