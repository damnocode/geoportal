#!/bin/bash

# Script untuk instalasi Palapa V5
# Dibuat berdasarkan dokumentasi Instalasi Palapa V5

# Warna untuk output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Fungsi untuk menampilkan pesan
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fungsi untuk menunggu pengguna menekan tombol
pause() {
    read -p "Tekan [Enter] untuk melanjutkan..."
}

# Fungsi untuk memastikan perintah berhasil dijalankan
ensure_success() {
    if [ $? -ne 0 ]; then
        print_error "Perintah gagal dijalankan: $1"
        print_warning "Instalasi tidak lengkap. Jalankan script kembali untuk melanjutkan."
        exit 1
    else
        print_message "Berhasil: $1"
    fi
}

# Fungsi untuk mendapatkan input dari pengguna
get_input() {
    local prompt="$1"
    local default="$2"
    local value=""
    
    if [ -z "$default" ]; then
        read -p "$prompt: " value
    else
        read -p "$prompt [$default]: " value
        value=${value:-$default}
    fi
    
    echo "$value"
}

# Fungsi untuk memeriksa apakah user memiliki izin sudo
check_sudo() {
    if sudo -n true 2>/dev/null; then
        print_message "Izin sudo tersedia"
        return 0
    else
        print_warning "Anda memerlukan izin sudo untuk menginstal beberapa komponen"
        print_warning "Silakan jalankan 'sudo -v' untuk memverifikasi akses sudo sebelum melanjutkan"
        if sudo -v; then
            print_message "Izin sudo dikonfirmasi"
            return 0
        else
            print_error "Tidak dapat memperoleh izin sudo. Silakan hubungi administrator sistem Anda"
            exit 1
        fi
    fi
}

# Fungsi untuk memeriksa dan membuat direktori config
setup_config_dir() {
    # Buat direktori konfigurasi jika belum ada
    if [ ! -d "$HOME/.palapa" ]; then
        mkdir -p "$HOME/.palapa"
    fi
}

# Fungsi untuk menyimpan variabel konfigurasi
save_config() {
    local name=$1
    local value=$2
    echo "export ${name}=\"${value}\"" >> "$HOME/.palapa/config"
}

# Fungsi untuk memuat konfigurasi yang sudah ada
load_config() {
    if [ -f "$HOME/.palapa/config" ]; then
        source "$HOME/.palapa/config"
        print_message "Memuat konfigurasi yang tersimpan"
    fi
}

# Fungsi untuk memeriksa apakah Docker sudah diinstal
check_docker() {
    if command -v docker &> /dev/null; then
        if docker --version &> /dev/null; then
            print_message "Docker sudah terinstal"
            return 0
        fi
    fi
    return 1
}

# Fungsi untuk menambahkan user ke grup docker
add_user_to_docker_group() {
    local current_user=$(whoami)
    
    # Periksa apakah user sudah di grup docker
    if groups $current_user | grep -q '\bdocker\b'; then
        print_message "User $current_user sudah terdaftar dalam grup docker"
    else
        print_message "Menambahkan user $current_user ke grup docker..."
        sudo usermod -aG docker $current_user
        ensure_success "Menambahkan user ke grup docker"
        print_warning "Perubahan grup akan aktif setelah login ulang"
        print_warning "Untuk mengaktifkan grup tanpa login ulang, jalankan: 'newgrp docker'"
        
        # Sarankan newgrp untuk mengaktifkan grup langsung
        if command -v newgrp &> /dev/null; then
            print_message "Mengaktifkan grup docker untuk sesi saat ini..."
            sg docker -c "echo Grup docker aktif untuk sesi ini"
        fi
    fi
}

# Fungsi untuk memeriksa dan menginstal paket yang diperlukan
ensure_package_installed() {
    local package=$1
    if ! dpkg -l | grep -q "ii  $package "; then
        print_message "Menginstal $package..."
        sudo apt-get install -y $package
        ensure_success "Instalasi $package"
    else
        print_message "$package sudah terinstal"
    fi
}

# Fungsi untuk menjalankan Docker tanpa sudo
run_docker() {
    local cmd=$1
    
    # Coba jalankan tanpa sudo dulu
    if docker $cmd &>/dev/null; then
        docker $cmd
    else
        # Jika gagal, gunakan sudo
        print_warning "Menjalankan docker dengan sudo (pertimbangkan untuk menambahkan user ke grup docker)"
        sudo docker $cmd
    fi
}

# Fungsi untuk memeriksa dan membuat variabel password yang aman
generate_secure_password() {
    local length=16
    local password=""
    
    # Jika tersedia, gunakan /dev/urandom
    if [ -e /dev/urandom ]; then
        password=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&*()_+' | head -c $length)
    else
        # Fallback ke metode kurang aman
        password=$(date +%s | sha256sum | base64 | head -c $length)
    fi
    
    echo $password
}

# Periksa OS
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" == "ubuntu" ]; then
            print_message "Sistem operasi: Ubuntu $VERSION_ID"
            return 0
        else
            print_warning "Sistem operasi bukan Ubuntu. Instalasi mungkin tidak berjalan dengan baik."
            read -p "Lanjutkan instalasi? (y/n): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                exit 1
            fi
        fi
    else
        print_warning "Tidak dapat mendeteksi sistem operasi. Instalasi mungkin tidak berjalan dengan baik."
        read -p "Lanjutkan instalasi? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            exit 1
        fi
    fi
}

