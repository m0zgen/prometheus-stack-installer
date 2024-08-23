#!/bin/bash
# Prometheus Push Gateway installation script
# Author: Yevgeniy Goncharov (https://sys-adm.in)

# Sys env / paths / etc
# -------------------------------------------------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd); cd $SCRIPT_PATH

# Variables
# -------------------------------------------------------------------------------------------\
_download_dir="${SCRIPT_PATH}/downloads"


# Functions
# -------------------------------------------------------------------------------------------\

# If downloaddir does not exist, create it
if [ ! -d $_download_dir ]; then
    mkdir -p $_download_dir
fi

function install_pushgateway {

    # Clean download dir
    rm -rf $_download_dir/*

    # Download and extract
    cd $_download_dir
    wget https://github.com/prometheus/pushgateway/releases/download/v1.8.0/pushgateway-1.8.0.linux-amd64.tar.gz
    tar -xzf pushgateway-1.8.0.linux-amd64.tar.gz; rm -f pushgateway-1.8.0.linux-amd64.tar.gz

    # Cp binary from extracted dir
    cp pushgateway-1.8.0.linux-amd64/pushgateway /usr/local/bin/

    # Create user
    useradd --no-create-home --shell /bin/false pushgateway

    # Set permissions
    chown -R pushgateway:pushgateway /usr/local/bin/pushgateway

    # Create systemd service
    cat <<EOF > /etc/systemd/system/pushgateway.service

    [Unit]
Description=Prometheus Pushgateway
Wants=network-online.target
After=network-online.target

[Service]
User=pushgateway
Group=pushgateway
Type=simple
ExecStart=/usr/local/bin/pushgateway

[Install]
WantedBy=multi-user.target

EOF

    # Reload systemd
    systemctl daemon-reload

    # Enable and start service
    systemctl enable pushgateway
    systemctl start pushgateway

    # Check status
    systemctl status pushgateway

    # Clean download dir
    rm -rf $_download_dir/*

    echo "Pushgateway installed and started"
}

install_pushgateway
