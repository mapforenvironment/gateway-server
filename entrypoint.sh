#!/bin/sh

set -euo pipefail

# Validate environment variables

MISSING=""

[ -z "${DOMAIN}" ] && MISSING="${MISSING} DOMAIN"
[ -z "${TASKSDOMAIN}" ] && MISSING="${TASKSDOMAIN} DOMAIN"
[ -z "${EMAIL}" ] && MISSING="${MISSING} EMAIL"

if [ "${MISSING}" != "" ]; then
  echo "Missing required environment variables:" >&2
  echo " ${MISSING}" >&2
  exit 1
fi

# Default other parameters

SERVER=""
[ -n "${STAGING:-}" ] && SERVER="--server https://acme-staging.api.letsencrypt.org/directory"

# Generate strong DH parameters for nginx, if they don't already exist.
if [ ! -f /etc/ssl/dhparams.pem ]; then
  if [ -f /cache/dhparams.pem ]; then
    cp /cache/dhparams.pem /etc/ssl/dhparams.pem
  else
    openssl dhparam -out /etc/ssl/dhparams.pem 2048
    # Cache to a volume for next time?
    if [ -d /cache ]; then
      cp /etc/ssl/dhparams.pem /cache/dhparams.pem
    fi
  fi
fi

#create temp file storage
mkdir -p /var/cache/nginx
chown nginx:nginx /var/cache/nginx

mkdir -p /var/tmp/nginx
chown nginx:nginx /var/tmp/nginx


mkdir -p /var/cache/nginx
chown nginx:nginx /var/cache/nginx

mkdir -p /var/tmp/nginx
chown nginx:nginx /var/tmp/nginx

# Template an nginx.conf
cat <<EOF >/etc/nginx/nginx.conf
user nginx;
worker_processes 2;

events {
  worker_connections 1024;
}

