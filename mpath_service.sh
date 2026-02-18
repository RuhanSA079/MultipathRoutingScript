#!/bin/bash

########################################################
#  Networking Multipath routing script by RuhanSA079  ##
########################################################
#               Code license is GPLv3                 ##
########################################################

# Changelog:
# v0.1 -> Initial version
# v0.2 -> Remove routes, as they are automatically added
# v0.3 -> Add route check to remove the "default" route from the default table to specified table.
# v0.4 -> Refine script to check for "default" table detection, re-initiate connection. (Sometimes it happens, or NetworkManager bug that injects the routes into default route table, not custom one.)
# v0.5 -> Add NetworkManager connection mod capability on script start

#-------------------CHANGE THESE-------------------
NETWORKMANAGER_CELLULAR_CONNECTION_NAME="Cellular"
TABLE_ID=200

#--------------DO NOT CHANGE THIS------------------
VERSION="0.5"
TABLE_RULES_INSTALLED=0
SCAN_INTERVAL_SECS=15
CURRENT_IFACE_NAME="wwan0"
CURRENT_IP=""
CURRENT_GW=""
GET_IFACE_NAME=""
GET_IFACE_STATE=""
GET_IFACE_IP=""
GET_IFACE_GW=""
RULE_EXIT_NETWORK=""


if [ "$(id -u)" -ne 0 ];
then
    echo "Please run as root." >&2
    exit 1
fi

function detectNMConfig(){
    connectionModified=0

    echo "Detecting and checking network configuration..."
    cellularUUID=$(nmcli con show | awk '$1=="Cellular" {print $2}')
    if [[ -z $cellularUUID ]];
    then
        echo "Cellular connection ID: $NETWORKMANAGER_CELLULAR_CONNECTION_NAME not found, aborting!"
        exit 1
    else
        echo "Found connection, checking now..."
        cellularRouteTable=$(nmcli con show "$cellularUUID" | awk '$1=="ipv4.route-table:" {print $2}')
        cellularIgnoreAutoRoutes=$(nmcli con show "$cellularUUID" | awk '$1=="ipv4.ignore-auto-routes:" {print $2}')
        cellularIgnoreAutoDNS=$(nmcli con show "$cellularUUID" | awk '$1=="ipv4.ignore-auto-dns:" {print $2}')

        if [[ -z $cellularRouteTable || -z $cellularIgnoreAutoRoutes || -z $cellularIgnoreAutoDNS ]];
        then
            echo "Error, misconfiguration. Aborting!"
            exit 1
        else
            if [[ $cellularRouteTable != "0" ]];
            then
                if [[ $cellularRouteTable != $TABLE_ID ]];
                then
                    echo "Warning: Cellular route table is $cellularRouteTable, must be $TABLE_ID, correcting."
                    nmcli con mod "$cellularUUID" ipv4.route-table $TABLE_ID
                    connectionModified=1
                fi
            else
                echo "Warning: Cellular route table is $cellularRouteTable, configuring as $TABLE_ID"
                nmcli con mod "$cellularUUID" ipv4.route-table $TABLE_ID
                connectionModified=1
            fi

            if [[ $cellularIgnoreAutoRoutes != "no" ]];
            then
                echo "Warning: Cellular ignore-auto-routes table is $cellularIgnoreAutoRoutes, must be 'no', correcting."
                nmcli con mod "$cellularUUID" ipv4.ignore-auto-routes no
                connectionModified=1
            fi

            if [[ $cellularIgnoreAutoDNS != "no" ]];
            then
                echo "Warning: Cellular ignore-auto-dns table is $cellularIgnoreAutoDNS, must be 'no', correcting."
                nmcli con mod "$cellularUUID" ipv4.ignore-auto-dns no
                connectionModified=1
            fi
        fi
    fi

    if [ $connectionModified -eq 1 ];
    then
        echo "Connection modified. Restarting connection..."
        nmcli con down $NETWORKMANAGER_CELLULAR_CONNECTION_NAME
        sleep 5
        nmcli con up $NETWORKMANAGER_CELLULAR_CONNECTION_NAME
    fi
}

function flushRules(){
    echo "Flushing rules..."
    while ip rule delete from 0/0 to 0/0 table $TABLE_ID 2>/dev/null; do true; done
}

function uninstall(){
    flushRules
    TABLE_RULES_INSTALLED=0
}

function detect_quirks() {
    # ensure iface is set
    if [[ -z "$CURRENT_IFACE_NAME" ]]; then
        return
    fi

    # find a default route in the main table that references this device
    route_line=$(ip route show default 2>/dev/null | awk -v dev="$CURRENT_IFACE_NAME" '$0 ~ dev { print; exit }' || true)
    if [[ -z "$route_line" ]]; then
        # no main-table default for this iface
        return
    fi

    echo "Found main-table default for $CURRENT_IFACE_NAME, restarting connection..."
    nmcli con down "$NETWORKMANAGER_CELLULAR_CONNECTION_NAME"
    uninstall
    sleep 5
    nmcli con up "$NETWORKMANAGER_CELLULAR_CONNECTION_NAME"
    getIfaceIP
    getIfaceGWIP
    CURRENT_IP=$GET_IFACE_IP
    CURRENT_GW=$GET_IFACE_GW
    CURRENT_IFACE_NAME=$GET_IFACE_NAME
    sleep 1
    installRules
}

