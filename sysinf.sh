#!/bin/bash

# Colors
RED="\033[0;31m"  
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
NC="\033[0m" # No Color

# Functions  
divider() {
  echo -e "${CYAN}----------------------------------------------------${NC}"
}

header() {
  echo -e "${WHITE}$1${NC}"
}

# Script
clear

header "System Information Script"
echo -e "${WHITE}Copyright (c) 2023 AMIRMNOOHI${NC}"

divider

# System Info
header "System Model"
file=/sys/class/dmi/id
MODEL=""
info_array=("sys_vendor" "board_vendor" "chassis_vendor" "product_name" "product_version")
for info in "${info_array[@]}"; do
    if [[ -r "$file/$info" && ! "$MODEL" =~ $(<"$file/$info") ]]; then
        MODEL+=" $(<"$file/$info")"
    fi
done

[[ -z "$MODEL" && -r /sys/firmware/devicetree/base/model ]] && read -r -d '' MODEL </sys/firmware/devicetree/base/model
echo -e "${YELLOW}Computer Model:${NC} $MODEL"

divider

header "CPU Details"
CPU=$(grep -m1 "model name" /proc/cpuinfo | cut -d ':' -f2 | sed 's/^[ \t]*//;s/[ \t]*$//')
[[ -z "$CPU" ]] && CPU=$(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
echo -e "${YELLOW}Processor (CPU):${NC} $CPU"

echo -e "${YELLOW}CPU Sockets/Cores/Threads:${NC} $(lscpu | grep 'Socket(s):' | awk '{print $2}')/$(lscpu | grep 'Core(s) per socket:' | awk '{print $4}')/$(nproc)"
echo -e "${YELLOW}Architecture:${NC} $HOSTTYPE ($(getconf LONG_BIT)-bit)"

divider 

# Memory
header "Memory"
MEM=$(sudo dmidecode -t memory | awk '
    /Size: [0-9]+/ {
        size=$2;
        if ($3 == "MB") size/=1024;
        total += size;
        if (nb == 0) first_size = size;  # store the size of the first slot
        nb++;
    }
    /Type: DDR/ { if (!type) type=$2 }  # store DDR version (like DDR4)
    /Speed:/ { if (!speed) speed=$2 }   # store frequency (like 2400 MHz)
    END {
        print total " GB (" nb " * " first_size " GB) " type " @ " speed " MHz ";
    }')
echo -e "$MEM"

divider

# Disks
header "Disks" 
lsblk -d -o NAME,SIZE,MODEL | awk '
    NR>1 {
        original_size=$2;
        gsub(" ","", $3);
        model=$3;
        
        multiplier = 1;
        if (index(original_size, "M") > 0) {
            multiplier = 10^6;
        } else if (index(original_size, "G") > 0) {
            multiplier = 10^9;
        } else if (index(original_size, "T") > 0) {
            multiplier = 10^12;
        }
        size = original_size;
        gsub("[MGT]","",size);
        
        if (size * multiplier < 100 * 10^6) {
            next;
        }
        
        disk[original_size " " model]++;
    } 
    END {
        for (key in disk) {
            split(key, s, " ");
            size = s[1];
            model = s[2];
            count = disk[key];
            
            speed = "6GB/s";
            if (index(model, "NVMe") > 0) {
                type = "NVMe SSD";
            } else if (index(model, "SSD") > 0) {
                type = "SSD";
            } else {
                type = "SATA HDD";
            }

            print count "x " size " " speed " " model " " type;
        }
    }'


divider

# Network
header "Network Interfaces"
for iface in /sys/class/net/*; do
    if [ -d "$iface" ]; then
        iface_name=$(basename $iface)
        speed_file="$iface/speed"
        driver_link="$iface/device/driver/module"
        if [ -e "$speed_file" ] && [ -L "$driver_link" ]; then
            # Use cat with error suppression
            speed=$(cat $speed_file 2>/dev/null)
            driver=$(basename $(readlink $driver_link))
            # Check if speed contains a number
            if ! [[ $speed =~ ^-?[0-9]+$ ]]; then
                echo "$iface_name: Type: $driver, Speed: Invalid"
                continue
            fi
            # Check for negative speed value
            if [ "$speed" -lt 0 ]; then
                echo "$iface_name: Type: $driver, Status: Down"
            else
                echo "$iface_name: Type: $driver, Speed: $speed Mbps"
            fi
        fi
    fi
done

divider