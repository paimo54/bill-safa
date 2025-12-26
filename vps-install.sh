#!/bin/bash
#
# SALFANET RADIUS - VPS Installation Script
# Untuk Ubuntu 20.04/22.04 LTS
# Auto-detect IP Address (Public or Local)
#

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

# ===================================
# AUTO-DETECT IP ADDRESS
# ===================================
detect_ip_address() {
    local PUBLIC_IP=""
    local LOCAL_IP=""
    
    # Try to get public IP from various services
    # Note: Using stderr for print_info to avoid capturing it in the return value
    echo -e "${YELLOW}âžœ Detecting IP address...${NC}" >&2
    
    # Method 1: Try curl to external services
    if command -v curl &> /dev/null; then
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null) || \
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://ifconfig.me 2>/dev/null) || \
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://icanhazip.com 2>/dev/null) || \
        PUBLIC_IP=$(curl -s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null) || \
        PUBLIC_IP=""
    fi
    
    # Method 2: Try wget if curl failed
    if [ -z "$PUBLIC_IP" ] && command -v wget &> /dev/null; then
        PUBLIC_IP=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null) || \
        PUBLIC_IP=$(wget -qO- --timeout=5 https://ifconfig.me 2>/dev/null) || \
        PUBLIC_IP=""
    fi
    
    # Get local/private IP
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || \
    LOCAL_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}') || \
    LOCAL_IP="127.0.0.1"
    
    # Validate public IP format (basic IPv4 check)
    if [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Check if public IP is actually public (not private range)
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
echo "=============================================="
echo "  SALFANET RADIUS - VPS Installation Script"
echo "=============================================="
echo ""
echo -e "  ðŸŒ Detected IP: ${CYAN}${DETECTED_IP}${NC} (${IP_TYPE})"
echo ""
echo "ðŸ“ Directory Structure:"
echo "   Source Code: /root/salfanet-radius-main (installer location)"
echo "   Application: /var/www/salfanet-radius (running app)"
echo "   Logs: /var/www/salfanet-radius/logs"
echo ""
echo "â±ï¸  Estimated time: 20-25 minutes"
echo "ðŸ“‹ Steps:"
echo "   1. System Update & Dependencies (2 min)"
echo "   2. Install Node.js 20 (2 min)"
echo "   3. Install & Configure MySQL (2 min)"
echo "   4. Setup Application & Database (10 min - LONGEST)"
echo "      - Copy from /root/salfanet-radius-main to /var/www/salfanet-radius"
echo "      - npm install (8 min)"
echo "      - Prisma setup & seeding (2 min)"
echo "   5. Install & Configure FreeRADIUS (2 min)"
echo "   6-12. Install PM2, Nginx, Configs (2 min)"
echo "   13. Build & Start Application (5-10 min)"
echo "      - npm run build (with swap if needed)"
echo "      - PM2 start"
echo ""
echo "âš ï¸  IMPORTANT: Run this from /root/salfanet-radius-main"
echo "âš ï¸  Do not interrupt this process!"
echo ""

# Allow user to override detected IP
read -t 10 -p "Use detected IP ($DETECTED_IP)? [Y/n/custom]: " IP_CONFIRM || IP_CONFIRM="y"
echo ""

if [[ "$IP_CONFIRM" =~ ^[Nn]$ ]]; then
    read -p "Enter IP address manually: " MANUAL_IP
    if [[ $MANUAL_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        DETECTED_IP="$MANUAL_IP"
        print_success "Using manual IP: $DETECTED_IP"
    else
        print_error "Invalid IP format, using detected IP: $DETECTED_IP"
    fi
elif [[ ! "$IP_CONFIRM" =~ ^[Yy]?$ ]] && [[ "$IP_CONFIRM" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # User entered an IP directly
    DETECTED_IP="$IP_CONFIRM"
    print_success "Using custom IP: $DETECTED_IP"
else
    print_success "Using detected IP: $DETECTED_IP"
fi

echo ""

# Verify we're in the right directory
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" != *"salfanet-radius-main"* ]]; then
    echo "âŒ ERROR: Please run this script from /root/salfanet-radius-main"
    echo "   Current directory: $CURRENT_DIR"
    echo ""
    echo "   Fix: cd /root/salfanet-radius-main && ./vps-install.sh"
    exit 1
fi

sleep 2

# Configuration - Use detected IP
VPS_IP="$DETECTED_IP"
APP_DIR="/var/www/salfanet-radius"
DB_NAME="salfanet_radius"
DB_USER="salfanet_user"
DB_PASSWORD="salfanetradius123"
DB_ROOT_PASSWORD="root123"
NEXTAUTH_SECRET=$(openssl rand -base64 32)
NODE_VERSION="20"

# Check if running as root

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

print_info "Starting installation..."

# ===================================
# 1. SYSTEM UPDATE & DEPENDENCIES
# ===================================
print_info "Step 1: Updating system and installing dependencies..."

apt-get update
apt-get upgrade -y
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    ufw \
    nginx \
    certbot \
    python3-certbot-nginx \
    sudo \
    vim \
    htop \
    chrony \
    ntpdate

print_success "System updated"

# ===================================
# 1.5 CONFIGURE TIMEZONE & NTP SYNC
# ===================================
print_info "Configuring timezone and NTP synchronization..."

# Set timezone to Asia/Jakarta (WIB)
print_info "Setting timezone to Asia/Jakarta (WIB)..."
timedatectl set-timezone Asia/Jakarta
print_success "Timezone set to: $(timedatectl show --property=Timezone --value)"

# Configure Chrony for NTP sync
print_info "Configuring NTP synchronization with Chrony..."

# Backup original chrony config
cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak 2>/dev/null || true

# Configure chrony with Indonesian NTP servers
cat > /etc/chrony/chrony.conf <<EOF
# Indonesian NTP Servers (closest for best accuracy)
server id.pool.ntp.org iburst prefer
server 0.id.pool.ntp.org iburst
server 1.id.pool.ntp.org iburst
server 2.id.pool.ntp.org iburst
server 3.id.pool.ntp.org iburst

# Fallback to Asia pool
server asia.pool.ntp.org iburst

# Google and Cloudflare NTP as backup
server time.google.com iburst
server time.cloudflare.com iburst

# Record the rate at which the system clock gains/losses time
driftfile /var/lib/chrony/drift

# Allow the system clock to be stepped in the first three updates
makestep 1 3

# Enable kernel synchronization of the real-time clock (RTC)
rtcsync

# Allow NTP client access from local network (optional)
# allow 192.168.0.0/16
# allow 10.0.0.0/8

# Log files location
logdir /var/log/chrony

# Enable logging
log measurements statistics tracking

# Enable hardware timestamping on all interfaces that support it
# hwtimestamp *
EOF

# Enable and start chrony
systemctl enable chrony
systemctl restart chrony

# Wait for sync
print_info "Waiting for time synchronization..."
sleep 3

# Force initial sync
chronyc makestep > /dev/null 2>&1 || true

# Check sync status
print_info "Checking NTP synchronization status..."
if chronyc tracking | grep -q "Reference ID"; then
    print_success "NTP synchronized successfully"
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
    print_success "Current server time: ${CURRENT_TIME}"
    
    # Show sync details
    echo ""
    echo "  NTP Server: $(chronyc tracking | grep 'Reference ID' | awk '{print $4}')"
    echo "  Stratum: $(chronyc tracking | grep 'Stratum' | awk '{print $3}')"
    echo "  System time offset: $(chronyc tracking | grep 'System time' | awk '{print $4, $5}')"
else
    print_error "NTP sync may have issues. Check with: chronyc tracking"
fi

# Sync hardware clock
hwclock --systohc 2>/dev/null || true
print_success "Hardware clock synced"

# ===================================
# 2. INSTALL NODE.JS 20 LTS
# ===================================
print_info "Step 2: Installing Node.js ${NODE_VERSION}..."

curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
apt-get install -y nodejs

# Verify installation
node --version
npm --version

print_success "Node.js installed: $(node --version)"

# ===================================
# 3. INSTALL MYSQL 8.0
# ===================================
print_info "Step 3: Installing MySQL 8.0..."

# Remove old MySQL installation completely
print_info "Removing old MySQL installation (if exists)..."
systemctl stop mysql 2>/dev/null || true
apt-get remove --purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean 2>/dev/null || true
rm -rf /etc/mysql /var/lib/mysql /var/log/mysql 2>/dev/null || true

print_info "Installing fresh MySQL..."
apt-get install -y mysql-server mysql-client

# Start MySQL
systemctl start mysql
systemctl enable mysql

print_info "Configuring MySQL and resetting database..."

# Secure MySQL installation (automated)
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_ROOT_PASSWORD}';" 2>/dev/null || true
mysql -u root -p${DB_ROOT_PASSWORD} -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -u root -p${DB_ROOT_PASSWORD} -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -u root -p${DB_ROOT_PASSWORD} -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
mysql -u root -p${DB_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Drop existing database and user (fresh start)
print_info "Dropping existing database and user (if exists)..."
mysql -u root -p${DB_ROOT_PASSWORD} <<EOF 2>/dev/null || true
DROP DATABASE IF EXISTS ${DB_NAME};
DROP USER IF EXISTS '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Create fresh database and user
print_info "Creating fresh database and user..."
mysql -u root -p${DB_ROOT_PASSWORD} <<EOF
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Test connection
print_info "Testing database connection..."
if mysql -u ${DB_USER} -p${DB_PASSWORD} -e "USE ${DB_NAME}; SELECT 1;" > /dev/null 2>&1; then
    print_success "Database connection test successful"
else
    print_error "Database connection test failed!"
    exit 1
fi

print_success "MySQL installed and configured"

# ===================================
# 4. SETUP APPLICATION & PUSH DATABASE SCHEMA
# ===================================
print_info "Step 4: Setting up application and database schema..."

# Setup application directory
print_info "Creating application directory..."
mkdir -p ${APP_DIR}

# Copy application code from root directory
print_info "Copying application code..."
print_info "From: /root/salfanet-radius-main"
print_info "To: ${APP_DIR}"

SOURCE_DIR="/root/salfanet-radius-main"

if [ ! -d "$SOURCE_DIR" ]; then
    print_error "Source directory not found: $SOURCE_DIR"
    print_error "Please ensure project is uploaded to /root/salfanet-radius-main"
    exit 1
fi

# Copy all files
print_info "Copying files (this may take a moment)..."
cp -r $SOURCE_DIR/* ${APP_DIR}/
cp -r $SOURCE_DIR/.* ${APP_DIR}/ 2>/dev/null || true

print_success "Application code copied successfully"

# Verify critical files exist
if [ ! -f "${APP_DIR}/package.json" ]; then
    print_error "package.json not found in ${APP_DIR}!"
    exit 1
fi

if [ ! -f "${APP_DIR}/prisma/schema.prisma" ]; then
    print_error "prisma/schema.prisma not found!"
    exit 1
fi

print_success "Critical files verified"

cd ${APP_DIR}

# Create .env file
print_info "Creating .env file..."
cat > ${APP_DIR}/.env <<EOF
# Database Configuration
DATABASE_URL="mysql://${DB_USER}:${DB_PASSWORD}@localhost:3306/${DB_NAME}?connection_limit=10&pool_timeout=20"

# Timezone - CRITICAL for WIB handling
TZ="Asia/Jakarta"
NEXT_PUBLIC_TIMEZONE="Asia/Jakarta"

# App Configuration
NEXT_PUBLIC_APP_NAME="SALFANET RADIUS ISP"
NEXT_PUBLIC_APP_URL="http://${VPS_IP}:3000"

# NextAuth
NEXTAUTH_SECRET="${NEXTAUTH_SECRET}"
NEXTAUTH_URL="http://${VPS_IP}:3000"

# Node Environment
NODE_ENV="production"

# GenieACS Configuration (optional - configure in admin panel)
# GENIEACS_URL="http://YOUR_GENIEACS_IP:7557"
# GENIEACS_USERNAME=""
# GENIEACS_PASSWORD=""
EOF

chmod 600 ${APP_DIR}/.env

# Install dependencies with error handling
print_info "Installing Node.js dependencies (this will take 5-10 minutes)..."
print_info "Please wait, downloading packages from npm registry..."

if ! npm install --production=false 2>&1 | tee /tmp/npm-install.log; then
    print_error "npm install failed!"
    echo "Last 20 lines of error:"
    tail -20 /tmp/npm-install.log
    exit 1
fi

print_success "Dependencies installed successfully"

# Verify node_modules exists
if [ ! -d "node_modules" ]; then
    print_error "node_modules directory not created!"
    exit 1
fi

print_success "node_modules verified"

# Generate Prisma Client
print_info "Generating Prisma Client..."
if ! npx prisma generate 2>&1 | tee /tmp/prisma-generate.log; then
    print_error "Prisma generate failed!"
    cat /tmp/prisma-generate.log
    exit 1
fi

print_success "Prisma Client generated"

# Push database schema - CREATE ALL TABLES
print_info "Creating database tables with Prisma..."
print_info "This will create 47 tables for the application..."

if ! npx prisma db push --accept-data-loss --skip-generate 2>&1 | tee /tmp/prisma-push.log; then
    print_error "Prisma db push failed!"
    cat /tmp/prisma-push.log
    exit 1
fi

print_success "Database schema pushed successfully"

# Verify tables were created
print_info "Verifying database tables..."
TABLE_COUNT=$(mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} -e "SHOW TABLES;" 2>/dev/null | wc -l)
if [ "$TABLE_COUNT" -gt "10" ]; then
    print_success "Database schema created successfully ($TABLE_COUNT tables)"
else
    print_error "Database schema creation failed! Only $TABLE_COUNT tables found."
    exit 1
fi

# Seed database
print_info "Seeding database with initial data..."
print_info "Creating admin user, permissions, profiles, categories, and templates..."

# Main seed file (seed.ts) now calls seed-all.ts which includes everything:
# - Transaction categories (13)
# - Permissions (53) + Role templates
# - Admin user (superadmin/admin123)
# - Hotspot profiles (5 sample)
# - WhatsApp templates (6)
# - RADIUS isolir group
if npx tsx prisma/seeds/seed-all.ts 2>&1 | tee /tmp/seed.log; then
    print_success "Database seeded successfully with all data"
else
    print_info "Main seed had issues, trying seed-all directly..."
    
    # Try seed-all.ts directly
    if [ -f "prisma/seeds/seed-all.ts" ]; then
        print_info "Running comprehensive seed..."
        if npx tsx prisma/seeds/seed-all.ts 2>&1 | tee -a /tmp/seed.log; then
            print_success "Comprehensive seed completed"
        else
            print_error "Comprehensive seed failed, trying individual seeds..."
            
            # Fallback to individual seeds
            if [ -f "prisma/seeds/permissions.ts" ]; then
                print_info "Seeding permissions..."
                npx tsx prisma/seeds/permissions.ts || print_error "Permissions seed failed"
            fi
            
            if [ -f "prisma/seeds/keuangan-categories.ts" ]; then
                print_info "Seeding financial categories..."
                npx tsx prisma/seeds/keuangan-categories.ts || print_error "Categories seed failed"
            fi
            
            if [ -f "prisma/seeds/seed-admin.ts" ]; then
                print_info "Seeding admin user..."
                npx tsx prisma/seeds/seed-admin.ts || print_error "Admin seed failed"
            fi
        fi
    fi
fi

# Verify admin user was created
print_info "Verifying admin user..."
ADMIN_CHECK=$(mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} -se "SELECT COUNT(*) FROM admin_users WHERE role='SUPER_ADMIN';" 2>/dev/null || echo "0")

if [ "$ADMIN_CHECK" -ge "1" ]; then
    print_success "Admin user verified ($ADMIN_CHECK user(s) found)"
else
    print_error "Warning: Admin user not found in database. You may need to seed manually."
    print_info "You can seed later with: cd ${APP_DIR} && npx tsx prisma/seeds/seed-all.ts"
fi

print_success "Application setup and database schema completed"

# ===================================
# 5. INSTALL FREERADIUS 3.x
# ===================================
print_info "Step 5: Installing FreeRADIUS..."

# Stop any existing FreeRADIUS
print_info "Removing old FreeRADIUS installation (if exists)..."
systemctl stop freeradius 2>/dev/null || true
killall -9 freeradius 2>/dev/null || true

# Complete removal of old installation
apt-get remove --purge -y freeradius freeradius-mysql freeradius-utils freeradius-common 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean 2>/dev/null || true
rm -rf /etc/freeradius /var/log/freeradius /var/run/freeradius 2>/dev/null || true

print_info "Installing fresh FreeRADIUS..."
apt-get install -y freeradius freeradius-mysql freeradius-utils freeradius-rest

# Function to remove BOM (Byte Order Mark) from files
# This handles UTF-8 BOM, UTF-16 LE/BE, and converts to clean UTF-8
remove_bom() {
    local file="$1"
    if [ -f "$file" ]; then
        # Get first bytes to detect encoding
        local first_bytes=$(head -c 4 "$file" | xxd -p 2>/dev/null)
        local needs_cleanup=false
        
        # Check for UTF-16 LE BOM (FF FE)
        if [[ "${first_bytes:0:4}" == "fffe" ]]; then
            print_info "Detected UTF-16 LE BOM in $file, converting..."
            iconv -f UTF-16LE -t UTF-8 "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" || {
                # If iconv fails, try removing BOM and using sed
                tail -c +3 "$file" | tr -d '\0' > "$file.tmp" && mv "$file.tmp" "$file"
            }
            needs_cleanup=true
        # Check for UTF-16 BE BOM (FE FF)
        elif [[ "${first_bytes:0:4}" == "feff" ]]; then
            print_info "Detected UTF-16 BE BOM in $file, converting..."
            iconv -f UTF-16BE -t UTF-8 "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" || {
                tail -c +3 "$file" | tr -d '\0' > "$file.tmp" && mv "$file.tmp" "$file"
            }
            needs_cleanup=true
        # Check for UTF-8 BOM (EF BB BF)
        elif [[ "${first_bytes:0:6}" == "efbbbf" ]]; then
            print_info "Detected UTF-8 BOM in $file, removing..."
            tail -c +4 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            needs_cleanup=true
        fi
        
        # Additional cleanup with sed for any remaining BOMs
        sed -i '1s/^\xEF\xBB\xBF//' "$file" 2>/dev/null || true
        sed -i '1s/^\xFF\xFE//' "$file" 2>/dev/null || true
        sed -i '1s/^\xFE\xFF//' "$file" 2>/dev/null || true
        
        # Remove any null bytes that might remain from UTF-16 conversion
        if [ "$needs_cleanup" = true ]; then
            tr -d '\0' < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            print_success "BOM removed from $file"
        fi
    fi
}

# Check if backup configs exist in project
FR_BACKUP_DIR="${APP_DIR}/freeradius-config"
if [ -d "$FR_BACKUP_DIR" ] && [ -f "$FR_BACKUP_DIR/mods-enabled-sql" ]; then
    print_info "Found FreeRADIUS backup configs in project..."
    print_info "Restoring FreeRADIUS configuration from backup..."
    
    # Restore SQL module
    if [ -f "$FR_BACKUP_DIR/mods-enabled-sql" ]; then
        cp "$FR_BACKUP_DIR/mods-enabled-sql" /etc/freeradius/3.0/mods-available/sql
        remove_bom /etc/freeradius/3.0/mods-available/sql
        # Update credentials in SQL config
        sed -i "s/login = .*/login = \"${DB_USER}\"/" /etc/freeradius/3.0/mods-available/sql
        sed -i "s/password = .*/password = \"${DB_PASSWORD}\"/" /etc/freeradius/3.0/mods-available/sql
        sed -i "s/radius_db = .*/radius_db = \"${DB_NAME}\"/" /etc/freeradius/3.0/mods-available/sql
        # Remove old symlink and create new one
        rm -f /etc/freeradius/3.0/mods-enabled/sql
        ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql
        print_success "SQL module restored"
    fi
    
    # Restore REST module
    if [ -f "$FR_BACKUP_DIR/mods-enabled-rest" ]; then
        cp "$FR_BACKUP_DIR/mods-enabled-rest" /etc/freeradius/3.0/mods-available/rest
        remove_bom /etc/freeradius/3.0/mods-available/rest
        rm -f /etc/freeradius/3.0/mods-enabled/rest
        ln -sf /etc/freeradius/3.0/mods-available/rest /etc/freeradius/3.0/mods-enabled/rest
        print_success "REST module restored"
    fi
    
    # Restore sites-enabled/default
    if [ -f "$FR_BACKUP_DIR/sites-enabled-default" ]; then
        cp "$FR_BACKUP_DIR/sites-enabled-default" /etc/freeradius/3.0/sites-available/default
        remove_bom /etc/freeradius/3.0/sites-available/default
        rm -f /etc/freeradius/3.0/sites-enabled/default
        ln -sf /etc/freeradius/3.0/sites-available/default /etc/freeradius/3.0/sites-enabled/default
        print_success "Default site restored"
    fi
    
    # Restore clients.conf
    if [ -f "$FR_BACKUP_DIR/clients.conf" ]; then
        cp "$FR_BACKUP_DIR/clients.conf" /etc/freeradius/3.0/clients.conf
        remove_bom /etc/freeradius/3.0/clients.conf
        print_success "Clients config restored"
    fi
    
    # Disable filter_username policy to allow PPPoE username@realm format
    print_info "Disabling filter_username policy for PPPoE support..."
    if grep -q "^\s*filter_username" /etc/freeradius/3.0/sites-enabled/default 2>/dev/null; then
        sed -i 's/^\(\s*\)filter_username/\1#filter_username # DISABLED for PPPoE realm support/' /etc/freeradius/3.0/sites-enabled/default
        print_success "filter_username policy disabled"
    fi
    
    print_success "FreeRADIUS configuration restored from backup"
else
    print_info "No backup configs found, creating fresh configuration..."
    
    # Configure FreeRADIUS to use MySQL
    print_info "Configuring FreeRADIUS SQL module..."
    cat > /etc/freeradius/3.0/mods-available/sql <<EOF
sql {
    driver = "rlm_sql_mysql"
    dialect = "mysql"
    
    server = "localhost"
    port = 3306
    login = "${DB_USER}"
    password = "${DB_PASSWORD}"
    
    radius_db = "${DB_NAME}"
    
    acct_table1 = "radacct"
    acct_table2 = "radacct"
    postauth_table = "radpostauth"
    authcheck_table = "radcheck"
    groupcheck_table = "radgroupcheck"
    authreply_table = "radreply"
    groupreply_table = "radgroupreply"
    usergroup_table = "radusergroup"
    
    # Group attribute for user groups
    group_attribute = "SQL-Group"
    
    # CRITICAL: Set sql_user_name to query for users!
    sql_user_name = "%{User-Name}"
    
    # Load NAS/clients from database
    read_clients = yes
    client_table = "nas"
    
    # Enable read_groups to check user groups
    read_groups = yes
    read_profiles = yes
    
    # Set delete_stale_sessions
    delete_stale_sessions = yes
    
    pool {
        start = 5
        min = 4
        max = 32
        spare = 3
        uses = 0
        lifetime = 0
        idle_timeout = 60
    }
}
EOF

    # Configure REST module for voucher management
    print_info "Configuring FreeRADIUS REST module..."
    cat > /etc/freeradius/3.0/mods-available/rest <<EOF
rest {
    tls {
        check_cert = no
        check_cert_cn = no
    }

    connect_uri = "http://localhost:3000"

    # CRITICAL: Authorize pre-check (Dec 13, 2025 - Voucher Validation)
    # This validates voucher status BEFORE password check
    # Prevents expired vouchers from authenticating
    authorize {
        uri = "\${..connect_uri}/api/radius/authorize"
        method = "post"
        body = "json"
        data = "{ \"username\": \"%{User-Name}\", \"nasIp\": \"%{NAS-IP-Address}\" }"
        timeout = 2
        tls = \${..tls}
    }

    # Post-auth: call webhook when user authenticated successfully
    post-auth {
        uri = "\${..connect_uri}/api/radius/post-auth"
        method = "post"
        body = "json"
        data = "{ \"username\": \"%{User-Name}\", \"reply\": \"%{reply:Packet-Type}\", \"nasIp\": \"%{NAS-IP-Address}\", \"framedIp\": \"%{Framed-IP-Address}\" }"
        tls = \${..tls}
    }

    # Accounting: track session start/stop
    accounting {
        uri = "\${..connect_uri}/api/radius/accounting"
        method = "post"
        body = "json"
        data = "{ \"username\": \"%{User-Name}\", \"statusType\": \"%{Acct-Status-Type}\", \"sessionId\": \"%{Acct-Session-Id}\", \"nasIp\": \"%{NAS-IP-Address}\", \"framedIp\": \"%{Framed-IP-Address}\", \"sessionTime\": \"%{Acct-Session-Time}\", \"inputOctets\": \"%{Acct-Input-Octets}\", \"outputOctets\": \"%{Acct-Output-Octets}\" }"
        tls = \${..tls}
    }

    pool {
        start = 0
        min = 0
        max = 32
        spare = 1
        uses = 0
        lifetime = 0
        idle_timeout = 60
        connect_timeout = 3
    }
}
EOF

    # Enable REST module
    print_info "Enabling REST module..."
    ln -sf /etc/freeradius/3.0/mods-available/rest /etc/freeradius/3.0/mods-enabled/rest

    # Enable SQL module
    print_info "Enabling SQL module..."
    # Remove any duplicate or backup files
    rm -f /etc/freeradius/3.0/mods-enabled/sql*
    rm -f /etc/freeradius/3.0/mods-available/sql.bak
    ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

    # Configure sites-enabled/default for PPPoE and Hotspot
    print_info "Configuring sites-enabled/default..."

    # 1. Disable filter_username to allow username@realm format for PPPoE
    # Find and comment out filter_username in authorize section
    if grep -q "^\s*filter_username" /etc/freeradius/3.0/sites-enabled/default; then
        sed -i 's/^\(\s*\)filter_username/\1#filter_username # DISABLED for PPPoE realm support/' /etc/freeradius/3.0/sites-enabled/default
        print_success "Disabled filter_username policy"
    fi

    # 2. Add conditional REST for vouchers in post-auth section
    # Only call REST API for vouchers (username without @)
    # PPPoE users (username@realm) will skip REST call
    if ! grep -q "Call REST API for voucher" /etc/freeradius/3.0/sites-enabled/default; then
        # Find the line with "-sql" in post-auth section and add REST condition after it
        # This targets the -sql after "Authentication Logging Queries"
        sed -i '/See "Authentication Logging Queries"/,/^[[:space:]]*-sql/{
            s/^\([[:space:]]*\)-sql$/\1-sql\n\n\1# Call REST API for voucher only (username without @)\n\1# PPPoE uses username@realm format, voucher does not have @\n\1if (!("%{User-Name}" =~ \/@\/)) {\n\1        rest.post-auth\n\1}/
        }' /etc/freeradius/3.0/sites-enabled/default
        print_success "Added conditional REST for vouchers"
    fi

    # Configure FreeRADIUS for CoA (Change of Authorization)
    print_info "Configuring CoA support..."
    if ! grep -q "type = coa" /etc/freeradius/3.0/sites-available/default; then
        cat >> /etc/freeradius/3.0/sites-available/default <<EOF

# CoA/Disconnect support
listen {
    type = coa
    ipaddr = *
    port = 3799
}
EOF
    fi
fi

# Set permissions
print_info "Setting FreeRADIUS permissions..."
chown -R freerad:freerad /etc/freeradius/3.0/
chmod 640 /etc/freeradius/3.0/mods-available/sql
chmod 750 /etc/freeradius/3.0/mods-enabled

# Test configuration before starting
print_info "Testing FreeRADIUS configuration..."

# Stop FreeRADIUS jika sudah running
systemctl stop freeradius 2>/dev/null || true
pkill -9 freeradius 2>/dev/null || true
sleep 2

# Check for duplicate modules
if freeradius -C 2>&1 | grep -qi "duplicate module"; then
    print_error "Found duplicate module configuration!"
    echo "Cleaning up duplicate files..."
    rm -f /etc/freeradius/3.0/mods-enabled/*.bak
    rm -f /etc/freeradius/3.0/mods-available/*.bak
    rm -f /etc/freeradius/3.0/sites-enabled/*.bak
    echo "Retrying configuration test..."
fi

if freeradius -C > /dev/null 2>&1; then
    print_success "FreeRADIUS configuration test passed"
    # Show any warnings
    WARNINGS=$(freeradius -C 2>&1 | grep -i warning || true)
    if [ -n "$WARNINGS" ]; then
        echo "  âš ï¸  Warnings (dapat diabaikan):"
        echo "$WARNINGS"
    fi
else
    print_error "FreeRADIUS configuration test failed"
    echo "Running in debug mode to show errors..."
    freeradius -X 2>&1 | head -100
    exit 1
fi

# Start FreeRADIUS
print_info "Starting FreeRADIUS..."
systemctl enable freeradius
systemctl start freeradius

# Wait and check status
sleep 3
if systemctl is-active --quiet freeradius; then
    print_success "FreeRADIUS started successfully"
else
    print_error "FreeRADIUS failed to start, checking logs..."
    journalctl -xeu freeradius.service --no-pager | tail -20
fi

print_success "FreeRADIUS installed and configured"

# ===================================
# 6. INSTALL PM2 (Process Manager)
# ===================================
print_info "Step 6: Installing PM2..."

npm install -g pm2
pm2 startup systemd -u root --hp /root

print_success "PM2 installed"

# ===================================
# 7. CONFIGURE NGINX
# ===================================
print_info "Step 7: Configuring Nginx..."

# Nginx configuration will use existing .env from Step 4
cat > /etc/nginx/sites-available/salfanet-radius <<EOF
server {
    listen 80;
    server_name ${VPS_IP};

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Client body size (for file uploads)
    client_max_body_size 10M;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/salfanet-radius /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

# Restart nginx
systemctl restart nginx
systemctl enable nginx

print_success "Nginx configured"

# ===================================
# 8. CONFIGURE FIREWALL
# ===================================
print_info "Step 8: Configuring firewall..."

ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 1812/udp  # RADIUS Auth
ufw allow 1813/udp  # RADIUS Accounting
ufw allow 3799/udp  # RADIUS CoA/Disconnect

print_success "Firewall configured"

# ===================================
# 10. SETUP SUDOERS FOR FREERADIUS
# ===================================
print_info "Step 10: Setting up sudoers for FreeRADIUS restart..."

cat > /etc/sudoers.d/freeradius-restart <<EOF
# Allow www-data (nginx/pm2) to restart FreeRADIUS without password
root ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart freeradius
root ALL=(ALL) NOPASSWD: /usr/bin/systemctl status freeradius
root ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload freeradius
EOF

chmod 440 /etc/sudoers.d/freeradius-restart

print_success "Sudoers configured"

# ===================================
# 10. CREATE PM2 ECOSYSTEM FILE
# ===================================
print_info "Step 10: Creating PM2 ecosystem file..."

cat > ${APP_DIR}/ecosystem.config.js <<EOF
module.exports = {
  apps: [{
    name: 'salfanet-radius',
    script: 'npm',
    args: 'start',
    cwd: '${APP_DIR}',
    instances: 1,
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000,
      TZ: 'Asia/Jakarta'
    },
    error_file: '${APP_DIR}/logs/error.log',
    out_file: '${APP_DIR}/logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    autorestart: true,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
EOF

mkdir -p ${APP_DIR}/logs

print_success "PM2 ecosystem file created"

# ===================================
# 11. CREATE DEPLOYMENT SCRIPT
# ===================================
print_info "Step 11: Creating deployment script..."

cat > ${APP_DIR}/deploy.sh <<'EOF'
#!/bin/bash
set -e

echo "ðŸš€ Deploying SALFANET RADIUS..."

APP_DIR="/var/www/salfanet-radius"
cd ${APP_DIR}

# Pull latest code (if using git)
if [ -d ".git" ]; then
    echo "ðŸ“¥ Pulling latest code..."
    git pull origin main
fi

# Install dependencies
echo "ðŸ“¦ Installing dependencies..."
npm install --production=false

# Generate Prisma Client
echo "ðŸ”§ Generating Prisma Client..."
npx prisma generate

# Push database schema (for first time or schema changes)
echo "ðŸ’¾ Updating database schema..."
npx prisma db push --accept-data-loss

# Run migrations (alternative to db push)
# npx prisma migrate deploy

# Build Next.js application
echo "ðŸ—ï¸  Building application..."
npm run build

# Restart PM2
echo "ðŸ”„ Restarting application..."
pm2 restart salfanet-radius || pm2 start ecosystem.config.js

# Save PM2 configuration
pm2 save

echo "âœ… Deployment completed!"
echo ""
echo "ðŸ“Š Application status:"
pm2 status

echo ""
echo "ðŸ“ View logs:"
echo "   pm2 logs salfanet-radius"
EOF

chmod +x ${APP_DIR}/deploy.sh

print_success "Deployment script created"

# ===================================
# 12. CREATE INSTALLATION INFO FILE
# ===================================
print_info "Step 12: Creating installation info..."

cat > ${APP_DIR}/INSTALLATION_INFO.txt <<EOF
============================================
SALFANET RADIUS - Installation Information
============================================

ðŸ“… Installation Date: $(date)
ðŸ–¥ï¸  VPS IP: ${VPS_IP}
ðŸ• Timezone: $(timedatectl show --property=Timezone --value)
ðŸ• Current Time: $(date '+%Y-%m-%d %H:%M:%S %Z')

ðŸ“Š SYSTEM INFORMATION
--------------------
Operating System: $(lsb_release -d | cut -f2)
Node.js Version: $(node --version)
npm Version: $(npm --version)
MySQL Version: $(mysql --version)
FreeRADIUS Version: $(freeradius -v | head -n1)
NTP Status: $(chronyc tracking | grep 'Reference ID' | awk '{print $4}' || echo 'Not synced')

ðŸ—„ï¸  DATABASE CREDENTIALS
-----------------------
Database Name: ${DB_NAME}
Database User: ${DB_USER}
Database Password: ${DB_PASSWORD}
Root Password: ${DB_ROOT_PASSWORD}

âš™ï¸  APPLICATION CONFIGURATION
----------------------------
App Directory: ${APP_DIR}
Environment File: ${APP_DIR}/.env
PM2 Config: ${APP_DIR}/ecosystem.config.js
Deployment Script: ${APP_DIR}/deploy.sh

ðŸŒ ACCESS INFORMATION
--------------------
Application URL: http://${VPS_IP}
Admin Panel: http://${VPS_IP}/admin/login

Default Admin Credentials (after seeding):
Username: superadmin
Password: admin123
âš ï¸  CHANGE THIS PASSWORD IMMEDIATELY!

ðŸ“¡ FTTH NETWORK FEATURES
------------------------
- OLT Management: /admin/network/olts
- ODC Management: /admin/network/odcs
- ODP Management: /admin/network/odps
- Customer Assignment: /admin/network/customers

Features:
- GPS location dengan Map picker
- Assign pelanggan ke port ODP
- Perhitungan jarak otomatis
- Sync PPPoE dari MikroTik

ðŸ“ LOGS LOCATION
---------------
Application Logs: ${APP_DIR}/logs/
FreeRADIUS Logs: /var/log/freeradius/
Nginx Logs: /var/log/nginx/

ðŸ”§ USEFUL COMMANDS
-----------------
# Application Management
pm2 status                    # Check application status
pm2 logs salfanet-radius        # View application logs
pm2 restart salfanet-radius     # Restart application
pm2 stop salfanet-radius        # Stop application

# FreeRADIUS Management
sudo systemctl status freeradius   # Check FreeRADIUS status
sudo systemctl restart freeradius  # Restart FreeRADIUS
sudo freeradius -X                 # Debug mode (stop service first)

# Database Management
mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME}

# Nginx Management
sudo systemctl status nginx
sudo systemctl restart nginx
sudo nginx -t                  # Test configuration

# View Logs
tail -f ${APP_DIR}/logs/out.log
tail -f ${APP_DIR}/logs/error.log
tail -f /var/log/freeradius/radius.log

# Time & NTP Management
timedatectl                       # Show current time & timezone
chronyc tracking                  # Check NTP sync status
chronyc sources                   # Show NTP servers
sudo chronyc makestep             # Force time sync
date                              # Show current date/time

ðŸš€ DEPLOYMENT STEPS
------------------
1. Upload your code to: ${APP_DIR}
2. Run deployment script: ${APP_DIR}/deploy.sh
3. Run database seeding (if needed):
   cd ${APP_DIR}
   npx tsx prisma/seeds/seed-all.ts
   # seed-all.ts includes:
   # - Transaction categories (13)
   # - Permissions (53) + Role templates
   # - Admin user (superadmin/admin123)
   # - Hotspot profiles (5 sample)
   # - WhatsApp templates (6)
   # - RADIUS isolir group

ðŸ“‹ FIREWALL RULES
----------------
Port 22   - SSH
Port 80   - HTTP
Port 443  - HTTPS
Port 1812 - RADIUS Authentication
Port 1813 - RADIUS Accounting
Port 3799 - RADIUS CoA/Disconnect

ðŸ”Œ GENIEACS INTEGRATION (Optional)
---------------------------------
If you have GenieACS server for TR-069 management:
1. Go to Admin â†’ Settings â†’ GenieACS
2. Configure:
   - GenieACS URL: http://YOUR_GENIEACS_IP:7557
   - Username/Password (if auth enabled)
3. Test connection
4. Access: Admin â†’ GenieACS â†’ Devices

For GenieACS installation guide, see:
docs/GENIEACS-GUIDE.md

ðŸ” SECURITY RECOMMENDATIONS
--------------------------
1. Change default admin password immediately
2. Change MySQL root password
3. Setup SSL certificate (Let's Encrypt)
4. Configure fail2ban for SSH protection
5. Regular system updates
6. Regular database backups
7. Monitor application logs
8. Keep NTP synchronized for accurate session tracking

ðŸ• TIMEZONE TROUBLESHOOTING
---------------------------
If time is incorrect:
1. Check timezone: timedatectl
2. Set timezone: sudo timedatectl set-timezone Asia/Jakarta
3. Force NTP sync: sudo chronyc makestep
4. Check NTP sources: chronyc sources -v
5. Restart chrony: sudo systemctl restart chrony

Common timezone codes:
- Asia/Jakarta (WIB - UTC+7)
- Asia/Makassar (WITA - UTC+8)
- Asia/Jayapura (WIT - UTC+9)

ðŸ“ž SUPPORT
---------
GitHub: https://github.com/gnetid/salfanet-radius
Documentation: Check README.md in app directory

============================================
Installation completed successfully! ðŸŽ‰
============================================
EOF

print_success "Installation info created"

# ===================================
# 13. BUILD & START APPLICATION
# ===================================
print_info "Step 13: Building and starting application..."

# Step 9: Build Application
print_info "Step 13: Building Next.js application..."
print_info "This is a critical step that requires adequate memory..."

# Verify all prerequisites
print_info "Verifying prerequisites..."

if [ ! -d "node_modules" ]; then
    print_error "node_modules not found!"
    print_info "Run: cd ${APP_DIR} && npm install"
    exit 1
fi

# Check memory and create swap if needed
TOTAL_MEM=$(free -m | awk 'NR==2{printf "%s", $2}')
AVAILABLE_MEM=$(free -m | awk 'NR==2{printf "%s", $7}')
print_info "System memory: ${TOTAL_MEM}MB total, ${AVAILABLE_MEM}MB available"

if [ "$TOTAL_MEM" -lt "2000" ]; then
    print_info "Low memory system detected (< 2GB RAM)"
    
    if [ ! -f /swapfile ]; then
        print_info "Creating 2GB swap file (one-time setup)..."
        print_info "This will take 2-3 minutes..."
        
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress 2>&1 | grep -v "records"
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        
        print_success "Swap file created and activated"
        free -h
    else
        print_success "Swap file already exists"
        swapon /swapfile 2>/dev/null || true
    fi
fi

# Clean previous build attempts
print_info "Cleaning previous build artifacts..."
rm -rf .next .turbo node_modules/.cache 2>/dev/null || true
print_success "Build cache cleared"

# Build with optimized settings
print_info "Starting Next.js build process..."
print_info "Building with Node.js memory limit: 1.5GB"
print_info "This will take 5-10 minutes - please be patient!"
echo ""

# Build command with optimizations
if NODE_OPTIONS="--max-old-space-size=1536 --max-semi-space-size=64" \
   NEXT_TELEMETRY_DISABLED=1 \
   npm run build 2>&1 | tee /tmp/build.log; then
    print_success "Build completed successfully!"
else
    print_error "Build failed!"
    echo ""
    print_info "Build error details:"
    echo "=========================================="
    grep -i "error" /tmp/build.log | tail -20 || tail -30 /tmp/build.log
    echo "=========================================="
    echo ""
    print_info "Common solutions:"
    echo "  1. Ensure you have enough memory/swap"
    echo "  2. Try: cd ${APP_DIR} && ./simple-build.sh"
    echo "  3. Check full log: cat /tmp/build.log"
    exit 1
fi

# Verify build output
if [ ! -d ".next" ]; then
    print_error ".next directory not created! Build may have failed."
    exit 1
fi

print_success ".next build directory verified"

# Create logs directory
mkdir -p ${APP_DIR}/logs

# Start with PM2
print_info "Starting application with PM2..."
pm2 delete salfanet-radius 2>/dev/null || true

if ! pm2 start ecosystem.config.js 2>&1 | tee /tmp/pm2-start.log; then
    print_error "PM2 start failed!"
    cat /tmp/pm2-start.log
    exit 1
fi

# Save PM2 configuration
pm2 save
pm2 startup systemd -u root --hp /root

# Wait a bit for app to start
sleep 3

# Check if app is running
if pm2 list | grep -q "salfanet-radius.*online"; then
    print_success "Application started successfully!"
else
    print_error "Application failed to start!"
    pm2 logs salfanet-radius --lines 20 --nostream
    exit 1
fi

print_success "Application deployed and started"

# ===================================
# FINAL MESSAGE
# ===================================
echo ""
echo "=============================================="
echo -e "${GREEN}âœ“ Installation completed successfully!${NC}"
echo "=============================================="
echo ""
echo "ðŸŽ‰ Application is now running!"
echo ""
echo "3. Access your application:"
echo "   http://${VPS_IP}"
echo ""
echo "ðŸ“– Full installation details saved to:"
echo "   ${APP_DIR}/INSTALLATION_INFO.txt"
echo ""
echo "ðŸ”‘ Important credentials:"
echo "   Database Name: ${DB_NAME}"
echo "   Database User: ${DB_USER}"
echo "   Database Password: ${DB_PASSWORD}"
echo "   MySQL Root Password: ${DB_ROOT_PASSWORD}"
echo "   NextAuth Secret: ${NEXTAUTH_SECRET}"
echo ""
echo "âš ï¸  SECURITY NOTICE:"
echo "   - Change default admin password after first login"
echo "   - Configure SSL certificate for production"
echo "   - Review firewall rules"
echo ""
echo "=============================================="
