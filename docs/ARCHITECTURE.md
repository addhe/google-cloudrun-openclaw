# 🏗️ Architecture Overview

Arsitektur deployment OpenClaw di Google Cloud Run.

## High-Level Architecture

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                    Google Cloud                         │
                              │                                                         │
┌──────────────┐              │  ┌─────────────┐    ┌────────────────────────────────┐ │
│    GitHub    │──── push ────┼─►│ Cloud Build │───►│        Artifact Registry       │ │
│  Repository  │              │  └─────────────┘    │    (Docker Images)             │ │
└──────────────┘              │                      └───────────────┬────────────────┘ │
                              │                                      │                  │
                              │                                      ▼                  │
                              │  ┌─────────────────────────────────────────────────┐   │
                              │  │                  Cloud Run                       │   │
                              │  │  ┌───────────────────────────────────────────┐  │   │
                              │  │  │            OpenClaw Gateway               │  │   │
┌──────────────┐              │  │  │  ┌─────────┐ ┌─────────┐ ┌─────────────┐ │  │   │
│    Users     │◄────HTTPS────┼──┼──┼──│   UI    │ │   API   │ │   Channels  │ │  │   │
│  (Telegram,  │              │  │  │  │ (React) │ │  (WS)   │ │ (TG,DC,etc) │ │  │   │
│  Discord,    │              │  │  │  └─────────┘ └─────────┘ └─────────────┘ │  │   │
│  Slack, etc) │              │  │  └───────────────────────────────────────────┘  │   │
└──────────────┘              │  └──────────────────────────┬──────────────────────┘   │
                              │                              │                          │
                              │                              ▼                          │
                              │  ┌─────────────────────────────────────────────────┐   │
                              │  │              Secret Manager                      │   │
                              │  │  ┌───────────┐ ┌───────────┐ ┌───────────────┐  │   │
                              │  │  │ Anthropic │ │  OpenAI   │ │ Channel Tokens│  │   │
                              │  │  │  API Key  │ │  API Key  │ │ (TG, DC, etc) │  │   │
                              │  │  └───────────┘ └───────────┘ └───────────────┘  │   │
                              │  └─────────────────────────────────────────────────┘   │
                              │                                                         │
                              └─────────────────────────────────────────────────────────┘
                              
                              ┌─────────────────────────────────────────────────────────┐
                              │                  External Services                       │
                              │  ┌───────────┐ ┌───────────┐ ┌───────────────────────┐  │
                              │  │ Anthropic │ │  OpenAI   │ │ Messaging Platforms   │  │
                              │  │  (Claude) │ │  (GPT)    │ │ (Telegram, Discord,..)│  │
                              │  └───────────┘ └───────────┘ └───────────────────────┘  │
                              └─────────────────────────────────────────────────────────┘
```

## Components

### Cloud Run Service

- **Stateless container** running OpenClaw Gateway
- **Auto-scaling**: 0-3 instances based on traffic
- **Memory**: 2Gi per instance
- **CPU**: 2 vCPU per instance
- **Cold start**: ~30-60 seconds (first request after scale-to-zero)

### Secret Manager

Menyimpan semua credentials secara encrypted:
- AI provider API keys (Anthropic, OpenAI)
- Gateway token untuk UI access
- Channel tokens (Telegram, Discord, Slack, etc.)

### Artifact Registry

Docker image storage:
- Build artifacts dari Cloud Build
- Tagged dengan commit SHA dan `latest`

### Cloud Build (Optional)

CI/CD pipeline:
- Trigger: push ke `main` branch
- Build Docker image
- Push ke Artifact Registry  
- Deploy ke Cloud Run

## Data Flow

### 1. Incoming Message (e.g., Telegram)

```
User → Telegram API → Cloud Run (OpenClaw) → AI Provider (Claude/GPT) → 
Cloud Run (OpenClaw) → Telegram API → User
```

### 2. Control UI Access

```
Browser → Cloud Run (HTTPS) → OpenClaw Gateway → 
Validate Token (from Secret Manager) → Respond
```

### 3. CI/CD Deployment

```
Git Push → Cloud Build Trigger → Build Image → 
Push to Artifact Registry → Deploy to Cloud Run
```

## Scaling Behavior

| Traffic | Instances | Behavior |
|---------|-----------|----------|
| None    | 0         | Scale to zero (no cost) |
| Low     | 1         | Single instance handles all |
| Medium  | 1-2       | Auto-scale based on CPU |
| High    | 2-3       | Max instances (configurable) |

## Cost Estimation

| Component | Free Tier | Estimated Monthly |
|-----------|-----------|-------------------|
| Cloud Run | 2M requests | ~$10-30 (depends on usage) |
| Secret Manager | 10K accesses | ~$0.06 |
| Artifact Registry | 500MB | ~$0.10 |
| Cloud Build | 120 min/day | Usually free |

> 💡 Actual costs depend on message volume dan AI provider usage.

## Security Model

### Network Security

- All traffic over HTTPS (TLS 1.3)
- Cloud Run manages SSL certificates
- No public IP exposed (managed by Google)

### Authentication

- Gateway token required untuk Control UI
- Channel-specific auth (bot tokens)
- DM pairing untuk untrusted senders

### Secrets

- Encrypted at rest (AES-256)
- IAM-based access control
- Audit logging enabled

## Limitations

### Cloud Run Constraints

1. **Stateless**: No persistent filesystem
   - WhatsApp session perlu external storage
   - Solution: Use Cloud Storage for session data

2. **Request timeout**: Max 60 minutes
   - Long-running tasks may timeout
   - Solution: Use Cloud Tasks untuk background jobs

3. **Cold starts**: 30-60 seconds
   - First request after idle is slow
   - Solution: Set min-instances=1 (increases cost)

### WebSocket Considerations

Cloud Run supports WebSocket dengan beberapa catatan:
- Connections tetap hidup selama ada activity
- Idle connections may be closed after timeout
- Client should implement reconnection logic
