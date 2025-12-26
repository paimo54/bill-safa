module.exports = {
  apps: [{
    name: 'salfanet-radius',
    script: 'npm',
    args: 'start',
    cwd: '/var/www/aibill-radius',
    instances: 1,
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000,
      TZ: 'Asia/Jakarta'
    },
    error_file: '/var/www/aibill-radius/logs/error.log',
    out_file: '/var/www/aibill-radius/logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    autorestart: true,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
