// supabase/functions/twilio-inbound/index.ts
//
// Twilio inbound-SMS webhook. Handles carrier STOP keywords so opt-outs are
// honored in our own data (Twilio also enforces them at the carrier level).
//
// Twilio POSTs application/x-www-form-urlencoded with fields including Body, From.
// If Body (trimmed/uppercased) is a stop keyword, set sms_opt_out = true on the
// player whose phone matches From (both normalized to E.164). Always responds
// with valid (empty) TwiML so Twilio does not auto-reply.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STOP_KEYWORDS = new Set([
  "STOP",
  "STOPALL",
  "UNSUBSCRIBE",
  "CANCEL",
  "END",
  "QUIT",
]);

const EMPTY_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response></Response>';

function twiml(status = 200): Response {
  return new Response(EMPTY_TWIML, {
    status,
    headers: { "Content-Type": "text/xml" },
  });
}

// Normalize a phone number to a best-effort E.164 form for matching.
// Keeps a leading '+', strips all other non-digits, and assumes a bare
// 10-digit US number is +1.
function normalizeE164(raw: string | null): string | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  const hasPlus = trimmed.startsWith("+");
  const digits = trimmed.replace(/\D/g, "");
  if (!digits) return null;
  if (hasPlus) return "+" + digits;
  if (digits.length === 10) return "+1" + digits;
  return "+" + digits;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    // Still return TwiML-shaped content type; do not leak details.
    return twiml(200);
  }

  let form: URLSearchParams;
  try {
    const raw = await req.text();
    form = new URLSearchParams(raw);
  } catch {
    return twiml(200);
  }

  const body = (form.get("Body") ?? "").trim().toUpperCase();
  const from = normalizeE164(form.get("From"));

  // Only act on recognized stop keywords with a resolvable sender.
  if (from && STOP_KEYWORDS.has(body)) {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (supabaseUrl && serviceKey) {
      const supabase = createClient(supabaseUrl, serviceKey, {
        auth: { persistSession: false },
      });
      // Update opt-out. Match on normalized phone.
      const { error } = await supabase
        .from("player")
        .update({ sms_opt_out: true })
        .eq("phone", from);
      if (error) {
        // Do not log sensitive content; a generic marker is enough.
        console.error("twilio-inbound: opt-out update failed");
      }
    }
  }

  return twiml(200);
});
