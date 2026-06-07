#!/bin/bash
# Setup script to create 4 separate GitHub repositories for vulnerable test apps

set -e

echo "🔧 Setting up separate vulnerable repositories..."

# Array of repo names
REPOS=(
  "vulnerable-python-api"
  "vulnerable-node-service"
  "vulnerable-java-app"
  "vulnerable-go-microservice"
)

# GitHub username
GITHUB_USER="kannavkunal"

# Base directory
BASE_DIR="/Users/kkannav/Documents/visa-docs/gcp-personal-config/security-patch-agent/vulnerable-repos"

for REPO in "${REPOS[@]}"; do
  echo ""
  echo "📦 Processing $REPO..."

  # Create repo using GitHub API
  echo "  Creating GitHub repository: $GITHUB_USER/$REPO"
  curl -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO\",\"private\":true,\"description\":\"Vulnerable app for security testing\"}" \
    2>/dev/null || echo "  (repo may already exist)"

  # Navigate to subdirectory
  cd "$BASE_DIR/$REPO"

  # Initialize git if not already
  if [ ! -d ".git" ]; then
    echo "  Initializing git repository"
    git init
  fi

  # Add remote
  echo "  Adding remote origin"
  git remote remove origin 2>/dev/null || true
  git remote add origin "git@github.com:$GITHUB_USER/$REPO.git"

  # Create main branch, add files, commit
  echo "  Creating initial commit"
  git checkout -b main 2>/dev/null || git checkout main
  git add -A
  git commit -m "Initial vulnerable code for security testing" --allow-empty

  # Push to GitHub
  echo "  Pushing to GitHub"
  git push -u origin main --force

  echo "  ✅ $REPO complete"
done

echo ""
echo "🎉 All repositories created and pushed!"
echo ""
echo "Repositories created:"
for REPO in "${REPOS[@]}"; do
  echo "  - https://github.com/$GITHUB_USER/$REPO"
done
