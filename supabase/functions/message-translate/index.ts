import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { text, target_language } = await req.json();
    const source = String(text ?? "").trim();
    const target = String(target_language ?? "uz");
    if (!source) {
      return Response.json({ translated_text: "" }, { headers: cors });
    }

    const key = Deno.env.get("TRANSLATE_API_KEY");
    const endpoint =
      Deno.env.get("TRANSLATE_API_URL") ??
      "https://translation.googleapis.com/language/translate/v2";
    if (!key) {
      return Response.json(
        { translated_text: source, provider: "passthrough" },
        { headers: cors },
      );
    }

    const res = await fetch(`${endpoint}?key=${key}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ q: source, target, format: "text" }),
    });
    if (!res.ok) throw new Error(await res.text());
    const data = await res.json();
    const translated =
      data?.data?.translations?.[0]?.translatedText ??
      data?.translated_text ??
      source;
    return Response.json(
      { translated_text: translated, target_language: target },
      { headers: cors },
    );
  } catch (error) {
    return Response.json(
      { error: String(error?.message ?? error) },
      { status: 500, headers: cors },
    );
  }
});
