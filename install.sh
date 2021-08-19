#!/usr/bin/env bash
#
# Install Prometheus, Node Exporter to CentOS
# Initial script
# Created by Yevgeniy Goncharov, https://sys-adm.in
# Creation at (c) 2021.
#

# Envs
# ---------------------------------------------------\
PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)

# POSIX / Reset in case getopts has been used previously in the shell.
OPTIND=1

_configPrometheus="/etc/prometheus/prometheus.yml"
_install=$SCRIPT_PATH/installs
_serverIP=`hostname -I | awk '{print $1}'`

# Functions
confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

_exit() {
    echo "Bye bye!"
    exit 0
}

# Options
setupNodeExporter() {

echo -e '[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target
[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/node_exporter.service

systemctl daemon-reload
systemctl enable --now node_exporter

firewall-cmd --add-port=9100/tcp  --permanent
firewall-cmd --reload

}

setupPrometheusSVC() {
    # setup systemd
echo -e '[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/prometheus.service

systemctl daemon-reload
systemctl enable --now prometheus

firewall-cmd --add-port=9090/tcp --permanent
firewall-cmd --reload

}

# Installers
installExporter() {

    # Temporary catalog
    cd $SCRIPT_PATH

    # Temporary catalog
    if [[ ! -d "$_install" ]]; then
        mkdir $_install
    else
        rm -rf $_install; mkdir $_install
    fi

    cd $_install; 

    # Check is wget installed
    if ! type "wget" >/dev/null 2>&1; then
        dnf install wget -y
    fi

    # Download Node Exporter
    local _binary=`curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep browser_download_url | grep "linux-amd64" | awk '{print $2}' | tr -d '\"'`
    wget $_binary; tar -xvf $(ls node_exporter*.tar.gz)
    cd `ls -l | grep '.linux-amd[0-9]*$' | awk '{print $9}'`
    cp node_exporter /usr/local/bin

    # Create user
    useradd --no-create-home --shell /bin/false node_exporter
    chown node_exporter:node_exporter /usr/local/bin/node_exporter

    # Setup systemd unit
    setupNodeExporter

    # User suggestion
    echo -e "Add the following lines to /etc/prometheus/prometheus.yml:
  - job_name: 'node_exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9100']

    or

  - job_name: 'node_exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['$_serverIP:9100'] 
"
    echo "node_exporter is installed!"

}

installPrometheus() {

    cd $SCRIPT_PATH; 

    # Temporary catalog
    if [[ ! -d "$_install" ]]; then
        mkdir $_install
    else
        rm -rf $_install; mkdir $_install
    fi

    cd $_install; 
    
    # Check is wget installed
    if ! type "wget" >/dev/null 2>&1; then
        dnf install wget -y
    fi
    
    # Download latest release
    local _binary=`curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep browser_download_url | grep "linux-amd64" | awk '{print $2}' | tr -d '\"'`
    wget $_binary; tar -xvf $(ls prometheus*.tar.gz)
    cd `ls -l | grep '.linux-amd[0-9]*$' | awk '{print $9}'`

    # User in catalogs creation 
    useradd -m -s /bin/false prometheus
    mkdir /var/lib/prometheus /etc/prometheus 
    chown prometheus:prometheus /etc/prometheus
    chown prometheus:prometheus /var/lib/prometheus

    # Copy executable and set permissions
    cp prometheus  /usr/local/bin
    cp promtool  /usr/local/bin

    chown prometheus:prometheus /usr/local/bin/prometheus
    chown prometheus:prometheus /usr/local/bin/promtool

    # Copy config
    cp -r consoles /etc/prometheus
    cp -r console_libraries /etc/prometheus
    cp prometheus.yml /etc/prometheus/prometheus.yml

    # Setup systemd unit
    setupPrometheusSVC

    echo "Prometheus installed!"
}

function setChoise()
{
    echo -e "What do you want install?\n"
    echo "   1) Exporter"
    echo "   2) Prometheus"
    echo "   3) Exit"
    echo ""
    read -p "Install [1-3]: " -e -i 3 INSTALL_CHOICE

    case $INSTALL_CHOICE in
        1)
        _installExporter=1
        ;;
        2)
        _installServer=1
        ;;
        3)
        _exit
        ;;
    esac

    if [[ "$_installExporter" == 1 ]]; then
        if confirm "Install Node Exporter (y/n)?"; then
                
                installExporter
        fi
    fi

    if [[ "$_installServer" == 1 ]]; then
        if confirm "Install Prometheus (y/n)?"; then

            if [ -f $_configPrometheus ]; then
                echo "Prometheus already installed!"
                _exit
            else
                installPrometheus
            fi

        fi
    fi

}

setChoise