clean_docker_resources() {
    print_message "Membersihkan resources Docker yang ada..."
    
    # Hentikan dan hapus semua container
    print_message "Menghentikan dan menghapus semua container..."
    docker ps -aq | xargs -r docker stop
    docker ps -aq | xargs -r docker rm
    
    # Hapus semua volume
    print_message "Menghapus semua volume Docker..."
    docker volume ls -q | xargs -r docker volume rm
    
    # Hapus semua network kustom (kecuali bridge, host, none)
    print_message "Menghapus semua network Docker kustom..."
    docker network ls -q | grep -v "bridge\|host\|none" | xargs -r docker network rm
    
    # Bersihkan resources (tanpa -a agar image tidak terhapus)
    print_message "Membersihkan resources Docker lainnya..."
    docker system prune --volumes -f
    
    # Hapus direktori instalasi lama jika ada
    if [ -d "palapaV5" ]; then
        print_message "Menghapus direktori instalasi lama..."
        sudo rm -rf palapaV5
    fi
    
    print_message "Pembersihan selesai! Sistem siap untuk instalasi baru."
}

# Fungsi untuk konfigurasi file web.xml
configure_web_xml() {
    print_message "Mengkonfigurasi file web.xml..."
    
    # Copy template web.xml
    cd config/web/
    cp ../../extras/web.xml web.xml
    ensure_success "Menyalin file web.xml dari template"
    
    # Ganti domain di web.xml
    sed -i "s|<param-value>https://localhost/geoserver/</param-value>|<param-value>https://$DOMAIN/geoserver/</param-value>|g" web.xml
    ensure_success "Mengganti domain di param-value pertama"
    
    sed -i "s|<param-value>localhost</param-value>|<param-value>$DOMAIN</param-value>|g" web.xml
    ensure_success "Mengganti domain di param-value kedua"
    
    # Copy web.xml ke container geoserver
    docker cp web.xml geoportal-palapa-geoserver:/usr/local/tomcat/webapps/geoserver/WEB-INF/
    ensure_success "Menyalin web.xml ke container geoserver"
    
    print_message "Konfigurasi web.xml berhasil diselesaikan"
}

# Fungsi untuk mengganti konfigurasi SSL di httpd.conf
configure_ssl_certs() {
    local http_conf_file="$1"
    
    # Ganti nama domain
    sed -i "s/ServerName your-domain.com/ServerName $DOMAIN/g" "$http_conf_file"
    ensure_success "Mengganti nama domain di file konfigurasi"
    
    # Tanya tentang file sertifikat
    local ssl_cert_file=$(read -p "Masukkan nama file SSLCertificateFile: " input; echo $input)
    local ssl_key_file=$(read -p "Masukkan nama file SSLCertificateKeyFile: " input; echo $input)
    local ssl_chain_file=$(read -p "Masukkan nama file SSLCertificateChainFile [kosongkan jika tidak ada]: " input; echo $input)
    
    # Ganti path sertifikat SSL
    if [ ! -z "$ssl_cert_file" ]; then
        sed -i "s|SSLCertificateFile.*|SSLCertificateFile      \"/usr/local/apache2/conf/ssl/$ssl_cert_file\"|g" "$http_conf_file"
        ensure_success "Mengganti SSLCertificateFile"
    fi
    
    if [ ! -z "$ssl_key_file" ]; then
        sed -i "s|SSLCertificateKeyFile.*|SSLCertificateKeyFile   \"/usr/local/apache2/conf/ssl/$ssl_key_file\"|g" "$http_conf_file"
        ensure_success "Mengganti SSLCertificateKeyFile"
    fi
    
    if [ ! -z "$ssl_chain_file" ]; then
        sed -i "s|SSLCertificateChainFile.*|SSLCertificateChainFile \"/usr/local/apache2/conf/ssl/$ssl_chain_file\"|g" "$http_conf_file"
        ensure_success "Mengganti SSLCertificateChainFile"
    else
        # Comment out SSLCertificateChainFile if not provided
        sed -i "s|SSLCertificateChainFile.*|# SSLCertificateChainFile \"/usr/local/apache2/conf/ssl/ca_bundle.crt\"|g" "$http_conf_file"
        ensure_success "Menonaktifkan SSLCertificateChainFile"
    fi
    
    print_message "Konfigurasi SSL berhasil diperbarui"
    print_message "Silakan masukkan file SSL Anda ke dalam folder /home/$(whoami)/palapaV5/ssl/"
    
    # Buat direktori SSL jika belum ada
    mkdir -p "/home/$(whoami)/palapaV5/ssl/"
    ensure_success "Membuat direktori SSL"
    
    pause
}

# ================================
# MULAI SCRIPT UTAMA
# ================================

# Setup direktori konfigurasi
setup_config_dir

# Muat konfigurasi yang tersimpan (jika ada)
load_config

# Konfirmasi sebelum memulai instalasi
print_message "=== INSTALASI PALAPA V5 ==="
print_message "Skrip ini akan menginstal semua komponen yang diperlukan untuk menjalankan Palapa V5."
print_message "Pastikan sistem Anda adalah Ubuntu dan memiliki akses internet."
pause

# Periksa OS
check_os

# Periksa izin sudo
check_sudo

# Bersihkan Docker resources yang ada
read -p "Apakah Anda ingin membersihkan semua resources Docker yang ada? (y/n): " clean_docker
if [[ "$clean_docker" == "y" || "$clean_docker" == "Y" ]]; then
    clean_docker_resources
fi

# 1. INSTALL DOCKER
print_message "=== 1. MENGECEK DAN MENGINSTAL DOCKER ==="

# Periksa apakah Docker sudah diinstal
if check_docker; then
    print_message "Docker sudah terinstal"
    docker_version=$(docker --version)
    print_message "Docker version: $docker_version"
else
    # Update sistem
    print_message "Memperbarui sistem..."
    sudo apt-get update
    ensure_success "Pembaruan sistem"
    
    # Install paket yang diperlukan
    print_message "Menginstal paket yang diperlukan..."
    ensure_package_installed "ca-certificates"
    ensure_package_installed "curl"
    ensure_package_installed "gnupg"
    
    # Setup repositori Docker
    print_message "Menambahkan repositori Docker..."
    sudo install -m 0755 -d /etc/apt/keyrings
    
    # Menangani error jika direktori sudah ada
    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    else
        print_message "File kunci Docker sudah ada"
    fi
    
    # Tambahkan repositori Docker
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    ensure_success "Penambahan repositori Docker"
    
    # Install Docker packages
    print_message "Menginstal Docker..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ensure_success "Instalasi Docker"
    
    # Verifikasi instalasi Docker
    print_message "Verifikasi instalasi Docker..."
    sudo docker run hello-world
    ensure_success "Verifikasi Docker"
    
    docker_version=$(docker --version)
    print_message "Docker version: $docker_version"
