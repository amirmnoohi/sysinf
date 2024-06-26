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
echo -e "${WHITE}Copyright (c) 2024 AMIRMNOOHI${NC}"

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
    NR>1 {
        original_size=$2;
        gsub(" ","", $3);
        model=$3;
        
        # Exclude optical drives by model name
        if (model ~ /DVD/) {
            next;
        }

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
        
        if (size_in_gb < 2) {
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
        }
        close(disk_name);

        key = sprintf("%.2f GB | %s | %s", size_in_gb, model, type);
        disk[key]++;
    } 
    END {
        for (key in disk) {
            split(key, s, " | ");
            size = s[1];
            model = s[3];
            type = substr(key, index(key, s[4]));  # Extract the type correctly
            
            count = disk[key];
            print count " x " size "GB " model " " type;
        }
        print "\nTotal SATA-HDD Capacity: " sprintf("%.2f GB", total_sata_capacity+0);
        print "Total SSD Capacity: " sprintf("%.2f GB", total_ssd_capacity+0);
        print "Total SSD-NVME Capacity: " sprintf("%.2f GB", total_nvme_capacity+0);
    }'

divider

# Network
header "Network Interfaces"
declare -A types speeds macs ips

for iface in /sys/class/net/*; do
    if [ -d "$iface" ]; then
        iface_name=$(basename $iface)
        
        # Skip the loopback interface
        if [ "$iface_name" == "lo" ]; then
            continue
        fi

        speed_file="$iface/speed"
        driver_link="$iface/device/driver/module"
        
        if [ -e "$speed_file" ]; then
            if [ -L "$driver_link" ]; then
                driver=$(basename $(readlink $driver_link))
            elif command -v ethtool &>/dev/null; then
                driver=$(ethtool -i $iface_name | grep driver | awk '{print $2}')
                if [ -z "$driver" ]; then
                    driver="Unknown"
                fi
            else
                driver="Unknown"
            fi
            types["$iface_name"]=$driver

            # Use cat with error suppression for speed
            speed=$(cat $speed_file 2>/dev/null)
            if [[ $speed =~ ^-?[0-9]+$ ]]; then
                if [ "$speed" -ge 0 ]; then
                    speeds["$iface_name"]="${speed} Mbps"
                else
                    speeds["$iface_name"]="Down"
                fi
            else
                speeds["$iface_name"]="Invalid"
            fi

            # Fetch MAC address
            mac_address=$(cat $iface/address)
            macs["$iface_name"]=$mac_address

            # Fetch IP address
            ip_address=$(ip -4 addr show $iface_name | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
            if [ -z "$ip_address" ]; then
                ip_address="N/A"
            fi
            ips["$iface_name"]=$ip_address
        fi
    fi
done

echo "Type:"
for key in $(echo ${!types[@]} | tr ' ' '\n' | sort); do
    echo "     $key: ${types[$key]}"
done

echo "Speed:"
for key in $(echo ${!speeds[@]} | tr ' ' '\n' | sort); do
    echo "     $key: ${speeds[$key]}"
done

echo "MAC:"
for key in $(echo ${!macs[@]} | tr ' ' '\n' | sort); do
    echo "     $key: ${macs[$key]}"
done

echo "IP Address:"
for key in $(echo ${!ips[@]} | tr ' ' '\n' | sort); do
    echo "     $key: ${ips[$key]}"
done


divider

# GPU Info
header "GPU Details"
# Check if nvidia-smi is installed and accessible
if command -v nvidia-smi &> /dev/null
then
    # Get the number of GPUs in the system
    NUM_GPUS=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1 | tr -d '[:space:]')

    if [[ $NUM_GPUS =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}NVIDIA GPUs Detected: $NUM_GPUS${NC}"

        # Loop through each GPU and display its details
        for (( i=0; i<$NUM_GPUS; i++ ))
        do
            echo -e "${YELLOW}Details for GPU $i:${NC}"
            # Display GPU name
            GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader --id=$i | head -n 1)
            echo -e "     ${YELLOW}GPU Name:${NC} $GPU_NAME"
            # Display GPU Driver Version
            GPU_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader --id=$i | head -n 1)
            echo -e "     ${YELLOW}Driver Version:${NC} $GPU_DRIVER"
            # Display GPU Memory
            GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader --id=$i | head -n 1)
            echo -e "     ${YELLOW}Total GPU Memory:${NC} $GPU_MEMORY"
        done
    else
        echo -e "${RED}Failed to retrieve the number of NVIDIA GPUs.${NC}"
    fi
else
    echo -e "${RED}No NVIDIA GPU Detected or nvidia-smi not installed.${NC}"
fi

divider
