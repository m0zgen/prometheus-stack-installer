# Prometheus Stack Installer

* Prometheus
* Node Exporter
* Grafana

## Features

* Automatically download latest releases from official repositories
* Can add `firewalld` port excludes to internal zone (available on default step-by-step install)
* Provide selection software menu
* Can installs full stack automatically

## Example

Just run `install.sh`:
```bash
./install.sh
```
Or you can install software automatically with `-a` argument:

```bash
./install.sh -a
```

## More info

Description (RU):
* https://sys-adm.in/live/960-prometheus-stack-ustanovshchik.html

Description (EN):
* https://sys-adm.in/en/linux/961-centos-fedora-autoinstaller-prometheus-stack.html