#!/bin/bash

if [ "$(id  -u)" = "0" ]
then
  echo "Start script as user!"
  exit 1
fi

read -d . DEBIAN_VERSION < /etc/debian_version
if [ "$DEBIAN_VERSION" != "11" ]
then
  echo "You should run Debian 11!"
  exit 1
fi

if ! grep xterm "$HOME/.xsession" > /dev/null
then
  echo "Configure container with XTerm graphics over VNC or X11!"
  exit 1
fi

### environment
echo "Initializing environment variables"

KIAUH="$HOME/kiauh"
KLIPPER="$HOME/klipper"
MOONRAKER="$HOME/moonraker"
KLIPPERSCREEN="$HOME/KlipperScreen"
FLUIDD="$HOME/fluidd"
KWC="https://github.com/fluidd-core/fluidd/releases/download/v1.16.2/fluidd.zip"

KLIPPER_START="/etc/init.d/klipper"
MOONRAKER_START="/etc/init.d/moonraker"

KLIPPER_CONFIG="$HOME/klipper_config"
KLIPPER_LOGS="$HOME/klipper_logs"
GCODE_FILES="$HOME/gcode_files"

KLIPPERSCREEN_XTERM="/usr/local/bin/xterm"

TTYFIX="/usr/bin/ttyfix"
TTYFIX_START="/etc/init.d/ttyfix"

### Mounting /tmp
echo "Re-mounting /tmp from tmpfs"

sudo mount -o mode=1777,nosuid,nodev -t tmpfs tmpfs /tmp

### packages
echo "Installing required packages"

sudo apt update
sudo apt install -y \
  git inotify-tools virtualenv python2-dev libffi-dev build-essential libncurses-dev libusb-dev stm32flash libnewlib-arm-none-eabi gcc-arm-none-eabi binutils-arm-none-eabi libusb-1.0-0 pkg-config dfu-util \
  python3-virtualenv python3-dev libopenjp2-7 python3-libgpiod liblmdb0 libsodium-dev zlib1g-dev libjpeg-dev libcurl4-openssl-dev libssl-dev python-markupsafe python-jinja2 \
  python3-tornado python3-serial python3-pillow python3-lmdb python3-libnacl python3-paho-mqtt python3-pycurl curl \
  libopenjp2-7 python3-distutils python3-gi python3-gi-cairo gir1.2-gtk-3.0 wireless-tools libatlas-base-dev fonts-freefont-ttf python3-websocket python3-requests python3-humanize python3-jinja2 python3-ruamel.yaml python3-matplotlib unzip
sudo apt install -f
sudo apt clean
sudo python2 -m pip install setuptools wheel
sudo python3 -m pip install setuptools wheel

### git
echo "Clonning klipper software"

sudo apt update
sudo apt install git wget -y

git clone https://github.com/th33xitus/kiauh.git $KIAUH
git clone https://github.com/KevinOConnor/klipper.git $KLIPPER
git clone -b v0.7.1 https://github.com/Arksine/moonraker.git $MOONRAKER
git clone https://github.com/jordanruthe/KlipperScreen.git $KLIPPERSCREEN

### fix systemctl
sudo mv /usr/bin/systemctl /usr/bin/systemctl2
sudo tee /usr/bin/systemctl <<EOF
#!/bin/bash
if [ "\$1" = "list-units" ]
then
 echo "klipper.service"
 echo "moonraker.service"
 exit 0
fi
/usr/sbin/service "\$2" "\$1"
EOF
sudo chmod +x /usr/bin/systemctl

## install klipper
echo "Installing klipper"
~/klipper/scripts/install-debian.sh

### fix klipper service
sudo sed -i "s#printer.cfg#klipper_config/printer.cfg#" /etc/systemd/system/klipper.service
sudo sed -i "s#/tmp#/home/$USER/klipper_logs#" /etc/systemd/system/klipper.service

### install moonraker
echo "Installing moonraker"
~/moonraker/scripts/install-moonraker.sh -c "${HOME}/klipper_config/moonraker.conf" -l "${HOME}/klipper_logs/moonraker.log"

