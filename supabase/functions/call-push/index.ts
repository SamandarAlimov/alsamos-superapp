import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

type CallRecord = {
  id: string;
  conversation_id: string;
  host_id: string;
  call_type?: string | null;
};

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const fcmServerKey = Deno.env.get('FCM_SERVER_KEY');
  if (!fcmServerKey) {
    return Response.json({ ok: false, error: 'FCM_SERVER_KEY missing' }, { status: 500 });
  }

  const { record } = await req.json() as { record: CallRecord };
  const sb = createClient(supabaseUrl, serviceKey);

  const { data: caller } = await sb
    .from('profiles')
    .select('display_name, username, avatar_url')
    .eq('id', record.host_id)
    .maybeSingle();

  const { data: participants } = await sb
    .from('conversation_participants')
    .select('user_id')
    .eq('conversation_id', record.conversation_id)
    .neq('user_id', record.host_id);

  const userIds = (participants ?? []).map((p) => p.user_id);
  if (userIds.length === 0) return Response.json({ ok: true, sent: 0 });

  const { data: tokens } = await sb
    .from('user_push_tokens')
    .select('token, user_id')
    .in('user_id', userIds);

  const registrationIds = (tokens ?? []).map((t) => t.token).filter(Boolean);
  if (registrationIds.length === 0) return Response.json({ ok: true, sent: 0 });

  const callerName = caller?.display_name || caller?.username || 'Alsamos';
  const response = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${fcmServerKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      registration_ids: registrationIds,
      priority: 'high',
      content_available: true,
      data: {
        type: 'incoming_call',
        call_id: record.id,
        conversation_id: record.conversation_id,
        caller_id: record.host_id,
        caller_name: callerName,
        caller_avatar: caller?.avatar_url ?? '',
        call_type: record.call_type ?? 'video',
      },
      notification: {
        title: callerName,
        body: record.call_type === 'audio' ? "Ovozli qo'ng'iroq" : "Video qo'ng'iroq",
        sound: 'default',
      },
    }),
  });

  return Response.json({ ok: response.ok, sent: registrationIds.length });
});
