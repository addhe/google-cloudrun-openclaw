# 🔐 Secret Management Guide

Panduan lengkap untuk mengelola credentials OpenClaw di Google Cloud.

## Overview

Semua credentials disimpan di **Google Secret Manager** dan diakses saat runtime oleh Cloud Run. Tidak ada credentials yang disimpan di repository.

```
┌─────────────────┐      ┌──────────────────────┐      ┌─────────────────┐
│  Secret Manager │ ───► │     Cloud Run        │ ───► │    OpenClaw     │
│  (API Keys)     │      │  (Injects at start)  │      │   (Uses keys)   │
└─────────────────┘      └──────────────────────┘      └─────────────────┘
```

## Daftar Secrets

| Secret Name | Environment Variable | Required | Description |
|------------|---------------------|----------|-------------|
| `gemini-api-key` | `GOOGLE_API_KEY` | Yes* | Google Gemini API Key |
| `anthropic-api-key` | `ANTHROPIC_API_KEY` | Yes* | Anthropic Claude API key |
| `openai-api-key` | `OPENAI_API_KEY` | Yes* | OpenAI API key |
| `openclaw-gateway-token` | `OPENCLAW_GATEWAY_TOKEN` | Yes | Token untuk Control UI |
| `telegram-bot-token` | `TELEGRAM_BOT_TOKEN` | No | Telegram bot token |
| `discord-bot-token` | `DISCORD_BOT_TOKEN` | No | Discord bot token |
| `slack-bot-token` | `SLACK_BOT_TOKEN` | No | Slack bot token |

\* Minimal salah satu AI provider key diperlukan.

## Mendapatkan API Keys

### Google Gemini (Primary)

1. Buka [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Login dengan akun Google
3. Klik **Get API key**
4. Copy key yang dihasilkan

### Anthropic Claude (Recommended)

1. Buka [console.anthropic.com](https://console.anthropic.com/)
2. Sign up atau login
3. Pilih **API Keys** di sidebar
4. Klik **Create Key**
5. Copy key yang dihasilkan

> 💡 **Tip**: Gunakan Claude Pro/Max subscription untuk performance terbaik.

### OpenAI

1. Buka [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Login ke akun OpenAI
3. Klik **Create new secret key**
4. Beri nama dan copy key

### Telegram Bot

1. Chat dengan [@BotFather](https://t.me/BotFather) di Telegram
2. Kirim `/newbot`
3. Ikuti instruksi untuk membuat bot
4. Copy token yang diberikan

### Discord Bot

1. Buka [Discord Developer Portal](https://discord.com/developers/applications)
2. Klik **New Application**
3. Pilih **Bot** di sidebar
4. Klik **Reset Token** dan copy

### Slack Bot

1. Buka [api.slack.com/apps](https://api.slack.com/apps)
2. Klik **Create New App**
3. Pilih **From scratch**
4. Setup OAuth & Permissions
5. Copy **Bot User OAuth Token**

## Mengelola Secrets

### Setup Awal

```bash
# Interactive setup
./scripts/setup-secrets.sh
```

### Manual Commands

```bash
# Create secret
echo -n "YOUR_API_KEY" | gcloud secrets create SECRET_NAME --data-file=-

# Update secret (add new version)
echo -n "NEW_API_KEY" | gcloud secrets versions add SECRET_NAME --data-file=-

# View secret value
gcloud secrets versions access latest --secret=SECRET_NAME

# List all secrets
gcloud secrets list

# Delete secret
gcloud secrets delete SECRET_NAME
```

### Rotating Secrets

Untuk security, rotate API keys secara berkala:

```bash
# 1. Generate new key dari provider
# 2. Add to Secret Manager
echo -n "NEW_KEY" | gcloud secrets versions add anthropic-api-key --data-file=-

# 3. Redeploy Cloud Run (otomatis menggunakan versi terbaru)
./scripts/deploy.sh

# 4. Disable old version (optional)
gcloud secrets versions disable VERSION_ID --secret=anthropic-api-key
```

## Security Best Practices

### ✅ DO

- Gunakan Secret Manager untuk semua credentials
- Rotate API keys setiap 90 hari
- Use least-privilege IAM permissions
- Monitor secret access via Cloud Audit Logs

### ❌ DON'T

- Commit credentials ke repository
- Share API keys via chat/email
- Use same key untuk dev dan production
- Disable secret versioning

## Troubleshooting

### "Permission denied" saat akses secret

```bash
# Grant Cloud Run service account access
gcloud secrets add-iam-policy-binding SECRET_NAME \
    --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
```

### Secret tidak ter-inject ke Cloud Run

1. Verify secret exists: `gcloud secrets describe SECRET_NAME`
2. Verify IAM permissions: `gcloud secrets get-iam-policy SECRET_NAME`
3. Redeploy: `./scripts/deploy.sh`

### Invalid API Key errors

1. Verify secret value: `gcloud secrets versions access latest --secret=SECRET_NAME`
2. Pastikan tidak ada whitespace/newlines
3. Verify key masih valid di provider dashboard
