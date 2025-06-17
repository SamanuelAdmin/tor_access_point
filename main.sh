#!/bin/bash

echo " _____                                                      _       _   "
echo "|_   _|__  _ __    __ _  ___ ___ ___  ___ ___   _ __   ___ (_)_ __ | |_ "
echo "  | |/ _ \| '__|  / _' |/ __/ __/ _ \/ __/ __| | '_ \ / _ \| | '_ \| __|"
echo "  | | (_) | |    | (_| | (_| (_|  __/\__ \__ \ | |_) | (_) | | | | | |_ "
echo "  |_|\___/|_|     \__,_|\___\___\___||___/___/ | .__/ \___/|_|_| |_|\__|"
echo "                                               |_|"



# CONFIGS

# Access point configs
SSID=Acp
PASSWORD=4lmaxaml4
WIFI_IFACE=wlp5s0
WIFI_CHANNEL=10

# base interfaces config
IFACES="eno1"
GATEWAY_IFACE=enp4s0

# DHCP configs
DHCP_SUBNET=10.110.110.0
DHCP_LOCAL_IP=10.110.110.1
DHCP_NETMASK=255.255.255.0
DHCP_USERS_RANGE="10.110.110.100 10.110.110.200"
DHCP_ROUTERS="$DHCP_LOCAL_IP"
DHCP_DNS="$DHCP_LOCAL_IP"

# redsocks configuration
REDSOCKS_IP=0.0.0.0
REDSOCKS_PORT=12345

# tor configuration
TOR_SOCKS_PROXY_IP=127.0.0.1
TOR_DNS_SERVER_IP=0.0.0.0
TOR_DNS_PORT=53
TOR_SOCKS_PORT=9050

# iptables config
LOCAL_NETWORKS="0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4"
DELETE_OLD_IPTABLES_RULES=1

# Names for components
BRIDGE_NAME="onion-bridge"
HOTSPOT_NAME="main-hotspot"

# Needed dependencies
DEPENDENCIES=" redsocks tor hostapd "



# checking for root rights
if [ "$EUID" -ne 0 ]
    then echo "Permission denied. Please, run script as root." && exit
fi

# checking for dependencies
for depend in $DEPENDENCIES
do
    if [ ! $(which $depend) ]
        then echo "$depend not found. Please install it using 'apt install $depend'" && exit 1
    fi
done

echo "All available interfaces: "
for ifaceName in $(nmcli -t -f DEVICE,TYPE device) 
do
    echo -n "$ifaceName   "
done

echo -e -n "\nWill be in use: $IFACES"
if [ $WIFI_IFACE != 0 ] 
    then echo "  $WIFI_IFACE"
fi
echo ""


# Up all useful interfaces and adding to created brige
ip link delete $BRIDGE_NAME type bridge
ip link add name $BRIDGE_NAME type bridge
ip addr add $DHCP_LOCAL_IP/24 dev onion-bridge
ip link set dev $BRIDGE_NAME up

for iface in $IFACES
do
    ip link set $iface down
    ip addr flush dev $iface
    ip link set $iface up
    ip link set $iface master $BRIDGE_NAME
    echo "$iface up, with master $BRIDGE_NAME"
done


if [[ $WIFI_IFACE != 0 ]] then
    ip link set $WIFI_IFACE down
    nmcli device set $WIFI_IFACE managed no
    ip addr flush dev $WIFI_IFACE
    ip link set $WIFI_IFACE up
    ip link set $WIFI_IFACE master $BRIDGE_NAME
    echo "$WIFI_IFACE up, with master $BRIDGE_NAME"
    
    echo "Configure access point. Your current hostapd configs will be at /root/hostapd.conf.bak and /etc/hostapd/hostapd.conf"
    pkill hostapd
    sleep 1
    cp /root/hostapd.conf /root/hostapd.conf.bak > /dev/null
    cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak
    echo "" > /etc/hostapd/hostapd.conf
    cat <<EOF > /root/hostapd.conf
interface=$WIFI_IFACE
bridge=$BRIDGE_NAME
ssid=$SSID
channel=$WIFI_CHANNEL
driver=nl80211
hw_mode=g
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
    cp /etc/default/hostapd /etc/default/hostapd.bak
    echo "DAEMON_CONF=\"/root/hostapd.conf\"" > /etc/default/hostapd
    hostapd -B /root/hostapd.conf
    echo "Wifi access point is ready."

fi


# Configure tor
# Bakc up current configs
echo "Configure Tor. Your current configs will be at /etc/tor/torrc.bak"
cp /etc/tor/torrc /etc/tor/torrc.bak
cat <<EOF > /etc/tor/torrc
# local socks proxy
SocksPort $TOR_SOCKS_PROXY_IP:$TOR_SOCKS_PORT
DNSPort $TOR_DNS_SERVER_IP:$TOR_DNS_PORT

RunAsDaemon 1 # can run at the background
AvoidDiskWrites 1 # less writes to ssd (disable logs)

MaxCircuitDirtiness 600 # use new exit node every [10 minutes]
CircuitBuildTimeout 10
NewCircuitPeriod 60 # new chain every minute
EOF

# Start/Restart tor
echo "Starting tor@default.service..."
systemctl restart tor@default.service
echo "tor@default.service is "
systemctl status tor@default.service | grep "Active\|Main PID"
echo "Checking if tor is listening port..."
if sudo netstat -plnt | grep 9050 | grep "LISTEN" 
    then echo "OK"