fi

# Tambahkan user ke grup docker
add_user_to_docker_group

# Cek versi Git
ensure_package_installed "git"
git_version=$(git --version)
print_message "Git version: $git_version"

# 2. INSTALL NVM
print_message "=== 2. MENGINSTAL NVM ==="

# Periksa apakah NVM sudah diinstal
if [ -d "$HOME/.nvm" ] && command -v nvm &> /dev/null; then
    print_message "NVM sudah terinstal"
else
    print_message "Mengunduh dan menginstal NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    ensure_success "Pengunduhan NVM"
    
    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # Verifikasi instalasi NVM
    if command -v nvm &> /dev/null; then
        print_message "NVM berhasil diinstal"
    else
        print_warning "NVM tidak terdeteksi setelah instalasi"
        print_message "Reload shell profile..."
        source "$HOME/.bashrc"
        if command -v nvm &> /dev/null; then
            print_message "NVM berhasil diinstal setelah reload"
        else
            print_error "Gagal memuat NVM. Silakan restart terminal atau jalankan: source ~/.bashrc"
        fi
    fi
fi

# Verifikasi instalasi NVM
nvm_version=$(nvm --version 2>/dev/null || echo "NVM belum terinstal atau dimuat")
print_message "NVM version: $nvm_version"

# Install Node.js LTS
print_message "Menginstal Node.js LTS..."
nvm install --lts
ensure_success "Instalasi Node.js"
node_version=$(node --version)
print_message "Node.js version: $node_version"

# 3. INSTALL NANO
print_message "=== 3. MENGINSTAL NANO ==="
ensure_package_installed "nano"
nano_version=$(nano --version | head -n 1)
print_message "Nano version: $nano_version"

# 4. CLONE REPO PALAPA V5
print_message "=== 4. MENGUNDUH REPOSITORY PALAPA V5 ==="

# Periksa apakah direktori palapaV5 sudah ada
if [ -d "palapaV5" ]; then
    print_message "Direktori palapaV5 sudah ada"
    read -p "Apakah Anda ingin meng-update repository? (y/n): " update_repo
    if [[ "$update_repo" == "y" || "$update_repo" == "Y" ]]; then
        # Selalu minta token untuk update
        GITHUB_TOKEN=$(get_input "Masukkan token GitHub" "")
        save_config "GITHUB_TOKEN" "$GITHUB_TOKEN"

        cd palapaV5
        # Pastikan remote URL pakai token
        git remote set-url origin https://${GITHUB_TOKEN}@github.com/BIG-Indonesia/palapaV5.git
        git pull
        ensure_success "Update repository"
        cd ..
    fi
else
    # Selalu minta token untuk clone baru
    GITHUB_TOKEN=$(get_input "Masukkan token GitHub" "")
    save_config "GITHUB_TOKEN" "$GITHUB_TOKEN"
    
    print_message "Mengunduh repository..."
    git -c http.sslVerify=false clone -b palapaV5.1 --single-branch https://${GITHUB_TOKEN}@github.com/BIG-Indonesia/palapaV5.git palapaV5
    ensure_success "Clone repository branch palapaV5.1"
fi

# Masuk ke direktori palapaV5
cd palapaV5 || exit
print_message "Masuk ke direktori palapaV5"

# Setup ENV
print_message "Mengatur file konfigurasi .env..."
# Copy file .env jika belum ada
if [ ! -f .env ]; then
    cp .env.example .env
    ensure_success "Copy file .env"
fi

# Mendapatkan konfigurasi env
DOMAIN=$(get_input "Masukkan domain server tanpa https/http (contoh: palapa.id atau localhost)" "localhost")
save_config "DOMAIN" "$DOMAIN"

# Tanya apakah sudah menggunakan domain publik
USE_HTTPS=$(get_input "Apakah domain sudah aktif dan menggunakan HTTPS? (y/n)" "n")
save_config "USE_HTTPS" "$USE_HTTPS"

# Set domain URL berdasarkan input
if [[ "$USE_HTTPS" == "y" || "$USE_HTTPS" == "Y" ]]; then
    DOMAIN_URL="https://$DOMAIN"
else
    DOMAIN_URL="http://$DOMAIN"
fi
save_config "DOMAIN_URL" "$DOMAIN_URL"

# Konfigurasi password database dan layanan
echo "Konfigurasi password database dan layanan:"

# PostgreSQL App Password
read -p "Masukkan PostgreSQL App password (kosongkan untuk generate otomatis): " user_postgres_app_pwd
if [ -z "$user_postgres_app_pwd" ]; then
    POSTGRES_APP_PASSWORD=$(generate_secure_password)
    print_message "Generated PostgreSQL App password: $POSTGRES_APP_PASSWORD"
else
    POSTGRES_APP_PASSWORD=$user_postgres_app_pwd
    print_message "Menggunakan PostgreSQL App password dari input pengguna"
fi
save_config "POSTGRES_APP_PASSWORD" "$POSTGRES_APP_PASSWORD"

# PostgreSQL Spasial Password
read -p "Masukkan PostgreSQL Spasial password (kosongkan untuk generate otomatis): " user_postgres_spasial_pwd
if [ -z "$user_postgres_spasial_pwd" ]; then
    POSTGRES_SPASIAL_PASSWORD=$(generate_secure_password)
    print_message "Generated PostgreSQL Spasial password: $POSTGRES_SPASIAL_PASSWORD"
