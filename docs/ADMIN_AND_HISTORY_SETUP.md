# Admin Panel & History Feature Setup Guide

This document explains how to set up and use the Admin Panel and History features in Alsamos.

## Features Overview

### 1. History Page (`/settings/history`)
- **Login & Session History**: Shows all user sessions with device info, platform, IP address, and timestamps
- **Security Activity**: Displays password changes, 2FA enable/disable, email/phone changes, account recovery events
- **Search History**: Shows recent searches with ability to clear individual items or all history
- **Features**: 
  - Filter by category (All, Sessions, Security, Search)
  - Pull-to-refresh
  - Relative timestamps
  - Device icons based on platform
  - Clear history with confirmation

### 2. Admin Panel Entry (Role-Gated)
- Only visible to users with admin role
- Server-enforced access control via RLS
- Located in Settings under "Admin" group
- Links to existing Admin Page (`/admin`)

## Database Setup

### Step 1: Run the Migration

Execute the migration to add required tables and columns:

```bash
# If using Supabase CLI
supabase db push

# Or run the SQL directly in Supabase SQL Editor
```

The migration file is located at: `supabase/migrations/20260111_admin_and_history_tables.sql`

### Step 2: Set Admin Users

After running the migration, grant admin access to specific users:

**Option A: By User ID**
```sql
UPDATE profiles 
SET is_admin = TRUE, role = 'alsamos_admin' 
WHERE id = 'YOUR_USER_ID_HERE';
```

**Option B: By Email (Recommended)**
```sql
UPDATE profiles 
SET is_admin = TRUE, role = 'alsamos_admin'
WHERE id = (SELECT id FROM auth.users WHERE email = 'admin@alsamos.uz');
```

**Option C: By Username**
```sql
UPDATE profiles 
SET is_admin = TRUE, role = 'alsamos_admin'
WHERE username = 'admin_username';
```

## Database Schema

### New Columns in `profiles` Table

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `is_admin` | BOOLEAN | FALSE | Quick boolean check for admin status |
| `role` | TEXT | 'user' | Role string (user, admin, alsamos_admin, moderator, etc.) |

### New `security_events` Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Foreign key to auth.users |
| `event_type` | TEXT | Type of security event |
| `description` | TEXT | Human-readable description |
| `metadata` | JSONB | Additional event data |
| `ip_address` | INET | IP address of the action |
| `user_agent` | TEXT | Browser/device user agent |
| `created_at` | TIMESTAMPTZ | Event timestamp |

### Security Event Types

- `password_change`: User changed their password
- `two_factor_enable`: User enabled 2FA
- `two_factor_disable`: User disabled 2FA
- `email_change`: User changed email address
- `phone_change`: User changed phone number
- `account_recovery`: User recovered their account

## Row Level Security (RLS) Policies

### Admin Access Control

1. **Profiles Table**: All authenticated users can read profiles (for role checking)
2. **Security Events Table**:
   - Users can only view their own security events
   - Admins can view all security events (for monitoring)
   - Only system (service_role) can insert events (prevents fake events)

### Admin Check Function

```sql
SELECT is_admin(); -- Returns true if current user is admin
```

## Testing the Features

### Testing History Page

1. **Prerequisites**:
   - Must be logged in
   - Have some data in `user_sessions`, `security_events`, or `search_history` tables

2. **Access**: Navigate to Settings → History (Tarix)

3. **Test Cases**:
   - [ ] Sessions display correctly with device info and IP
   - [ ] Security events show up when you change password/2FA
   - [ ] Search history displays recent searches
   - [ ] Filter buttons work (All, Sessions, Security, Search)
   - [ ] Pull-to-refresh reloads data
   - [ ] Clear search history prompts for confirmation
   - [ ] Empty states show when no data
   - [ ] Error states display properly

### Testing Admin Panel Entry

1. **Prerequisites**:
   - User must have `is_admin = TRUE` OR `role = 'admin'/'alsamos_admin'`

2. **Test as Non-Admin**:
   ```sql
   UPDATE profiles SET is_admin = FALSE, role = 'user' WHERE id = auth.uid();
   ```
   - [ ] Admin Panel entry should NOT appear in settings
   - [ ] Direct navigation to `/admin` should be blocked by RLS

