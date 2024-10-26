#!/bin/bash
set -e

KJ_AVAIL_TAG_VERSION='2.2.5.0' # without the `v` prefix
KJ_AVAIL_NODE_VERSION='2.2.0-a6600ea38c9'


CHECK_POSITIONAL='y'
screen_main() {

	echo -e '\e[0m' >&2

	if [ "x$CHECK_POSITIONAL" == 'xy' ]; then
		CHECK_POSITIONAL=''
		case "$1" in
			'')
				# no-op
				;;
			init)
				screen_init
				exit 0
				;;
			upgrade)
				screen_upgrade
				exit 0
				;;
			restart)
				screen_restart
				exit 0
				;;
			logs)
				screen_logs
				exit 0
				;;
			snapshot)
				screen_snapshot
				exit 0
				;;
			monitor)
				screen_monitor
				exit 0
				;;
			remove_all)
				screen_remove_all
				exit 0
				;;
			*)
				echo "Received unexpected argument: $1" >&2
				exit 1
				;;
		esac
	fi

	AVAIL_VERSION_OUT=''
	if [ -x "/usr/local/bin/avail-node" ]; then
		AVAIL_VERSION_OUT="$(/usr/local/bin/avail-node --version 2>&1 | cut -d' ' -f2)"
	fi

	if [ "$AVAIL_VERSION_OUT" ]; then
		echo -e "\e[1m\e[32mCurrently running Avail node $AVAIL_VERSION_OUT.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mDid not find a local Avail node.\e[0m" >&2
	fi

	echo '' >&2

	echo -e 'Select an option:\e[0m' >&2
	( [ "x$AVAIL_VERSION_OUT" != 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '1 - Initialize service\e[0m' >&2
	( [ "x$AVAIL_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '2 - Upgrade service\e[0m' >&2
	( [ "x$AVAIL_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '3 - Restart services\e[0m' >&2
	( [ "x$AVAIL_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '4 - Show service logs\e[0m' >&2
	( [ "x$AVAIL_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '5 - Reset local data to pruned snapshot\e[0m' >&2
	( [ "x$AVAIL_VERSION_OUT" == 'x' ] ) && echo -ne '\033[0;90m' >&2
	echo -e '6 - Configure local monitoring solution\e[0m' >&2
	echo -e '9 - Remove service and data\e[0m' >&2
	echo -e '0 - Exit\e[0m' >&2
	read -e -p '  > Enter your choice: ' choice
	echo '' >&2

	case "$choice" in
		1)
			screen_init
			;;
		2)
			screen_upgrade
			;;
		3)
			screen_restart
			;;
		4)
			screen_logs
			;;
		5)
			screen_snapshot
			;;
		6)
			screen_monitor
			;;
		9)
			screen_remove_all
			;;
		0)
			exit 0
			;;
		*)
			echo 'Unrecognized choice. Expected an option number to be provided.' >&2
			screen_main
			;;
	esac

}