else
    POSTGRES_SPASIAL_PASSWORD=$user_postgres_spasial_pwd
    print_message "Menggunakan PostgreSQL Spasial password dari input pengguna"
fi
save_config "POSTGRES_SPASIAL_PASSWORD" "$POSTGRES_SPASIAL_PASSWORD"

# GeoServer Admin Password
read -p "Masukkan GeoServer Admin password (kosongkan untuk generate otomatis): " user_geoserver_admin_pwd
if [ -z "$user_geoserver_admin_pwd" ]; then
    GEOSERVER_ADMIN_PASSWORD=$(generate_secure_password)
    print_message "Generated GeoServer Admin password: $GEOSERVER_ADMIN_PASSWORD"
else
    GEOSERVER_ADMIN_PASSWORD=$user_geoserver_admin_pwd
    print_message "Menggunakan GeoServer Admin password dari input pengguna"
fi
save_config "GEOSERVER_ADMIN_PASSWORD" "$GEOSERVER_ADMIN_PASSWORD"

# Edit file .env
sed -i "s|^DOMAIN=.*|DOMAIN=$DOMAIN_URL|" .env
sed -i "s|^DB_APP_CONNECTION_PASSWORD=.*|DB_APP_CONNECTION_PASSWORD=$POSTGRES_APP_PASSWORD|" .env
sed -i "s|^DB_SPASIAL_CONNECTION_PASSWORD=.*|DB_SPASIAL_CONNECTION_PASSWORD=$POSTGRES_SPASIAL_PASSWORD|" .env
sed -i "s|^GEOSERVER_ADMIN_PASSWORD=.*|GEOSERVER_ADMIN_PASSWORD=$GEOSERVER_ADMIN_PASSWORD|" .env

print_message "File .env telah dikonfigurasi"

# Build Docker
print_message "Membangun dan menjalankan container Docker..."
# Coba menjalankan docker compose tanpa sudo
if docker compose &>/dev/null; then
    docker compose up --build -d
else
    # Jika gagal, gunakan sudo
    print_warning "Menjalankan docker compose dengan sudo"
    sudo docker compose up --build -d
fi
ensure_success "Build Docker"

# Cek container Docker
print_message "Memeriksa container Docker..."
docker ps -a || sudo docker ps -a

# Menunggu container berjalan
print_message "Menunggu semua container berjalan..."
sleep 10

# Matikan container pycsw untuk di set
print_message "Mematikan container pycsw untuk konfigurasi..."
docker stop geoportal-palapa-pycsw || sudo docker stop geoportal-palapa-pycsw
ensure_success "Stop container pycsw"

# Edit konfigurasi URL
print_message "Mengatur konfigurasi URL untuk production..."
cd web/geoportal-react/src/config/
cp environment.js environment.js.backup

# Replace blok production
sed -i '/if (process.env.REACT_APP_ENV === "production") {/,/^}/c\
if (process.env.REACT_APP_ENV === "production") {\
  environment.baseUrl = "'"$DOMAIN_URL"'/main/";\
  environment.api = "'"$DOMAIN_URL"'/api/";\
  environment.csw = "'"$DOMAIN_URL"'/csw";\
  environment.geoserver = "'"$DOMAIN_URL"'/geoserver/";\
}' environment.js

ensure_success "Blok konfigurasi production berhasil diperbarui."

# Setup geoportal-react
print_message "Menyiapkan geoportal-react..."
cd ../../
cp .env.example .env

# Set env untuk React
react_env_type="production"

REACT_APP_SITE_KEY=$(get_input "Masukkan REACT_APP_RECAPTCHA_SITE_KEY untuk reCAPTCHA" "")
save_config "REACT_APP_RECAPTCHA_SITE_KEY" "$REACT_APP_SITE_KEY"

sed -i "s/^REACT_APP_ENV=.*/REACT_APP_ENV=$react_env_type/" .env
sed -i "s|^REACT_APP_RECAPTCHA_SITE_KEY=.*|REACT_APP_RECAPTCHA_SITE_KEY=$REACT_APP_SITE_KEY|" .env

ensure_success "Konfigurasi React env"

# Install dan build
print_message "Berikan izin folder react"

# Ambil path absolut dari script
SCRIPT_PATH="$(readlink -f "$0")"
CURRENT_DIR="$(dirname "$SCRIPT_PATH")"

# Cari direktori bernama 'palapaV5' ke atas
while [[ "$CURRENT_DIR" != "/" ]]; do
    if [[ "$(basename "$CURRENT_DIR")" == "palapaV5" ]]; then
        BASE_DIR="$CURRENT_DIR"
        break
    fi
    CURRENT_DIR="$(dirname "$CURRENT_DIR")"
done

# Jika tidak ditemukan
if [[ -z "$BASE_DIR" ]]; then
    echo "[ERROR] Direktori 'palapaV5' tidak ditemukan di atas script."
    exit 1
fi

# Set node path
NODE_PATH="$BASE_DIR"

# Hanya ubah permission jika bukan user root
if [ "$(id -u)" -ne 0 ]; then
  # Apply permissions since user is not root
  print_message "Mengatur izin folder node untuk user $USER..."
  sudo chown -R "$USER:$USER" "$NODE_PATH/"
  ensure_success "Izin folder node berhasil diatur untuk path: $NODE_PATH"
else
  # User is root, no need to change permissions
  echo "User adalah root, tidak perlu mengubah izin folder"
fi

print_message "Menginstal dan membangun aplikasi React..."
npm ci
ensure_success "NPM ci"

npm run build
ensure_success "NPM build"

# 4. PERBAIKI PERMISSION DATA POSTGRESQL
print_message "=== 4. MEMPERBAIKI PERMISSION DATA POSTGRESQL ==="

# Perbaiki permission pada container postgis-app
docker exec -u root geoportal-palapa-postgis-app sh -c "chown -R postgres:postgres /var/lib/postgresql/data && find /var/lib/postgresql/data -type d -exec chmod 700 '{}' ';' && find /var/lib/postgresql/data -type f -exec chmod 600 '{}' ';'"

