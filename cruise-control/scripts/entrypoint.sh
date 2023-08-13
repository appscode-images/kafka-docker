#!/bin/bash

set -eo pipefail
set -x

cc_default_config_dir=/opt/cruise-control/config
cc_ui_default_config_dir=/opt/cruise-control/cruise-control-ui/dist/static
cc_temp_config_dir=/opt/cruise-control/temp-config
cc_custom_config_dir=/opt/cruise-control/custom-config

## cruise control default configs
cc_config=$cc_default_config_dir/cruisecontrol.properties
capacity_config=$cc_default_config_dir/capacity.json
cc_ui_config=$cc_ui_default_config_dir/config.csv
brokerSet_config=$cc_default_config_dir/brokerSets.json
cluster_config=$cc_default_config_dir/clusterConfigs.json

## cruise control operator generated configs
cc_temp_config=$cc_temp_config_dir/cruisecontrol.properties
capacity_temp_config=$cc_temp_config_dir/capacity.json
cc_ui_temp_config=$cc_temp_config_dir/config.csv
brokerSet_temp_config=$cc_temp_config_dir/brokerSets.json

## cruise control custom configs
cc_custom_config=$cc_custom_config_dir/cruisecontrol.properties
cc_custom_capacity_config=$cc_custom_config_dir/capacity.json
cc_custom_ui_config=$cc_custom_config_dir/config.csv
cc_custom_brokerSet_config=$cc_custom_config_dir/brokerSets.json
cc_custom_clusterConfig=$cc_custom_config_dir/clusterConfigs.json


## merge the operator generated cruise control config with the default one
if [[ -f $cc_temp_config ]]; then
  $cc_default_config_dir/merge_custom_config.sh $cc_temp_config $cc_config $cc_default_config_dir/cruisecontrol.properties.updated
  cp $cc_default_config_dir/cruisecontrol.properties.updated $cc_config
fi

# Replace the default broker capacity config with operator generated one
if [[ -f $capacity_temp_config ]]; then
  cp $capacity_temp_config $capacity_config
fi

# Replace the default BrokerSets config with operator generated one
if [[ -f $brokerSet_temp_config ]]; then
  cp $brokerSet_temp_config $brokerSet_config
fi

# Replace the default CC UI config csv with operator generated one
if [[ -f $cc_ui_temp_config ]]; then
  cp $cc_ui_temp_config $cc_ui_config
fi

# Remove the default Cluster config json as operator is not generating one
if [[ -f $cluster_config ]]; then
  rm $cluster_config
fi

## merge/replace the operator generated cruise control config with the user provided one
if [[ -f $cc_custom_config ]]; then
  $cc_default_config_dir/merge_custom_config.sh $cc_custom_config $cc_config $cc_default_config_dir/cruisecontrol.properties.updated
  cp $cc_default_config_dir/cruisecontrol.properties.updated $cc_config
fi

# Replace the default broker capacity config with operator generated one
if [[ -f $cc_custom_capacity_config ]]; then
  cp $cc_custom_capacity_config $capacity_config
fi

# Replace the default BrokerSets config with operator generated one
if [[ -f $cc_custom_brokerSet_config ]]; then
  cp $cc_custom_brokerSet_config $brokerSet_config
fi

# Replace the default CC UI config csv with operator generated one
if [[ -f $cc_custom_ui_config ]]; then
  cp $cc_custom_ui_config $cc_ui_config
fi

# Remove the default Cluster config json as operator is not generating one
if [[ -f $cc_custom_clusterConfig ]]; then
  cp $cc_custom_clusterConfig $cluster_config
fi

./kafka-cruise-control-start.sh $cc_config 9090


