# Deploying the Oralis Proxy

This is a one-time setup. After deploying you get a free HTTPS URL that all
Oralis users hit instead of Anthropic directly.

## Prerequisites

- A free Cloudflare account (cloudflare.com)
- Node.js installed (`brew install node`)

## Steps

### 1. Install Wrangler (Cloudflare's CLI)

```bash
npm install -g wrangler
```

### 2. Log in to Cloudflare

```bash
wrangler login
```

A browser window opens — log in and approve access.

### 3. Create the KV namespace for rate limiting

```bash
wrangler kv namespace create RATE_LIMIT
```

Copy the `id` value from the output and paste it into `wrangler.toml`,
replacing `REPLACE_WITH_KV_NAMESPACE_ID`.

### 4. Add your Anthropic API key as a secret

```bash
wrangler secret put ANTHROPIC_API_KEY
```

Paste your key when prompted. It is stored encrypted — Cloudflare staff
cannot read it and it never appears in logs.

### 5. Deploy

```bash
cd /Users/lisanhasnain/Desktop/Development/Aria/proxy
wrangler deploy
```

Wrangler prints a URL like:
```
https://oralis-proxy.<your-subdomain>.workers.dev
```

Copy that URL and update `Sources/Aria/Services/AIAgentService.swift` —
replace the `proxyURL` constant with your URL.

### 6. Rebuild Oralis and release a new DMG

```bash
cd /Users/lisanhasnain/Desktop/Development/Aria
xcodebuild -project Oralis.xcodeproj -scheme Oralis \
  -configuration Release -derivedDataPath build/DerivedData build
```

## Rate limits (free tier)

- Cloudflare Workers free tier: 100,000 requests / day across all users
- Proxy enforces: 150 requests / device / day
- At 150 requests/day per user: supports ~666 active users daily for free

## Costs

- Cloudflare Workers: free up to 100k requests/day, then $5/month flat
- Anthropic (Haiku model): ~$0.0003 per typical request
  - $20 covers ~65,000 requests
  - At 50 requests/user/day: covers ~1,300 user-days per $20
