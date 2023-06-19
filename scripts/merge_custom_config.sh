#!/bin/bash
master_file=$1
slave_file=$2
output_file=$3
#ignore the following properties while merging
arr=("process.roles" "cluster.id" "node.id" "controller.quorum.voters"
"control.plane.listener.name" "listeners" "advertised.listeners")
# Ensure files exist before attempting to merge
if [ ! -e $slave_file ] ; then
    echo 'Unable to merge custom configuration property files: $slave_file doesn''t exist'
    return
fi
# Delete the previous output file if exists
if [ -e $output_file ] ; then
    rm -rf "$output_file"
fi
echo "Merging custom config with default config"
# Read property files into arrays
readarray master_file_a < "$master_file"
readarray slave_file_a < "$slave_file"
# Regex strings to check for values and
COMMENT_LINE_REGEX="[#*]"
HAS_VALUE_REGEX="[*=*]"
declare -A all_properties
# All the master file property names and values will be preserved
for master_file_line in "${master_file_a[@]}"; do
    master_property_name=`echo $master_file_line | cut -d = -f1`
    if [[ $(echo ${arr[@]} | fgrep -w $master_property_name) ]]; then
        continue
    else
        # Only attempt to get the property value if it exists
        if [[ $master_file_line =~ $HAS_VALUE_REGEX ]]; then
            master_property_value=`echo $master_file_line | cut -d = -f2-`
        else
            master_property_value=''
        fi
        # Ignore the line if it begins with the # symbol as it is a comment
        if ! [[ $master_property_name =~ $COMMENT_LINE_REGEX ]]; then
            all_properties[$master_property_name]=$master_property_value
        fi
    fi
done
# Properties that are in the slave but not the master will be preserved
for slave_file_line in "${slave_file_a[@]}"; do
    slave_property_name=`echo $slave_file_line | cut -d = -f1`
    # Only attempt to get the property value if it exists
    if [[ $slave_file_line =~ $HAS_VALUE_REGEX ]]; then
        slave_property_value=`echo $slave_file_line | cut -d = -f2-`
    else
        slave_property_value=''
    fi
    # If a slave property exists in the master, the master's value will be used preserved
    if [ ! ${all_properties[$slave_property_name]+_ } ]; then
        # If the line begins with a # symbol it is a comment line and should be ignored
        if ! [[ $slave_property_name =~ $COMMENT_LINE_REGEX ]]; then
            all_properties[$slave_property_name]=$slave_property_value
        fi
    fi
done

for key in "${!all_properties[@]}"; do
    echo "$key=${all_properties[$key]}" >> "$output_file"
done
# move merge file to kafkaconfig directory
mv "$output_file" "$slave_file"
echo "Merged custom config with default config"