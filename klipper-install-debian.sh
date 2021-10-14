#!/bin/bash

if [ "$(id  -u)" = "0" ]
then
  echo "Start script as user!"
  exit 1
fi

### environment
echo "Initializing environment variables"

KLIPPY_ENV="$HOME/klippy-env"
MOONRAKER_ENV="$HOME/moonraker-env"

KIAUH_GIT="$HOME/kiauh"
KLIPPER_GIT="$HOME/klipper"
MOONRAKER_GIT="$HOME/moonraker"

GLOBAL_START="/etc/rc.local"
KLIPPER_START="/etc/init.d/klipper"
MOONRAKER_START="/etc/init.d/moonraker"

KLIPPER_CONFIG="$HOME/klipper_config"
GCODE_FILES="$HOME/gcode_files"

### Mounting /tmp
echo "Re-mounting /tmp from tmpfs"

sudo mount -o mode=1777,nosuid,nodev -t tmpfs tmpfs /tmp

### packages
echo "Installing required packages"

sudo apt update
sudo apt install git virtualenv python-dev libffi-dev build-essential libncurses-dev libusb-dev stm32flash libnewlib-arm-none-eabi gcc-arm-none-eabi binutils-arm-none-eabi libusb-1.0 pkg-config dfu-util python3-virtualenv python3-dev libopenjp2-7 python3-libgpiod liblmdb0 libsodium-dev zlib1g-dev libjpeg-dev libcurl4-openssl-dev libssl-dev
sudo apt install -f
sudo apt clean

### git
echo "Clonning klipper software"

git clone https://github.com/th33xitus/kiauh.git $KIAUH_GIT
git clone https://github.com/KevinOConnor/klipper.git $KLIPPER_GIT
git clone https://github.com/Arksine/moonraker.git $MOONRAKER_GIT

### folders
echo "Creating klipper folders"

mkdir -p $KLIPPER_CONFIG
mkdir -p $GCODE_FILES

### configs
echo "Fixing config files"

cp -f $KIAUH_GIT/resources/printer.cfg $KLIPPER_CONFIG
cp -f $KIAUH_GIT/resources/kiauh_macros.cfg $KLIPPER_CONFIG
sed -i "s#serial:.*#serial: /dev/ttyACM0#" $KLIPPER_CONFIG/printer.cfg
sed -i "1 i [include kiauh_macros.cfg]" $KLIPPER_CONFIG/printer.cfg

### klipper
echo "Installing klipper"

mkdir -p $KLIPPY_ENV
virtualenv $KLIPPY_ENV
$KLIPPY_ENV/bin/pip install -U pip setuptools wheel
$KLIPPY_ENV/bin/pip install -r $KLIPPER_GIT/scripts/klippy-requirements.txt

### moonraker
echo "Installing moonraker"

mkdir -p $MOONRAKER_ENV
virtualenv -p /usr/bin/python3 $MOONRAKER_ENV
${MOONRAKER_ENV}/bin/pip install -U pip setuptools wheel
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 streaming-form-data
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 tornado
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 pillow
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 lmdb
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 pycurl
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 distro
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 inotify-simple
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 libnacl
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 paho-mqtt
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 -r ${MOONRAKER_GIT}/scripts/moonraker-requirements.txt
${MOONRAKER_ENV}/bin/pip install -r ${MOONRAKER_GIT}/scripts/moonraker-requirements.txt

cat <<EOF > ${KLIPPER_CONFIG}/moonraker.conf
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

### autostart
echo "Creating autostart entries for run-parts"

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

sudo tee $KLIPPER_START <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          klipper
# Default-Start:        2 3 4 5
# Default-Stop:
# Required-Start:    $local_fs $remote_fs
# Short-Description: klipper
# Description: klipper
### END INIT INFO

. /lib/lsb/init-functions

N=/etc/init.d/klipper
PIDFILE=/run/klipper.pid
USERNAME=$USER
EXEC="/home/\$USERNAME/klippy-env/bin/python"
EXEC_OPTS="/home/\$USERNAME/klipper/klippy/klippy.py /home/\$USERNAME/klipper_config/printer.cfg -l /tmp/klippy.log -a /tmp/klippy_uds"

set -e

f_start ()
{
  chmod 777 /dev/ttyACM0
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
# Required-Start:    $local_fs $remote_fs klipper
# Short-Description: moonraker
# Description: moonraker
### END INIT INFO

. /lib/lsb/init-functions

N=/etc/init.d/moonraker
PIDFILE=/run/moonraker.pid
USERNAME=$USER
EXEC="/home/\$USERNAME/moonraker-env/bin/python"
EXEC_OPTS="/home/\$USERNAME/moonraker/moonraker/moonraker.py -c /home/\$USERNAME/klipper_config/moonraker.conf -l /tmp/moonraker.log"

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

sudo tee -a $GLOBAL_START <<EOF
#!/bin/bash
mount -o mode=1777,nosuid,nodev -t tmpfs tmpfs /tmp
sudo chmod 777 /dev/ttyACM0

service klipper start
service moonraker start
EOF
sudo chmod +x $GLOBAL_START

sudo service klipper start
sleep 10
sudo service moonraker start

### complete
echo "Installation complete! Starting klipper and moonraker now!"