screen_init() {

	# Check whether services already exist, and abort if so.
	if systemctl list-unit-files -q avail.service >/dev/null; then
		echo 'Found `avail` service file already installed.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi
	if [ -e '/usr/local/bin/avail' ]; then
		echo 'Found pre-existing `avail` binary.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi
	if [ -d "$HOME/.avail" ]; then
		echo 'Found pre-existing Avail configuration/data.' >&2
		echo 'Please execute removal first, if you want a clean installation.' >&2
		screen_main
		return 1
	fi

	# Check if values are provided as flags.
	moniker=''
	OPTIND=1
	while getopts hvf: opt; do
		case $opt in
			m)
				moniker="$OPTARG"
				;;
			*)
				# ignore unknown flags
				;;
		esac
	done
	shift "$((OPTIND-1))"

	# Update OS packages for sanity.
	echo -e '\e[1m\e[32mUpdating system packages...\e[0m' >&2
	sudo apt-get -qq update
	sudo apt-get -qqy upgrade

	# Install OS package dependencies.
	echo -e '\e[1m\e[32mInstalling system dependencies...\e[0m' >&2
	sudo apt-get -qqy install curl git jq lz4 ccze

	# Prepare directories for downloads.
	mkdir -p "$HOME/.avail/"
	KJ_TMP_DIR="$(mktemp -dqt avail.XXXXXXXXXX)"
	trap "rm -rf '$KJ_TMP_DIR'" EXIT # and always clean up after ourselves.

	# Download Avail consensus binary.
	echo -e "\e[1m\e[32mDownloading Avail consensus client v$KJ_AVAIL_TAG_VERSION...\e[0m" >&2
	curl -L https://github.com/availproject/avail/releases/download/v$KJ_AVAIL_TAG_VERSION/x86_64-ubuntu-$(lsb_release -sr | tr -d .)-avail-node.tar.gz | tar -xz -C /usr/local/bin
	sudo chown 0:0 /usr/local/bin/avail-node
	sudo chmod 755 /usr/local/bin/avail-node

	# Configure SystemD services.
	echo -e '\e[1m\e[32mConfiguring background services...\e[0m' >&2
	sudo tee /etc/systemd/system/avail.service <<- EOF > /dev/null
		[Unit]
		Description=Avail node service
		After=network-online.target

		[Service]
		User=$USER
		ExecStart=$(which avail-node) \
		--base-path $HOME/.avail/data/ \
		--chain mainnet \
		--name "$moniker" \
		--prometheus-external \
		--rpc-external \
		--rpc-cors all

		Restart=on-failure
		RestartSec=10
		LimitNOFILE=65535

		[Install]
		WantedBy=multi-user.target
	EOF
	sudo systemctl daemon-reload
	sudo systemctl enable avail.service

	# Create data folder
	mkdir -p $HOME/.avail/data/chains/avail_da_mainnet/paritydb

	# Download snapshot.
	echo -e '\e[1m\e[32mDownloading snapshots...\e[0m' >&2
	rm -rf "$HOME/.avail/data/chains/avail_da_mainnet/paritydb"
	curl -L "https://snapshots.kjnodes.com/avail/snapshot_latest.tar.lz4" | tar -Ilz4 -xf - -C "$HOME/.avail/data/chains/avail_da_mainnet"

	# Start services. It's a wrap!
	echo -e '\e[1m\e[32mStarting background services...\e[0m' >&2
	sudo systemctl start avail.service

	screen_main

}


screen_upgrade() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q avail.service >/dev/null; then
		echo 'Aborting! Did not find `avail` service file installed.' >&2
		echo 'Is Avail actually running on this system?' >&2
		screen_main
		return 1
	fi
	if ! [ -d "$HOME/.avail" ]; then
		echo 'Aborting! Did not find Avail configuration/data.' >&2
		echo 'Is Avail actually running on this system?' >&2
		screen_main
		return 1
	fi

	# Update OS packages for sanity.
	echo -e '\e[1m\e[32mUpdating system packages...\e[0m' >&2
	sudo apt-get -qq update
	sudo apt-get -qqy upgrade

	# Prepare directories for downloads.
	KJ_TMP_DIR="$(mktemp -dqt avail.XXXXXXXXXX)"
	trap "rm -rf '$KJ_TMP_DIR'" EXIT # and always clean up after ourselves.

	# Download Avail binary.
	if [ "x$(/usr/local/bin/avail-node --version 2>&1 | cut -d' ' -f2)" == "x${KJ_AVAIL_NODE_VERSION}" ]; then
		echo -e "\e[1m\e[32mSkipping downloading Avail node v$KJ_AVAIL_TAG_VERSION.\e[0m" >&2
	else
		echo -e "\e[1m\e[32mDownloading Avail node v$KJ_AVAIL_TAG_VERSION...\e[0m" >&2
		curl -L https://github.com/availproject/avail/releases/download/v$KJ_AVAIL_TAG_VERSION/x86_64-ubuntu-$(lsb_release -sr | tr -d .)-avail-node.tar.gz | tar -xz -C /usr/local/bin
		sudo chown 0:0 /usr/local/bin/avail-node
		sudo chmod 755 /usr/local/bin/avail-node
		echo -e '\e[1m\e[32mRestarting Avail node...\e[0m' >&2
		sudo systemctl restart avail.service
	fi

	screen_main

}