# Perbaiki permission pada container postgis-spasial
docker exec -u root geoportal-palapa-postgis-spasial sh -c "chown -R postgres:postgres /var/lib/postgresql/data && find /var/lib/postgresql/data -type d -exec chmod 700 '{}' ';' && find /var/lib/postgresql/data -type f -exec chmod 600 '{}' ';'"

# Restart container agar PostgreSQL membaca ulang permission yang benar
docker restart geoportal-palapa-postgis-app
docker restart geoportal-palapa-postgis-spasial

# 5. SETUP DATABASE APLIKASI
print_message "=== 5. SETUP DATABASE APLIKASI ==="

# Buat skrip SQL untuk database aplikasi
cat > setup_db_app.sql << EOF
CREATE DATABASE palapa_app;
\c palapa_app
CREATE EXTENSION postgis;
EOF

# Salin dan jalankan skrip SQL di dalam container
docker cp setup_db_app.sql geoportal-palapa-postgis-app:/tmp/ || sudo docker cp setup_db_app.sql geoportal-palapa-postgis-app:/tmp/
docker exec -i geoportal-palapa-postgis-app bash -c "psql -U postgres -f /tmp/setup_db_app.sql" || sudo docker exec -i geoportal-palapa-postgis-app bash -c "psql -U postgres -f /tmp/setup_db_app.sql"
ensure_success "Setup database aplikasi"

# 6. SETUP DATABASE SPASIAL
print_message "=== 6. SETUP DATABASE SPASIAL ==="

# Buat skrip SQL untuk database spasial
cat > setup_db_spasial.sql << EOF
CREATE DATABASE palapa_geodb;
\c palapa_geodb
CREATE EXTENSION postgis;
EOF

# Salin dan jalankan skrip SQL di dalam container
docker cp setup_db_spasial.sql geoportal-palapa-postgis-spasial:/tmp/ || sudo docker cp setup_db_spasial.sql geoportal-palapa-postgis-spasial:/tmp/
docker exec -i geoportal-palapa-postgis-spasial bash -c "psql -U postgres -f /tmp/setup_db_spasial.sql" || sudo docker exec -i geoportal-palapa-postgis-spasial bash -c "psql -U postgres -f /tmp/setup_db_spasial.sql"
ensure_success "Setup database spasial"

# 7. SETUP API
print_message "=== 7. SETUP API ==="
cd ../../api/node/app/config/
cp db.config.js.example db.config.js

# Edit konfigurasi DB
cat > db.config.js << EOF
module.exports = {
  HOST: "db-app",
  USER: "postgres",
  PASSWORD: "$POSTGRES_APP_PASSWORD",
  DB: "palapa_app",
  PORT: 5432,
  dialect: "postgres",
  pool: {
    max: 5,
    min: 0,
    acquire: 30000,
    idle: 10000
  }
};
EOF
ensure_success "Konfigurasi DB API"

# 8. SETUP CONTAINER NODE-API
print_message "=== 8. SETUP CONTAINER NODE-API ==="
cd ../../
cp .env.example .env

# Tanya input tambahan
RECAPTCHA_SECRET_KEY=$(get_input "Masukkan RECAPTCHA_SECRET_KEY" "")
save_config "RECAPTCHA_SECRET_KEY" "$RECAPTCHA_SECRET_KEY"

# Edit .env untuk node-api
cat > .env << EOF
HOST=$DOMAIN_URL
RESET_PASSWORD=P4lapa123!@
GEOSERVER_HOST=http://geoserver
GEOSERVER_PORT=8080
GEOSERVER_WORKSPACE=palapa
GEOSERVER_STORE=palapa_geodb
GEOSERVER_USER=admin
GEOSERVER_PASS=$GEOSERVER_ADMIN_PASSWORD
DB_SPASIAL_CONNECTION_PASSWORD=$POSTGRES_SPASIAL_PASSWORD
RECAPTCHA_SECRET_KEY=$RECAPTCHA_SECRET_KEY
EOF

ensure_success "Konfigurasi Node API env"

# posisi di api/node akan masuk ke app/utils
# 9. SETUP CONTAINER NODE-API UTILS SHAPEFILE TO POSTGIS
# print_message "=== 9. SETUP CONTAINER NODE-API UTILS SHAPEFILE TO POSTGIS ==="
# cd app/utils/
# cp shapefile_to_postgis.js shapefile_to_postgis.js.backup

# # Edit konfigurasi DB di file shapefile_to_postgis.js
# sed -i "s/password: '.*'/password: '$POSTGRES_SPASIAL_PASSWORD'/" shapefile_to_postgis.js
# ensure_success "Konfigurasi shapefile to postgis"

# posisi di api/node/app/utils akan masuk ke api/node
# 10. SETUP CONTAINER NODE-API SEED DB
print_message "=== 10. SETUP CONTAINER NODE-API SEED DB ==="
# cd ../../
npm ci
sleep 45
ensure_success "NPM ci untuk Node API"

# Edit server.js untuk sync
cp server.js server.js.backup
sed -i 's|^[[:space:]]*//[[:space:]]*initializeApp();|initializeApp();|' server.js
ensure_success "Konfigurasi sync database"

# Restart container node-api 1
print_message "Restart container node-api untuk sync database..."
sudo docker restart geoportal-palapa-node-api
ensure_success "Restart node-api"

# Tunggu beberapa detik untuk memastikan sync selesai
print_message "Menunggu proses sync database selesai..."
sleep 45

# Restart container node-api 2
print_message "Restart container node-api untuk sync database..."
sudo docker restart geoportal-palapa-node-api
ensure_success "Restart node-api"

# Tunggu beberapa detik untuk memastikan sync selesai
print_message "Menunggu proses sync database selesai..."
sleep 45

# Edit kembali server.js, comment fungsi sync
sed -i 's|^initializeApp();|//initializeApp();|' server.js
ensure_success "Konfigurasi sync database disable initial"

