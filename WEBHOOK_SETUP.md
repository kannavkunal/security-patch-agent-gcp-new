# GitHub Webhook Configuration Guide

## Overview

Configure GitHub webhooks on your vulnerable repositories to enable automatic security scanning when pull requests are opened or updated.

## Webhook Secret

**IMPORTANT:** Store this secret securely. You'll need it to configure webhooks on GitHub.

```
Webhook Secret: 47dca8eeae767c5f07f4967864feadcdcb34688f41022c2c8e7402662e474cd3
```

This secret is stored in GCP Secret Manager at:
```
projects/security-patch-agent-gcp/secrets/github-webhook-secret/versions/latest
```

## Configure Webhooks for Vulnerable Repositories

Configure webhooks for all 4 vulnerable test repositories:

1. https://github.com/kannavkunal/vulnerable-python-web
2. https://github.com/kannavkunal/vulnerable-node-api
3. https://github.com/kannavkunal/vulnerable-go-microservice
4. https://github.com/kannavkunal/vulnerable-java-app

## Step-by-Step Instructions

### For Each Repository:

1. **Navigate to Repository Settings**
   ```
   Go to: https://github.com/kannavkunal/<REPO_NAME>/settings/hooks
   ```

2. **Click "Add webhook"**

3. **Configure Webhook**:

   **Payload URL:**
   ```
   http://34.67.157.196/webhook/github
   ```

   **Content type:**
   ```
   application/json
   ```

   **Secret:**
   ```
   47dca8eeae767c5f07f4967864feadcdcb34688f41022c2c8e7402662e474cd3
   ```

   **SSL verification:**
   ```
   ☐ Enable SSL verification (not required for HTTP)
   ```

   **Which events would you like to trigger this webhook?**
   ```
   ☑ Let me select individual events
   
   Events to select:
   ☑ Pull requests
   ☐ Push events (uncheck this)
   ```

   **Active:**
   ```
   ☑ Active
   ```

4. **Click "Add webhook"**

5. **Verify Configuration**
   - GitHub will send a ping event
   - Check the "Recent Deliveries" tab
   - You should see a ping event with a green checkmark

## Quick Configuration Script

Run this script to get the webhook URLs for easy copy-paste:

```bash
echo "Webhook Payload URL:"
echo "http://34.67.157.196/webhook/github"
echo ""
echo "Webhook Secret:"
echo "47dca8eeae767c5f07f4967864feadcdcb34688f41022c2c8e7402662e474cd3"
echo ""
echo "Configure for these repositories:"
echo "1. https://github.com/kannavkunal/vulnerable-python-web/settings/hooks"
echo "2. https://github.com/kannavkunal/vulnerable-node-api/settings/hooks"
echo "3. https://github.com/kannavkunal/vulnerable-go-microservice/settings/hooks"
echo "4. https://github.com/kannavkunal/vulnerable-java-app/settings/hooks"
```

## Testing the Webhook

### Test 1: Create a Test PR

1. Create a new branch in one of the vulnerable repos:
   ```bash
   cd vulnerable-python-web
   git checkout -b test-webhook
   echo "# Test" >> README.md
   git add README.md
   git commit -m "Test webhook"
   git push origin test-webhook
   ```

2. Open a pull request on GitHub

3. Check the webhook delivery:
   - Go to Settings → Webhooks
   - Click on your webhook
   - Check "Recent Deliveries"
   - You should see a `pull_request` event with status 200

### Test 2: Monitor Worker Logs

```bash
kubectl logs -n security-patch-agent -l app=security-patch-agent -c worker -f --insecure-skip-tls-verify
```

You should see:
```
INFO:__main__:Webhook: Queueing review scan for https://github.com/kannavkunal/vulnerable-python-web PR#1
INFO:__main__:Received scan request: {'scan_id': 'scan-...', 'mode': 'review', ...}
```

## Webhook Event Flow

```
GitHub PR Event
    ↓
POST /webhook/github
    ↓
Validate HMAC Signature
    ↓
Check Repository Whitelist
    ↓
Publish to Pub/Sub
    ↓
Worker Receives Event
    ↓
Spawn K8s Job (REVIEW mode)
    ↓
Scan PR Diff
    ↓
Comment on PR with Findings
```

## Security

- **HMAC Validation**: All webhook requests are validated using HMAC-SHA256
- **Repository Whitelist**: Only configured repositories in VULNERABLE_REPOS can trigger scans
- **Secret Rotation**: Webhook secret is stored in Secret Manager and can be rotated

## Troubleshooting

### Webhook shows "403 Forbidden"
- Check that the webhook secret matches exactly (no extra spaces)
- Verify repository is in the VULNERABLE_REPOS whitelist

### Webhook shows "401 Unauthorized"
- Check that HMAC signature validation is working
- Verify webhook secret in Secret Manager matches GitHub configuration

### No scan triggered
- Check worker logs for errors
- Verify Pub/Sub is receiving messages
- Check repository whitelist configuration

## Rotating the Webhook Secret

If you need to rotate the webhook secret:

```bash
# Generate new secret
NEW_SECRET=$(openssl rand -hex 32)

# Update Secret Manager
echo -n "$NEW_SECRET" | gcloud secrets versions add github-webhook-secret \
  --project=security-patch-agent-gcp \
  --data-file=-

# Update all GitHub webhooks with new secret
# (Manual step - update each repository's webhook configuration)

# Restart deployment to pick up new secret
kubectl rollout restart deployment/security-patch-agent -n security-patch-agent --insecure-skip-tls-verify
```

## Additional Resources

- GitHub Webhooks Documentation: https://docs.github.com/en/webhooks
- HMAC Signature Validation: https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