function installRules(){
    derive_to_net_simple
    
    if ! ip rule show | grep -q "from $CURRENT_IP/32 .* lookup $TABLE_ID"; then
        ip rule add from $CURRENT_IP/32 table $TABLE_ID priority 1000 2>/dev/null \
            && echo "Added rule from $CURRENT_IP/32 -> table $TABLE_ID (pref 1000)" \
            || echo "Failed to add from rule"
    else
        echo "From rule already exists"
    fi


    if [[ -n "$RULE_EXIT_NETWORK" ]]; then
        ip rule add to "$RULE_EXIT_NETWORK" table $TABLE_ID priority 900 2>/dev/null \
            && echo "Added rule to $RULE_EXIT_NETWORK -> table $TABLE_ID (pref 900)" \
            || echo "Failed to add to-rule for $RULE_EXIT_NETWORK"
    else
        echo "No RULE_EXIT_NETWORK derived; skipping to-rule"
    fi
}

function derive_to_net_simple() {
    if [[ -z "$CURRENT_IP" ]]; then
        return
    fi

    IFS='.' read -r a b _ <<< "$CURRENT_IP"
    if [[ -z "$a" || -z "$b" ]]; then
        return
    fi
    RULE_EXIT_NETWORK="${a}.${b}.0.0/16"
    #echo $RULE_EXIT_NETWORK
}

function install(){
    echo "Installing new rules..."
    CURRENT_IP=$GET_IFACE_IP
    CURRENT_GW=$GET_IFACE_GW
    CURRENT_IFACE_NAME=$GET_IFACE_NAME
    installRules
    detect_quirks
    TABLE_RULES_INSTALLED=1
}

function getIface(){
    # Get interface name, should be wwan0 or wwx067b8493290a 
    # Try to find wwan/wwx with an IPv4 address
    candidate=$(ip -o -4 addr show | awk -F': ' '/inet/ {print $2" "$0}' | awk '{print $1}' | sort -u | grep -E '^wwan|^wwx' | head -n1 || true)
    if [[ -n "$candidate" ]]; then
        GET_IFACE_NAME="$candidate"
        return
    else
        GET_IFACE_NAME=""
    fi
}

function getIfaceState(){
    if [[ -z "$GET_IFACE_NAME" ]]; then
        GET_IFACE_STATE="down"
        return
    else
        if ip link show dev "$GET_IFACE_NAME" 2>/dev/null | grep -q 'DOWN'; then
            GET_IFACE_STATE="down"
        else
            GET_IFACE_STATE="up"
        fi
    fi
}

function getIfaceIP(){
    if [[ -z "$GET_IFACE_NAME" ]]; then
        GET_IFACE_IP=""
        return
    fi

    # get first IPv4 address (without CIDR)
    cidr=$(ip -o -4 addr show dev "$GET_IFACE_NAME" | awk '{print $4; exit}' || true)
    GET_IFACE_IP=${cidr%%/*}
}

function getIfaceGWIP(){
    if [[ -z "$GET_IFACE_NAME" ]]; then
        GET_IFACE_GW=""
        return
    fi

    # find default route associated to this interface
    GET_IFACE_GW=$(ip route show table $TABLE_ID 2>/dev/null | awk -v dev="$GET_IFACE_NAME" '$0 ~ dev && $0 ~ /via/ {for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1 || true)
    
    # fallback: ask route for a remote IP to find gateway
    if [[ -z "$GET_IFACE_GW" && -n "$GET_IFACE_IP" ]]; then
        # query route to a public IP from this source to reveal gateway
        GET_IFACE_GW=$(ip route get 8.8.8.8 from "$GET_IFACE_IP" 2>/dev/null | awk '/via/ {for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1 || true)
    fi
}

function reinstall(){
    echo "Reinstalling rules and routes..."
    uninstall
    sleep 1
    install
}

function doWork(){
    getIface
    getIfaceState

    if [[ $GET_IFACE_STATE == "down" ]];
    then
        if [[ $TABLE_RULES_INSTALLED == 1 ]];
        then
            uninstall
        fi

        return
    fi

    getIfaceIP
    getIfaceGWIP

    if [[ $GET_IFACE_NAME != $CURRENT_IFACE_NAME ]];
    then
        echo "Interface name change detected, reinstalling..."
        reinstall
    fi

    if [[ $GET_IFACE_IP != $CURRENT_IP ]];
    then
        echo "Interface IP address change detected! $CURRENT_IP -> $GET_IFACE_IP"
        reinstall
    fi

    if [[ $TABLE_RULES_INSTALLED == 0 ]];
    then
        echo "Interface baought up again, reinstalling..."
        reinstall
    fi 

    # if [[ $GET_IFACE_GW != $CURRENT_GW ]];
    # then
    #     echo "Interface gateway address change detected! $CURRENT_GW -> $GET_IFACE_GW"
    #     reinstall
    # fi
}

function main(){
    detectNMConfig
    sleep 1
    while true; do
        doWork
        sleep "$SCAN_INTERVAL_SECS"
    done
}

main