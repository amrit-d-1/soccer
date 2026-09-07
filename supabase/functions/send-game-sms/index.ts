// supabase/functions/send-game-sms/index.ts
//
// POST { game_id, kind: 'invite' | 'reminder' | 'rate' }
//
// Sends the appropriate SMS to the right set of recipients for a game and logs
// every attempt to sms_log. Uses a service-role client so it can read the full
// roster and write logs regardless of RLS. Requires a valid JWT (verify_jwt =
// true in config.toml) so only the authenticated admin app can invoke it.
//
// Recipients by kind:
//   invite   - all active players with a phone (the roster)
//   reminder - players who are 'in' OR have no rsvp yet, excluding 'out'/'maybe'
//   rate     - players with an appearance for the game and no rating yet
// Always skips players who opted out (sms_opt_out) or have an empty phone.
//
// Provider: SMS_PROVIDER = 'console' (default, logs only) or 'twilio'.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PUBLIC_APP_BASE_URL,
//      SMS_PROVIDER, TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Kind = "invite" | "reminder" | "rate";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface Recipient {
  player_id: string;
  phone: string;
}

// Send one SMS through the configured provider. Returns { ok, error }.
async function sendSms(
  provider: string,
  to: string,
  body: string,
): Promise<{ ok: boolean; error: string | null }> {
  if (provider === "twilio") {
    const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const token = Deno.env.get("TWILIO_AUTH_TOKEN");
    const from = Deno.env.get("TWILIO_FROM_NUMBER");
    if (!sid || !token || !from) {
      return { ok: false, error: "twilio env vars missing" };
    }
    try {
      const url = `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`;
      const form = new URLSearchParams({ To: to, From: from, Body: body });
      const res = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: "Basic " + btoa(`${sid}:${token}`),
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: form.toString(),
      });
      if (!res.ok) {
        const text = await res.text();
        return { ok: false, error: `twilio ${res.status}: ${text.slice(0, 300)}` };
      }
      return { ok: true, error: null };
    } catch (e) {
      return { ok: false, error: String(e) };
    }
  }

  // 'console' (default): log only, treat as success.
  console.log(`[sms:console] To=${to} Body=${body}`);
  return { ok: true, error: null };
}

function fmtDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  });
}

function fmtTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "server misconfigured" }, 500);
  }

  let payload: { game_id?: string; kind?: Kind };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const gameId = payload.game_id;
  const kind = payload.kind;
  if (!gameId || (kind !== "invite" && kind !== "reminder" && kind !== "rate")) {
    return json({ error: "game_id and valid kind are required" }, 400);
  }

  const provider = Deno.env.get("SMS_PROVIDER") ?? "console";
  const appBase = Deno.env.get("PUBLIC_APP_BASE_URL") ?? "";

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // Load the game.
  const { data: game, error: gameErr } = await supabase
    .from("game")
    .select("id, starts_at, location")
    .eq("id", gameId)
    .single();
  if (gameErr || !game) {
    return json({ error: "game not found" }, 404);
  }

  // Build the recipient set for this kind.
  let recipients: Recipient[] = [];

  if (kind === "invite") {
    const { data, error } = await supabase
      .from("player")
      .select("id, phone")
      .eq("is_active", true)
      .eq("sms_opt_out", false)
      .not("phone", "is", null);
    if (error) return json({ error: error.message }, 500);
    recipients = (data ?? []).map((p) => ({ player_id: p.id, phone: p.phone }));
  } else if (kind === "reminder") {
    // Active players with a phone, whose rsvp is 'in' or absent (exclude out/maybe).
    const { data: players, error: pErr } = await supabase
      .from("player")
      .select("id, phone")
      .eq("is_active", true)
      .eq("sms_opt_out", false)
      .not("phone", "is", null);
    if (pErr) return json({ error: pErr.message }, 500);

    const { data: rsvps, error: rErr } = await supabase
      .from("rsvp")
      .select("player_id, status")
      .eq("game_id", gameId);
    if (rErr) return json({ error: rErr.message }, 500);

    const statusByPlayer = new Map<string, string>();
    for (const r of rsvps ?? []) statusByPlayer.set(r.player_id, r.status);

    recipients = (players ?? [])
      .filter((p) => {
        const st = statusByPlayer.get(p.id);
        return st === undefined || st === "in"; // no rsvp yet, or 'in'
      })
      .map((p) => ({ player_id: p.id, phone: p.phone }));
  } else {
    // rate: players with an appearance for the game and no rating yet.
    const { data: apps, error: aErr } = await supabase
      .from("appearance")
      .select("player_id, player:player_id(id, phone, is_active, sms_opt_out)")
      .eq("game_id", gameId);
    if (aErr) return json({ error: aErr.message }, 500);

    const { data: ratings, error: rtErr } = await supabase
      .from("rating")
      .select("rater_id")
      .eq("game_id", gameId);
    if (rtErr) return json({ error: rtErr.message }, 500);

    const rated = new Set<string>((ratings ?? []).map((r) => r.rater_id));

    recipients = (apps ?? [])
      // deno-lint-ignore no-explicit-any
      .map((a: any) => a.player)
      .filter(
        (p: { id: string; phone: string | null; is_active: boolean; sms_opt_out: boolean } | null) =>
          p && p.is_active && !p.sms_opt_out && p.phone && !rated.has(p.id),
      )
      .map((p: { id: string; phone: string }) => ({ player_id: p.id, phone: p.phone }));
  }

  // Compose the body for this kind.
  const link = `${appBase}/game/${gameId}`;
  const rateLink = `${appBase}/rate/${gameId}`;
  const loc = game.location ?? "TBD";
  const bodyFor = (): string => {
    if (kind === "invite") {
      return `Soccer Game ${fmtDate(game.starts_at)} ${fmtTime(game.starts_at)} at ${loc}. In? ${link}`;
    }
    if (kind === "reminder") {
      return `Soccer Game reminder: game ${fmtTime(game.starts_at)}. RSVP: ${link}`;
    }
    return `Soccer Game: how was it? Rate in 10s: ${rateLink}`;
  };
  const body = bodyFor();

  let sent = 0;
  let skipped = 0;
  let failed = 0;

  for (const r of recipients) {
    // Defensive: skip empty phones (should already be filtered).
    if (!r.phone || r.phone.trim() === "") {
      skipped++;
      continue;
    }

    const { ok, error } = await sendSms(provider, r.phone, body);

    await supabase.from("sms_log").insert({
      player_id: r.player_id,
      game_id: gameId,
      kind,
      body,
      provider,
      ok,
      error,
    });

    if (ok) sent++;
    else failed++;
  }

  return json({ sent, skipped, failed });
});
