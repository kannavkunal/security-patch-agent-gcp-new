#!/bin/bash
# Push clean repository to GitHub

set -e

echo "🚀 Pushing to GitHub"
echo "===================="
echo ""

# Check if remote exists
if git remote | grep -q origin; then
    echo "✓ Remote 'origin' already configured"
else
    echo "Adding remote..."
    git remote add origin git@github.com:kannavkunal/security-patch-agent-gcp.git
fi

echo ""
echo "Pushing to main branch..."
git push -u origin main

echo ""
echo "✅ Success!"
echo ""
echo "Repository: https://github.com/kannavkunal/security-patch-agent-gcp"
echo ""
echo "Next steps:"
echo "1. Verify files on GitHub"
echo "2. Set GitHub Secrets (GCP_PROJECT_ID, GCP_SA_KEY, API keys)"
echo "3. Run 'Full Deployment' workflow"
echo ""
