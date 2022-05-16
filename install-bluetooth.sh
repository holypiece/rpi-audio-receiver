#!/bin/bash -e

if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

echo
echo -n "Do you want to install Bluetooth Audio (PulseAudio)? [y/N] "
read REPLY
if [[ ! "$REPLY" =~ ^(yes|y|Y)$ ]]; then exit 0; fi

apt install -y --no-install-recommends bluez-tools pulseaudio-module-bluetooth

# Bluetooth settings
cat <<'EOF' > /etc/bluetooth/main.conf
[General]
Class = 0x200414
DiscoverableTimeout = 0

[Policy]
AutoEnable=true
EOF

# Bluetooth PIN / Password protection
BT_DEVICE="*"
BT_PIN="1248"
BT_SSP_MODE=1

echo
echo "Exposing Bluetooth without a PIN comes with risks."
echo "Otherwise, some devices may not be able to pair with a PIN enabled due to incompatibilities."
echo -n "Do you want to protect Bluetooth pairing with a default PIN? [y/N] "

read REPLY
if [[ "$REPLY" =~ ^(yes|y|Y)$ ]]
then
  BT_SSP_MODE=0;
  cat <<EOF > /etc/bluetooth/pin.conf
${BT_DEVICE} ${BT_PIN}
EOF
  echo;
  echo -n "Your Bluetooth PIN is: ${BT_PIN}";
  echo;
fi

# Make Bluetooth discoverable after initialisation
mkdir -p /etc/systemd/system/bthelper@.service.d
cat <<'EOF' > /etc/systemd/system/bthelper@.service.d/override.conf
[Service]
Type=oneshot
EOF

cat <<EOF > /etc/systemd/system/bt-agent@.service
[Unit]
Description=Bluetooth Agent
Requires=bluetooth.service
After=bluetooth.service

[Service]
ExecStartPre=/usr/bin/bluetoothctl discoverable on
ExecStartPre=/bin/hciconfig %I piscan
ExecStartPre=/bin/hciconfig %I sspmode ${BT_SSP_MODE}
ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput $(if [[ ${BT_SSP_MODE} == 0 ]]; then echo "--pin /etc/bluetooth/pin.conf"; fi)
RestartSec=5
Restart=always
KillSignal=SIGUSR1

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable bt-agent@hci0.service

usermod -a -G bluetooth pulse

# PulseAudio settings
#sed -i.orig 's/^load-module module-udev-detect$/load-module module-udev-detect tsched=0/' /etc/pulse/system.pa
echo "load-module module-bluetooth-policy" >> /etc/pulse/system.pa
echo "load-module module-bluetooth-discover" >> /etc/pulse/system.pa

# Bluetooth udev script
cat <<'EOF' > /usr/local/bin/bluetooth-udev
#!/bin/bash
if [[ ! $NAME =~ ^\"([0-9A-F]{2}[:-]){5}([0-9A-F]{2})\"$ ]]; then exit 0; fi

action=$(expr "$ACTION" : "\([a-zA-Z]\+\).*")

if [ "$action" = "add" ]; then
    bluetoothctl discoverable off
    # disconnect wifi to prevent dropouts
    #ifconfig wlan0 down &
fi

if [ "$action" = "remove" ]; then
    # reenable wifi
    #ifconfig wlan0 up &
    bluetoothctl discoverable on
fi
EOF
chmod 755 /usr/local/bin/bluetooth-udev

cat <<'EOF' > /etc/udev/rules.d/99-bluetooth-udev.rules
SUBSYSTEM=="input", GROUP="input", MODE="0660"
KERNEL=="input[0-9]*", RUN+="/usr/local/bin/bluetooth-udev"
EOF