### fix moonraker service
sudo ln -s /usr/local/lib/python3.9/dist-packages/pip /usr/bin/pip
~/moonraker/scripts/sudo_fix.sh

### config nginx
report_status "Installing symbolic link..."
FILE=/etc/nginx/sites-available/fluidd
if [ -e "$FILE" ];
then
	echo "$FILE exist"
else
	echo "$FILE does not exist"
	
	NGINXDIR="/etc/nginx/sites-available"
	NGINXUPS="/etc/nginx/conf.d/"
	NGINXVARS="/etc/nginx/conf.d/"
	sudo /bin/sh -c "cp ${SRCDIR}/Fluidd-install/fluidd $NGINXDIR/"
	sudo /bin/sh -c "cp ${SRCDIR}/Fluidd-install/upstreams.conf $NGINXUPS/"
	sudo /bin/sh -c "cp ${SRCDIR}/Fluidd-install/common_vars.conf $NGINXVARS/"

	sudo ln -s /etc/nginx/sites-available/fluidd /etc/nginx/sites-enabled/
	sudo rm /etc/nginx/sites-available/default
	sudo rm /etc/nginx/sites-enabled/default
	sudo systemctl restart nginx
fi

### install fluidd
mkdir ${FLUIDD}
cd ${FLUIDD}
wget -q -O fluidd.zip ${KWC} && unzip fluidd.zip && rm fluidd.zip
cd ~/

### install KlipperScreen
echo "Installing KlipperScreen"
~/KlipperScreen/scripts/KlipperScreen-install.sh

### fix KlipperScreen service
sudo systemctl enable KlipperScreen

sudo tee "$KLIPPERSCREEN_XTERM" <<EOF
#!/bin/bash

cd $KLIPPERSCREEN
exec ../.KlipperScreen-env/bin/python ./screen.py
EOF
sudo chmod +x "$KLIPPERSCREEN_XTERM"

sudo tee  ${KLIPPER_CONFIG}/moonraker.conf <<EOF
[server]
host: 0.0.0.0
port: 7125
enable_debug_logging: False
config_path: $KLIPPER_CONFIG
database_path: ~/.moonraker_database
klippy_uds_address: /tmp/klippy_uds

[authorization]
trusted_clients:
    127.0.0.1
    192.168.0.0/16
    ::1/128
    FE80::/10
cors_domains:
    *.lan
    *.local
    *://my.mainsail.xyz
    *://app.fluidd.xyz
    *://dev-app.fluidd.xyz

[octoprint_compat]

[history]
EOF

### configs
echo "Fixing config files"

mkdir ${KLIPPER_CONFIG} ${KLIPPER_LOGS} ${GCODE_FILES}
cp -f $KIAUH/resources/printer.cfg $KLIPPER_CONFIG
sed -i "s#serial:.*#serial: /dev/ttyACM0#" $KLIPPER_CONFIG/printer.cfg
cp -f $KLIPPERSCREEN/ks_includes/defaults.conf $KLIPPER_CONFIG/KlipperScreen.conf

### autostart
echo "Creating autostart entries for sysv"

sudo tee $TTYFIX <<EOF
#!/bin/bash
inotifywait -m /dev -e create |
  while read dir action file
  do
    [ "\$file" = "ttyACM0" ] && chmod 777 /dev/ttyACM0
  done
EOF
sudo chmod +x $TTYFIX

sudo tee $TTYFIX_START <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ttyfix
# Default-Start:        2 3 4 5
# Default-Stop:
# Required-Start:    \$local_fs \$remote_fs
# Short-Description: ttyfix
# Description: ttyfix
### END INIT INFO

. /lib/lsb/init-functions

N=$TTYFIX_START
PIDFILE=/run/ttyfix.pid

EXEC=$TTYFIX
set -e

f_start ()
{
  start-stop-daemon --start --background --make-pidfile --pidfile \$PIDFILE --exec \$EXEC
}

f_stop ()
{
  start-stop-daemon --stop --pidfile \$PIDFILE
}

case "\$1" in
  start)
        f_start
        ;;
  stop)
        f_stop
        ;;
  restart)
        f_stop
        sleep 1
        f_start
        ;;
  reload|force-reload|status)
        ;;
  *)
        echo "Usage: $N {start|stop|restart|force-reload|status}" >&2
        exit 1
        ;;