screen_restart() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q avail.service >/dev/null; then
		echo 'Aborting! Did not find `avail` service file installed.' >&2
		echo 'Is Avail actually running on this system?' >&2
		screen_main
		return 1
	fi

	sudo systemctl restart avail.service

	echo 'Successfully restarted!' >&2

	screen_main

}


screen_logs() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q avail.service >/dev/null; then
		echo 'Aborting! Did not find `avail` service file installed.' >&2
		echo 'Is Avail actually running on this system?' >&2
		screen_main
		return 1
	fi

	trap 'exit 0' INT; journalctl -f -ocat --no-pager -u avail.service | ccze -A

	screen_main

}


screen_snapshot() {

	# Check whether services already exist, and abort if not.
	if ! systemctl list-unit-files -q avail.service >/dev/null; then
		echo 'Aborting! Did not find `avail` service file installed.' >&2
		echo 'Is Avail actually running on this system?' >&2
		screen_main
		return 1
	fi

	echo '!!! THIS WILL REPLACE ALL NODE DATA WITH SNAPSHOT' >&2
	read -e -p '!!! PLEASE CONFIRM THIS OPERATION (yes/no): ' really_remove
	echo '' >&2

	if [ "x$really_remove" != 'xyes' ]; then
		echo 'Cancelling.' >&2
		screen_main
		return 0
	fi

	echo -e "\e[1m\e[32mStopping services...\e[0m" >&2
	sudo systemctl stop avail.service

	echo -e "\e[1m\e[32mRemoving existing local data...\e[0m" >&2
	rm -rf "$HOME/.avail/data/chains/avail_da_mainnet/paritydb"

	echo -e "\e[1m\e[32mDownloading latest available snapshot...\e[0m" >&2
	curl -L https://snapshots.kjnodes.com/avail/snapshot_latest.tar.lz4 | tar -Ilz4 -xf - -C "$HOME/.avail/avail"

	echo -e "\e[1m\e[32mStarting services...\e[0m" >&2
	sudo systemctl start avail.service

	echo 'Successfully completed!' >&2

	screen_main

}


screen_monitor() {

	myip="$(curl -4s https://myipv4.addr.tools/plain)"
	if [ "x$myip" == 'x' ]; then
		echo 'Stopping! Unable to determine an IP address of the host.' >&2
		screen_main
		return 1
	fi
	echo -e "\e[1m\e[32mUsing $myip as the host IP address.\e[0m" >&2

	telegram_bot_token=''
	telegram_user_id=''
	echo -e "\e[1m\e[32mThis process expects you to have configured a Bot token from @botfather.\e[0m" >&2
	echo -e "\e[1m\e[32mPlease see the steps at https://core.telegram.org/bots#6-botfather if not.\e[0m" >&2
	read -e -p '> Enter your Telegram bot token: ' telegram_bot_token
	if [ "x$telegram_bot_token" == 'x' ]; then
		echo 'Aborting! Expected a token to be provided.' >&2
		screen_main
		return 1
	fi
	read -e -p '> Enter your Telegram user ID (from @userinfobot): ' telegram_user_id
	if [ "x$telegram_bot_token" == 'x' ]; then
		echo 'Aborting! Expected a user ID to be provided.' >&2
		screen_main
		return 1
	fi

	echo -e "\e[1m\e[32mEnsuring pre-requisites...\e[0m" >&2
	sudo apt-get -qqy install ca-certificates curl

	echo -e "\e[1m\e[32mAdding Docker keyring...\e[0m" >&2
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc

	echo -e "\e[1m\e[32mAdding Docker package repository...\e[0m" >&2
	sudo tee /etc/apt/sources.list.d/docker.list <<- EOF > /dev/null
		deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable
	EOF
	sudo apt-get -qq update

	echo -e "\e[1m\e[32mInstalling Docker packages...\e[0m" >&2
	sudo apt-get -qqy install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

	echo -e "\e[1m\e[32mConfiguring Docker services...\e[0m" >&2
	sudo systemctl enable docker.service
	sudo systemctl enable containerd.service
	sudo systemctl start docker.service
	sudo systemctl start containerd.service

	if [ -d "$HOME/avail-node-monitoring" ]; then
		echo -e "\e[1m\e[32mResetting the node-monitoring repository...\e[0m" >&2
		git -C "$HOME/avail-node-monitoring" fetch --quiet origin +main:main
		git -C "$HOME/avail-node-monitoring" reset --quiet --hard origin/main
	else
		echo -e "\e[1m\e[32mObtaining the node-monitoring repository...\e[0m" >&2
		git clone --quiet https://github.com/kjnodes/avail-node-monitoring.git "$HOME/avail-node-monitoring"
	fi

	echo -e "\e[1m\e[32mUpdating configuration files...\e[0m" >&2
	sed -i -e "s'YOUR_TELEGRAM_BOT_TOKEN'${telegram_bot_token}'" "$HOME/avail-node-monitoring/prometheus/alert_manager/alertmanager.yml"
	sed -i -e "s'YOUR_TELEGRAM_USER_ID'${telegram_user_id}'" "$HOME/avail-node-monitoring/prometheus/alert_manager/alertmanager.yml"
	sed -i -e "s'YOUR_NODE_IP:COMET_PORT'${myip}:26660'" "$HOME/avail-node-monitoring/prometheus/prometheus.yml"
	sed -i -e "s'YOUR_NODE_IP:GETH_PORT'${myip}:6060'" "$HOME/avail-node-monitoring/prometheus/prometheus.yml"

	echo -e "\e[1m\e[32mStarting services...\e[0m" >&2
	pushd "$HOME/avail-node-monitoring" >/dev/null
	docker compose up --detach --force-recreate --pull always
	popd >/dev/null

	echo 'Successfully started!' >&2
	echo "You can open Grafana at http://${myip}:9999 with default credentials admin/admin." >&2

	screen_main

}


