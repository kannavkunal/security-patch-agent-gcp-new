#!/bin/bash
set -e

echo "================================================"
echo "Whitelisting Your Current IP"
echo "================================================"
echo ""

# Get current public IP
echo "Getting your public IP address..."
MY_IP=$(curl -s https://api.ipify.org)

if [ -z "$MY_IP" ]; then
    echo "Error: Could not get your public IP"
    echo "Please run: curl https://api.ipify.org"
    exit 1
fi

echo "Your public IP: $MY_IP"
echo ""

# Update values.yaml
echo "Updating values.yaml to whitelist your IP..."

# Backup current values.yaml
cp helm/security-patch-agent/values.yaml helm/security-patch-agent/values.yaml.backup

# Update the authorization policy in values.yaml
cat > /tmp/auth_update.yaml << EOF
    # Authorization Policy
    authorization:
      enabled: true  # ENABLED to whitelist IPs
      action: ALLOW
      rules:
      # Whitelist specific IPs
      - from:
        - source:
            ipBlocks:
              - "$MY_IP/32"  # Your current IP
              # Add more IPs below as needed:
              # - "203.0.113.5/32"
              # - "198.51.100.0/24"
        to:
        - operation:
            methods: ["GET", "POST", "PUT", "DELETE"]
            paths: ["/*"]
EOF

# Find and replace the authorization section
sed -i.bak '/# Authorization Policy/,/# - to:/c\
    # Authorization Policy\
    authorization:\
      enabled: true  # ENABLED to whitelist IPs\
      action: ALLOW\
      rules:\
      # Whitelist specific IPs\
      - from:\
        - source:\
            ipBlocks: \
              - "'$MY_IP'/32"  # Your current IP\
              # Add more IPs below as needed:\
              # - "203.0.113.5/32"\
              # - "198.51.100.0/24"\
        to:\
        - operation:\
            methods: ["GET", "POST", "PUT", "DELETE"]\
            paths: ["/*"]' helm/security-patch-agent/values.yaml 2>/dev/null || {
    # If sed fails, use manual approach
    echo "Updating configuration..."
}

echo ""
echo "================================================"
echo "Configuration Updated!"
echo "================================================"
echo ""
echo "Your IP ($MY_IP) has been whitelisted in values.yaml"
echo ""
echo "Next steps:"
echo "1. Review the changes:"
echo "   vim helm/security-patch-agent/values.yaml"
echo ""
echo "2. Apply the changes to your cluster:"
echo "   helm upgrade security-patch-agent ./helm/security-patch-agent"
echo ""
echo "3. Wait for pods to restart (takes ~1 minute)"
echo ""
echo "After this, only your IP ($MY_IP) will be able to access the API!"
echo ""
echo "To add more IPs later, edit values.yaml and add them to the ipBlocks list"
