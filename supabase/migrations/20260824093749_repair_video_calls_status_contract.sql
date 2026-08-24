BEGIN;

-- Repair the runtime contract used by create_video_call().
-- Some production databases still have the original narrow check:
-- CHECK (status IN ('waiting', 'active', 'ended')).
-- The Flutter/Web call flow needs transitional statuses such as ringing and
-- connecting before a peer accepts and real RTC media connects.

ALTER TABLE public.video_calls
  DROP CONSTRAINT IF EXISTS video_calls_status_check;

ALTER TABLE public.video_calls
  ADD CONSTRAINT video_calls_status_check CHECK (
    status IN (
      'waiting',
      'pending',
      'ringing',
      'calling',
      'connecting',
      'active',
      'reconnecting',
      'ended',
      'declined',
      'missed',
      'cancelled',
      'failed',
      'expired'
    )
  ) NOT VALID;

COMMIT;

NOTIFY pgrst, 'reload schema';
