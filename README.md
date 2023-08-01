## Monitor connection from Ubiquiti Router via SNMP

This script was designed to monitor the status of my Internet connection from my home automation system. This script was designed because in Germany, most DSL connections have a mandatory disconnection every 24 hours ("Zwangstrennung") to force IP address changes, supposedly for privacy reasons. This interruption lasts a few minutes, but is particularly annoying when it occurs in the middle of the day, preferably during an important videoconference.That's why I wanted to have the following information available: last disconnection, download and upload data volume and interface status.

I'm using a Vigor 166 modem on a VDSL2 line, connected to a Ubiquiti UniFi Security Gateway (USG3) router. The Vigor 166 acts as a pure modem (it takes care of synchronizing the DSL line), and the connection is initiated by the router via PPPoE.

### Dealing with changing OID

Most home automation systems are capable of reading SNMP information out-of-the-box, as long as you know which OIDs you need to read. The difficulty is that, in its SNMP implementation, Ubiquiti assigns an interface number that changes every time the interface is disconnected and reconnected, so the OID to be read changes at least every day in my case because of the disconnection every 24h. 

For example, all OIDs starting with 1.3.6.1.2.1.2.2.1.2 (interface descriptor according to RFC 1213), the DSL connection WAN interface has index number 25 and is steadily increasing at least every day.

```
iso.3.6.1.2.1.2.2.1.2.1 = STRING: "lo"
iso.3.6.1.2.1.2.2.1.2.2 = STRING: "eth0"  
[...]
iso.3.6.1.2.1.2.2.1.2.25 = STRING: "pppoe2"
```

Once you know the index number, you can obtain information on the interface. For my script I use following OID :
| OID                    | Label RFC 1213           | Description               |
| ---------------------- | ------------------------ | ------------------------- |
| 1.3.6.1.2.1.2.2.1.2.x  | ifDescr                  | Description               |
| 1.3.6.1.2.1.2.2.1.8.x  | ifOperStatus             | Operational state of interface (1 = up, 2 = down) |
| 1.3.6.1.2.1.2.2.1.10.x  | ifInOctets             | Total number of octets received on the interface |
| 1.3.6.1.2.1.2.2.1.10.x  | ifOutOctets             | Total number of octets sent on the interface |

Important to know about the number of bytes:
- The number of bytes is coded on a U32 and therefore returns to zero above ~4.2 GB. 
- The counters reset to zero (as they change OID) each time they are disconnected.

To obtain statistics for a given day or period of time, you need a cumulative counter that supports resetting the underlying partial counter to zero. Most home automation systems are able to do this, so I haven't implemented it in the script.

### Requirements
- An MQTT server in operation (with a valid user name and password)
- snmp (snmp executables among which snmpwalk and snmpget)
- jo (command-line processor to output JSON from a shell)
- mosquitto_clients (Command line tools to send and receive data form MQTT server)
- SNMP must be enabled on the router (see below)

### Activate SNMP in Ubiquiti Unifi
SNMP is not enabled by default. To do this, connect to the Unifi administration interface : Settings > System and toggle Advanced submenu. Check "SNMP Version 3", note and ( if desired change ) the user/password pair proposed by the system then confirm to provision the router. The script has been written to use SNMP version 3 with user/password protection.

### Completing data in the script
```
# SNMP parameters
snmp_ip= <USG3 IP>
snmp_user= <SNMP Username>
snmp_passphrase= <SNMP password>
snmp_polling_time=30

# MQTT parameters
mqtt_ip= <MQTT server IP>
mqtt_user=<MQTT user>
mqtt_passphrase=<MQTT password>
mqtt_topic_prefix=<MQTT topic prefix>
```
**Important**: Since the script contains passwords in clear text, protect the script adequately by limiting read permissions to the user who will be executing it.

### Function description
The script works quite simply. The detection of the disconnection and its time is carried out by reading the current interface index. If the index has changed between two read cycles, the date and time are recorded in the form of a timestamp.
The script works quite simply. The detection of the disconnection and its time is carried out by reading the current interface index. If the index has increased between two reading cycles, the date and time are recorded in the form of a timestamp. This is done using messages retained on the MQTT server.

- At start-up, the interface index is set to 0 to force an initial update.
- The interface index is detected by searching for the OID that contains the string "pppoe" in all the OIDs describing interface 1.3.6.1.2.1.2.2.1.2.X (X is the value searched for) and extracted using grep and sed.
- The interface index detected is compared with the last value available on the MQTT server. If a change has been detected, the index and timestamp are updated.
- The script uses the Jo data processor to create a JSON containing the state of the interface, the volume of download and upload data and is broadcast on the MQTT server. Jo is used to avoid making successive connections and sending all the information at once
- The cycle resumes after a waiting period: thirty seconds seems to be a good compromise, but it is entirely possible to adjust the value in the script.
- 
### Results
From the data, any home automation application that supports MQTT (and therefore most of them) can retrieve the information needed for milking and/or display it on a dashboard.

For example, here with Home Assistant :
