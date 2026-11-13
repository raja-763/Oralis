# Deploying the Oralis proxy (public build)

Two builds come from this repo:

| | Oralis (personal) | OralisPublic (customers) |
|---|---|---|
| Bundle ID | `com.oralis.app` | `com.oralis.public` |
| API keys | In `Secrets.xcconfig`, on your Mac only | **None.** They live only in this Worker |
| AI / voice | Calls Anthropic / ElevenLabs directly | Calls this Worker |
| Settings | `Secrets.xcconfig` | `Public.xcconfig` (committed, no secrets) |

The Worker is the only place the keys exist. Users prove who they are with their
Google sign-in, so limits are per account.

---

## Part 1: Cloudflare (about 10 minutes)

### 1. Create a free account
Go to https://dash.cloudflare.com/sign-up and verify your email. No domain is needed;
you get a free `*.workers.dev` address.

### 2. Install Node 20 and Wrangler
Wrangler needs Node 18 or newer (this Mac has Node 16).
```bash
brew install node
```
```bash
npm install -g wrangler
```

### 3. Log in
```bash
wrangler login
```
A browser tab opens. Click **Allow**.

### 4. Create the storage for limits
```bash
cd /Users/lisanhasnain/Desktop/Development/Aria/proxy
```
```bash
wrangler kv namespace create RATE_LIMIT
```
Copy the `id` it prints into `wrangler.toml`, replacing `REPLACE_WITH_KV_NAMESPACE_ID`.

### 5. Add your keys as secrets
Each command asks you to paste a key. Nothing is shown or logged, and Cloudflare stores
it encrypted.

Use **new** keys for the public service rather than the ones in your personal
`Secrets.xcconfig`, so you can revoke one without breaking the other.
```bash
wrangler secret put ANTHROPIC_API_KEY
```
```bash
wrangler secret put ELEVENLABS_API_KEY
```

### 6. Set your Google client ID (needed before step 7)
Do **Part 2** first, then put the public client ID in `wrangler.toml` as
`GOOGLE_CLIENT_ID`. The Worker rejects any token not issued to that client.

### 7. Deploy
```bash
wrangler deploy
```
It prints `https://oralis-proxy.<you>.workers.dev`. Check it:
```bash
curl https://oralis-proxy.<you>.workers.dev/health
```
You should see `{"ok":true}`.

### 8. Point the public app at it
Edit `Public.xcconfig` in the repo root (note the `$()` trick; plain `//` is a comment
in xcconfig files):
```
ORALIS_PROXY_URL = https:/$()/oralis-proxy.<you>.workers.dev/v1/messages
ELEVENLABS_PROXY_URL = https:/$()/oralis-proxy.<you>.workers.dev/v1/speech
GOOGLE_OAUTH_CLIENT_ID = <public client id from Part 2>
```

---

## Part 2: A Google OAuth client for the public app

Use a **separate** client from your personal one.

1. https://console.cloud.google.com > create a project "Oralis Public".
2. **APIs & Services > Library**: enable **Gmail API**.
3. **OAuth consent screen**: user type External. Add the app name, your support email,
   a privacy policy URL and a home page.
4. **Credentials > Create credentials > OAuth client ID**. The redirect uses a custom
   scheme (`com.oralis.public:/oauth/google`). Create the client type Google offers for a
   native Mac app without a client secret, and copy the **client ID** only.
   Leave `GOOGLE_OAUTH_CLIENT_SECRET` empty; the app signs in with PKCE.
5. **Verification:** `https://mail.google.com/` is a restricted scope. Until Google
   verifies the app (and, for restricted scopes, an annual security assessment), only
   up to 100 listed test users can sign in. Plan for this before a public launch.

---

## Part 3: Build and test the public app

```bash
cd /Users/lisanhasnain/Desktop/Development/Aria
```
```bash
xcodegen generate
```
```bash
xcodebuild -project Oralis.xcodeproj -scheme OralisPublic -configuration Release build
```
The build fails on purpose if any API key or client secret is present in the app.

---

## Running it

- **Free tier:** 100,000 requests a day for Workers. KV free tier covers about 1,000
  writes a day; the limiter uses 2 per request, so move to the $5/month plan before
  you pass roughly 500 requests a day.
- **Spend protection:** per-account daily limits (`DAILY_LIMIT`, `DAILY_TTS_LIMIT`) plus
  a whole-service cap (`GLOBAL_DAILY_LIMIT`). Also set a monthly spend limit in the
  Anthropic and ElevenLabs dashboards.
- **Emergency stop:** set `KILL_SWITCH = "true"` in `wrangler.toml` and run
  `wrangler deploy`.
- **Paid users only:** set `REQUIRE_PLAN = "true"`, then add each paying account. The
  key is the SHA-256 of the lowercase email:
  ```bash
  HASH=$(printf 'person@gmail.com' | shasum -a 256 | cut -d' ' -f1)
  wrangler kv key put --binding=RATE_LIMIT "plan:$HASH" "1"
  ```
- **Block an abuser:** same command with the key `block:$HASH`.
- **Watch traffic:** `wrangler tail`. The Worker never logs message content.
- **Known limits:** KV counters are not atomic, so a burst of parallel requests can
  slightly exceed a limit; the global cap and provider spend limits are the backstop.
  Only Gmail accounts can use the AI in the public build; other accounts see a prompt to
  sign in with Google.
- **Rotating keys:** `wrangler secret put ANTHROPIC_API_KEY` again. No app update needed.
