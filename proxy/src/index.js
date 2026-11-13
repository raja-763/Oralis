/**
 * Oralis API Proxy — Cloudflare Worker
 *
 * The only place the Anthropic and ElevenLabs keys exist. The Mac app talks to this
 * Worker and never holds either key.
 *
 *   POST /v1/messages   Claude (email / calendar / browser assistant)
 *   POST /v1/speech     ElevenLabs text-to-speech
 *   GET  /health        liveness check
 *
 * Who may call it
 *   Every request must carry `Authorization: Bearer <Google access token>` — the same
 *   token the app already uses to read the user's Gmail. The Worker checks with Google
 *   that the token is valid, was issued to *Oralis's* OAuth client, and belongs to a
 *   real Gmail account. Limits are then counted per account, not per device, so
 *   reinstalling or faking a device id gains nothing.
 *
 * What a caller can and cannot do
 *   - The model, token limit and every request field are fixed or allow-listed here.
 *   - Per-account daily limits plus a global daily cap protect your bill.
 *   - KILL_SWITCH=true stops all AI traffic instantly.
 *   - REQUIRE_PLAN=true limits access to accounts you have added to KV (paid users).
 *
 * Secrets (wrangler secret put): ANTHROPIC_API_KEY, ELEVENLABS_API_KEY
 * Vars (wrangler.toml):          GOOGLE_CLIENT_ID, limits, REQUIRE_PLAN, KILL_SWITCH
 * KV binding:                    RATE_LIMIT
 */

const ANTHROPIC_API = "https://api.anthropic.com/v1/messages";
const FORCED_MODEL  = "claude-haiku-5-5";
const MAX_TOKENS    = 1024;

// Request shape limits: enough for the app's real traffic, too small to be a free API.
const MAX_MESSAGES     = 45;
const MAX_SYSTEM_CHARS = 12000;
const MAX_TOTAL_CHARS  = 80000;
const ALLOWED_FIELDS   = new Set(["model", "max_tokens", "system", "messages"]);

const ALLOWED_VOICES = new Set([
  "21m00Tcm4TlvDq8ikWAM", // Rachel
  "AZnzlk1XvdvUeBnXmlld", // Domi
  "EXAVITQu4vr4xnSDxMaL", // Bella
  "ErXwobaYiN019PkySvjV", // Antoni
  "MF3mGyEYCl7XYWbV9V6O", // Elli
  "TxGEqnHWrfWFTfGW9XjX", // Josh
  "VR6AewLTigWG4xSOukaG", // Arnold
  "pNInz6obpgDQGcFmaJgB", // Adam
  "yoZ06aMxZJJ28mfd3POQ", // Sam
]);
const MAX_TTS_CHARS = 2000;

const AUTH_CACHE_SECONDS = 600;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true }, 200);
    }
    if (request.method !== "POST") return json({ error: "Not found" }, 404);
    if (url.pathname !== "/v1/messages" && url.pathname !== "/v1/speech") {
      return json({ error: "Not found" }, 404);
    }
    if (env.KILL_SWITCH === "true") {
      return json({ error: "Oralis AI is temporarily unavailable." }, 503);
    }

    // --- Who is calling? ---
    const user = await authenticate(request, env);
    if (!user) {
      return json({ error: "Sign in with your Google account in Oralis to use the AI." }, 401);
    }
    if (env.REQUIRE_PLAN === "true" && !(await env.RATE_LIMIT.get(`plan:${user}`))) {
      return json({ error: "Your account does not have an active Oralis plan." }, 402);
    }
    if (await env.RATE_LIMIT.get(`block:${user}`)) {
      return json({ error: "This account has been blocked." }, 403);
    }

    let body;
    try { body = await request.json(); }
    catch { return json({ error: "Invalid JSON" }, 400); }

    return url.pathname === "/v1/messages"
      ? handleMessages(body, user, env)
      : handleSpeech(body, user, env);
  },
};

// ---------------------------------------------------------------------------
// Claude
// ---------------------------------------------------------------------------

