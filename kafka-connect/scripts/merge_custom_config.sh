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
master_file=$1
slave_file=$2
output_file=$3

# Ensure files exist before attempting to merge
# Exit if $master_file doesn't exist
# Exit if $slave_file doesn't exist
# Delete the previous output file if exists
if [ ! -e $master_file ] ; then
    exit
elif [ ! -e $slave_file ] ; then
    echo 'Unable to merge custom configuration property files: $slave_file doesn''t exist'
    exit
else [ -e $output_file ]
    rm -rf "$output_file"
fi



echo "Merging custom config with default config"

# The contents of the master_file are read into the master_file_a array and
# The contents of the slave_file are read into the slave_file_a array.
readarray master_file_a < "$master_file"
readarray slave_file_a < "$slave_file"

# This script declares an associative array named "all_properties".
declare -A all_properties

# The script loops through each line of the master file and extracts the property name and value.
# If the property name contains whitespace or is a comment line, it is skipped.
# If the property has a value, it is added to an associative array with the property name as the key.
# All the master file property names and values will be preserved
for master_file_line in "${master_file_a[@]}"; do

    master_property_name=`echo $master_file_line | cut -d = -f1 | tr -d '[:space:]'`
    # If it contains whitespace or comment, the loop continues to the next iteration.
    if [[ $master_property_name =~ $WHITESPACE_REGEX || $master_property_name =~ COMMENT_LINE_REGEX ]]; then
        continue
    fi

    # Only attempt to get the property value if it exists
    if [[ $master_file_line =~ $HAS_VALUE_REGEX ]]; then
        master_property_value=`echo $master_file_line | cut -d = -f2-`
        all_properties[$master_property_name]=$master_property_value
    fi

done


# This loop iterates over each line of the slave_file_a array and extracts the property name and value from each line.
# If the property name is not already available in the master file, then it uses the slave property value.
# The loop skips any lines that contain whitespace or are commented out.
# The loop also skips any lines that do not have a value.
for slave_file_line in "${slave_file_a[@]}"; do

    slave_property_name=`echo $slave_file_line | cut -d = -f1 | tr -d '[:space:]'`
    # If it contains whitespace or comment, the loop continues to the next iteration.
    if [[ $slave_property_name =~ $WHITESPACE_REGEX || $slave_property_name =~ $COMMENT_LINE_REGEX ]]; then
        continue
    fi

    # Only attempt to get the property value if it exists
    if [[ $slave_file_line =~ $HAS_VALUE_REGEX ]]; then
        slave_property_value=`echo $slave_file_line | cut -d = -f2-`
    else
        continue
    fi

    # If the slave property name is not already set in the all_properties array, then set it to the slave property value.
    if [ ! ${all_properties[$slave_property_name]+_ } ]; then
       all_properties[$slave_property_name]=$slave_property_value
    fi

done



# This loop iterates over all the keys in the associative array 'all_properties' and 
# Appends the key-value pairs to the output file.
for key in "${!all_properties[@]}"; do
    echo "$key=${all_properties[$key]}" >> "$output_file"
done


# It moves the output file to the slave file location.
mv "$output_file" "$slave_file"
echo "Merged custom config with default config"