screen_remove_all() {

	if ! systemctl list-units -q avail.service | grep avail.service >/dev/null &&
			! [ -e '/etc/systemd/system/avail.service' ] &&
			! [ -e '/usr/local/bin/avail-node' ] &&
			! [ -e "$HOME/.avail" ] &&
			! [ -e "$HOME/avail-node-monitoring" ]; then
		echo 'Did not find anything to remove.' >&2
		screen_main
		return 0
	fi


	echo '!!! THIS WILL REMOVE ALL NODE SERVICES AND DATA' >&2
	read -e -p '!!! PLEASE CONFIRM THIS OPERATION (yes/no): ' really_remove
	echo '' >&2

	if [ "x$really_remove" != 'xyes' ]; then
		echo 'Cancelling.' >&2
		screen_main
		return 0
	fi

	if systemctl list-units -q avail.service | grep avail.service >/dev/null; then
		sudo systemctl disable avail.service
		sudo systemctl stop avail.service
	fi
	if [ -e '/etc/systemd/system/avail.service' ]; then
		sudo rm -v '/etc/systemd/system/avail.service'
		sudo systemctl daemon-reload
	fi

	[ -e '/usr/local/bin/avail-node' ] && sudo rm -v '/usr/local/bin/avail-node'

	[ -e "$HOME/.avail" ] && rm -rf "$HOME/.avail"
	
	if [ -e "$HOME/avail-node-monitoring" ]; then
		pushd "$HOME/avail-node-monitoring" >/dev/null
		docker compose down --volumes
		popd >/dev/null
		rm -rf "$HOME/avail-node-monitoring"
	fi

	echo 'Successfully completed!' >&2

	screen_main

}


clear

echo '' >&2
echo '██╗  ██╗     ██╗███╗   ██╗ ██████╗ ██████╗ ███████╗███████╗' >&2
echo '██║ ██╔╝     ██║████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝' >&2
echo '█████╔╝      ██║██╔██╗ ██║██║   ██║██║  ██║█████╗  ███████╗' >&2
echo '██╔═██╗ ██   ██║██║╚██╗██║██║   ██║██║  ██║██╔══╝  ╚════██║' >&2
echo '██║  ██╗╚█████╔╝██║ ╚████║╚██████╔╝██████╔╝███████╗███████║' >&2
echo '╚═╝  ╚═╝ ╚════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚══════╝' >&2
echo '' >&2
echo 'Website: https://kjnodes.com' >&2
echo 'Avail services: https://services.kjnodes.com/mainnet/avail' >&2
echo 'Twitter: https://x.com/kjnodes' >&2
echo '' >&2
sleep 1

screen_main
