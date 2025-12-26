#!/bin/bash
#
# SALFANET RADIUS - Local VPS Installation Script (Non-Root)
# Untuk VPS lokal tanpa akses full root (menggunakan sudo)
# Cocok untuk: Proxmox VM, LXC Container, Local Server
# Ubuntu 20.04/22.04 LTS
#
# Perbedaan dengan vps-install.sh:
# - Semua command menggunakan sudo
# - Tidak memerlukan akses SSH sebagai root
# - Cocok untuk user dengan sudo privilege
#

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}âœ“ $1${NC}"
}

print_error() {
    echo -e "${RED}âœ— $1${NC}"
}

print_info() {
    echo -e "${YELLOW}âžœ $1${NC}"
}

print_step() {
    echo ""
    echo -e "${BLUE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
}

# ===================================
# CHECK SUDO ACCESS
# ===================================
check_sudo() {
    if ! sudo -v &> /dev/null; then
        print_error "User tidak memiliki akses sudo!"
        echo "Pastikan user Anda ada di grup sudo:"
        echo "  sudo usermod -aG sudo \$USER"
        exit 1
    fi
    print_success "Sudo access OK"
}

# ===================================
# AUTO-DETECT IP ADDRESS
# ===================================
detect_ip_address() {
    local PUBLIC_IP=""
    local LOCAL_IP=""
    
    echo -e "${YELLOW}âžœ Detecting IP address...${NC}" >&2
    
    # Try to get public IP from various services
    if command -v curl &> /dev/null; then
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) || \
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null) || \
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://icanhazip.com 2>/dev/null) || \
        PUBLIC_IP=""
    fi
    
    # Get local/private IP
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || \
    LOCAL_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}') || \
    LOCAL_IP="127.0.0.1"
    
    # Validate public IP format
    if [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ ! $PUBLIC_IP =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.) ]]; then
            echo "$PUBLIC_IP"
            return 0
        fi
    fi
    
    # Fallback to local IP
    echo "$LOCAL_IP"
    return 0
}

# Detect IP before showing banner
DETECTED_IP=$(detect_ip_address)

# Check if it's a public or private IP
if [[ $DETECTED_IP =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.) ]]; then
    IP_TYPE="Local/Private"
else
    IP_TYPE="Public"
fi

echo ""
echo "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
echo "  SALFANET RADIUS - Local VPS Installation Script (Sudo Mode)"
echo "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
echo ""
echo -e "  ðŸ‘¤ User: ${CYAN}$(whoami)${NC}"
echo -e "  ðŸŒ Detected IP: ${CYAN}${DETECTED_IP}${NC} (${IP_TYPE})"
echo ""
echo "ðŸ“ Directory Structure:"
echo "   Source Code: $(pwd) (current directory)"
echo "   Application: /var/www/salfanet-radius"
echo "   Logs: /var/www/salfanet-radius/logs"
echo ""
echo "âš¡ Mode: Sudo (Non-Root Installation)"
echo "â±ï¸  Estimated time: 20-25 minutes"
echo ""
echo "ðŸ“‹ Fitur Installer:"
echo "   âœ“ Auto-detect IP Address"
echo "   âœ“ Session Timeout (30 menit idle logout)"
echo "   âœ“ FTTH Network Management (OLT/ODC/ODP)"
echo "   âœ“ FreeRADIUS dengan CoA Support"
echo ""

# Check sudo access
check_sudo

read -p "Lanjutkan instalasi? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Instalasi dibatalkan."
    exit 1
fi

# ===================================
# CONFIGURATION
# ===================================
print_step "Konfigurasi Instalasi"

# Default values
DEFAULT_DB_NAME="salfanet_radius"
DEFAULT_DB_USER="salfanet_user"
DEFAULT_DB_PASS="salfanetradius123"
DEFAULT_RADIUS_SECRET="secret123"
DEFAULT_APP_PORT="3000"

