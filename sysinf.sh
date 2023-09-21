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

# OS and Kernel Info
header "OS and Kernel Info"
# Display OS name using ID
OS_NAME=$(source /etc/os-release; echo $ID)
echo -e "${YELLOW}OS Name:${NC} $OS_NAME"
# Display OS version
OS_VERSION=$(source /etc/os-release; echo $VERSION_ID)
echo -e "${YELLOW}OS Version:${NC} $OS_VERSION"
# Display Kernel version
KERNEL_VERSION=$(uname -r)
echo -e "${YELLOW}Kernel Version:${NC} $KERNEL_VERSION"

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
    BEGIN {
        total = 0;
        nb = 0;
    }
    /Size:/ && $2 ~ /^[0-9]+/ {
        size = $2;
        if ($3 == "MB") size /= 1024;
        total += size;
        sizes[nb] = size;
        nb++;
    }
    /Type: DDR/ && !type { type = $2 }
    /Speed:/ && $2 ~ /^[0-9]+/ && !speed { speed = $2 }
    END {
        if (nb > 0) {
            average_size = total / nb;
            print total " GB (" nb " * " average_size " GB) " type " @ " speed " MT/s";
        } else {
            print "No memory modules installed.";
        }
    }')
echo -e "$MEM"

divider

# Disks
header "Disks" 
lsblk -d -o NAME,SIZE,MODEL | awk '
    NR>1 && !/^loop/ {
        original_size=$2;
        gsub(" ","", $3);
        model=$3;
        
        size_in_gb = 0;
        if (index(original_size, "M") > 0) {
            gsub("[M]","",original_size);
            size_in_gb = original_size / 1024;
        } else if (index(original_size, "G") > 0) {
            gsub("[G]","",original_size);
            size_in_gb = original_size;
        } else if (index(original_size, "T") > 0) {
            gsub("[T]","",original_size);
            size_in_gb = original_size * 1024;
        }
        
        if (size_in_gb < 0.1) {
            next;
        }

        disk_name = "/sys/block/" $1 "/queue/rotational";
        if ((getline rotational < disk_name) > 0) {
            if ($1 ~ /^nvme/) {
                type = "NVMe SSD";
                total_nvme_capacity += size_in_gb;
            } else if (rotational == 0) {
                type = "SSD";
                total_ssd_capacity += size_in_gb;
            } else if (rotational == 1) {
                type = "SATA HDD";
                total_sata_capacity += size_in_gb;
            } else {
                type = "Unknown";
            }
        } else {
            type = "Unknown";
        }
        close(disk_name);

        key = sprintf("%.2f GB | %s | %s", size_in_gb, model, type);
        disk[key]++;
    } 
    END {
        for (key in disk) {
            split(key, s, " | ");
            size = s[1];
            model = s[2];
            type = s[3] " " s[4]; # Combine the two parts for type
            count = disk[key];
            
            speed = "6GB/s";
            print count "x " size " " speed " " model " " type;
        }
        print "\nTotal SATA HDD Capacity: " sprintf("%.2f GB", total_sata_capacity+0);
        print "Total SSD Capacity: " sprintf("%.2f GB", total_ssd_capacity+0);
        print "Total NVMe SSD Capacity: " sprintf("%.2f GB", total_nvme_capacity+0);
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