# Restart container node-api lagi
print_message "Restart container node-api kembali..."
sudo docker restart geoportal-palapa-node-api
ensure_success "Restart node-api"

# 11. SETUP CONTAINER PYCSW
print_message "Setup PyCSW menggunakan konfigurasi YAML..."

# =====================================================
# Pastikan yq terinstall
# =====================================================
print_message "Memeriksa dan menginstall yq jika belum ada..."

if ! command -v yq &> /dev/null; then
    print_message "yq belum terinstall, menginstall manual..."

    YQ_VERSION="v4.44.1"
    sudo wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -O /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq

    ensure_success "Install yq"
else
    print_message "yq sudah terinstall"
fi

# =====================================================
# Salin file konfigurasi
# =====================================================
cd ../../config/pycsw/
cp pycsw.yml.example pycsw.yml

# =====================================================
# INPUT & KONFIRMASI METADATA PYCSW (TAMBAHKAN DI SINI)
# =====================================================
print_message "Mengisi metadata PyCSW..."

while true; do
    IDENTIFICATION_TITLE=$(get_input "Judul Identifikasi (Wajib)" "Katalog Geospasial Geoportal Kementerian/Lembaga/Pemerintah Daerah")
    PROVIDER_NAME=$(get_input "Nama Kementerian atau Lembaga atau Pemerintah Daerah (K/L/PD) (Wajib)")

    CONTACT_NAME=$(get_input "Nama Kontak (PIC) (Wajib)" "Nama Belakang, Nama Depan")
    CONTACT_POSITION=$(get_input "Posisi atau Jabatan (Wajib)" "Jabatan")
    CONTACT_ADDRESS=$(get_input "Alamat Instansi (Wajib)" "Alamat")
    CONTACT_CITY=$(get_input "Kota Instansi (Wajib)" "Kota")
    CONTACT_STATEORPROVINCE=$(get_input "Provinsi Instansi (Wajib)" "Provinsi")
    CONTACT_POSTALCODE=$(get_input "Kode Pos Instansi (Wajib)" "Kode Pos")
    CONTACT_COUNTRY=$(get_input "Negara Instansi (Wajib)" "Negara")
    CONTACT_PHONE=$(get_input "Telepon (PIC / Instansi) (Wajib)" "+xx-xxx-xxx-xxxx")
    CONTACT_FAX=$(get_input "Fax (PIC / Instansi) (Opsional)" "+xx-xxx-xxx-xxxx")
    CONTACT_EMAIL=$(get_input "Email (PIC / Instansi) (Wajib)" "Email")
    CONTACT_URL=$(get_input "URL Kontak (Opsional)" "Website URL Instansi")
    CONTACT_HOURS=$(get_input "Jam Layanan (Opsional)" "Contoh: 08:00-17:00")
    CONTACT_INSTRUCTIONS=$(get_input "Instruksi Kontak (Opsional)" "Senin-Jumat, 08:00-17:00")
    CONTACT_ROLE=$(get_input "Peran Kontak (Wajib)" "Walidata")

    echo ""
    print_message "Ringkasan Metadata PyCSW:"
    echo "----------------------------------------"
    echo "Judul Katalog        : $IDENTIFICATION_TITLE"
    echo "Instansi Penyedia    : $PROVIDER_NAME"
    echo "Nama Kontak          : $CONTACT_NAME"
    echo "Jabatan              : $CONTACT_POSITION"
    echo "Alamat               : $CONTACT_ADDRESS"
    echo "Kota                 : $CONTACT_CITY"
    echo "Provinsi             : $CONTACT_STATEORPROVINCE"
    echo "Kode Pos             : $CONTACT_POSTALCODE"
    echo "Negara               : $CONTACT_COUNTRY"
    echo "Telepon              : $CONTACT_PHONE"
    echo "Fax                  : $CONTACT_FAX"
    echo "Email                : $CONTACT_EMAIL"
    echo "URL                  : $CONTACT_URL"
    echo "Jam Layanan          : $CONTACT_HOURS"
    echo "Instruksi            : $CONTACT_INSTRUCTIONS"
    echo "Peran                : $CONTACT_ROLE"
    echo "----------------------------------------"

    read -p "Apakah data di atas sudah benar? (y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        print_message "Metadata PyCSW dikonfirmasi"
        break
    else
        print_warning "Mengulang pengisian metadata PyCSW..."
        echo ""
    fi
done

# =====================================================
# Update URL & PROVIDER URL
# =====================================================
yq -i ".server.url = \"${DOMAIN_URL}/\"" pycsw.yml
yq -i ".server.provider_url = \"${DOMAIN_URL}\"" pycsw.yml

# =====================================================
# Update koneksi database
# =====================================================
yq -i ".repository.database = \"postgresql://postgres:${POSTGRES_APP_PASSWORD}@db-app/palapa_app\"" pycsw.yml

# =====================================================
# Update metadata IDENTIFICATION
# =====================================================
yq -i ".metadata.identification.title = \"${IDENTIFICATION_TITLE}\"" pycsw.yml
yq -i ".metadata.identification_title = \"${IDENTIFICATION_TITLE}\"" pycsw.yml

# =====================================================
# Update metadata PROVIDER
# =====================================================
yq -i ".metadata.provider.name = \"${PROVIDER_NAME}\"" pycsw.yml
yq -i ".metadata.provider.url = \"${DOMAIN_URL}\"" pycsw.yml