esac

exit 0
EOF
sudo chmod +x $TTYFIX_START

sudo tee $KLIPPER_START <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          klipper
# Default-Start:        2 3 4 5
# Default-Stop:
# Required-Start:    \$local_fs \$remote_fs
# Short-Description: klipper
# Description: klipper
### END INIT INFO

. /lib/lsb/init-functions

N=$KLIPPER_START
PIDFILE=/run/klipper.pid
USERNAME=$USER
EXEC="/home/\$USERNAME/klippy-env/bin/python"
EXEC_OPTS="/home/\$USERNAME/klipper/klippy/klippy.py $KLIPPER_CONFIG/printer.cfg -l $KLIPPER_LOGS/klippy.log -a /tmp/klippy_uds"
set -e
f_start ()
{
  chmod 777 /dev/ttyACM0 ||:
  mount -o mode=1777,nosuid,nodev -t tmpfs tmpfs /tmp
  start-stop-daemon --start --background --chuid \$USERNAME --make-pidfile --pidfile \$PIDFILE --exec \$EXEC -- \$EXEC_OPTS
}

f_stop ()
{
  start-stop-daemon --stop --pidfile \$PIDFILE
}

case "\$1" in
  start)
        f_start
        ;;
  stop)
        f_stop
        ;;
  restart)
        f_stop
        sleep 1
        f_start
        ;;
  reload|force-reload|status)
        ;;
  *)
        echo "Usage: $N {start|stop|restart|force-reload|status}" >&2
        exit 1
        ;;
esac

exit 0
EOF
sudo chmod +x $KLIPPER_START

sudo tee $MOONRAKER_START <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          moonraker
# Default-Start:        2 3 4 5
# Default-Stop:
# Required-Start:    \$local_fs \$remote_fs klipper
# Short-Description: moonraker
# Description: moonraker
### END INIT INFO

. /lib/lsb/init-functions

N=$MOONRAKER_START
PIDFILE=/run/moonraker.pid
USERNAME=$USER
EXEC="/home/\$USERNAME/moonraker-env/bin/python"
EXEC_OPTS="/home/\$USERNAME/moonraker/moonraker/moonraker.py -c $KLIPPER_CONFIG/moonraker.conf -l $KLIPPER_LOGS/moonraker.log"
set -e
f_start ()
{
  start-stop-daemon --start --background --chuid \$USERNAME --make-pidfile --pidfile \$PIDFILE --exec \$EXEC -- \$EXEC_OPTS
}

f_stop ()
{
  start-stop-daemon --stop --pidfile \$PIDFILE
}

case "\$1" in
  start)
        f_start
        ;;
  stop)
        f_stop
        ;;
  restart)
        f_stop
        sleep 1
        f_start
        ;;
  reload|force-reload|status)
        ;;
  *)
        echo "Usage: $N {start|stop|restart|force-reload|status}" >&2
        exit 1
        ;;
esac

exit 0
EOF
sudo chmod +x $MOONRAKER_START

sudo update-rc.d klipper defaults
sudo update-rc.d moonraker defaults
sudo update-rc.d ttyfix defaults
sudo update-rc.d nginx defaults

echo " "
echo "########################"
echo "###  Fixing logs...  ###"
echo "########################"
echo " "

echo " "
echo "Creating logrotate configuration files..."
echo " "

sudo tee /etc/logrotate.d/klipper <<EOF
$KLIPPER_LOGS/klippy.log
{
    rotate 7
    daily
    maxsize 64M
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
}
EOF

sudo tee /etc/logrotate.d/moonraker <<EOF
$KLIPPER_LOGS/moonraker.log
{
    rotate 7
    daily
    maxsize 64M
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
}
EOF

echo "Starting klipper and moonraker services now"

sudo service ttyfix start
sudo service klipper start
sleep 10
sudo service moonraker start

echo "Starting KlipperScreen instead of XTerm"

sudo pkill xterm
export DISPLAY=:0
xterm >/dev/null 2>&1 &

### complete
echo "Installation completed!"