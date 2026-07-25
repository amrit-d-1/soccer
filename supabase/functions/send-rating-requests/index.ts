// supabase/functions/send-rating-requests/index.ts
//
// Sends per-player rating-request SMS for a session.
//
// POST body: { session_id: string, mode: "initial" | "reminder" }
//   - initial:  message every rating_link for the session
//   - reminder: message only players who have NOT yet submitted a rating
//
// Skips players with no phone or sms_opt_out = true.
// Writes EVERY attempt to sms_log. Returns { sent, skipped, failed }.
//
// Env:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   (service-role client; bypasses RLS)
//   PUBLIC_RATING_BASE_URL                    (base for the rating page, no trailing slash)
//   SMS_PROVIDER = "console" (default) | "twilio"
//   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER  (when provider = twilio)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface SendResult {
  ok: boolean;
  error: string | null;
}

async function sendViaTwilio(to: string, body: string): Promise<SendResult> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_FROM_NUMBER");

  if (!sid || !token || !from) {
    return { ok: false, error: "Twilio credentials not configured" };
  }

  const url = `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`;
  const form = new URLSearchParams({ To: to, From: from, Body: body });

  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(`${sid}:${token}`),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
    });

    if (!resp.ok) {
      const text = await resp.text();
      return { ok: false, error: `Twilio ${resp.status}: ${text}` };
    }
    return { ok: true, error: null };
  } catch (e) {
    return { ok: false, error: `Twilio request failed: ${String(e)}` };
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let payload: { session_id?: string; mode?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const sessionId = payload.session_id;
  const mode = payload.mode === "reminder" ? "reminder" : "initial";
  if (!sessionId) {
    return json({ error: "session_id is required" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Server not configured (missing SUPABASE_URL / SERVICE_ROLE_KEY)" }, 500);
  }

  const baseUrl = (Deno.env.get("PUBLIC_RATING_BASE_URL") ?? "").replace(/\/+$/, "");
  const provider = Deno.env.get("SMS_PROVIDER") ?? "console";

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // Load rating links for this session, joined to the player.
  const { data: links, error: linksErr } = await supabase
    .from("rating_link")
    .select("token, player_id, player:player_id ( id, name, phone, sms_opt_out )")
    .eq("session_id", sessionId);

  if (linksErr) {
    return json({ error: `Failed to load rating links: ${linksErr.message}` }, 500);
  }

  // For reminder mode, exclude players who already submitted a rating.
  let ratedIds = new Set<string>();
  if (mode === "reminder") {
    const { data: ratings, error: ratingsErr } = await supabase
      .from("rating")
      .select("rater_id")
      .eq("session_id", sessionId);
    if (ratingsErr) {
      return json({ error: `Failed to load ratings: ${ratingsErr.message}` }, 500);
    }
    ratedIds = new Set((ratings ?? []).map((r: { rater_id: string }) => r.rater_id));
  }

  let sent = 0;
  let skipped = 0;
  let failed = 0;

  for (const link of links ?? []) {
    // supabase-js may return the embedded relation as an object or array.
    const rawPlayer = (link as Record<string, unknown>).player;
    const player = Array.isArray(rawPlayer) ? rawPlayer[0] : rawPlayer;
    const p = player as
      | { id: string; name: string; phone: string | null; sms_opt_out: boolean }
      | undefined;

    const playerId = (link as { player_id: string }).player_id;

    if (mode === "reminder" && ratedIds.has(playerId)) {
      skipped++;
      continue;
    }

    const phone = p?.phone?.trim() ?? "";
    if (!phone || p?.sms_opt_out) {
      skipped++;
      continue;
    }

    const token = (link as { token: string }).token;
    const body = `Friday soccer — how was it? 10 seconds: ${baseUrl}/r/${token}`;

    let result: SendResult;
    if (provider === "twilio") {
      result = await sendViaTwilio(phone, body);
    } else {
      // "console" provider: log only, send nothing.
      console.log(`[console-sms] to=${phone} body=${body}`);
      result = { ok: true, error: null };
    }

    // Log every attempt regardless of outcome.
    await supabase.from("sms_log").insert({
      player_id: playerId,
      session_id: sessionId,
      body,
      provider,
      ok: result.ok,
      error: result.error,
    });

    if (result.ok) sent++;
    else failed++;
  }

  return json({ sent, skipped, failed });
});