async function handleMessages(body, user, env) {
  const invalid = validateMessages(body);
  if (invalid) return json({ error: invalid }, 400);

  const limited = await countRequest(env, user, "ai",
    intVar(env.DAILY_LIMIT, 150), intVar(env.GLOBAL_DAILY_LIMIT, 20000));
  if (limited) return limited;

  const upstream = {
    model:      FORCED_MODEL,
    max_tokens: Math.min(Number(body.max_tokens) || MAX_TOKENS, MAX_TOKENS),
    system:     body.system,
    messages:   body.messages,
  };

  let res;
  try {
    res = await fetch(ANTHROPIC_API, {
      method: "POST",
      headers: {
        "Content-Type":      "application/json",
        "x-api-key":         env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(upstream),
    });
  } catch {
    return json({ error: "The AI service could not be reached." }, 502);
  }
  // Pass Claude's answer through; never forward headers that could reveal anything.
  return new Response(await res.text(), {
    status: res.status,
    headers: { "Content-Type": "application/json" },
  });
}

export function validateMessages(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return "Invalid request.";
  for (const key of Object.keys(body)) {
    if (!ALLOWED_FIELDS.has(key)) return `Field not allowed: ${key}`;
  }
  if (typeof body.system !== "string" || body.system.length > MAX_SYSTEM_CHARS) {
    return "Invalid system prompt.";
  }
  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return "Invalid messages.";
  }
  let total = body.system.length;
  for (const m of messages) {
    if (!m || (m.role !== "user" && m.role !== "assistant") || typeof m.content !== "string") {
      return "Invalid message.";
    }
    total += m.content.length;
  }
  if (total > MAX_TOTAL_CHARS) return "Request too large.";
  return null;
}

// ---------------------------------------------------------------------------
// ElevenLabs
// ---------------------------------------------------------------------------

async function handleSpeech(body, user, env) {
  const { text, voice_id = "21m00Tcm4TlvDq8ikWAM" } = body || {};
  if (typeof text !== "string" || text.length === 0 || text.length > MAX_TTS_CHARS) {
    return json({ error: `text required, max ${MAX_TTS_CHARS} characters` }, 400);
  }
  if (!ALLOWED_VOICES.has(voice_id)) return json({ error: "Voice not allowed" }, 400);

  const limited = await countRequest(env, user, "tts",
    intVar(env.DAILY_TTS_LIMIT, 100), intVar(env.GLOBAL_DAILY_TTS_LIMIT, 10000));
  if (limited) return limited;

  let res;
  try {
    res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice_id}`, {
      method: "POST",
      headers: { "xi-api-key": env.ELEVENLABS_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        text,
        model_id: "eleven_multilingual_v2",
        voice_settings: { stability: 0.5, similarity_boost: 0.75 },
      }),
    });
  } catch {
    return json({ error: "The voice service could not be reached." }, 502);
  }
  if (!res.ok) return json({ error: "The voice service returned an error." }, 502);
  return new Response(res.body, {
    status: 200,
    headers: { "Content-Type": "audio/mpeg", "Cache-Control": "no-store" },
  });
}

// ---------------------------------------------------------------------------
// Authentication: a Google access token issued to Oralis for a Gmail account
// ---------------------------------------------------------------------------

export async function authenticate(request, env) {
  const header = request.headers.get("Authorization") || "";
  if (!header.startsWith("Bearer ")) return null;
  const token = header.slice(7).trim();
  if (token.length < 20 || token.length > 4096) return null;

  const cacheKey = `auth:${await sha256(token)}`;
  const cached = await env.RATE_LIMIT.get(cacheKey);
  if (cached) return cached;

  try {
    // 1. The token must have been issued to Oralis's own OAuth client.
    const info = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?access_token=${encodeURIComponent(token)}`);
    if (!info.ok) return null;
    const meta = await info.json();
    if (!env.GOOGLE_CLIENT_ID || (meta.azp !== env.GOOGLE_CLIENT_ID && meta.aud !== env.GOOGLE_CLIENT_ID)) {
      return null;
    }
    // 2. It must belong to a real mailbox; its address identifies the account.
    const profile = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/profile", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!profile.ok) return null;
    const email = String((await profile.json()).emailAddress || "").toLowerCase();
    if (!email.includes("@")) return null;

    // Only a hash of the address is ever stored.
    const user = await sha256(email);
    await env.RATE_LIMIT.put(cacheKey, user, { expirationTtl: AUTH_CACHE_SECONDS });
    return user;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Limits
// ---------------------------------------------------------------------------

/** Counts one request for the account and the whole service; returns a 429 response if over. */
async function countRequest(env, user, kind, perUser, global) {
  const day = new Date().toISOString().slice(0, 10);
  const userKey = `rate:${kind}:${user}:${day}`;
  const globalKey = `rate:${kind}:ALL:${day}`;

  const [u, g] = await Promise.all([
    env.RATE_LIMIT.get(userKey).then(n => parseInt(n || "0", 10)),
    env.RATE_LIMIT.get(globalKey).then(n => parseInt(n || "0", 10)),
  ]);
  if (g >= global) return json({ error: "Oralis is busy today. Please try again tomorrow." }, 429);
  if (u >= perUser) return json({ error: "Daily limit reached. It resets tomorrow." }, 429);

  await Promise.all([
    env.RATE_LIMIT.put(userKey, String(u + 1), { expirationTtl: 172800 }),
    env.RATE_LIMIT.put(globalKey, String(g + 1), { expirationTtl: 172800 }),
  ]);
  return null;
}

// ---------------------------------------------------------------------------

function intVar(value, fallback) {
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
