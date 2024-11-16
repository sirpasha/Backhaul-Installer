#!/bin/bash

# Clear screen and display header
clear
echo -e "\e[1;34m===================================\e[0m"
echo -e "\e[1;34m    Backhaul Installation Script   \e[0m"
echo -e "\e[1;34m          By Pasha Ghomi           \e[0m"
echo -e "\e[1;34m===================================\e[0m"

# Function to show loading spinner
show_loading() {
    echo -n "Loading"
    pid=$!
    while ps -p $pid > /dev/null; do
        echo -n "."
        sleep 1
    done
    echo -e "\nDone!"
}

# Detect CPU architecture
echo -e "\e[1;32mDetecting CPU architecture...\e[0m"
ARCH=$(dpkg --print-architecture)
if [[ "$ARCH" == "arm64" ]]; then
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/v0.6.3/backhaul_linux_arm64.tar.gz"
elif [[ "$ARCH" == "amd64" ]]; then
    DOWNLOAD_URL="https://github.com/Musixal/Backhaul/releases/download/v0.6.3/backhaul_linux_amd64.tar.gz"
else
    echo "Unsupported architecture!"
    exit 1
fi

# Install required packages
echo -e "\e[1;32mUpdating package list and installing wget...\e[0m"
sudo apt update -qq && sudo apt install wget -qq &
show_loading

# Download Backhaul
echo -e "\e[1;32mDownloading Backhaul...\e[0m"
wget -q $DOWNLOAD_URL -O backhaul.tar.gz &
show_loading

# Decompress and move Backhaul binary to PATH
echo -e "\e[1;32mDecompressing Backhaul...\e[0m"
tar -zxvf backhaul.tar.gz -C /root/ >/dev/null
mv /root/backhaul /usr/local/bin/
rm backhaul.tar.gz
chmod +x /usr/local/bin/backhaul

# Create backhaul config directory
mkdir -p /etc/backhaul

# Input custom config name
read -p "Enter configuration name (without extension): " config_name
config_file="/etc/backhaul/$config_name.toml"

# Server/Client Selection
echo -e "\e[1;33mSelect Server Type:\e[0m"
echo -e "\e[1;36m1. Client [Kharej]\e[0m"
echo -e "\e[1;36m2. Server [Iran]\e[0m"
read -p "Enter choice [1-2]: " server_type

# Validate input
if [[ "$server_type" != "1" && "$server_type" != "2" ]]; then
    echo "Invalid server type!"
    exit 1
fi

# Prompt for details based on server type
if [ "$server_type" == "1" ]; then
    client_server="client"
    read -p "Enter remote address [0.0.0.0:3080]: " remote_addr
else
    client_server="server"
    remote_addr="0.0.0.0:3080"
fi

# Transport Selection
echo -e "\e[1;33mSelect Transport Type:\e[0m"
echo -e "\e[1;36m1. TCP\e[0m"
echo -e "\e[1;36m2. TCPMUX\e[0m"
echo -e "\e[1;36m3. WebSocket (WS)\e[0m"
read -p "Enter choice [1-3]: " transport_choice

# Validate transport input
if [[ "$transport_choice" != "1" && "$transport_choice" != "2" && "$transport_choice" != "3" ]]; then
    echo "Invalid transport type!"
    exit 1
fi

# Set transport and parameters
case $transport_choice in
    1) transport="tcp" ;;
    2) transport="tcpmux" ;;
    3) transport="ws" ;;
esac

# Prompt for token
read -p "Enter secure token: " token

# Channel pool (for TCP and WS)
if [[ "$transport" != "tcpmux" ]]; then
    read -p "Enter channel pool size (default 8): " channel_pool
    channel_pool=${channel_pool:-8}
fi

# Nodelay
read -p "Enable nodelay? (y/n): " nodelay_choice
if [[ "$nodelay_choice" == "y" ]]; then
    nodelay=true
else
    nodelay=false
fi

# Ports Configuration (for server)
if [ "$client_server" == "server" ]; then
    ports=()
    while true; do
        read -p "Enter local port (or type 'done' to finish): " local_port
        if [[ "$local_port" == "done" ]]; then
            break
        fi
        read -p "Enter remote port: " remote_port
        ports+=("\"$local_port=$remote_port\"")
    done
fi

# Generate config.toml based on user inputs
echo -e "\e[1;32mGenerating configuration...\e[0m"
if [[ "$client_server" == "client" ]]; then
    echo "[client]" > $config_file
    echo "remote_addr = \"$remote_addr\"" >> $config_file
else
    echo "[server]" > $config_file
    echo "bind_addr = \"$remote_addr\"" >> $config_file
    echo "ports = [" >> $config_file
    for port_pair in "${ports[@]}"; do
        echo "  $port_pair," >> $config_file
    done
    echo "]" >> $config_file
fi

echo "transport = \"$transport\"" >> $config_file
echo "token = \"$token\"" >> $config_file
echo "nodelay = $nodelay" >> $config_file

if [[ "$transport" == "tcpmux" ]]; then
    echo "mux_session = 1" >> $config_file
else
    echo "channel_size = 2048" >> $config_file
    echo "connection_pool = $channel_pool" >> $config_file
fi

# Create service file with the same name as the config
service_file="/etc/systemd/system/backhaul-$config_name.service"
echo -e "\e[1;32mCreating service file...\e[0m"
cat <<EOF > $service_file
[Unit]
Description=Backhaul Reverse Tunnel Service ($config_name)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/backhaul -c /etc/backhaul/$config_name.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start the new service
echo -e "\e[1;32mSetting up Backhaul service ($config_name)...\e[0m"
sudo systemctl daemon-reload
sudo systemctl enable backhaul-$config_name.service
sudo systemctl start backhaul-$config_name.service

# Show service status
sudo systemctl status backhaul-$config_name.service
