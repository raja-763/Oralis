/**
 * Oralis API Proxy — Cloudflare Worker
 *
 * Sits between the Oralis app and Anthropic's API.
 * - Keeps the Anthropic API key server-side (never sent to users)
 * - Rate-limits by device ID (150 requests / device / day)
 * - Forces cost-efficient model (claude-haiku-4-5)
 * - Strips any attempt by the client to use a more expensive model
 */

const ANTHROPIC_API = "https://api.anthropic.com/v1/messages";
const FORCED_MODEL  = "claude-haiku-4-5";   // 12× cheaper than Sonnet
const MAX_TOKENS    = 1024;                  // cap per request

export default {
  async fetch(request, env) {
    // --- CORS pre-flight ---
    if (request.method === "OPTIONS") {
      return corsResponse(null, 204);
    }

    // Only POST to /v1/messages
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/messages") {
      return corsResponse(JSON.stringify({ error: "Not found" }), 404);
    }

    // --- Parse body ---
    let body;
    try {
      body = await request.json();
    } catch {
      return corsResponse(JSON.stringify({ error: "Invalid JSON" }), 400);
    }

    // --- Rate limiting ---
    const deviceID = request.headers.get("X-Device-ID") || ip(request);
    const today    = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    const kvKey    = `rate:${deviceID}:${today}`;
    const daily    = parseInt(env.DAILY_LIMIT ?? "150", 10);

    let count = 0;
    try {
      const stored = await env.RATE_LIMIT.get(kvKey);
      count = stored ? parseInt(stored, 10) : 0;
    } catch {
      // KV unavailable — allow the request rather than block users
    }

    if (count >= daily) {
      return corsResponse(
        JSON.stringify({ error: "Daily limit reached. Try again tomorrow." }),
        429
      );
    }

    // Increment counter (fire-and-forget, don't block the response)
    env.RATE_LIMIT.put(kvKey, String(count + 1), {
      expirationTtl: 86400 * 2, // keep for 2 days then auto-delete
    }).catch(() => {});

    // --- Build upstream request ---
    // Force model and cap max_tokens regardless of what the client sends
    const upstream = {
      ...body,
      model:      FORCED_MODEL,
      max_tokens: Math.min(body.max_tokens ?? MAX_TOKENS, MAX_TOKENS),
    };

    // --- Forward to Anthropic ---
    let anthropicRes;
    try {
      anthropicRes = await fetch(ANTHROPIC_API, {
        method:  "POST",
        headers: {
          "Content-Type":      "application/json",
          "x-api-key":         env.ANTHROPIC_API_KEY,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify(upstream),
      });
    } catch (err) {
      return corsResponse(
        JSON.stringify({ error: "Upstream request failed", detail: String(err) }),
        502
      );
    }

    const responseBody = await anthropicRes.text();
    return corsResponse(responseBody, anthropicRes.status, {
      "Content-Type": "application/json",
    });
  },
};

// --- Helpers ---

function ip(request) {
  return (
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For") ||
    "unknown"
  );
}

function corsResponse(body, status = 200, extra = {}) {
  return new Response(body, {
    status,
    headers: {
      "Access-Control-Allow-Origin":  "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, X-Device-ID",
      "Content-Type": "application/json",
      ...extra,
    },
  });
}