# =====================================================
# Update metadata CONTACT
# =====================================================
yq -i ".metadata.contact.name = \"${CONTACT_NAME}\"" pycsw.yml
yq -i ".metadata.contact.position = \"${CONTACT_POSITION}\"" pycsw.yml
yq -i ".metadata.contact.address = \"${CONTACT_ADDRESS}\"" pycsw.yml
yq -i ".metadata.contact.city = \"${CONTACT_CITY}\"" pycsw.yml
yq -i ".metadata.contact.stateorprovince = \"${CONTACT_STATEORPROVINCE}\"" pycsw.yml
yq -i ".metadata.contact.postalcode = \"${CONTACT_POSTALCODE}\"" pycsw.yml
yq -i ".metadata.contact.country = \"${CONTACT_COUNTRY}\"" pycsw.yml
yq -i ".metadata.contact.phone = \"${CONTACT_PHONE}\"" pycsw.yml
yq -i ".metadata.contact.fax = \"${CONTACT_FAX}\"" pycsw.yml
yq -i ".metadata.contact.email = \"${CONTACT_EMAIL}\"" pycsw.yml
yq -i ".metadata.contact.url = \"${CONTACT_URL}\"" pycsw.yml
yq -i ".metadata.contact.hours = \"${CONTACT_HOURS}\"" pycsw.yml
yq -i ".metadata.contact.instructions = \"${CONTACT_INSTRUCTIONS}\"" pycsw.yml
yq -i ".metadata.contact.role = \"${CONTACT_ROLE}\"" pycsw.yml

ensure_success "Konfigurasi PyCSW YAML dari file konfigurasi"

# =====================================================
# Restart container PyCSW
# =====================================================
print_message "Restart container pycsw..."
docker restart geoportal-palapa-pycsw || sudo docker restart geoportal-palapa-pycsw
ensure_success "Restart PyCSW"

print_message "Konfigurasi PyCSW YAML berhasil diterapkan"

# 12. KONFIGURASI SSL DAN AKSES GEOSERVER
print_message "=== 12. Konfig SSL dan Akses Geoserver ==="
cd ../../../

# Cek jika HTTPS digunakan
if [[ "$USE_HTTPS" == "y" || "$USE_HTTPS" == "Y" ]]; then
    # Tanya penggunaan SSL
    read -p "Apakah Anda menggunakan SSL WAF atau certificate? (waf/cert): " SSL_TYPE
    if [[ "$SSL_TYPE" != "waf" && "$SSL_TYPE" != "cert" ]]; then
        print_error "Pilihan tidak valid. Harus 'waf' atau 'cert'"
        exit 1
    fi

    # Tanya akses UI GeoServer
    read -p "Apakah Anda ingin menutup UI GeoServer? (y/n): " CLOSE_GEOSERVER
    if [[ "$CLOSE_GEOSERVER" != "y" && "$CLOSE_GEOSERVER" != "n" ]]; then
        print_error "Pilihan tidak valid. Harus 'y' atau 'n'"
        exit 1
    fi

    # Logika konfigurasi berdasarkan input
    if [[ "$SSL_TYPE" == "waf" && "$CLOSE_GEOSERVER" == "y" ]]; then
        print_message "Mengkonfigurasi SSL via WAF dan menutup UI GeoServer..."
        cd palapaV5/config/web/
        mv httpd.conf httpd.conf.bak
        cp ../../extras/httpd-close-geoserver-waf.conf httpd.conf
        ensure_success "Menyalin file konfigurasi httpd-close-geoserver-waf.conf"
        
        # Restart container web
        print_message "Restart container web..."
        docker restart geoportal-palapa-httpd-proxy || sudo docker restart geoportal-palapa-httpd-proxy
        ensure_success "Restart web container"
        print_message "Berhasil menutup UI GeoServer."

        # Konfigurasi web.xml
        configure_web_xml

        print_message "Menunggu GeoServer untuk memulai..."
        sleep 45
        
    elif [[ "$SSL_TYPE" == "waf" && "$CLOSE_GEOSERVER" == "n" ]]; then
        print_message "Mengkonfigurasi SSL via WAF dan membuka UI GeoServer..."
        cd palapaV5/config/web/
        mv httpd.conf httpd.conf.bak
        cp ../../extras/httpd-open-geoserver-waf.conf httpd.conf
        ensure_success "Menyalin file konfigurasi httpd-open-geoserver-waf.conf"
        
        # Restart container web
        print_message "Restart container web..."
        docker restart geoportal-palapa-httpd-proxy || sudo docker restart geoportal-palapa-httpd-proxy
        ensure_success "Restart web container"
        print_message "UI GeoServer tetap dapat diakses."

        # Konfigurasi web.xml
        configure_web_xml

        print_message "Menunggu GeoServer untuk memulai..."
        sleep 45
        
    elif [[ "$SSL_TYPE" == "cert" && "$CLOSE_GEOSERVER" == "n" ]]; then
        print_message "Mengkonfigurasi SSL via certificate dan membuka UI GeoServer..."
        
        # Ganti docker-compose file
        cd palapaV5/
        mv docker-compose.yml docker-compose.yml.bak
        cp extras/docker-compose-ssl-cert.yml docker-compose.yml
        ensure_success "Menyalin file docker-compose-ssl-cert.yml"
        
        # Ganti konfigurasi Apache
        cd config/web/
        mv httpd.conf httpd.conf.bak
        cp ../../extras/httpd-open-geoserver-cert.conf httpd.conf
        ensure_success "Menyalin file konfigurasi httpd-open-geoserver-cert.conf"
        
        # Konfigurasi SSL
        configure_ssl_certs "httpd.conf"
        
        # Restart container
        cd ../../
        print_message "Menghentikan dan memulai ulang semua container..."
        docker compose down
        docker compose up -d
        ensure_success "Restart semua container"

        # Konfigurasi web.xml
        configure_web_xml

        print_message "Menunggu GeoServer untuk memulai..."
        sleep 45
        
    elif [[ "$SSL_TYPE" == "cert" && "$CLOSE_GEOSERVER" == "y" ]]; then
        print_message "Mengkonfigurasi SSL via certificate dan menutup UI GeoServer..."
        
        # Ganti docker-compose file
        cd palapaV5/
        mv docker-compose.yml docker-compose.yml.bak
        cp extras/docker-compose-ssl-cert.yml docker-compose.yml
        ensure_success "Menyalin file docker-compose-ssl-cert.yml"
        
        # Ganti konfigurasi Apache
        cd config/web/
        mv httpd.conf httpd.conf.bak
        cp ../../extras/httpd-close-geoserver-cert.conf httpd.conf
        ensure_success "Menyalin file konfigurasi httpd-close-geoserver-cert.conf"
        
        # Konfigurasi SSL
        configure_ssl_certs "httpd.conf"
        
        # Restart container
        cd ../../
        print_message "Menghentikan dan memulai ulang semua container..."
        docker compose down -v
        docker compose up -d
        ensure_success "Restart semua container"
        print_message "Berhasil menutup UI GeoServer."

        # Konfigurasi web.xml
        configure_web_xml

        print_message "Menunggu GeoServer untuk memulai..."
        sleep 45
    else
        print_error "Kombinasi pilihan tidak valid"
        exit 1
    fi

    print_message "=== KONFIGURASI SSL DAN AKSES GEOSERVER PALAPA V5 SELESAI ==="
