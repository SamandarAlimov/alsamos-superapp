# Schema Alignment - Action Required

## 🎯 Goal
Align Flutter app with the REAL Supabase schema to eliminate all 42703 "column does not exist" errors.

---

## ⚡ What You Must Do RIGHT NOW

### Step 1: Run Schema Introspection (5 minutes)

1. **Open Supabase Dashboard**  
   Go to: https://supabase.com/dashboard/project/mbhjganbihamoiqmankv

2. **Open SQL Editor**  
   Click: `SQL Editor` in left sidebar

3. **Create New Query**  
   Click: `New query`

4. **Copy & Paste**  
   Open file: `INTROSPECT_SCHEMA_NOW.sql`  
   Copy entire contents  
   Paste into SQL Editor

5. **Run Query**  
   Click: `Run` button (or press Ctrl+Enter)

6. **Wait for Results**  
   Query will execute 17 parts showing:
   - All tables and columns
   - Primary and foreign keys
   - Enums and custom types
   - Indexes and RLS policies
   - Functions/RPCs
   - Triggers and views
   - Storage buckets
   - And more...

7. **Copy ALL Output**  
   Scroll through results  
   Select ALL text output  
   Copy to clipboard

8. **Save Output**  
   Create new file: `SCHEMA_INTROSPECTION_OUTPUT.txt`  
   Paste all output  
   Save file

9. **Provide to Me**  
   Share the contents of `SCHEMA_INTROSPECTION_OUTPUT.txt` in chat

---

## 📋 What Happens Next (Automated)

Once you provide the schema output, I will:

1. **Parse the introspection** → Create `SUPABASE_SCHEMA_REFERENCE.md`
2. **Audit all Flutter queries** → Compare against real schema
3. **Generate mismatch report** → File:line → Problem
4. **Fix all mismatches**:
   - Correct wrong column names
   - Remove non-existent column selects
   - Add null-tolerance to models
   - Update foreign key references
5. **Identify missing features**:
   - Columns web has that Flutter doesn't use yet
   - RPCs that need to be called differently
   - Policies that affect queries
6. **Clean up migrations**:
   - Remove conflicting migrations
   - Add minimal migrations for truly new features
7. **Verify fixes**:
   - Run `flutter analyze`
   - Check all known 42703 error locations
   - Document remaining issues (if any)

---

## 🚨 Why This Is Critical

### Current State
- **Web app works** ✅ (TypeScript, same Supabase backend)
- **Flutter app crashes** ❌ (42703 errors everywhere)

### Root Cause
Flutter queries assume columns/tables that **differ from reality**:
- `user_settings.search_safe_mode` → Does this column exist?
- `posts.source_type, poll_data, tags, location...` → Do these exist?
- `conversation_participants.mute_until` → Does this exist?
- `products.title, description, price` → Are these the real names?

### The Fix
**Stop guessing. Introspect reality. Align Flutter.**

---

## 📁 Files Created

### Ready to Use
- ✅ `INTROSPECT_SCHEMA_NOW.sql` - Run this in Supabase SQL Editor NOW
- ✅ `FLUTTER_SCHEMA_AUDIT.md` - Documents all Flutter queries (for comparison)
- ✅ `SCHEMA_ALIGNMENT_INSTRUCTIONS.md` - This file (what to do)

### Will Be Created After You Provide Output
- ⏳ `SUPABASE_SCHEMA_REFERENCE.md` - The REAL schema (source of truth)
- ⏳ `SCHEMA_MISMATCH_REPORT.md` - All Flutter queries that don't match
- ⏳ `SCHEMA_FIX_PLAN.md` - Detailed fix strategy
- ⏳ Fixed Dart files - Corrected queries throughout codebase
- ⏳ `SCHEMA_ALIGNMENT_VERIFICATION.md` - Final status report

---

## ⏱️ Time Estimate

| Task | Time | Who |
|------|------|-----|
| Run introspection SQL | 5 min | **YOU** |
| Copy/save output | 2 min | **YOU** |
| Parse schema + audit | 10 min | **ME** |
| Fix all mismatches | 30 min | **ME** |
| Verify + test | 10 min | **ME** |
| **TOTAL** | **~1 hour** | |

---

## 🎬 What to Do Right Now

1. Open `INTROSPECT_SCHEMA_NOW.sql`
2. Copy contents
3. Go to Supabase SQL Editor
4. Paste and run
5. Copy all output
6. Save as `SCHEMA_INTROSPECTION_OUTPUT.txt`
7. Share with me

**Then I handle the rest.**

---

## 💡 Alternative: Direct Schema Access

If you can provide me with:
- Supabase project connection string (service role)
- Or: Run the SQL and give me output

I can work with either. The SQL script is comprehensive and captures everything needed.

---

**Status**: ⏸️ **BLOCKED** - Waiting for you to run `INTROSPECT_SCHEMA_NOW.sql` and provide output
