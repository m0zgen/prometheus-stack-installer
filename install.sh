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
SCRIPT_PATH=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd); cd $SCRIPT_PATH

# POSIX / Reset in case getopts has been used previously in the shell.
OPTIND=1

_configPrometheus="/etc/prometheus/prometheus.yml"
_install=$SCRIPT_PATH/installs

# Help information
usage() {

    echo -e "You can also use this script for automate install prometheus stack:"
    echo -e "$ON_CHECK" "./install.sh -a : Auto-install and configure all software"
    exit 1

}

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

# Checks supporting distros
checkDistro() {
    # Checking distro
    if [ -e /etc/centos-release ]; then
        DISTRO=`cat /etc/redhat-release | awk '{print $1,$4}'`
        RPM=1
    elif [ -e /etc/fedora-release ]; then
        DISTRO=`cat /etc/fedora-release | awk '{print ($1,$3~/^[0-9]/?$3:$4)}'`
        RPM=1
    elif [ -e /etc/os-release ]; then
        DISTRO=`lsb_release -d | awk -F"\t" '{print $2}'`
        RPM=0
    else
        echo -e "Your distribution is not supported (yet). Exit. Bye!"
        exit 1
    fi
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
ExecStart=/usr/local/bin/node_exporter \
--collector.processes \
--collector.filesystem.ignored-mount-points="^/(dev|proc|sys|var/lib/docker/.+)($|/)"
Restart=always
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/node_exporter.service

systemctl daemon-reload
systemctl enable --now node_exporter

if [[ "$1" -eq "auto" ]]; then
    firewall-cmd --permanent --add-port=9100/tcp
else
    if confirm "Setup firewalld to INternal zone? (y/n or enter)"; then
        firewall-cmd --permanent --add-port=9100/tcp --zone=internal
    else
        firewall-cmd --permanent --add-port=9100/tcp
    fi
fi

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

if [[ "$1" -eq "auto" ]]; then
    firewall-cmd --permanent --add-port=9090/tcp
else
    if confirm "Setup firewalld to INternal zone? (y/n or enter)"; then
        firewall-cmd --permanent --add-port=9090/tcp --zone=internal
    else
        firewall-cmd --permanent --add-port=9090/tcp
    fi
fi

firewall-cmd --reload

}

# Installers
installExporter() {

    # If /usr/local/bin/node_exporter exists
    if [ -f /usr/local/bin/node_exporter ]; then
        echo "Node Exporter already installed!"
        echo "Skip..."
        return
    else
        local _serverIP=`hostname -I | awk '{print $1}'`
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

        or just add to exist yml file to node_exporter section:
        - targets: ['$_serverIP:9100'] 
    "
        echo "node_exporter is installed!"

    fi

}

installPrometheus() {

    # If /usr/local/bin/prometheus exists
    if [ -f /usr/local/bin/prometheus ]; then
        echo "Prometheus already installed!"
        echo "Skip..."
        return
    else

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

    fi
}

installGrafana() {

    # If /etc/grafana/grafana.ini exists
    if [ -f /etc/grafana/grafana.ini ]; then
        echo "Grafana already installed!"
        echo "Skip..."
        return
    else


    if [[ "$RPM" -eq "1" ]]; then
        echo -e "
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
" > /etc/yum.repos.d/grafana.repo

    yum install grafana -y
    
    else
        # Install Grafana for Debian
        echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
        curl https://packages.grafana.com/gpg.key | apt-key add -
        apt-get update
        apt-get install grafana -y
    fi
  
  
    sleep 15
    systemctl daemon-reload
    systemctl enable --now grafana-server
    sleep 5

    grafana-cli plugins install grafana-piechart-panel
    sed -i 's/;admin_user/admin_user/g' /etc/grafana/grafana.ini
    sed -i 's/;admin_password/admin_password/g' /etc/grafana/grafana.ini
    sed -i 's/;disable_sanitize_html.*/disable_sanitize_html = true/g' /etc/grafana/grafana.ini

    NEWPASS=$(openssl rand -base64 12)
    grafana-cli --config "/etc/grafana/grafana.ini" admin reset-admin-password $NEWPASS
    systemctl restart grafana-server
    # systemctl status grafana-server

    if [[ "$1" -eq "auto" ]]; then
        firewall-cmd --permanent --add-port=3000/tcp
    else
        if confirm "Setup firewalld to INternal zone? (y/n or enter)"; then
            firewall-cmd --permanent --add-port=3000/tcp --zone=internal
        else
            firewall-cmd --permanent --add-port=3000/tcp
        fi
    fi

    firewall-cmd --reload

    echo "Grafana installed!"
    echo "Login: admin"
    echo "Password: $NEWPASS"

    # Save login data to file
    echo "Login: admin" > /root/grafana_login.txt
    echo "Password: $NEWPASS" >> /root/grafana_login.txt
    echo "Login data saved to /root/grafana_login.txt"

fi

}

# Install alertmanager with run alertmanager.sh function
installAlertmanager() {
    # If /usr/local/bin/alertmanager exists
    if [ -f /usr/local/bin/alertmanager ]; then
        echo "Alertmanager already installed!"
        echo "Skip..."
        return
    else
        bash $SCRIPT_PATH/install-alertmanager.sh
    fi
}

# Install pushgateway with run pushgateway.sh function
installPushgateway() {
    # If /usr/local/bin/pushgateway exists
    if [ -f /usr/local/bin/pushgateway ]; then
        echo "Pushgateway already installed!"
        echo "Skip..."
        return
    else
        bash $SCRIPT_PATH/install-pushgtw.sh
    fi
}

checkDistro

auto_install() {
    installPrometheus auto
    installExporter auto
    installGrafana auto
    installAlertmanager auto
    installPushgateway auto
}

function setChoise()
{
    echo -e "What do you want install?\n"
    echo "   1) Exporter"
    echo "   2) Prometheus"
    echo "   3) Grafana"
    echo "   4) Alertmanager"
    echo "   5) Pushgateway"
    echo "   6) Auto install"
    echo "   7) Help"
    echo "   8) Exit"
    echo ""
    read -p "Install [1-4]: " -e -i 5 INSTALL_CHOICE

    case $INSTALL_CHOICE in
        1)
        _installExporter=1
        ;;
        2)
        _installServer=1
        ;;
        3)
        _installGrafana=1
        ;;
        4)
        _installAlertmanager=1
        ;;
        5)
        _installPushgateway=1
        ;;
        6)
        _installAuto=1
        ;;
        7)
        usage
        ;;
        8)
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

    if [[ "$_installGrafana" == 1 ]]; then
        if confirm "Install Grafana (y/n)?"; then
                installGrafana
        fi
    fi

    if [[ "$_installAlertmanager" == 1 ]]; then
        if confirm "Install Alertmanager (y/n)?"; then
                installAlertmanager
        fi
    fi

    if [[ "$_installPushgateway" == 1 ]]; then
        if confirm "Install Pushgateway (y/n)?"; then
                installPushgateway
        fi
    fi

    if [[ "$_installAuto" == 1 ]]; then
        auto_install
    fi

}

# setChoise

if [[ -z "$1" ]]; then
    setChoise
else
    # Checks arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
                -a|--auto) auto_install; ;;
                -h|--help) usage ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done
fi
