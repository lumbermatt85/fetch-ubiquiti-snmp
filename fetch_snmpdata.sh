#!/bin/bash

# SNMP parameters (fill here)
snmp_ip=
snmp_user=
snmp_passphrase=
snmp_polling_time=

# MQTT parameters (fill here)
mqtt_ip=
mqtt_user=
mqtt_passphrase=
mqtt_topic_prefix=

# Initiate snmp_index with 0 with a retained message for the script startup
mosquitto_pub -r -h $mqtt_ip -u $mqtt_user -P $mqtt_passphrase -t $mqtt_topic_prefix/ifIndex -m 0

# Start loop
while true
do
  # Find actual interface index in the SNMP tree for the WAN
  snmp_index=$(snmpwalk -v3 -l authPriv -a SHA -A $snmp_passphrase -u $snmp_user -x AES -X $snmp_passphrase $snmp_ip 1.3.6.1.2.1.2.2.1.2 | grep -m1 pppoe | sed -e "s/.*[0-9.]*\.\([0-9]*\).*/\1/")

  # Check if interface index has changed sine last poling
  if [ $snmp_index -ne $(mosquitto_sub -C 1 -h $mqtt_ip -u $mqtt_user -P $mqtt_passphrase -t $mqtt_topic_prefix/ifIndex) ]
  then
     # Publish the new interface Index as retained message
     mosquitto_pub -r -h $mqtt_ip -u $mqtt_user -P $mqtt_passphrase -t $mqtt_topic_prefix/ifIndex -m $snmp_index

     # Update timestamp
     mosquitto_pub -r -h $mqtt_ip -u $mqtt_user -P $mqtt_passphrase -t $mqtt_topic_prefix/ifReconnectTimestamp -m $(date +"%Y-%m-%dT%H:%M:%S%:z")
  fi

  # Fetch statut, input, output from the SNMP tree, assemble them to a json (frequentavoid multiple connections) and send it to the MQTT ifInfo topic
   mosquitto_pub -r -h $mqtt_ip -u $mqtt_user -P $mqtt_passphrase -t $mqtt_topic_prefix/ifInfo -m \
     $(jo \
       ifOperStatus=$(snmpget -Oqv -v3 -l authPriv -a SHA -A $snmp_passphrase -u $snmp_user -x AES -X $snmp_passphrase $snmp_ip 1.3.6.1.2.1.2.2.1.8.$snmp_index) \
       ifInOctets=$(snmpget -Oqv -v3 -l authPriv -a SHA -A $snmp_passphrase -u $snmp_user -x AES -X $snmp_passphrase $snmp_ip 1.3.6.1.2.1.2.2.1.10.$snmp_index)  \
       ifOutOctets=$(snmpget -Oqv -v3 -l authPriv -a SHA -A $snmp_passphrase -u $snmp_user -x AES -X $snmp_passphrase $snmp_ip 1.3.6.1.2.1.2.2.1.16.$snmp_index) )

  # Go sleep and wait
  sleep $snmp_polling_time

done
