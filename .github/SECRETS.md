# GitHub Secrets Configuration

## Required Secrets

To use the GitHub Actions workflows, you need to configure the following secrets in your repository.

### Setup Instructions

1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** for each secret below

---

## Secrets List

### 1. GCP_SERVICE_ACCOUNT_KEY (Required)

**Description**: GCP service account key JSON for authentication

**How to get**:
```bash
# Use the existing service account key file
cat compact-orb-498606-f9-e492d67082b0.json
```

**Setup**:
- Name: `GCP_SERVICE_ACCOUNT_KEY`
- Value: Paste the **entire JSON content**
- Used in: All deployment workflows

---

### 2. API_KEY_PRIMARY (Required for testing)

**Description**: Primary API key for testing deployed application

**How to get**:
```bash
# From API-KEYS.txt
cat API-KEYS.txt | grep "Primary"
```

**Setup**:
- Name: `API_KEY_PRIMARY`
- Value: `fff07335eeaf3a829be34d092b21ff1817a4f830afc1a7886789619a04c8ce43`
- Used in: `deploy-application.yml` (integration tests)

---

### 3. API_KEY_SECONDARY (Optional)

**Description**: Secondary API key for rotation/backup

**How to get**:
```bash
# From API-KEYS.txt
cat API-KEYS.txt | grep "Secondary"
```

**Setup**:
- Name: `API_KEY_SECONDARY`
- Value: `e191c4393ef55de6167edade16c5a901c3f4743865a52e1afd72ce82a1646df1`
- Used in: Manual testing, key rotation

---

## Verification

After adding secrets, verify they are set:

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. You should see:
   - ✅ `GCP_SERVICE_ACCOUNT_KEY`
   - ✅ `API_KEY_PRIMARY`
   - ✅ `API_KEY_SECONDARY` (optional)

## Security Best Practices

### ✅ DO:
- Use different API keys for different environments (dev/staging/prod)
- Rotate API keys regularly
- Limit service account permissions to minimum required
- Use separate service accounts for CI/CD vs production

### ❌ DON'T:
- Commit secrets to git (already in .gitignore)
- Share API keys in plain text
- Use production keys for testing
- Give CI/CD service account more permissions than needed

## Service Account Permissions

The `kunal-kannav@compact-orb-498606-f9.iam.gserviceaccount.com` service account has:
- ✅ Owner role (for full infrastructure management)
- ✅ Workload Identity enabled
- ✅ Artifact Registry write access
- ✅ GKE cluster admin access
- ✅ Monitoring & Logging access

## Using Secrets in Workflows

Example from `deploy-application.yml`:

```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    credentials_json: ${{ secrets.GCP_SERVICE_ACCOUNT_KEY }}

- name: Run Integration Tests
  run: |
    export API_KEY=${{ secrets.API_KEY_PRIMARY }}
    ./infrastructure/scripts/comprehensive-test.sh
```

## Troubleshooting

### Workflow fails with "Secret not found"
- Verify the secret name matches exactly (case-sensitive)
- Check the secret is set in **Actions** secrets, not **Dependabot** secrets
- Ensure you have admin access to the repository

### Authentication fails
- Verify the JSON key is valid and complete
- Check the service account exists and has required permissions
- Ensure the project ID in the JSON matches your GCP project

### API tests fail
- Verify the API key matches what's deployed in the cluster
- Check the secret is in the `deployment/k8s-manifests/03-secret.yaml`
- Ensure the LoadBalancer IP is accessible

## Rotation Schedule

Recommended rotation schedule:

| Secret | Frequency | Method |
|--------|-----------|--------|
| Service Account Key | Every 90 days | Create new key, update secret, delete old |
| API Keys | Every 30 days | Generate new, update K8s secret, rotate in GitHub |

## Emergency Access Revocation

If a secret is compromised:

1. **Immediately** delete the GitHub secret
2. For API keys:
   ```bash
   kubectl delete secret api-keys -n security-patch-agent
   # Create new keys
   openssl rand -hex 32
   # Update secret with new keys
   kubectl create secret generic api-keys --from-literal=keys='["new-key-1","new-key-2"]' -n security-patch-agent
   ```

3. For service account:
   ```bash
   # Disable the key in GCP Console
   gcloud iam service-accounts keys list --iam-account=kunal-kannav@compact-orb-498606-f9.iam.gserviceaccount.com
   gcloud iam service-accounts keys delete KEY_ID --iam-account=kunal-kannav@compact-orb-498606-f9.iam.gserviceaccount.com
   # Create new key
   gcloud iam service-accounts keys create new-key.json --iam-account=kunal-kannav@compact-orb-498606-f9.iam.gserviceaccount.com
   ```

4. Update GitHub secret with new value
5. Re-run failed workflows
