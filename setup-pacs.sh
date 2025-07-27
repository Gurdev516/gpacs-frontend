#!/bin/bash
set -e

DOMAIN="pacs.jpreet.com"
USERNAME=$(whoami)  # Auto-detect username

echo "✅ Detected username: $USERNAME"

echo "🔹 Updating system..."
sudo apt update && sudo apt upgrade -y

echo "🔹 Installing Orthanc, Nginx, Certbot..."
sudo apt install -y orthanc orthanc-webviewer nginx certbot python3-certbot-nginx unzip curl tar

echo "🔹 Configuring Orthanc..."
sudo tee /etc/orthanc/orthanc.json >/dev/null <<EOF
{
  "Name": "Gurdev PACS",
  "RemoteAccessAllowed": true,
  "AuthenticationEnabled": false,
  "HttpServerEnabled": true,
  "HttpPort": 8042,
  "DicomWeb": { "Enable": true },
  "Cors": {
    "AllowOrigin": "*",
    "AllowMethods": "GET,POST,PUT,DELETE,OPTIONS",
    "AllowHeaders": "Authorization,Content-Type"
  }
}
EOF

sudo systemctl enable orthanc
sudo systemctl restart orthanc

echo "🔹 Setting up Nginx config..."
sudo tee /etc/nginx/sites-available/$DOMAIN >/dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /home/$USERNAME/react-app;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /orthanc/ {
        proxy_pass http://127.0.0.1:8042/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type' always;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

echo "🔹 Downloading React UI build..."
mkdir -p ~/react-app
curl -L https://github.com/Gurdev516/gpacs-frontend/releases/download/latest/build.tar.gz -o ~/build.tar.gz
tar -xzf ~/build.tar.gz -C ~/react-app --strip-components=1 || { echo "❌ Failed to extract build.tar.gz"; exit 1; }

if [ ! -f ~/react-app/index.html ]; then
  echo "❌ React app not found in ~/react-app"
  exit 1
else
  echo "✅ React app installed successfully."
fi

echo "🔹 Setting up SSL (Let's Encrypt)..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN --redirect || echo "⚠️ Certbot failed, continuing without SSL"

sudo systemctl restart nginx

echo "🎉 Setup Complete! Open https://$DOMAIN"