else
    print_message "Mode HTTP dipilih, melewati konfigurasi SSL..."
    
    # Tanya akses UI GeoServer
    read -p "Apakah Anda ingin menutup UI GeoServer? (y/n): " CLOSE_GEOSERVER
    if [[ "$CLOSE_GEOSERVER" != "y" && "$CLOSE_GEOSERVER" != "n" ]]; then
        print_error "Pilihan tidak valid. Harus 'y' atau 'n'"
        exit 1
    fi

    # Jika HTTP Logika konfigurasi berdasarkan input
    if [[ "$CLOSE_GEOSERVER" == "y" ]]; then
        print_message "Mengkonfigurasi dan menutup UI GeoServer..."
        cd palapaV5/config/web/
        mv httpd.conf httpd.conf.bak
        cp ../../extras/httpd-close-geoserver-waf.conf httpd.conf
        ensure_success "Menyalin file konfigurasi httpd-close-geoserver-waf.conf"
        
        # Restart container web
        print_message "Restart container web..."
        docker restart geoportal-palapa-httpd-proxy || sudo docker restart geoportal-palapa-httpd-proxy
        ensure_success "Restart web container"
        print_message "Berhasil menutup UI GeoServer."
        
    elif [[ "$CLOSE_GEOSERVER" == "n" ]]; then
        print_message "Mengkonfigurasi dan membuka UI GeoServer..."
        cd palapaV5/config/web/
        mv httpd.conf httpd.conf.bak
        cp ../../extras/httpd-open-geoserver-waf.conf httpd.conf
        ensure_success "Menyalin file konfigurasi httpd-open-geoserver-waf.conf"
        
        # Restart container web
        print_message "Restart container web..."
        docker restart geoportal-palapa-httpd-proxy || sudo docker restart geoportal-palapa-httpd-proxy
        ensure_success "Restart web container"
        print_message "UI GeoServer tetap dapat diakses."

    else
        print_error "Kombinasi pilihan tidak valid"
        exit 1
    fi
fi

# 13. Ringkasan Konfigurasi dan Instruksi
print_message "=== 13. RINGKASAN KONFIGURASI ==="
print_message "Domain: $DOMAIN_URL"
print_message "PostgreSQL App Password: $POSTGRES_APP_PASSWORD"
print_message "PostgreSQL Spasial Password: $POSTGRES_SPASIAL_PASSWORD"
print_message "GeoServer Admin Password: $GEOSERVER_ADMIN_PASSWORD"
print_message "Semua pengaturan konfigurasi telah disimpan di: $HOME/.palapa/config"

# Verifikasi semua container berjalan
print_message "Verifikasi status container..."
docker ps -a || sudo docker ps -a

# Jika ingin membuat backup konfigurasi
print_message "=== 14. BACKUP KONFIGURASI ==="
read -p "Apakah Anda ingin membuat backup konfigurasi? (y/n): " create_backup

if [[ "$create_backup" == "y" || "$create_backup" == "Y" ]]; then
    backup_dir="$HOME/palapa_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup konfigurasi penting
    cp "$HOME/.palapa/config" "$backup_dir/" 2>/dev/null || true
    cp ".env" "$backup_dir/" 2>/dev/null || true
    cp "web/geoportal-react/.env" "$backup_dir/react.env" 2>/dev/null || true
    cp "api/node/.env" "$backup_dir/node_api.env" 2>/dev/null || true
    cp "config/pycsw/pycsw.cfg" "$backup_dir/" 2>/dev/null || true
    
    print_message "Backup konfigurasi disimpan di: $backup_dir"
    print_message "CATATAN: Backup ini berisi informasi sensitif seperti password. Simpan dengan aman!"
fi

# Selesai
print_message "=== INSTALASI PALAPA V5 SELESAI ==="
print_message "Akses aplikasi di: $DOMAIN_URL"
print_message "Email default admin: emhayusa@gmail.com"
print_message "Password default admin: P4lapa123!@"
print_message "Jangan lupa untuk mengganti password default!"

print_message "Langkah-langkah selanjutnya yang perlu dilakukan secara manual:"
print_message "1. Setup Workspace di Geoserver (jika belum otomatis terbuat)"
print_message "2. Setup Store di Geoserver (jika belum otomatis terbuat)"
print_message "3. Ganti password admin"
print_message "4. Buat user untuk role Walidata dan Produsen"
print_message "5. Buat kategori IGT"
print_message "6. Buat produsen untuk kategori IGT"
print_message "7. Kaitkan user yang telah dibuat sesuai kategori IGT dan produsen"
print_message "8. Buat IGT sesuai kategori IGT dan produsen yang telah ada"
print_message "9. Input Informasi situs dan Upload logo, icon dan background situs pada site settings"
print_message "10. Input Informasi panduan pada halaman panduan"

print_message "Untuk lebih detail, silakan lihat dokumen panduan instalasi Palapa V5"

exit 0
