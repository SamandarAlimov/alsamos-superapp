# Social Map Features

Professional social GPS features inspired by Life360, Zenly, Snapchat Map, and Find My Friends.

## Features Overview

### 1. Check-ins
Snapchat-style location check-ins at places:
- ✅ Check-in at any place (restaurant, cafe, park, etc.)
- ✅ Add feeling/mood (happy, excited, hungry, tired)
- ✅ Write optional note about the place
- ✅ Visibility control (public, followers, friends, private)
- ✅ Photo attachments support
- ✅ Tag friends in check-ins
- ✅ View nearby check-ins
- ✅ Check-in history

**Database**: `check_ins` table with location index for spatial queries

**Use cases**:
- Share interesting places with friends
- Track visited locations
- Discover where friends hang out
- Social exploration of city

### 2. Place Reviews
Google Maps-style reviews with ratings:
- ✅ 5-star rating system
- ✅ Written review text
- ✅ Category ratings (food, service, ambiance, etc.)
- ✅ Photo uploads
- ✅ Visit date tracking
- ✅ Helpful votes system
- ✅ One review per user per place
- ✅ Sort by most helpful / most recent

**Database**: `place_reviews` + `review_helpful_votes` tables

**Features**:
- Users can upvote helpful reviews
- Helpful count auto-updates via database trigger
- Reviews tied to place_id (from OSM or custom)

**Use cases**:
- Help others discover quality places
- Share detailed experiences
- Community-driven local recommendations

### 3. Meet Here Invitations
Coordinate meetups at specific locations:
- ✅ Select place on map
- ✅ Set meeting time
- ✅ Add message/details
- ✅ Invite multiple friends
- ✅ Track responses (accepted/declined)
- ✅ Status tracking (pending/confirmed/cancelled/completed)
- ✅ Realtime notifications

**Database**: `meet_here_invitations` table

**Workflow**:
1. User selects location + time
2. Invites friends
3. Friends accept/decline
4. Creator sees who's coming
5. Everyone gets navigation to meeting point
6. Auto-complete when time passes

**Use cases**:
- Plan meetups with friends
- Coordinate family gatherings
- Set pickup/drop-off points
- Schedule work meetings

### 4. Family Circles
Life360-style family location sharing:
- ✅ Create named circles (My Family, Work Team, etc.)
- ✅ Invite members
- ✅ Admin roles
- ✅ Auto location sharing within circle
- ✅ See all members on map in real-time
- ✅ Member battery status
- ✅ Driving detection
- ✅ Circle-specific settings

**Database**: `family_circles` + `circle_invitations` tables

**Settings per circle**:
```json
{
  "auto_share_location": true,
  "show_battery": true,
  "show_driving_status": true
}
```

**Member management**:
- Creator has full control
- Admins can invite/remove members
- Members can leave anytime
- Invitation flow (pending → accepted/declined)

**Use cases**:
- Keep track of family members
- Coordinate with work colleagues
- Monitor elderly parents
- Teen safety monitoring

## Summary

Phase 5 delivers Life360 + Zenly + Snapchat Map level social features:
- ✅ Location-based check-ins with feelings and notes
- ✅ Place reviews with ratings and helpful votes
- ✅ Meet here invitations for coordinating meetups
- ✅ Family circles for real-time family tracking
- ✅ Member management and invitations
- ✅ Realtime subscriptions for live updates
- ✅ Comprehensive privacy and visibility controls
- ✅ Spatial queries for nearby discovery
- ✅ Professional UI with Uzbek localization

This positions Alsamos Maps as a complete social GPS platform, not just navigation.
