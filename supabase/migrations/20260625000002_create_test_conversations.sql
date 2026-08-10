-- Create test conversations and messages for development
-- This migration creates sample data matching web's structure

DO $$
DECLARE
  test_user_id uuid;
  test_user2_id uuid;
  conv1_id uuid;
  conv2_id uuid;
  conv3_id uuid;
BEGIN
  -- Get or create test users
  SELECT id INTO test_user_id FROM profiles WHERE username = 'testuser1' LIMIT 1;
  IF test_user_id IS NULL THEN
    -- Create test user in auth.users first (you'll need to do this manually or via Supabase dashboard)
    -- For now, just use existing user
    SELECT id INTO test_user_id FROM profiles LIMIT 1;
  END IF;

  SELECT id INTO test_user2_id FROM profiles WHERE id != test_user_id LIMIT 1 OFFSET 1;

  IF test_user_id IS NOT NULL AND test_user2_id IS NOT NULL THEN
    -- Create test conversation 1 (private)
    INSERT INTO conversations (type, owner_id, last_message_at, created_at)
    VALUES ('private', test_user_id, NOW(), NOW())
    RETURNING id INTO conv1_id;

    INSERT INTO conversation_participants (conversation_id, user_id, role, is_pinned)
    VALUES 
      (conv1_id, test_user_id, 'owner', false),
      (conv1_id, test_user2_id, 'member', false);

    -- Add test messages
    INSERT INTO messages (conversation_id, sender_id, content, created_at)
    VALUES 
      (conv1_id, test_user2_id, 'Salom! Qalaysiz?', NOW() - INTERVAL '2 hours'),
      (conv1_id, test_user_id, 'Yaxshi, rahmat! Sizchi?', NOW() - INTERVAL '1 hour'),
      (conv1_id, test_user2_id, 'Menda ham hammasi yaxshi', NOW() - INTERVAL '30 minutes');

    -- Create test conversation 2 (private with unread)
    INSERT INTO conversations (type, owner_id, last_message_at, created_at)
    VALUES ('private', test_user_id, NOW(), NOW() - INTERVAL '1 day')
    RETURNING id INTO conv2_id;

    INSERT INTO conversation_participants (conversation_id, user_id, role, is_pinned)
    VALUES 
      (conv2_id, test_user_id, 'owner', true), -- pinned
      (conv2_id, test_user2_id, 'member', false);

    INSERT INTO messages (conversation_id, sender_id, content, created_at)
    VALUES 
      (conv2_id, test_user2_id, 'Yangi xabar!', NOW() - INTERVAL '10 minutes'),
      (conv2_id, test_user2_id, 'Bu o\'qilmagan', NOW() - INTERVAL '5 minutes');

    -- Create test conversation 3 (group)
    INSERT INTO conversations (type, owner_id, name, last_message_at, created_at)
    VALUES ('group', test_user_id, 'Test Guruh', NOW(), NOW() - INTERVAL '2 days')
    RETURNING id INTO conv3_id;

    INSERT INTO conversation_participants (conversation_id, user_id, role)
    VALUES 
      (conv3_id, test_user_id, 'admin'),
      (conv3_id, test_user2_id, 'member');

    INSERT INTO messages (conversation_id, sender_id, content, created_at)
    VALUES 
      (conv3_id, test_user_id, 'Guruhga xush kelibsiz!', NOW() - INTERVAL '2 days'),
      (conv3_id, test_user2_id, 'Rahmat!', NOW() - INTERVAL '1 day');

    RAISE NOTICE 'Test conversations created successfully!';
  ELSE
    RAISE NOTICE 'Not enough users found. Please create users first.';
  END IF;
END $$;
