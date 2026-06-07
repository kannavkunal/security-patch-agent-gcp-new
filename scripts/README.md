# Scripts Directory

## Create Webhooks Script

Automates webhook creation for all 4 vulnerable test repositories.

### Quick Start

```bash
# 1. Install PyGithub if not already installed
pip install PyGithub

# 2. Create a GitHub Personal Access Token
# Go to: https://github.com/settings/tokens
# Click: "Generate new token (classic)"
# Scopes needed: admin:repo_hook

# 3. Export your token
export GITHUB_TOKEN='ghp_your_token_here'

# 4. Run the script
python scripts/create-webhooks.py
```

### What it does

The script will:
- ✅ Authenticate with GitHub using your token
- ✅ Create webhooks on all 4 repositories:
  - kannavkunal/vulnerable-python-api
  - kannavkunal/vulnerable-node-service
  - kannavkunal/vulnerable-go-microservice
  - kannavkunal/vulnerable-java-app
- ✅ Configure each webhook with:
  - Payload URL: http://34.67.157.196/webhook/github
  - Secret: 47dca8eeae767c5f07f4967864feadcdcb34688f41022c2c8e7402662e474cd3
  - Events: pull_request only
  - Active: true

### Manual Alternative

If you prefer to create webhooks manually, follow the instructions in [WEBHOOK_SETUP.md](../WEBHOOK_SETUP.md).

### Troubleshooting

**Error: "GITHUB_TOKEN not set"**
```bash
export GITHUB_TOKEN='ghp_...'
```

**Error: "Resource not accessible by integration"**
- Your token needs `admin:repo_hook` scope
- Create a new token at: https://github.com/settings/tokens

**Error: "Not Found"**
- Verify you have access to all 4 repositories
- Check repository names are correct

### Verification

After running the script, verify webhooks were created:

1. Check webhook deliveries:
   - https://github.com/kannavkunal/vulnerable-python-api/settings/hooks
   - https://github.com/kannavkunal/vulnerable-node-service/settings/hooks
   - https://github.com/kannavkunal/vulnerable-go-microservice/settings/hooks
   - https://github.com/kannavkunal/vulnerable-java-app/settings/hooks

2. Test a webhook by creating a test PR:
   ```bash
   cd vulnerable-python-api
   git checkout -b test-webhook
   echo "test" >> README.md
   git add . && git commit -m "test webhook"
   git push origin test-webhook
   # Open PR on GitHub
   ```

3. Monitor worker logs:
   ```bash
   kubectl logs -n security-patch-agent -l app=security-patch-agent -c worker -f --insecure-skip-tls-verify
   ```

You should see:
```
INFO:__main__:Webhook: Queueing review scan for https://github.com/kannavkunal/vulnerable-python-api PR#1
```