else
    echo "Cannot find tor on 9050 port. Please, configure /etc/tor/torrc file and check if tor is running."
    exit
fi

# Installing, configure and starting isc-dhcp-server
echo "Installing/updating isc-dhcp-server..."
apt install isc-dhcp-server -y
echo "Configure DHCP server. All current configs will be saved at /etc/dhcp/dhcpd.conf.bak"
cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak

cat <<EOF > /etc/dhcp/dhcpd.conf 
default-lease-time 600;
max-lease-time 7200;

subnet $DHCP_SUBNET netmask $DHCP_NETMASK {
 range $DHCP_USERS_RANGE;
 option routers $DHCP_ROUTERS;
 option domain-name-servers $DHCP_DNS;
}
EOF
echo "INTERFACESv4=\"$BRIDGE_NAME\"" > /etc/default/isc-dhcp-server

echo "Done. Restarting isc-dhcp-server"
systemctl restart isc-dhcp-server
echo "Checking: "
systemctl status isc-dhcp-server | grep "Active"



# fome fix for tcp sessions
cat <<EOF > /etc/sysctl.d/99-nfconntrack.conf
net.netfilter.nf_conntrack_tcp_timeout_established = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 10
net.netfilter.nf_conntrack_max = 65536
EOF

sysctl --system > /dev/null


# Starting RedSocks proxy server and configure it
echo "Baclup current configs to /etc/redsocks.conf"
cp /etc/redsocks.conf /etc/redsocks.conf.bak
echo "Creating new RedSocks config file..."
cat <<EOF > /etc/redsocks.conf
base {
    log_debug = off;
    log_info = on;
    log = "file:/var/log/redsocks.log";
    daemon = on;
    redirector = iptables;
}

redsocks { 
    local_ip = $REDSOCKS_IP; 
    local_port = $REDSOCKS_PORT; 

    ip = $TOR_SOCKS_PROXY_IP; 
    port = $TOR_SOCKS_PORT; 
    type = socks5; 
}
EOF
echo "Starting redsocks..."
pkill redsocks
systemctl restart redsocks
if pgrep redsocks > /dev/null; then
    echo "RedSocks is running."
else
    echo "RedSocks not started."
    exit 1
fi

# Configure NAT and ip forwarding
echo "Turn on ip forwarding."
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -p
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.bridge.bridge-nf-call-ip6tables=1

if [ $DELETE_OLD_IPTABLES_RULES = 1 ]; then
    echo "Deleting all current iptables rules."
    sudo iptables -F
    sudo iptables -X
    sudo iptables -t nat -F
    sudo iptables -t nat -X
    iptables -t nat -F REDSOCKS
    iptables -t nat -X REDSOCKS

    sudo iptables -t mangle -F
    sudo iptables -t mangle -X
    sudo iptables -t raw -F
    sudo iptables -t raw -X

    echo "Setting default iptables policies to ACCEPT for now."
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -t nat -P PREROUTING ACCEPT
    sudo iptables -t nat -P POSTROUTING ACCEPT
    sudo iptables -t nat -P OUTPUT ACCEPT
fi

echo "Configuring iptables..."
# create new table
iptables -t nat -N REDSOCKS

iptables -t nat -A POSTROUTING -o $GATEWAY_IFACE -j MASQUERADE
iptables -A FORWARD -i $BRIDGE_NAME -o $GATEWAY_IFACE -j ACCEPT
iptables -A FORWARD -i $GATEWAY_IFACE -o $BRIDGE_NAME -m state --state ESTABLISHED,RELATED -j ACCEPT

# do not proxy local trafic
for netw in $LOCAL_NETWORKS
do
	iptables -t nat -A REDSOCKS -d $netw -j RETURN
done

# waiting for starting tor
sleep 10
TOR_UID=$(id -u debian-tor)
REDSOCKS_UID=$(id -u redsocks)
echo "Tor ID: $TOR_UID, Redsocks ID: $REDSOCKS_UID"
iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
iptables -t nat -A OUTPUT -m owner --uid-owner "$REDSOCKS_UID" -j RETURN


# REDSOCKS chain rules
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports $REDSOCKS_PORT
iptables -t nat -A REDSOCKS -p udp --dport 53 -j REDIRECT --to-ports $TOR_DNS_PORT

# redirecting ONLY TCP trafic to REDSOCKS chain
iptables -t nat -A PREROUTING -p tcp -i $BRIDGE_NAME -j REDSOCKS
#iptables -t nat -A OUTPUT -p tcp -j REDSOCKS

# block any other trafic
iptables -t raw -A PREROUTING -i $BRIDGE_NAME -p udp ! --dport 53 -j DROP
# block any other dns servers except local tor dns
iptables -t raw -A PREROUTING -i $BRIDGE_NAME -p udp --dport 53 -d $DHCP_LOCAL_IP -j ACCEPT
iptables -t raw -A PREROUTING -i $BRIDGE_NAME -p udp --dport 53 -j DROP
# block ICMP trafic
iptables -t raw -A PREROUTING -i $BRIDGE_NAME -p icmp -j DROP
iptables -t raw -A OUTPUT -o $BRIDGE_NAME -p icmp -j DROP



echo "Done. NAT is working."

sleep infinity

# do smth to close script