http {
  include mime.types;
  default_type application/octet-stream;

  proxy_cache_path /var/cache/nginx keys_zone=anonymous:10m;
  proxy_temp_path /var/tmp/nginx;
  client_body_temp_path /var/tmp/nginx/client_body_temp;
  proxy_request_buffering off;

  client_max_body_size 300M;

  sendfile on;
  tcp_nopush on;
  keepalive_timeout 65;

  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;



  upstream taskmgr {
    server ${TM_WEB_1_PORT_6543_TCP_ADDR}:6543;
  }

  server {
    listen 443 ssl;
    server_name "${TASKSDOMAIN}";

    ssl_certificate /etc/letsencrypt/live/${TASKSDOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${TASKSDOMAIN}/privkey.pem;
    ssl_dhparam /etc/ssl/dhparams.pem;

    ssl_ciphers "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA";
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    root /etc/letsencrypt/webrootauth;

    location / {
      proxy_pass http://taskmgr;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$remote_addr;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_cache   anonymous;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
    }

    location /.well-known/acme-challenge {
      alias /etc/letsencrypt/webrootauth/.well-known/acme-challenge;
      location ~ /.well-known/acme-challenge/(.*) {
        add_header Content-Type application/jose+json;
      }
    }
  }

  # Redirect from port 80 to port 443
  server {
    listen 80;
    server_name "${TASKSDOMAIN}";
    return 301 https://${TASKSDOMAIN}\$request_uri;
  }

  upstream wordpress {
    server ${WORDPRESS_1_PORT_80_TCP_ADDR}:80;
  }

  server {
    listen 443 ssl;
    server_name "${DOMAIN}";

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_dhparam /etc/ssl/dhparams.pem;

    ssl_ciphers "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA";
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    root /etc/letsencrypt/webrootauth;

    location / {
      proxy_pass http://wordpress;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$remote_addr;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_cache   anonymous;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
    }

    location /.well-known/acme-challenge {
      alias /etc/letsencrypt/webrootauth/.well-known/acme-challenge;
      location ~ /.well-known/acme-challenge/(.*) {
        add_header Content-Type application/jose+json;
      }
    }
  }

  server {
    listen 80;
    server_name "${DOMAIN}";
    return 301 https://${DOMAIN}\$request_uri;
  }

  server {
    listen 443 ssl;
    server_name "maphubs.com";

    ssl_certificate /etc/letsencrypt/live/maphubs.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/maphubs.com/privkey.pem;
    ssl_dhparam /etc/ssl/dhparams.pem;

    ssl_ciphers "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA";
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    #add_header Strict-Transport-Security "max-age=63072000; preload";
    #add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    root /etc/letsencrypt/webrootauth;

    location / {
      proxy_pass http://website.maphubs.com:80;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$remote_addr;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_cache   anonymous;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
    }

    location /.well-known/acme-challenge {
      alias /etc/letsencrypt/webrootauth/.well-known/acme-challenge;
      location ~ /.well-known/acme-challenge/(.*) {
        add_header Content-Type application/jose+json;
      }
    }
  }

  server {
    listen 80;
    server_name "maphubs.com";
    return 301 https://maphubs.com\$request_uri;
  }

  upstream crowdcover {
    server ${CROWDCOVER_1_PORT_4003_TCP_ADDR}:4003;
  }

  server {
    listen 443 ssl;
    server_name "crowdcover.us";

    ssl_certificate /etc/letsencrypt/live/crowdcover.us/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/crowdcover.us/privkey.pem;
    ssl_dhparam /etc/ssl/dhparams.pem;

    ssl_ciphers "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA";
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;

    root /etc/letsencrypt/webrootauth;

    location / {
      proxy_pass http://crowdcover;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$remote_addr;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_cache   anonymous;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
    }

    location /.well-known/acme-challenge {
      alias /etc/letsencrypt/webrootauth/.well-known/acme-challenge;
      location ~ /.well-known/acme-challenge/(.*) {
        add_header Content-Type application/jose+json;
      }
    }
  }

  server {
    listen 80;
    server_name "crowdcover.us";
    return 301 https://crowdcover.us\$request_uri;
  }

  server {
    listen 80;
    listen 443 ssl;
    server_name www.crowdcover.us;
    return 302 \$scheme://crowdcover.us;
  }
  server {
    listen 80;
    listen 443 ssl;
    server_name crowdcover.org;
    return 302 \$scheme://crowdcover.us;
  }
  server {
    listen 80;
    listen 443 ssl;
    server_name www.crowdcover.org;
    return 302 \$scheme://crowdcover.us;
  }
}
EOF
TERM=xterm
# Initial certificate request, but skip if cached
if [ ! -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ]; then
  letsencrypt certonly \
    --domain ${DOMAIN} \
    --authenticator standalone \
    ${SERVER} \
    --email "${EMAIL}" --agree-tos --text --non-interactive
fi

if [ ! -f /etc/letsencrypt/live/${TASKSDOMAIN}/fullchain.pem ]; then
  letsencrypt certonly \
    --domain ${TASKSDOMAIN} \
    --authenticator standalone \
    ${SERVER} \
    --email "${EMAIL}" --agree-tos --text --non-interactive
fi

if [ ! -f /etc/letsencrypt/live/crowdcover.us/fullchain.pem ]; then
  letsencrypt certonly \
    --domain crowdcover.us \
    --authenticator standalone \
    ${SERVER} \
    --email "${EMAIL}" --agree-tos --text --non-interactive
fi

if [ ! -f /etc/letsencrypt/live/maphubs.com/fullchain.pem ]; then
  letsencrypt certonly \
    --domain maphubs.com \
    --authenticator standalone \
    ${SERVER} \
    --email "${EMAIL}" --agree-tos --text --non-interactive
fi

# Template a cronjob to reissue the certificate with the webroot authenticator
cat <<EOF >/etc/periodic/monthly/reissue
#!/bin/sh

set -euo pipefail
TERM=xterm
mkdir -p /etc/letsencrypt/webrootauth
# Certificate reissue
letsencrypt certonly --renew-by-default \
  --domain "${TASKSDOMAIN}" \
  --authenticator webroot \
  --webroot-path /etc/letsencrypt/webrootauth/ ${SERVER} \
  --email "${EMAIL}" --agree-tos --text --non-interactive

letsencrypt certonly --renew-by-default \
  --domain "${DOMAIN}" \
  --authenticator webroot \
  --webroot-path /etc/letsencrypt/webrootauth/ ${SERVER} \
  --email "${EMAIL}" --agree-tos --text --non-interactive

letsencrypt certonly --renew-by-default \
  --domain "crowdcover.us" \
  --authenticator webroot \
  --webroot-path /etc/letsencrypt/webrootauth/ ${SERVER} \
  --email "${EMAIL}" --agree-tos --text --non-interactive

  letsencrypt certonly --renew-by-default \
    --domain "maphubs.com" \
    --authenticator webroot \
    --webroot-path /etc/letsencrypt/webrootauth/ ${SERVER} \
    --email "${EMAIL}" --agree-tos --text --non-interactive

# Reload nginx configuration to pick up the reissued certificates
/usr/sbin/nginx -s reload
EOF
chmod +x /etc/periodic/monthly/reissue

# Kick off cron to reissue certificates as required
# Background the process and log to stderr
/usr/sbin/crond -f -d 8 &

echo Ready
# Launch nginx in the foreground
/usr/sbin/nginx -g "daemon off;"
