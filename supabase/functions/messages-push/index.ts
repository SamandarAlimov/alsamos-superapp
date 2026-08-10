import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const fcmServerKey = Deno.env.get("FCM_SERVER_KEY")!;
const supabase = createClient(url, serviceRole);

serve(async (req) => {
  const payload = await req.json();
  const record = payload.record ?? payload;
  const conversationId = record.conversation_id;
  const senderId = record.sender_id;
  if (!conversationId || !senderId) return new Response("ignored");

  const { data: participants } = await supabase
    .from("conversation_participants")
    .select("user_id")
    .eq("conversation_id", conversationId)
    .neq("user_id", senderId);
  const userIds = (participants ?? []).map((p) => p.user_id);
  if (userIds.length === 0) return new Response("no recipients");

  const { data: tokens } = await supabase
    .from("user_push_tokens")
    .select("token,user_id")
    .in("user_id", userIds);
  const data = {
    type: record.media_type === "call_history" ? "call" : "message",
    conversation_id: conversationId,
    message_id: record.id,
    sender_id: senderId,
    title: "Alsamos",
    body: record.content ?? "New message",
  };

  const results = await Promise.allSettled((tokens ?? []).map((row) =>
    fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Authorization": `key=${fcmServerKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        to: row.token,
        priority: "high",
        content_available: true,
        data,
      }),
    })
  ));

  return Response.json({ sent: results.filter((r) => r.status === "fulfilled").length });
});
