# Onion access point

The script sets up a secure local network (with WiFi access point optional), which routes all TCP and DNS trafic throught TOR (The onion network). Any other trafic like UDP and ICMP will be blocked to maintain privacy and anonymity.

## Features
- Creates a wireless access point using `hostapd`
- Bridges traffic from wired and wireless interfaces
- Configures a DHCP server (`isc-dhcp-server`)
- Redirects all TCP traffic through Tor via `redsocks`
- Blocks all UDP and ICMP traffic except Tor-compatible DNS
- Automatically sets up NAT and iptables rules
- Isolates and anonymizes client traffic

## Requirements
- Linux system with root privileges
- Network interfaces:
  - At least one upstream (e.g., `enp4s0`)
  - One or more wired or wireless interface for local network
- Installed dependencies:
  - `tor`
  - `redsocks`
  - `hostapd`
  - `isc-dhcp-server`
- 'git' for installation process

## Install
1) Install dependencies
```
sudo apt install tor redsocks hostapd isc-dhcp-server git
```
2) Clone script using <code>git clone URL</code>
3) Change current dirrectory with <code>cd tor_access_point</code>
4) Change script's rights
```
chmod +x main.sh
```
5) Start script as root
```
sudo ./main.sh
```


