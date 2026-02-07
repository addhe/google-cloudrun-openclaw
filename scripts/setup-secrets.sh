#!/bin/bash
# ============================================================
# OpenClaw - Setup Secrets Script
# ============================================================
# Script ini membuat secrets di Google Secret Manager.
# Jalankan sekali sebelum deployment pertama.
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "============================================================"
echo "   OpenClaw - Google Secret Manager Setup"
echo "============================================================"
echo -e "${NC}"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI not found. Please install Google Cloud SDK.${NC}"
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if logged in
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null 2>&1; then
    echo -e "${YELLOW}Not logged in to gcloud. Running 'gcloud auth login'...${NC}"
    gcloud auth login
fi

# Get or set project ID
if [ -z "$GCP_PROJECT_ID" ]; then
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$CURRENT_PROJECT" ]; then
        echo -e "${YELLOW}Current GCP Project: ${CURRENT_PROJECT}${NC}"
        read -p "Use this project? (y/n): " USE_CURRENT
        if [ "$USE_CURRENT" = "y" ] || [ "$USE_CURRENT" = "Y" ]; then
            GCP_PROJECT_ID=$CURRENT_PROJECT
        fi
    fi
    
    if [ -z "$GCP_PROJECT_ID" ]; then
        read -p "Enter GCP Project ID: " GCP_PROJECT_ID
    fi
fi

echo -e "${GREEN}Using project: ${GCP_PROJECT_ID}${NC}"
gcloud config set project "$GCP_PROJECT_ID"

# Enable Secret Manager API
echo -e "${BLUE}Enabling Secret Manager API...${NC}"
gcloud services enable secretmanager.googleapis.com

# Function to create or update secret
create_secret() {
    local SECRET_NAME=$1
    local SECRET_DESCRIPTION=$2
    local REQUIRED=$3
    
    echo ""
    echo -e "${YELLOW}──────────────────────────────────────${NC}"
    echo -e "${YELLOW}Secret: ${SECRET_NAME}${NC}"
    echo -e "${YELLOW}${SECRET_DESCRIPTION}${NC}"
    echo -e "${YELLOW}──────────────────────────────────────${NC}"
    
    if [ "$REQUIRED" = "required" ]; then
        echo -e "${RED}[REQUIRED]${NC}"
    else
        echo -e "${GREEN}[OPTIONAL]${NC}"
    fi
    
    read -p "Enter value (leave empty to skip): " SECRET_VALUE
    
    if [ -z "$SECRET_VALUE" ]; then
        echo -e "${YELLOW}Skipped.${NC}"
        return
    fi
    
    # Check if secret exists
    if gcloud secrets describe "$SECRET_NAME" --project="$GCP_PROJECT_ID" > /dev/null 2>&1; then
        echo -e "${YELLOW}Secret exists. Adding new version...${NC}"
        echo -n "$SECRET_VALUE" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$GCP_PROJECT_ID"
    else
        echo -e "${GREEN}Creating new secret...${NC}"
        echo -n "$SECRET_VALUE" | gcloud secrets create "$SECRET_NAME" --data-file=- --replication-policy="automatic" --project="$GCP_PROJECT_ID"
    fi
    
    echo -e "${GREEN}✓ Secret '${SECRET_NAME}' configured.${NC}"
}

# Create secrets
echo ""
echo -e "${BLUE}Let's set up your secrets...${NC}"
echo -e "${BLUE}You can always update these later with 'gcloud secrets versions add'${NC}"
echo ""

# AI Provider Keys
create_secret "gemini-api-key" "Google Gemini API Key (get from aistudio.google.com/apikey)" "required"
create_secret "anthropic-api-key" "Anthropic API Key (get from console.anthropic.com)" "optional"
create_secret "openai-api-key" "OpenAI API Key (get from platform.openai.com/api-keys)" "optional"

# Gateway Security
echo ""
echo -e "${BLUE}Generating gateway token...${NC}"
GATEWAY_TOKEN=$(openssl rand -hex 32)
echo -e "${GREEN}Generated token: ${GATEWAY_TOKEN:0:16}...${NC}"

if gcloud secrets describe "openclaw-gateway-token" --project="$GCP_PROJECT_ID" > /dev/null 2>&1; then
    echo -n "$GATEWAY_TOKEN" | gcloud secrets versions add "openclaw-gateway-token" --data-file=- --project="$GCP_PROJECT_ID"
else
    echo -n "$GATEWAY_TOKEN" | gcloud secrets create "openclaw-gateway-token" --data-file=- --replication-policy="automatic" --project="$GCP_PROJECT_ID"
fi
echo -e "${GREEN}✓ Gateway token configured.${NC}"

# Channel tokens (optional)
echo ""
echo -e "${BLUE}Channel tokens are optional. Skip if you don't need them.${NC}"
create_secret "telegram-bot-token" "Telegram Bot Token (get from @BotFather)" "optional"
create_secret "discord-bot-token" "Discord Bot Token (get from discord.com/developers)" "optional"
create_secret "slack-bot-token" "Slack Bot Token (get from api.slack.com/apps)" "optional"

# Grant Cloud Run access to secrets
echo ""
echo -e "${BLUE}Granting Cloud Run access to secrets...${NC}"

# Get the compute service account
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT_ID" --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# List of all secrets
SECRETS=("gemini-api-key" "anthropic-api-key" "openai-api-key" "openclaw-gateway-token" "telegram-bot-token" "discord-bot-token" "slack-bot-token")

for SECRET in "${SECRETS[@]}"; do
    if gcloud secrets describe "$SECRET" --project="$GCP_PROJECT_ID" > /dev/null 2>&1; then
        gcloud secrets add-iam-policy-binding "$SECRET" \
            --member="serviceAccount:${SERVICE_ACCOUNT}" \
            --role="roles/secretmanager.secretAccessor" \
            --project="$GCP_PROJECT_ID" > /dev/null 2>&1 || true
        echo -e "${GREEN}✓ Granted access to ${SECRET}${NC}"
    fi
done

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   Setup Complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${BLUE}Your gateway token (save this somewhere safe):${NC}"
echo -e "${YELLOW}${GATEWAY_TOKEN}${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Run ./scripts/deploy.sh to deploy to Cloud Run"
echo "2. Access the Control UI and enter your gateway token"
echo ""
