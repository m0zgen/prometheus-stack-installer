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

# If pushgateway is already installed, exit
if [ -f /usr/local/bin/alertmanager ]; then
    echo "Alertmanager is already installed"
    exit 0
fi

# If arg is empty, exit
if [ -z "$1" ]; then
    echo "Usage: $0 <Telegram ID>"
    exit 1
fi

_TG_ID=$1

function install {

    local _serverIP=`hostname -I | awk '{print $1}'`
    # Clean download dir
    rm -rf $_download_dir/*

    # Download and extract
    cd $_download_dir
    wget https://github.com/prometheus/alertmanager/releases/download/v0.24.0/alertmanager-0.24.0.linux-amd64.tar.gz
    tar -xzf alertmanager-0.24.0.linux-amd64.tar.gz; rm -f alertmanager-0.24.0.linux-amd64.tar.gz

    # Cp binary from extracted dir
    mkdir -p /etc/alertmanager
    cp alertmanager-0.24.0.linux-amd64/amtool /usr/local/bin/
    cp alertmanager-0.24.0.linux-amd64/alertmanager /usr/local/bin/
    cp alertmanager-0.24.0.linux-amd64/alertmanager.yml /etc/alertmanager/

    mkdir -p /data/alertmanager

    # Create user
    useradd --no-create-home --shell /bin/false alertmanager

    # Set permissions
    chown -R alertmanager:alertmanager /data/alertmanager /etc/alertmanager/*
    chown alertmanager:alertmanager /usr/local/bin/amtool /usr/local/bin/alertmanager
    chown alertmanager:alertmanager /data/alertmanager

    # Update config
    cat <<EOF > /etc/alertmanager/alertmanager.yml

route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'web.hook'
receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:9087/alert/${_TG_ID}'
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']

EOF

    # Create systemd service
    cat <<EOF > /etc/systemd/system/alertmanager.service

[Unit]
Description=Alert Manager
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=alertmanager
Group=alertmanager
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/data/alertmanager \
  --web.external-url http://${_serverIP}:9093 \
  --cluster.advertise-address="${_serverIP}:9093"

Restart=always

[Install]
WantedBy=multi-user.target

EOF

    # Reload systemd
    systemctl daemon-reload

    # Enable and start service
    systemctl enable alertmanager
    systemctl start alertmanager

    # Check status
    systemctl status alertmanager

    # Clean download dir
    rm -rf $_download_dir/*

    echo "Alertmanager installed and started"
}

install
