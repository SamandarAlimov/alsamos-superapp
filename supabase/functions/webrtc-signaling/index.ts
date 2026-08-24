// Lightweight WebSocket relay for Flutter/Web WebRTC calls.
//
// Durable DB signaling remains the source-of-truth fallback. This Edge
// Function is only a low-latency relay for offer/answer/ICE/media events.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Client = {
  socket: WebSocket;
  roomId: string;
  userId: string;
};

const rooms = new Map<string, Map<string, Client>>();

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const upgrade = req.headers.get("upgrade") ?? "";
  if (upgrade.toLowerCase() !== "websocket") {
    return new Response("WebSocket required", {
      status: 426,
      headers: corsHeaders,
    });
  }

  const url = new URL(req.url);
  const initialRoomId =
    url.searchParams.get("roomId") ?? url.searchParams.get("callId");
  const initialUserId = url.searchParams.get("userId");

  const { socket, response } = Deno.upgradeWebSocket(req);
  let client: Client | null = null;
  const tokenUserId = getUserIdFromToken(req.headers.get("authorization"));

  socket.onopen = async () => {
    if (initialRoomId != null && initialUserId != null) {
      client = await registerClient({
        socket,
        roomId: initialRoomId,
        userId: initialUserId,
        tokenUserId,
      });
      return;
    }
    socket.send(JSON.stringify({ type: "ready" }));
  };

  socket.onmessage = async (event) => {
    const message = parseMessage(event.data);
    if (message == null) return;

    const type = String(message.type ?? "");
    if (type.length === 0) return;

    if (type === "join" || type === "join-room") {
      const roomId =
        stringOrNull(message.roomId) ?? stringOrNull(message.callId);
      const userId = stringOrNull(message.userId);
      if (roomId == null || userId == null) {
        socket.send(JSON.stringify({
          type: "error",
          message: "Missing roomId/callId or userId",
        }));
        return;
      }
      client = await registerClient({ socket, roomId, userId, tokenUserId });
      return;
    }

    if (client == null) {
      socket.send(JSON.stringify({
        type: "error",
        message: "Join the call before sending signaling messages",
      }));
      return;
    }

    const normalized = {
      ...message,
      type,
      roomId: client.roomId,
      callId: client.roomId,
      userId: client.userId,
      fromUserId: client.userId,
      from: client.userId,
    };

    const targetUserId =
      stringOrNull(message.targetUserId) ?? stringOrNull(message.to);

    if (targetUserId != null) {
      sendTo(client.roomId, targetUserId, normalized);
      return;
    }

    broadcast(client.roomId, client.userId, normalized);
  };

  socket.onerror = () => {
    if (client != null) leave(client);
  };

  socket.onclose = () => {
    if (client != null) leave(client);
  };

  return response;
});

async function registerClient({
  socket,
  roomId,
  userId,
  tokenUserId,
}: {
  socket: WebSocket;
  roomId: string;
  userId: string;
  tokenUserId: string | null;
}): Promise<Client | null> {
  const candidate: Client = { socket, roomId, userId };

  if (tokenUserId != null && tokenUserId !== userId) {
    send(candidate, {
      type: "error",
      message: "User ID mismatch with authentication token",
    });
    socket.close(1008, "user_id_mismatch");
    return null;
  }

  const allowed = await verifyParticipant(userId, roomId);
  if (!allowed) {
    send(candidate, {
      type: "error",
      message: "Not authorized to join this call",
    });
    socket.close(1008, "not_authorized");
    return null;
  }

  const room = getRoom(roomId);
  const previous = room.get(userId);
  if (previous != null && previous.socket !== socket) {
    previous.socket.close(1000, "replaced");
  }
  room.set(userId, candidate);

  const peers = [...room.keys()].filter((id) => id !== userId);
  send(candidate, {
    type: "joined",
    roomId,
    callId: roomId,
    userId,
    peers,
    participants: peers,
    participantCount: room.size,
  });

  broadcast(roomId, userId, {
    type: "user-joined",
    roomId,
    callId: roomId,
    userId,
    participantCount: room.size,
  });

  return candidate;
}

function getRoom(roomId: string): Map<string, Client> {
  let room = rooms.get(roomId);
  if (room == null) {
    room = new Map<string, Client>();
    rooms.set(roomId, room);
  }
  return room;
}

function leave(client: Client) {
  const room = rooms.get(client.roomId);
  if (room == null) return;

  const existing = room.get(client.userId);
  if (existing?.socket !== client.socket) return;

  room.delete(client.userId);
  broadcast(client.roomId, client.userId, {
    type: "user-left",
    roomId: client.roomId,
    callId: client.roomId,
    userId: client.userId,
    fromUserId: client.userId,
    from: client.userId,
  });

  if (room.size === 0) rooms.delete(client.roomId);
}

function broadcast(
  roomId: string,
  exceptUserId: string,
  message: Record<string, unknown>,
) {
  const room = rooms.get(roomId);
  if (room == null) return;

  for (const [peerId, peer] of room.entries()) {
    if (peerId === exceptUserId) continue;
    send(peer, message);
  }
}

function sendTo(
  roomId: string,
  targetUserId: string,
  message: Record<string, unknown>,
) {
  const peer = rooms.get(roomId)?.get(targetUserId);
  if (peer == null) return;
  send(peer, message);
}

function send(client: Client, message: Record<string, unknown>) {
  if (client.socket.readyState !== WebSocket.OPEN) return;
  client.socket.send(JSON.stringify(message));
}

function parseMessage(data: unknown): Record<string, unknown> | null {
  try {
    if (typeof data === "string") {
      const parsed = JSON.parse(data);
      return isRecord(parsed) ? parsed : null;
    }
    if (data instanceof ArrayBuffer) {
      const parsed = JSON.parse(new TextDecoder().decode(data));
      return isRecord(parsed) ? parsed : null;
    }
  } catch {
    return null;
  }
  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function getUserIdFromToken(authHeader: string | null): string | null {
  if (authHeader == null || !authHeader.startsWith("Bearer ")) return null;

  try {
    const token = authHeader.substring(7);
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const payload = JSON.parse(atob(parts[1]));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

async function verifyParticipant(
  userId: string,
  callId: string,
): Promise<boolean> {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (supabaseUrl == null || serviceKey == null) return false;

    const supabase = createClient(supabaseUrl, serviceKey);

    const { data: directParticipant } = await supabase
      .from("call_participants")
      .select("call_id")
      .eq("call_id", callId)
      .eq("user_id", userId)
      .maybeSingle();

    if (directParticipant != null) return true;

    const { data: call } = await supabase
      .from("video_calls")
      .select("id, host_id, conversation_id")
      .eq("id", callId)
      .maybeSingle();

    if (call == null) return false;
    if (call.host_id === userId) return true;

    const conversationId = call.conversation_id;
    if (typeof conversationId !== "string") return false;

    const { data: byUserId } = await supabase
      .from("conversation_participants")
      .select("conversation_id")
      .eq("conversation_id", conversationId)
      .eq("user_id", userId)
      .maybeSingle();

    if (byUserId != null) return true;

    const { data: byProfileId } = await supabase
      .from("conversation_participants")
      .select("conversation_id")
      .eq("conversation_id", conversationId)
      .eq("profile_id", userId)
      .maybeSingle();

    return byProfileId != null;
  } catch (error) {
    console.error("WebRTC participant verification failed", error);
    return false;
  }
}
