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
GLOBAL_START_PH="$HOME/rc.local"
KLIPPER_START="$HOME/klipper-start.sh"
MOONRAKER_START="$HOME/moonraker-start.sh"

KLIPPER_CONFIG="$HOME/klipper_config"
GCODE_FILES="$HOME/gcode_files"

### Mounting /tmp
echo "Re-mounting /tmp from tmpfs"

sudo rm -rf /tmp
sudo mkdir -p /tmp
sudo mount -o mode=1777,nosuid,nodev -t tmpfs tmpfs /tmp

### packages
echo "Installing required packages"

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
${MOONRAKER_ENV}/bin/pip install --no-use-pep517 -r ${MOONRAKER_GIT}/scripts/moonraker-requirements.txt

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

cat <<EOF > $KLIPPER_START
#!/bin/bash
$KLIPPY_ENV/bin/python $KLIPPER_GIT/klippy/klippy.py $KLIPPER_CONFIG/printer.cfg -l /tmp/klippy.log -a /tmp/klippy_uds
EOF
chmod +x $KLIPPER_START

cat <<EOF > $MOONRAKER_START
#!/bin/bash
$MOONRAKER_ENV/bin/python $MOONRAKER_GIT/moonraker/moonraker.py -c ${KLIPPER_CONFIG}/moonraker.conf -l /tmp/moonraker.log
EOF
chmod +x $MOONRAKER_START

cat <<EOF > $GLOBAL_START_PH
#!/bin/bash
mount -o mode=1777,nosuid,nodev -t tmpfs tmpfs /tmp
chmod 777 /dev/ttyACM0

su -l $USER $KLIPPER_START &
su -l $USER $MOONRAKER_START &
EOF
sudo mv $GLOBAL_START_PH $GLOBAL_START
sudo chmod +x $GLOBAL_START

### complete
echo "Installation complete! Please start/stop container now!"