# Avail Node Configuration Script

This project provides a Bash script to initialize and manage a Avail testnet node. The script provides multiple features such as initializing and upgrading the services, observing logs, and catching up quickly using a snapshot.

## Quick Start

To initialize or manage your Avail node, simply run the following line in your terminal:

```sh
bash <(curl -sL https://github.com/kjnodes/avail-node-configuration/raw/refs/heads/main/script.sh)
```

![image](images/main-menu.png)

## Features

- Node Initialization: Set up the Avail testnet node from scratch, including Golang, Cosmovisor, and the Avail/Geth binaries.
- Upgrade Management: Seamlessly prepare for upgrades for your node when a new version is available.
- Snapshot Restore: Easily reset your node to the latest snapshot, with support for both pruned and archival data.
- Service Restart: Simply perform node service restart.
- Log Monitoring: View real-time logs of the Avail and Geth clients.
- Service Monitoring: Optional setup of a monitoring solution using Docker, Prometheus, and Grafana with Telegram alert integration.
- Service Removal: Cleanly remove all traces of the Avail and Geth services, including binaries and data.

## Monitoring Setup

The script can configure a monitoring solution, based on [`kjnodes/avail-node-monitoring`](https://github.com/kjnodes/avail-node-monitoring).

For configuration, you will need:
- A Telegram bot token, which can be obtained from [@botfather](https://t.me/botfather), based on instructions outlined in [Telegram Bots documentation](https://core.telegram.org/bots#6-botfather).
- Your Telegram user ID, which can be obtained from [@userinfobot](https://t.me/userinfobot).

After setup, Grafana will be available at your node's IP on port 9999 with default credentials `admin/admin`.
