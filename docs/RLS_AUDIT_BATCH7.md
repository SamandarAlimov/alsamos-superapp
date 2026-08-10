# RLS Audit Batch 7

Run after applying `20260713038000_rls_audit_report.sql`:

```sql
select * from public.get_rls_audit_report();
```

Expected state for MVP-critical Messages scope:

- `ok`: `messages`, `conversation_participants`, `message_reads`, `message_delivery_receipts`, `message_reactions`, `message_edit_history`, `message_drafts`, `message_hashtags`, `message_media_items`, `message_polls`, `message_poll_votes`, `message_reports`, `conversation_restrictions`, `conversation_admin_actions`, `conversation_notification_settings`, `user_blocks`, `user_settings`, `user_sessions`, `notifications`.
- `missing_rls` or `missing_policy`: must be fixed before production if the table contains user-owned, private, moderation, payment, or location data.
- Public catalog/content tables may intentionally expose read policies, but writes must remain authenticated/admin-scoped.

Audit note: the report is admin-only through `is_user_admin(auth.uid())`; it exposes table/policy metadata, not row data.
