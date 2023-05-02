#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN='\033[0m'

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "Note: Please run the script under the root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
    fi
done

[[ -z $SYSTEM ]] && red "The current VPS system is not supported, please use a mainstream operating system" && exit 1

# Detect VPS processor architecture
archAffix() {
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        s390x) echo 's390x' ;;
        *) red "Unsupported CPU architecture!" && exit 1 ;;
    esac
}

install_base(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo tar openssl
}

install_singbox(){
    install_base

    last_version=$(curl -s https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | sed -n 4p | tr -d ',"' | awk '{print $1}')
    if [[ -z $last_version ]]; then
        red "Failed to obtain version information, please check the network status of the VPS!"
        exit 1
    fi

    if [[ $SYSTEM == "CentOS" ]]; then
        wget https://github.com/SagerNet/sing-box/releases/download/v"$last_version"/sing-box_"$last_version"_linux_$(archAffix).rpm -O sing-box.rpm
        rpm -ivh sing-box.rpm
        rm -f sing-box.rpm
    else
        wget https://github.com/SagerNet/sing-box/releases/download/v"$last_version"/sing-box_"$last_version"_linux_$(archAffix).deb -O sing-box.deb
        dpkg -i sing-box.deb
        rm -f sing-box.deb
    fi

    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        green "Sing-box Successful installation！"
    else
        red "Sing-box installation failed！"
        exit 1
    fi

    # Ask user about Reality port, UUID and fallback domain name
    read -p "Set Sing-box port [1-65535] (Enter will randomly assign port):" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} The port is already occupied by another program, please change the port and try again！"
            read -p "Set Sing-box port [1-65535] (Enter will randomly assign port):" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done
    read -rp "Please enter the UUID [can be left blank for script generation]: " UUID
    [[ -z $UUID ]] && UUID=$(sing-box generate uuid)
    read -rp "Please enter the domain name [default Microsoft official website] for configuration fallback: " dest_server
    [[ -z $dest_server ]] && dest_server="www.microsoft.com"

    # Reality short-id
    short_id=$(openssl rand -hex 8)

    # Reality public and private keys
    keys=$(sing-box generate reality-keypair)
    private_key=$(echo $keys | awk -F " " '{print $2}')
    public_key=$(echo $keys | awk -F " " '{print $4}')

    # Delete the default configuration file and write it into the Reality configuration
    rm -f /etc/sing-box/config.json
    cat << EOF > /etc/sing-box/config.json
{
    "log": {
        "level": "trace",
        "timestamp": true
    },
    "inbounds": [
        {
            "type": "vless",
            "tag": "vless-in",
            "listen": "::",
            "listen_port": $port,
            "sniff": true,
            "sniff_override_destination": true,
            "users": [
                {
                    "uuid": "$UUID",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "$dest_server",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$dest_server",
                        "server_port": 443
                    },
                    "private_key": "$private_key",
                    "short_id": [
                        "$short_id"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        }
    ],
    "route": {
        "rules": [
            {
                "geoip": "cn",
                "outbound": "block"
            },
            {
                "geosite": "category-ads-all",
                "outbound": "block"
            }
        ],
        "final": "direct"
    }
}
EOF

    warp_v4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warp_v6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warp_v4 =~ on|plus ]] || [[ $warp_v6 =~ on|plus ]]; then
        systemctl stop warp-go >/dev/null 2>&1
        systemctl disable warp-go >/dev/null 2>&1
        wg-quick down wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf >/dev/null 2>&1
        IP=$(expr "$(curl -ks4m8 -A Mozilla https://api.ip.sb/geoip)" : '.*ip\":[ ]*\"\([^"]*\).*') || IP=$(expr "$(curl -ks6m8 -A Mozilla https://api.ip.sb/geoip)" : '.*ip\":[ ]*\"\([^"]*\).*')
        systemctl start warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        wg-quick start wgcf >/dev/null 2>&1
        systemctl enable wg-quick@wgcf >/dev/null 2>&1
    else
        IP=$(expr "$(curl -ks4m8 -A Mozilla https://api.ip.sb/geoip)" : '.*ip\":[ ]*\"\([^"]*\).*') || IP=$(expr "$(curl -ks6m8 -A Mozilla https://api.ip.sb/geoip)" : '.*ip\":[ ]*\"\([^"]*\).*')
    fi

    mkdir /root/sing-box >/dev/null 2>&1

    # Generate vless sharing link and Clash Meta configuration file
    share_link="vless://$UUID@$IP:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$dest_server&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#Misaka-Reality"
    echo ${share_link} > /root/sing-box/share-link.txt
    cat << EOF > /root/sing-box/clash-meta.yaml
mixed-port: 7890
external-controller: 127.0.0.1:9090
allow-lan: false
mode: rule
log-level: debug
ipv6: true

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
    - 114.114.114.114

proxies:
  - name: Misaka-Reality
    type: vless
    server: $IP
    port: $port
    uuid: $UUID
    network: tcp
    tls: true
    udp: true
    xudp: true
    flow: xtls-rprx-vision
    servername: $dest_server
    reality-opts:
      public-key: "$public_key"
      short-id: "$short_id"
    client-fingerprint: chrome

proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Misaka-Reality
      
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
EOF

    systemctl start sing-box >/dev/null 2>&1
    systemctl enable sing-box >/dev/null 2>&1

    if [[ -n $(systemctl status sing-box 2>/dev/null | grep -w active) && -f '/etc/sing-box/config.json' ]]; then
        green "Sing-box service started successfully"
    else
        red "The Sing-box service failed to start. Please run systemctl status sing-box to view the service status and give feedback. The script exits" && exit 1
    fi

    yellow "The following is the share link of Sing-box Reality, and it has been saved to /root/sing-box/share-link.txt"
    red $share_link
    yellow "Clash Meta configuration file saved to /root/sing-box/clash-meta.yaml"
}

uninstall_singbox(){
    systemctl stop sing-box >/dev/null 2>&1
    systemctl disable sing-box >/dev/null 2>&1
    ${PACKAGE_UNINSTALL} sing-box
    rm -rf /root/sing-box
    green "Sing-box has been completely uninstalled successfully!"
}

start_singbox(){
    systemctl start sing-box
    systemctl enable sing-box >/dev/null 2>&1
}

stop_singbox(){
    systemctl stop sing-box
    systemctl disable sing-box >/dev/null 2>&1
}

changeport(){
    old_port=$(cat /etc/sing-box/config.json | grep listen_port | awk -F ": " '{print $2}' | sed "s/,//g")

    read -p "Set Sing-box port [1-65535] (Enter will randomly assign port):" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "The ${RED} $port ${PLAIN} port is already occupied by another program, please change the port and try again!"
            read -p "Set Sing-box port [1-65535] (Enter will randomly assign port):" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "s/$old_port/$port/g" /etc/sing-box/config.json
    sed -i "s/$old_port/$port/g" /root/sing-box/share-link.txt
    stop_singbox && start_singbox

    green "Sing-box port has been modified successfully!"
}

changeuuid(){
    old_uuid=$(cat /etc/sing-box/config.json | grep uuid | awk -F ": " '{print $2}' | sed "s/\"//g" | sed "s/,//g")

    read -rp "Please enter the UUID [can be left blank for script generation]: " UUID
    [[ -z $UUID ]] && UUID=$(sing-box generate uuid)

    sed -i "s/$old_uuid/$UUID/g" /etc/sing-box/config.json
    sed -i "s/$old_uuid/$UUID/g" /root/sing-box/share-link.txt
    stop_singbox && start_singbox

    green "Sing-box UUID has been modified successfully!"
}

changedest(){
    old_dest=$(cat /etc/sing-box/config.json | grep server | sed -n 1p | awk -F ": " '{print $2}' | sed "s/\"//g" | sed "s/,//g")

    read -rp "Please enter the domain name [default Microsoft official website] for configuration fallback: " dest_server
    [[ -z $dest_server ]] && dest_server="www.microsoft.com"

    sed -i "s/$old_dest/$dest_server/g" /etc/sing-box/config.json
    sed -i "s/$old_dest/$dest_server/g" /root/sing-box/share-link.txt
    stop_singbox && start_singbox

    green "Sing-box fallback domain has been modified successfully!"
}

change_conf(){
    green "Sing-box configuration change options are as follows:"
    echo -e " ${GREEN}1.${PLAIN} modify port"
    echo -e " ${GREEN}2.${PLAIN} modify UUID"
    echo -e " ${GREEN}3.${PLAIN} modify fallback domain name"
    echo ""
    read -p "Please select action [1-3]: " confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changeuuid ;;
        3 ) changedest ;;
        * ) exit 1 ;;
    esac
}

menu(){
    clear
    echo "#############################################################"
    echo -e "# ${RED}Sing-box Reality one-click installation script ${PLAIN}             #"
    echo -e "# ${GREEN}Author ${PLAIN}: MisakaNo's Small Broken Site                     #"
    echo -e "# ${GREEN}blog${PLAIN}: https://blog.misaka.rest                            #"
    echo -e "# ${GREEN}GitHub project${PLAIN}: https://github.com/Misaka-blog               #"
    echo -e "# ${GREEN}GitLab project${PLAIN}: https://gitlab.com/Misaka-blog               #"
    echo -e "# ${GREEN}Telegram channel${PLAIN}: https://t.me/misakanocchannel              #"
    echo -e "# ${GREEN}Telegram group${PLAIN}: https://t.me/misakanoc                     #"
    echo -e "# ${GREEN}YouTube channel${PLAIN}: https://www.youtube.com/@misaka-blog        #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} install Sing-box Reality"
    echo -e " ${GREEN}2.${PLAIN} uninstall Sing-box Reality"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} start Sing-box Reality"
    echo -e " ${GREEN}4.${PLAIN} stop Sing-box Reality"
    echo -e " ${GREEN}5.${PLAIN} restart Sing-box Reality"
    echo " -------------"
    echo -e " ${GREEN}6.${PLAIN} modify Sing-box Reality configuration"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} quit"
    echo ""
    read -rp " please enter options [0-6] ：" answer
    case $answer in
        1) install_singbox ;;
        2) uninstall_singbox ;;
        3) start_singbox ;;
        4) stop_singbox ;;
        5) stop_singbox && start_singbox ;;
        6) change_conf ;;
        *) red "Please enter the correct option [0-6]！" && exit 1 ;;
    esac
}

menu
