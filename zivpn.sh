#!/bin/bash

# ==============================================================================
# 🧩 ZIVPN MASTER MANAGER - ALL-IN-ONE
# ==============================================================================
# Database URL dari GitHub Anda
URL_DB="https://raw.githubusercontent.com/Votingpemilihanketuaosis/dbsnew2/refs/heads/main/keys.json"

# Warna
RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
CYAN="\e[1;36m"
MAGENTA="\e[1;35m"
RESET="\e[0m"

# File Konfigurasi Lokal
CONFIG_FILE="/etc/zivpn/config.json"
USER_DB="/etc/zivpn/users.db"
CONF_FILE="/etc/zivpn.conf"

# ------------------------------------------------------------------------------
# 🔐 FUNGSI LOGIN (Sesuai Database GitHub)
# ------------------------------------------------------------------------------
cek_akses() {
    clear
    echo -e "${CYAN}==========================================${RESET}"
    echo -e "${CYAN}      LOGIN SISTEM INSTALLER ZIVPN        ${RESET}"
    echo -e "${CYAN}==========================================${RESET}"
    read -p "👤 Username: " user_input
    read -s -p "🔑 Password: " pass_input
    echo -e "\n"

    echo -e "${YELLOW}🔍 Memverifikasi akun dan lisensi...${RESET}"
    DB=$(curl -sL "$URL_DB")
    
    # Mencari username:password:expired di file keys.json
    USER_DATA=$(echo "$DB" | grep "^$user_input:$pass_input:")

    if [ -z "$USER_DATA" ]; then
        echo -e "${RED}❌ Login Gagal! Akun tidak ditemukan.${RESET}"
        exit 1
    fi

    EXP_DATE=$(echo "$USER_DATA" | cut -d':' -f3)
    TODAY=$(date +%Y-%m-%d)

    if [[ "$TODAY" > "$EXP_DATE" ]]; then
        echo -e "${RED}❌ Masa aktif akun Anda telah habis pada $EXP_DATE.${RESET}"
        exit 1
    else
        echo -e "${GREEN}✅ Login Berhasil! Masa aktif hingga: $EXP_DATE${RESET}"
        sleep 2
    fi
}

# ------------------------------------------------------------------------------
# 📥 FUNGSI INSTALASI (AMD/ARM)
# ------------------------------------------------------------------------------
jalankan_install() {
    clear
    echo -e "${CYAN}PILIH ARSITEKTUR VPS:${RESET}"
    echo -e "1) AMD64 (VPS Biasa / DigitalOcean / Vultr)"
    echo -e "2) ARM64 (Oracle Cloud / Ampere)"
    read -p "Pilihan [1/2]: " arch_opt

    if [ "$arch_opt" == "1" ]; then
        TIPE="AMD64"
        URL_BIN="https://github.com/ChristopherAGT/zivpn-tunnel-udp/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
    else
        TIPE="ARM64"
        URL_BIN="https://github.com/ChristopherAGT/zivpn-tunnel-udp/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
    fi

    echo -e "${YELLOW}🚀 Memulai Instalasi $TIPE...${RESET}"
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install wget curl openssl iptables ufw jq -y

    systemctl stop zivpn.service &>/dev/null
    wget -q "$URL_BIN" -O /usr/local/bin/zivpn
    chmod +x /usr/local/bin/zivpn

    mkdir -p /etc/zivpn
    wget -q https://raw.githubusercontent.com/ChristopherAGT/zivpn-tunnel-udp/main/config.json -O /etc/zivpn/config.json

    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=Jakarta/L=Jakarta/O=ZIVPN/OU=IT/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

    # Create Service
    cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP VPN Server ($TIPE)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service
    
    # Apply IPTables Fix
    fix_iptables
    
    echo -e "${GREEN}✅ Instalasi Selesai!${RESET}"
    read -p "Tekan Enter untuk kembali..."
}

# ------------------------------------------------------------------------------
# 🛠️ FUNGSI FIX IPTABLES (Persisten)
# ------------------------------------------------------------------------------
fix_iptables() {
    echo -e "${CYAN}🔍 Mengonfigurasi IPTables Persisten...${RESET}"
    iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    
    iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    
    if command -v ufw &>/dev/null; then
        ufw allow 6000:19999/udp &>/dev/null
        ufw allow 5667/udp &>/dev/null
    fi

    if ! dpkg -s iptables-persistent &>/dev/null; then
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        apt-get install -y iptables-persistent &>/dev/null
    fi
    iptables-save > /etc/iptables/rules.v4
    echo -e "${GREEN}✅ IPTables berhasil diperbaiki.${RESET}"
}

# ------------------------------------------------------------------------------
# 🧹 FUNGSI UNINSTALL (Hapus Total)
# ------------------------------------------------------------------------------
hapus_total() {
    echo -e "${RED}⚠️  Menghapus ZIVPN dari sistem...${RESET}"
    systemctl stop zivpn.service &>/dev/null
    systemctl disable zivpn.service &>/dev/null
    rm -f /etc/systemd/system/zivpn.service
    rm -rf /etc/zivpn
    rm -f /usr/local/bin/zivpn
    rm -f /usr/local/bin/menu-zivpn
    echo -e "${GREEN}✅ Semua komponen telah dihapus.${RESET}"
    read -p "Tekan Enter untuk kembali..."
}

# ------------------------------------------------------------------------------
# 📱 MENU PANEL PENGGUNA (Pindahkan ke Internal)
# ------------------------------------------------------------------------------
panel_pengguna() {
    # Memanggil file panel yang sudah ada atau menjalankan fungsinya di sini
    # Jika file panel-udp-zivpn.sh sudah terinstall, jalankan:
    if [ -f "/usr/local/bin/menu-zivpn" ]; then
        /usr/local/bin/menu-zivpn
    else
        echo -e "${RED}❌ Panel belum terinstall. Silakan jalankan instalasi terlebih dahulu.${RESET}"
        sleep 2
    fi
}

# ------------------------------------------------------------------------------
# 📋 MENU UTAMA (Bahasa Indonesia)
# ------------------------------------------------------------------------------
menu_utama() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║           ZIVPN UDP MASTER MANAGER               ║${RESET}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════╣${RESET}"
        echo -e "║ [1] 📥 Install ZIVPN UDP (AMD/ARM)               ║"
        echo -e "║ [2] 🧩 Buka Panel Manajemen Pengguna             ║"
        echo -e "║ [3] 🔧 Perbaiki IPTables (Fix Reset)             ║"
        echo -e "║ [4] 🗑️  Hapus Total ZIVPN (Uninstall)            ║"
        echo -e "║ [5] 📋 Cek Status Layanan                        ║"
        echo -e "║ [0] 🚪 Keluar                                    ║"
        echo -e "${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
        read -p "📌 Pilih opsi: " opt
        
        case $opt in
            1) jalankan_install ;;
            2) panel_pengguna ;;
            3) fix_iptables; read -p "Selesai. Enter...";;
            4) hapus_total ;;
            5) systemctl status zivpn.service; read -p "Enter...";;
            0) exit ;;
            *) echo -e "${RED}Opsi tidak valid!${RESET}"; sleep 1 ;;
        esac
    done
}

# Jalankan Login lalu Menu
cek_akses
menu_utama
