-- Add default TURN/STUN servers for WebRTC calls
-- This ensures calls work across NAT/firewalls without env config

BEGIN;

-- Insert default ICE servers configuration
-- Uses free public STUN servers + Metered TURN (free tier)
INSERT INTO public.call_webrtc_config (key, value, updated_at)
VALUES (
  'ice_servers',
  '{
    "iceServers": [
      {
        "urls": "stun:stun.l.google.com:19302"
      },
      {
        "urls": "stun:stun1.l.google.com:19302"
      },
      {
        "urls": "stun:stun2.l.google.com:19302"
      },
      {
        "urls": [
          "turn:openrelay.metered.ca:80",
          "turn:openrelay.metered.ca:443",
          "turn:openrelay.metered.ca:443?transport=tcp"
        ],
        "username": "openrelayproject",
        "credential": "openrelayproject"
      },
      {
        "urls": [
          "turn:a.relay.metered.ca:80",
          "turn:a.relay.metered.ca:80?transport=tcp",
          "turn:a.relay.metered.ca:443",
          "turn:a.relay.metered.ca:443?transport=tcp",
          "turns:a.relay.metered.ca:443?transport=tcp"
        ],
        "username": "e46d064e3c1b60019d6052e1",
        "credential": "BGmFZmMFZ2rQnPCP"
      }
    ]
  }'::jsonb,
  now()
)
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  updated_at = now();

-- Add comment explaining the configuration
COMMENT ON TABLE public.call_webrtc_config IS
'WebRTC ICE server configuration for video/audio calls.
Contains STUN servers (for discovering public IP) and TURN servers (for relaying traffic through NAT/firewalls).
Default config uses free public servers - replace with your own for production.';

COMMIT;

-- IMPORTANT NOTES FOR PRODUCTION:
-- 1. Replace Metered TURN credentials with your own (get free tier at https://www.metered.ca/tools/openrelay/)
-- 2. Or use Twilio TURN (https://www.twilio.com/stun-turn)
-- 3. Or host your own Coturn server (https://github.com/coturn/coturn)
-- 4. Monitor TURN usage - free tiers have bandwidth limits
-- 5. For high-traffic production, use dedicated TURN infrastructure

-- To update ICE servers via SQL:
-- UPDATE call_webrtc_config
-- SET value = '{"iceServers": [...your servers...]}'::jsonb
-- WHERE key = 'ice_servers';

-- To verify current config:
-- SELECT value FROM call_webrtc_config WHERE key = 'ice_servers';
