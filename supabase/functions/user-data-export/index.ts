import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const userId = userData.user.id;
  const [profile, conversations, messages, settings] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", userId).maybeSingle(),
    supabase
      .from("conversation_participants")
      .select("conversation_id, role, joined_at")
      .eq("user_id", userId),
    supabase
      .from("messages")
      .select("id, conversation_id, content, media_url, media_type, created_at")
      .eq("sender_id", userId)
      .order("created_at", { ascending: false })
      .limit(5000),
    supabase.from("user_settings").select("*").eq("user_id", userId).maybeSingle(),
  ]);

  const manifest = {
    generated_at: new Date().toISOString(),
    profile: profile.data,
    conversations: conversations.data ?? [],
    messages: messages.data ?? [],
    settings: settings.data,
  };

  const { data: exportRow, error } = await supabase
    .from("user_data_exports")
    .insert({ user_id: userId, status: "ready", manifest })
    .select("id, status, created_at, expires_at")
    .single();

  if (error) return Response.json({ error: error.message }, { status: 400 });
  return Response.json({ status: "ready", export: exportRow, manifest });
});
