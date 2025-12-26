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