# Ask for configuration
read -p "Database Name [$DEFAULT_DB_NAME]: " DB_NAME
DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

read -p "Database User [$DEFAULT_DB_USER]: " DB_USER
DB_USER=${DB_USER:-$DEFAULT_DB_USER}

read -p "Database Password [$DEFAULT_DB_PASS]: " DB_PASS
DB_PASS=${DB_PASS:-$DEFAULT_DB_PASS}

read -p "RADIUS Secret [$DEFAULT_RADIUS_SECRET]: " RADIUS_SECRET
RADIUS_SECRET=${RADIUS_SECRET:-$DEFAULT_RADIUS_SECRET}

read -p "Application Port [$DEFAULT_APP_PORT]: " APP_PORT
APP_PORT=${APP_PORT:-$DEFAULT_APP_PORT}

read -p "Server IP/Domain [$DETECTED_IP]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DETECTED_IP}

echo ""
print_info "Configuration Summary:"
echo "   Database: $DB_NAME"
echo "   DB User: $DB_USER"
echo "   App Port: $APP_PORT"
echo "   Server IP: $SERVER_IP"
echo ""

# ===================================
# STEP 1: SYSTEM UPDATE
# ===================================
print_step "Step 1: System Update & Dependencies"

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y curl wget git unzip build-essential software-properties-common \
    apt-transport-https ca-certificates gnupg lsb-release

print_success "System updated"

# ===================================
# STEP 2: TIMEZONE & NTP
# ===================================
print_step "Step 2: Configure Timezone (Asia/Jakarta)"

sudo timedatectl set-timezone Asia/Jakarta
sudo apt-get install -y ntp ntpdate
sudo systemctl enable ntp
sudo systemctl start ntp || true

print_success "Timezone set to Asia/Jakarta (WIB)"

# ===================================
# STEP 3: INSTALL NODE.JS 20
# ===================================
print_step "Step 3: Install Node.js 20 LTS"

# Remove old nodejs if exists
sudo apt-get remove -y nodejs npm 2>/dev/null || true

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify
node --version
npm --version

print_success "Node.js $(node --version) installed"

# ===================================
# STEP 4: INSTALL MYSQL 8.0
# ===================================
print_step "Step 4: Install MySQL 8.0"

sudo apt-get install -y mysql-server mysql-client

# Start MySQL
sudo systemctl enable mysql
sudo systemctl start mysql

# Create database and user
print_info "Creating database and user..."

sudo mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "GRANT ALL PRIVILEGES ON radius.* TO '$DB_USER'@'localhost';" 2>/dev/null || true
sudo mysql -e "FLUSH PRIVILEGES;"

# Set timezone in MySQL
sudo mysql -e "SET GLOBAL time_zone = '+07:00';"
sudo mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"

print_success "MySQL configured with database: $DB_NAME"

# ===================================
# STEP 5: INSTALL FREERADIUS
# ===================================
print_step "Step 5: Install FreeRADIUS 3.0"

sudo apt-get install -y freeradius freeradius-mysql freeradius-utils freeradius-rest

# Stop FreeRADIUS for configuration
sudo systemctl stop freeradius

print_success "FreeRADIUS installed"

# ===================================
# STEP 6: SETUP APPLICATION
# ===================================
print_step "Step 6: Setup Application Directory"

# Create app directory
sudo mkdir -p /var/www/salfanet-radius
sudo chown -R $USER:$USER /var/www/salfanet-radius

