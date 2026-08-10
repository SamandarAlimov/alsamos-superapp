import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { audio_url } = await req.json();
    const audioUrl = String(audio_url ?? "").trim();
    if (!audioUrl) return Response.json({ text: "" }, { headers: cors });

    const key = Deno.env.get("STT_API_KEY");
    const endpoint = Deno.env.get("STT_API_URL");
    if (!key || !endpoint) {
      return Response.json(
        { text: "", provider: "not_configured" },
        { headers: cors },
      );
    }

    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${key}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ audio_url: audioUrl }),
    });
    if (!res.ok) throw new Error(await res.text());
    const data = await res.json();
    return Response.json(
      {
        text: data.text ?? data.transcript ?? "",
        language: data.language,
      },
      { headers: cors },
    );
  } catch (error) {
    return Response.json(
      { error: String(error?.message ?? error) },
      { status: 500, headers: cors },
    );
  }
});
