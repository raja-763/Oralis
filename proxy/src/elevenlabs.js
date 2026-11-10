/**
 * Oralis ElevenLabs TTS Proxy — Cloudflare Worker
 *
 * Deploy alongside oralis-proxy or as a separate worker.
 * Env vars needed:
 *   ELEVENLABS_API_KEY  — your ElevenLabs secret key
 *   RATE_LIMIT          — KV namespace binding (shared with main proxy is fine)
 *
 * Rate limit: 100 TTS requests per device per day (generous for voice responses).
 * Voice IDs are allowlisted so users can't use arbitrary voices.
 */

const ALLOWED_VOICES = new Set([
  "21m00Tcm4TlvDq8ikWAM", // Rachel  — calm, natural female
  "AZnzlk1XvdvUeBnXmlld", // Domi    — strong, confident female
  "EXAVITQu4vr4xnSDxMaL", // Bella   — soft, friendly female
  "ErXwobaYiN019PkySvjV", // Antoni  — well-rounded male
  "MF3mGyEYCl7XYWbV9V6O", // Elli    — emotional, young female
  "TxGEqnHWrfWFTfGW9XjX", // Josh    — deep, young male
  "VR6AewLTigWG4xSOukaG", // Arnold  — crisp, authoritative male
  "pNInz6obpgDQGcFmaJgB", // Adam    — deep, US male
  "yoZ06aMxZJJ28mfd3POQ", // Sam     — raspy, US male
]);

const DAILY_LIMIT = 100;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return corsResponse(null, 200);
    }

    if (request.method !== "POST") {
      return corsResponse(JSON.stringify({ error: "POST only" }), 405);
    }

    const deviceID = request.headers.get("X-Device-ID") || "unknown";
    const today    = new Date().toISOString().slice(0, 10);
    const ratKey   = `tts:${deviceID}:${today}`;

    // Rate limit
    const count = parseInt((await env.RATE_LIMIT.get(ratKey)) || "0");
    if (count >= DAILY_LIMIT) {
      return corsResponse(JSON.stringify({ error: "Daily TTS limit reached" }), 429);
    }

    let body;
    try { body = await request.json(); }
    catch { return corsResponse(JSON.stringify({ error: "Invalid JSON" }), 400); }

    const { text, voice_id = "21m00Tcm4TlvDq8ikWAM", model_id = "eleven_multilingual_v2" } = body;

    if (!text || typeof text !== "string" || text.length > 2000) {
      return corsResponse(JSON.stringify({ error: "text required, max 2000 chars" }), 400);
    }

    if (!ALLOWED_VOICES.has(voice_id)) {
      return corsResponse(JSON.stringify({ error: "Voice not allowed" }), 400);
    }

    // Proxy to ElevenLabs
    const elRes = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voice_id}`,
      {
        method: "POST",
        headers: {
          "xi-api-key":   env.ELEVENLABS_API_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          text,
          model_id,
          voice_settings: { stability: 0.5, similarity_boost: 0.75 },
        }),
      }
    );

    if (!elRes.ok) {
      const err = await elRes.text();
      return corsResponse(JSON.stringify({ error: "ElevenLabs error", detail: err }), 502);
    }

    // Bump rate limit counter
    await env.RATE_LIMIT.put(ratKey, String(count + 1), { expirationTtl: 86400 });

    // Return audio stream directly
    return new Response(elRes.body, {
      status: 200,
      headers: {
        "Content-Type":                "audio/mpeg",
        "Access-Control-Allow-Origin": "*",
        "Cache-Control":               "no-store",
      },
    });
  },
};

function corsResponse(body, status) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type":                "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, X-Device-ID",
    },
  });
}