# Copy files (assuming we're in the source directory)
print_info "Copying application files..."
cp -r ./* /var/www/salfanet-radius/ 2>/dev/null || true
cp -r ./.* /var/www/salfanet-radius/ 2>/dev/null || true

cd /var/www/salfanet-radius

print_success "Application files copied"

# ===================================
# STEP 7: CREATE .ENV FILE
# ===================================
print_step "Step 7: Create Environment Configuration"

# Generate NextAuth secret
NEXTAUTH_SECRET=$(openssl rand -base64 32)

cat > /var/www/salfanet-radius/.env << EOF
# Database
DATABASE_URL="mysql://$DB_USER:$DB_PASS@localhost:3306/$DB_NAME?connection_limit=10&pool_timeout=20"

# Timezone - CRITICAL for WIB handling
TZ="Asia/Jakarta"
NEXT_PUBLIC_TIMEZONE="Asia/Jakarta"

# App Configuration
NEXT_PUBLIC_APP_NAME="SALFANET RADIUS"
NEXT_PUBLIC_APP_URL="http://$SERVER_IP:$APP_PORT"

# RADIUS Server Configuration
RADIUS_SERVER_IP="$SERVER_IP"
VPS_IP="$SERVER_IP"

# NextAuth
NEXTAUTH_SECRET=$NEXTAUTH_SECRET
NEXTAUTH_URL=http://$SERVER_IP:$APP_PORT

# FreeRADIUS
FREERADIUS_SECRET="$RADIUS_SECRET"

# Session Configuration
# Idle timeout: 30 minutes
# Session max age: 1 day
SESSION_IDLE_TIMEOUT=1800000
SESSION_MAX_AGE=86400
EOF

print_success ".env file created"

# ===================================
# STEP 8: INSTALL NPM PACKAGES
# ===================================
print_step "Step 8: Install NPM Dependencies"

cd /var/www/salfanet-radius
npm install

print_success "NPM packages installed"

# ===================================
# STEP 9: SETUP DATABASE SCHEMA
# ===================================
print_step "Step 9: Setup Database Schema"

npx prisma generate
npx prisma db push

print_success "Database schema created"

# ===================================
# STEP 10: SEED DATABASE
# ===================================
print_step "Step 10: Seed Database"

npx prisma db seed || print_info "Seed skipped or already exists"

print_success "Database seeded"

# ===================================
# STEP 11: CONFIGURE FREERADIUS
# ===================================
print_step "Step 11: Configure FreeRADIUS"

# Function to remove BOM
remove_bom() {
    local file="$1"
    if [ -f "$file" ]; then
        # Check for UTF-16 BOM (FFFE or FEFF)
        if xxd "$file" 2>/dev/null | head -1 | grep -qE "fffe|feff"; then
            print_info "Converting UTF-16 BOM in $file"
            iconv -f UTF-16 -t UTF-8 "$file" > "${file}.tmp" 2>/dev/null && mv "${file}.tmp" "$file"
        fi
        # Remove UTF-8 BOM if exists
        sed -i '1s/^\xEF\xBB\xBF//' "$file" 2>/dev/null || true
    fi
}

# Configure SQL module
print_info "Configuring SQL module..."

sudo tee /etc/freeradius/3.0/mods-enabled/sql > /dev/null << 'SQLEOF'
sql {
    dialect = "mysql"
    driver = "rlm_sql_mysql"
    
    mysql {
        tls {
            tls_required = no
        }
    }
    
    server = "localhost"
    port = 3306
SQLEOF

sudo tee -a /etc/freeradius/3.0/mods-enabled/sql > /dev/null << EOF
    login = "$DB_USER"
    password = "$DB_PASS"
    radius_db = "$DB_NAME"
EOF

sudo tee -a /etc/freeradius/3.0/mods-enabled/sql > /dev/null << 'SQLEOF'
    
    acct_table1 = "radacct"
    acct_table2 = "radacct"
    postauth_table = "radpostauth"
    authcheck_table = "radcheck"
    groupcheck_table = "radgroupcheck"
    authreply_table = "radreply"
    groupreply_table = "radgroupreply"
    usergroup_table = "radusergroup"
    
    delete_stale_sessions = yes
    
    pool {
        start = 5
        min = 3
        max = 32
        spare = 3
        uses = 0
        retry_delay = 30
        lifetime = 0
        idle_timeout = 60
    }
    
    read_clients = yes
    client_table = "nas"
    
    group_attribute = "SQL-Group"
    
    $INCLUDE ${modconfdir}/${.:name}/main/${dialect}/queries.conf
}
SQLEOF

remove_bom "/etc/freeradius/3.0/mods-enabled/sql"

# Configure REST module
print_info "Configuring REST module..."

sudo tee /etc/freeradius/3.0/mods-enabled/rest > /dev/null << EOF
rest {
    tls {
        check_cert = no
        check_cert_cn = no
    }
    
    connect_uri = "http://127.0.0.1:$APP_PORT"
    
    # CRITICAL: Authorize pre-check (Dec 13, 2025 - Voucher Validation)
    # This validates voucher status BEFORE password check
    # Prevents expired vouchers from authenticating
    authorize {
        uri = "\${..connect_uri}/api/radius/authorize"
        method = 'post'
        body = 'json'
        data = '{"username": "%{User-Name}", "nasIp": "%{NAS-IP-Address}"}'
        timeout = 2
        tls = \${..tls}
    }
    
    post-auth {
        uri = "\${..connect_uri}/api/radius/post-auth"
        method = 'post'
        body = 'json'
        data = '{"username": "%{User-Name}", "nasIp": "%{NAS-IP-Address}", "nasPort": "%{NAS-Port}", "framedIp": "%{Framed-IP-Address}", "callingStation": "%{Calling-Station-Id}", "calledStation": "%{Called-Station-Id}"}'
        tls = \${..tls}
    }
    
    pool {
        start = 0
        min = 0
        max = 10
        spare = 1
        uses = 0
        retry_delay = 30
        lifetime = 0
        idle_timeout = 60
        connect_timeout = 3
    }
}
EOF

remove_bom "/etc/freeradius/3.0/mods-enabled/rest"

# Configure clients.conf
print_info "Configuring clients.conf..."

sudo tee /etc/freeradius/3.0/clients.conf > /dev/null << EOF
# Default localhost client
client localhost {
    ipaddr = 127.0.0.1
    secret = $RADIUS_SECRET
    require_message_authenticator = no
    nas_type = other
    shortname = localhost
}

# Allow from local network
client localnet {
    ipaddr = 192.168.0.0/16
    secret = $RADIUS_SECRET
    require_message_authenticator = no
    nas_type = other
    shortname = localnet
}

client private-network-10 {
    ipaddr = 10.0.0.0/8
    secret = $RADIUS_SECRET
    require_message_authenticator = no
    nas_type = other
    shortname = private-10
}

# Read clients from database
# Additional clients loaded from SQL 'nas' table
EOF

remove_bom "/etc/freeradius/3.0/clients.conf"

# Configure sites-enabled/default
print_info "Configuring default site..."

# Check if backup exists
if [ -f "freeradius-config/sites-enabled-default" ]; then
    sudo cp freeradius-config/sites-enabled-default /etc/freeradius/3.0/sites-enabled/default
    remove_bom "/etc/freeradius/3.0/sites-enabled/default"
fi

# Set permissions
sudo chown -R freerad:freerad /etc/freeradius/3.0/
sudo chmod 640 /etc/freeradius/3.0/mods-enabled/sql
sudo chmod 640 /etc/freeradius/3.0/mods-enabled/rest
sudo chmod 640 /etc/freeradius/3.0/clients.conf

# Test FreeRADIUS configuration
print_info "Testing FreeRADIUS configuration..."
sudo freeradius -XC 2>&1 | tail -5 || true

# Enable and start FreeRADIUS
sudo systemctl enable freeradius
sudo systemctl start freeradius || print_info "FreeRADIUS may need manual start after app is running"

print_success "FreeRADIUS configured"

# ===================================
# STEP 12: INSTALL PM2
# ===================================
print_step "Step 12: Install PM2 Process Manager"

sudo npm install -g pm2

# Setup PM2 startup (for current user with sudo)
pm2 startup systemd -u $USER --hp /home/$USER 2>/dev/null || \
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp /home/$USER 2>/dev/null || true

print_success "PM2 installed"

# ===================================
# STEP 13: BUILD APPLICATION
# ===================================
print_step "Step 13: Build Application"

cd /var/www/salfanet-radius
npm run build

print_success "Application built"

# ===================================
# STEP 14: START WITH PM2
# ===================================
print_step "Step 14: Start Application with PM2"

# Create PM2 ecosystem file
cat > /var/www/salfanet-radius/ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'salfanet-radius',
    script: 'node_modules/next/dist/bin/next',
    args: 'start -p $APP_PORT',
    cwd: '/var/www/salfanet-radius',
    instances: 1,
    exec_mode: 'cluster',
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: $APP_PORT
    }
  }]
};
EOF

# Start application
pm2 delete salfanet-radius 2>/dev/null || true
pm2 start ecosystem.config.js
pm2 save

print_success "Application started on port $APP_PORT"

# ===================================
# STEP 15: CONFIGURE NGINX (OPTIONAL)
# ===================================
print_step "Step 15: Install Nginx (Optional Reverse Proxy)"

read -p "Install Nginx as reverse proxy? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo apt-get install -y nginx
    
    sudo tee /etc/nginx/sites-available/salfanet-radius > /dev/null << EOF
server {
    listen 80;
    server_name $SERVER_IP _;
    
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}
EOF

    sudo ln -sf /etc/nginx/sites-available/salfanet-radius /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx -t && sudo systemctl reload nginx
    
    print_success "Nginx configured"
fi

# ===================================
# STEP 16: CONFIGURE FIREWALL (OPTIONAL)
# ===================================
print_step "Step 16: Configure Firewall (Optional)"

read -p "Configure UFW firewall? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo ufw allow ssh
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw allow $APP_PORT/tcp
    sudo ufw allow 1812/udp   # RADIUS Auth
    sudo ufw allow 1813/udp   # RADIUS Acct
    sudo ufw allow 3799/udp   # RADIUS CoA
    
    print_info "Enable firewall with: sudo ufw enable"
fi

# ===================================
# INSTALLATION COMPLETE
# ===================================
echo ""
echo "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
echo -e "${GREEN}  âœ“ INSTALASI SELESAI!${NC}"
echo "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
echo ""
echo "ðŸ“ Application URL:"
echo -e "   ${CYAN}http://$SERVER_IP:$APP_PORT/admin${NC}"
echo ""
echo "ðŸ” Default Login:"
echo "   Username: superadmin"
echo "   Password: admin123"
echo ""
echo "âš ï¸  GANTI PASSWORD SEGERA SETELAH LOGIN!"
echo ""
echo "ðŸ“‹ Useful Commands:"
echo "   pm2 status              # Check app status"
echo "   pm2 logs salfanet-radius  # View logs"
echo "   pm2 restart salfanet-radius"
echo "   sudo systemctl status freeradius"
echo "   sudo freeradius -X      # Debug mode"
echo ""
echo "ðŸ”§ RADIUS Configuration:"
echo "   Auth Port: 1812"
echo "   Acct Port: 1813"
echo "   CoA Port: 3799"
echo "   Secret: $RADIUS_SECRET"
echo ""
echo "ðŸ“ Configuration Files:"
echo "   App Config: /var/www/salfanet-radius/.env"
echo "   FreeRADIUS: /etc/freeradius/3.0/"
echo "   Nginx: /etc/nginx/sites-available/salfanet-radius"
echo ""
echo "ðŸ“– Fitur Session Management:"
echo "   - Auto logout setelah 30 menit tidak aktif"
echo "   - Warning popup 1 menit sebelum logout"
echo "   - Session maksimal 1 hari"
echo ""
echo "â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•"
