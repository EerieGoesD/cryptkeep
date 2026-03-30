import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabase.auth.getUser(token);

  if (authError || !user) {
    return new Response(
      JSON.stringify({ error: "Invalid token" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Check premium status server-side
  const premiumUntil = user.user_metadata?.premium_until;
  if (!premiumUntil || new Date(premiumUntil) <= new Date()) {
    return new Response(
      JSON.stringify({ error: "Pro subscription required" }),
      { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Expects { hashes: [{ id: "entry-id", prefix: "A94A8", suffix: "FE5CCB19..." }] }
  let body: { hashes: { id: string; prefix: string; suffix: string }[] };
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid request body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  if (!body.hashes || !Array.isArray(body.hashes)) {
    return new Response(
      JSON.stringify({ error: "Missing hashes array" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const results: Record<string, number> = {};
  const checkedPrefixes: Record<string, string> = {};

  for (const entry of body.hashes) {
    const { id, prefix, suffix } = entry;
    if (!prefix || !suffix || prefix.length !== 5) continue;

    let hibpResponse = checkedPrefixes[prefix];
    if (!hibpResponse) {
      try {
        const resp = await fetch(
          `https://api.pwnedpasswords.com/range/${prefix}`,
          { headers: { "User-Agent": "CryptKeep-Server" } }
        );
        if (resp.ok) {
          hibpResponse = await resp.text();
          checkedPrefixes[prefix] = hibpResponse;
        }
      } catch {
        continue;
      }
      await new Promise((r) => setTimeout(r, 50));
    }

    if (hibpResponse) {
      for (const line of hibpResponse.split("\n")) {
        const parts = line.trim().split(":");
        if (parts.length === 2 && parts[0] === suffix.toUpperCase()) {
          results[id] = parseInt(parts[1], 10) || 0;
          break;
        }
      }
    }
  }

  return new Response(
    JSON.stringify({ results }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
});
