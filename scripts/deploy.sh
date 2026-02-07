#!/bin/bash
# ============================================================
# OpenClaw - Deploy Script
# ============================================================
# Script ini melakukan deployment manual ke Google Cloud Run.
# Untuk CI/CD otomatis, gunakan Cloud Build trigger.
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGION="${GCP_REGION:-asia-southeast1}"
SERVICE_NAME="${CLOUD_RUN_SERVICE_NAME:-openclaw}"
REPOSITORY="${ARTIFACT_REPOSITORY:-openclaw-repo}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo -e "${BLUE}"
echo "============================================================"
echo "   OpenClaw - Cloud Run Deployment"
echo "============================================================"
echo -e "${NC}"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI not found. Please install Google Cloud SDK.${NC}"
    exit 1
fi

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker not found. Please install Docker.${NC}"
    exit 1
fi

# Get project ID
if [ -z "$GCP_PROJECT_ID" ]; then
    GCP_PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$GCP_PROJECT_ID" ]; then
        echo -e "${RED}Error: No GCP project set. Run 'gcloud config set project PROJECT_ID'${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  Project:    $GCP_PROJECT_ID"
echo "  Region:     $REGION"
echo "  Service:    $SERVICE_NAME"
echo "  Repository: $REPOSITORY"
echo ""

# Enable required APIs
echo -e "${BLUE}[1/6] Enabling required APIs...${NC}"
gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    secretmanager.googleapis.com \
    --project="$GCP_PROJECT_ID"

# Create Artifact Registry repository if not exists
echo -e "${BLUE}[2/6] Setting up Artifact Registry...${NC}"
if ! gcloud artifacts repositories describe "$REPOSITORY" --location="$REGION" --project="$GCP_PROJECT_ID" > /dev/null 2>&1; then
    echo "Creating repository..."
    gcloud artifacts repositories create "$REPOSITORY" \
        --repository-format=docker \
        --location="$REGION" \
        --description="OpenClaw Docker images" \
        --project="$GCP_PROJECT_ID"
fi

# Configure docker for Artifact Registry
echo -e "${BLUE}[3/6] Configuring Docker authentication...${NC}"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Build Docker image
IMAGE_URI="${REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${REPOSITORY}/${SERVICE_NAME}:${IMAGE_TAG}"
echo -e "${BLUE}[4/6] Building Docker image...${NC}"
echo "Image: $IMAGE_URI"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

docker build \
    -t "$IMAGE_URI" \
    -f "$PROJECT_DIR/Dockerfile.cloudrun" \
    "$PROJECT_DIR"

# Push image to Artifact Registry
echo -e "${BLUE}[5/6] Pushing image to Artifact Registry...${NC}"
docker push "$IMAGE_URI"

# Deploy to Cloud Run
echo -e "${BLUE}[6/6] Deploying to Cloud Run...${NC}"

# Build secrets argument dynamically based on what exists
SECRETS_ARG=""
for SECRET_PAIR in "ANTHROPIC_API_KEY=anthropic-api-key" "OPENAI_API_KEY=openai-api-key" "OPENCLAW_GATEWAY_TOKEN=openclaw-gateway-token" "TELEGRAM_BOT_TOKEN=telegram-bot-token" "DISCORD_BOT_TOKEN=discord-bot-token" "SLACK_BOT_TOKEN=slack-bot-token"; do
    ENV_VAR="${SECRET_PAIR%%=*}"
    SECRET_NAME="${SECRET_PAIR##*=}"
    
    if gcloud secrets describe "$SECRET_NAME" --project="$GCP_PROJECT_ID" > /dev/null 2>&1; then
        if [ -n "$SECRETS_ARG" ]; then
            SECRETS_ARG="${SECRETS_ARG},"
        fi
        SECRETS_ARG="${SECRETS_ARG}${ENV_VAR}=${SECRET_NAME}:latest"
    fi
done

# Deploy command
DEPLOY_CMD="gcloud run deploy $SERVICE_NAME \
    --image=$IMAGE_URI \
    --region=$REGION \
    --platform=managed \
    --allow-unauthenticated \
    --memory=2Gi \
    --cpu=2 \
    --min-instances=0 \
    --max-instances=3 \
    --timeout=300s \
    --set-env-vars=NODE_ENV=production,LOG_LEVEL=info \
    --project=$GCP_PROJECT_ID"

if [ -n "$SECRETS_ARG" ]; then
    DEPLOY_CMD="$DEPLOY_CMD --set-secrets=$SECRETS_ARG"
fi

eval $DEPLOY_CMD

# Get service URL
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$GCP_PROJECT_ID" \
    --format="value(status.url)")

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   Deployment Complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${BLUE}Service URL:${NC} $SERVICE_URL"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Open $SERVICE_URL in your browser"
echo "2. Enter your gateway token in Settings"
echo "3. Configure channels (Telegram, Discord, etc.)"
echo ""
echo -e "${YELLOW}Get your gateway token:${NC}"
echo "gcloud secrets versions access latest --secret=openclaw-gateway-token --project=$GCP_PROJECT_ID"
echo ""
