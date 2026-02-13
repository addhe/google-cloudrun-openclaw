# 🦞 OpenClaw on Google Cloud Run

Deploy [OpenClaw](https://github.com/openclaw/openclaw) AI Assistant ke Google Cloud Run dengan secure secret management.

## 📋 Prerequisites

1. **Google Cloud Account** dengan billing aktif
2. **gcloud CLI** terinstall ([install guide](https://cloud.google.com/sdk/docs/install))
3. **Docker** terinstall ([install guide](https://docs.docker.com/get-docker/))
4. **API Keys** (minimal salah satu):
   - [Anthropic API Key](https://console.anthropic.com/) (recommended)
   - [OpenAI API Key](https://platform.openai.com/api-keys)

## 🚀 Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/awan-openclaw.git
cd awan-openclaw
```

### 2. Login ke Google Cloud

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 3. Setup Secrets

```bash
chmod +x scripts/*.sh
./scripts/setup-secrets.sh
```

Script akan meminta Anda memasukkan:
- Anthropic/OpenAI API Key
- (Optional) Channel tokens untuk Telegram, Discord, dll.

### 4. Deploy ke Cloud Run

```bash
./scripts/deploy.sh
```

Setelah selesai, Anda akan mendapat URL Cloud Run service.

### 5. Akses Control UI

1. Buka URL dari output deployment
2. Masuk ke **Settings**
3. Masukkan gateway token:
   ```bash
   gcloud secrets versions access latest --secret=openclaw-gateway-token
   ```

## 📁 Project Structure

```
awan-openclaw/
├── Dockerfile.cloudrun     # Docker config for Cloud Run
├── cloudbuild.yaml         # CI/CD pipeline (optional)
├── .env.example            # Environment template
├── .gitignore              # Git ignore rules
├── scripts/
│   ├── setup-secrets.sh    # Setup Google Secret Manager
│   └── deploy.sh           # Manual deployment script
└── docs/
    ├── SECRETS.md          # Secret management guide
    └── ARCHITECTURE.md     # Architecture overview
```

## 🔐 Secret Management

**PENTING**: Semua credentials dikelola via [Google Secret Manager](https://cloud.google.com/secret-manager).

❌ **JANGAN** commit `.env` files dengan credentials  
❌ **JANGAN** hardcode API keys di code  
✅ **GUNAKAN** Google Secret Manager  
✅ **GUNAKAN** `.env.example` sebagai template  

Lihat [docs/SECRETS.md](docs/SECRETS.md) untuk panduan lengkap.

## 🔄 CI/CD (Optional)

Untuk automated deployment saat push ke GitHub:

1. Connect repository ke Cloud Build
2. Create trigger dengan `cloudbuild.yaml`
3. Set substitution variables:
   - `_REGION`: asia-southeast1
   - `_SERVICE_NAME`: openclaw

## 📖 Useful Commands

```bash
# View logs
gcloud run logs read openclaw --region=asia-southeast1

# Get service URL
gcloud run services describe openclaw --region=asia-southeast1 --format="value(status.url)"

# Update a secret
echo -n "NEW_VALUE" | gcloud secrets versions add SECRET_NAME --data-file=-

# Redeploy with latest image
./scripts/deploy.sh
```

## 🔗 Resources

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)

## 📝 License

This deployment configuration is provided as-is. OpenClaw is licensed under its own terms.
# Emergency rebuild trigger Fri Feb 13 16:11:10 WIB 2026