3. **Test as Admin**:
   ```sql
   UPDATE profiles SET is_admin = TRUE, role = 'alsamos_admin' WHERE id = auth.uid();
   ```
   - [ ] Admin Panel entry appears under "Admin" group in settings
   - [ ] Entry has purple shieldCheck icon
   - [ ] Clicking navigates to `/admin` page
   - [ ] Can view all security events in database

4. **Test RLS Enforcement**:
   - Try to manually insert a security event as a regular user (should fail)
   - Try to view another user's security events as non-admin (should fail)
   - As admin, query all security events (should succeed)

## Logging Security Events

### Manual Logging (from backend/edge functions)

```typescript
// Example: Log 2FA enable event
await supabase
  .from('security_events')
  .insert({
    user_id: userId,
    event_type: 'two_factor_enable',
    description: '2FA yoqildi',
    ip_address: request.headers.get('x-forwarded-for'),
    user_agent: request.headers.get('user-agent'),
  });
```

### Automatic Logging

Password changes are automatically logged via database trigger.

## Troubleshooting

### Admin Panel Not Showing

**Issue**: Admin Panel entry doesn't appear in settings

**Solutions**:
1. Verify admin status:
   ```sql
   SELECT id, username, is_admin, role FROM profiles WHERE id = auth.uid();
   ```
2. Check provider is loading:
   - Open Flutter DevTools
   - Check `isAdminProvider` and `adminRoleStateProvider` values
3. Restart app after granting admin access
4. Clear app cache

### History Page Empty

**Issue**: History page shows no data

**Solutions**:
1. Check if tables have data:
   ```sql
   SELECT COUNT(*) FROM user_sessions WHERE user_id = auth.uid();
   SELECT COUNT(*) FROM security_events WHERE user_id = auth.uid();
   SELECT COUNT(*) FROM search_history WHERE user_id = auth.uid();
   ```
2. Generate test data:
   ```sql
   -- Insert test security event
   INSERT INTO security_events (user_id, event_type, description)
   VALUES (auth.uid(), 'password_change', 'Test parol o''zgarishi');
   ```
3. Check RLS policies are enabled
4. Verify user is authenticated

### RLS Errors

**Issue**: Getting "permission denied" errors

**Solutions**:
1. Verify RLS policies exist:
   ```sql
   SELECT * FROM pg_policies WHERE tablename = 'security_events';
   ```
2. Check if policies are enabled:
   ```sql
   SELECT * FROM pg_tables WHERE tablename = 'security_events';
   ```
3. Re-run migration if policies are missing
4. Check user authentication state

## Security Best Practices

1. **Never expose admin checks client-side only**: Always enforce with RLS
2. **Use service_role for inserting security events**: Prevents user tampering
3. **Audit admin actions**: Log when admins view sensitive data
4. **Regularly review admin list**: Remove admin access when no longer needed
5. **Use strong passwords for admin accounts**: Enable 2FA
6. **Monitor security_events table**: Set up alerts for suspicious activity

## Production Checklist

Before deploying to production:

- [ ] Run migration on production database
- [ ] Set up admin users (only trusted personnel)
- [ ] Test RLS policies thoroughly
- [ ] Set up monitoring for security_events table
- [ ] Configure alerts for critical security events
- [ ] Document admin access procedures
- [ ] Train admin users on responsible access
- [ ] Set up audit logs for admin actions
- [ ] Configure IP allowlisting for admin access (optional)
- [ ] Set up 2FA requirement for all admin accounts

## Future Enhancements

Potential improvements to consider:

1. **Granular Roles**: Add moderator, support, etc. with different permissions
2. **Admin Audit Log**: Separate table for admin actions
3. **IP Allowlisting**: Restrict admin access to specific IPs
4. **Session Management**: Force re-authentication for sensitive actions
5. **Activity Dashboard**: Real-time security event monitoring
6. **Automated Alerts**: Email/SMS for critical security events
7. **Export Functionality**: Download history as CSV/PDF
8. **Data Retention**: Auto-delete old history entries
9. **Advanced Filtering**: Date ranges, event types, search
10. **Anomaly Detection**: ML-based suspicious activity detection

## Support

For questions or issues:
- File a bug report in the project repository
- Contact the Alsamos development team
- Check Supabase documentation for RLS questions

