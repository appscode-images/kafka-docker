#!/bin/bash

cc_config_dir="/opt/cruise-control/config"
cc_config="/opt/cruise-control/config/cruisecontrol.properties"
cc_temp_config="/opt/cruise-control/temp-config/cruisecontrol.properties"
capacity_config="/opt/cruise-control/config/capacity.json"
capacity_temp_config="/opt/cruise-control/temp-config/capacity.json"
cc_ui_config="/opt/cruise-control/cruise-control-ui/dist/static/config.csv"
cc_ui_temp_config="/opt/cruise-control/temp-config/config.csv"
brokerSet_config="/opt/cruise-control/config/brokerSets.json"
brokerSet_temp_config="/opt/cruise-control/temp-config/brokerSets.json"


# merge the operator generated cruise control config with the default one
if [[ -f $cc_temp_config ]]; then
  $cc_config_dir/merge_custom_config.sh $cc_temp_config $cc_config $cc_config_dir/cruisecontrol.properties.updated
  cp $cc_config_dir/cruisecontrol.properties.updated $cc_config
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

rm $cc_config_dir/clusterConfigs.json


if [[ $KAFKA_PASSWORD != "" && $KAFKA_USER != "" ]]; then
   echo "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${KAFKA_USER}' password='${KAFKA_PASSWORD}';" >> $cc_config
fi

./kafka-cruise-control-start.sh $cc_config 9090


