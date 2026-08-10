-- Test data for messages feature
-- This creates sample conversations and messages for testing

-- Create a test conversation if not exists
INSERT INTO conversations (id, type, owner_id, last_message_at)
VALUES (
  'test-conv-001',
  'private',
  auth.uid(),
  NOW()
)
ON CONFLICT (id) DO NOTHING;

-- Add current user as participant
INSERT INTO conversation_participants (conversation_id, user_id, role)
VALUES (
  'test-conv-001',
  auth.uid(),
  'owner'
)
ON CONFLICT (conversation_id, user_id) DO NOTHING;

-- Create some test messages
INSERT INTO messages (id, conversation_id, sender_id, content, created_at)
VALUES
  ('msg-001', 'test-conv-001', auth.uid(), 'Salom! Bu test xabar', NOW() - INTERVAL '5 minutes'),
  ('msg-002', 'test-conv-001', auth.uid(), 'Qalaysiz? Hammasi yaxshimi?', NOW() - INTERVAL '4 minutes'),
  ('msg-003', 'test-conv-001', auth.uid(), 'Messages feature ishlayaptimi?', NOW() - INTERVAL '3 minutes'),
  ('msg-004', 'test-conv-001', auth.uid(), 'Professional UI juda chiroyli 🎉', NOW() - INTERVAL '2 minutes'),
  ('msg-005', 'test-conv-001', auth.uid(), 'Hamma narsalar to''g''ri ishlashi kerak', NOW() - INTERVAL '1 minute')
ON CONFLICT (id) DO NOTHING;

-- Update conversation last_message_at
UPDATE conversations 
SET last_message_at = NOW() 
WHERE id = 'test-conv-001';
