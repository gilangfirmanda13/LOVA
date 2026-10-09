// Edge Function: anthropic-proxy
// Tugasnya cuma satu: terima body dari app React, teruskan ke Anthropic API
// dengan ANTHROPIC_API_KEY yang disimpan aman sebagai secret di server Supabase
// (bukan di browser), lalu kembalikan responsnya apa adanya.
//
// Deploy sekali via Supabase CLI (lihat SETUP.md), lalu set secretnya:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-xxxxx
//
// Secara default Supabase MEWAJIBKAN JWT (login) yang valid untuk memanggil
// function ini — jangan deploy dengan flag --no-verify-jwt, supaya orang lain
// yang kebetulan tahu URL-nya tidak bisa numpang pakai API key Anda.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY belum di-set di Supabase secrets." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    });

    const data = await anthropicRes.json();

    return new Response(JSON.stringify(data), {
      status: anthropicRes.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err instanceof Error ? err.message : err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
