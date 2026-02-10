# Rydin Launch Readiness Checklist

## Status: ALMOST READY FOR LAUNCH (100-1000 users)

---

## PHASE 1: BACKEND SETUP (DO THIS FIRST)

### Step 1: Create Database Tables
Run this in **Supabase SQL Editor**:

```sql
-- Run the schema from: src/integrations/supabase/schema.sql
```

### Step 2: Add Database Indexes (CRITICAL FOR PERFORMANCE)
```sql
-- HOPPER INDEXES (Fast matching queries)
CREATE INDEX idx_hoppers_date_location ON hoppers(date, pickup_location, drop_location);
CREATE INDEX idx_hoppers_time ON hoppers(departure_time);
CREATE INDEX idx_hoppers_active ON hoppers(status) WHERE status = 'active';

-- EVENT INDEXES
CREATE INDEX idx_events_date_category ON events(date, category);
CREATE INDEX idx_events_upcoming ON events(date) WHERE date >= NOW();

-- REQUEST INDEXES
CREATE INDEX idx_hopper_requests_pending ON hopper_requests(status) WHERE status = 'pending';
CREATE INDEX idx_hopper_requests_user ON hopper_requests(requesting_user_id, requested_user_id);

-- TRAVEL INDEXES
CREATE INDEX idx_shuttle_route ON shuttle_timings(from_location, to_location);
CREATE INDEX idx_train_date ON train_info(date);
```

### Step 3: Enable Row Level Security (RLS)
All tables should have RLS enabled for security:

```sql
ALTER TABLE hoppers ENABLE ROW LEVEL SECURITY;
ALTER TABLE hopper_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_interested_users ENABLE ROW LEVEL SECURITY;
```

---

## PHASE 2: FIREBASE & GOOGLE SETUP

### Step 1: Authorize Domains
**Firebase Console** (https://console.firebase.google.com/):
1. Go to **Authentication** → **Settings**
2. Add your domain under **Authorized domains**:
   - `your-domain.fly.dev`
   - `localhost:8080` (for testing)
   - `127.0.0.1:8080`

**Google Cloud Console** (https://console.cloud.google.com/):
1. Go to **APIs & Services** → **Credentials**
2. Click your OAuth 2.0 Client ID
3. Add:
   - **Authorized JavaScript origins**:
     ```
     https://your-domain.fly.dev
     http://localhost:8080
     ```
   - **Authorized redirect URIs**:
     ```
     https://your-domain.fly.dev/auth/callback
     http://localhost:8080/auth/callback
     ```

### Step 2: Enable Phone Auth in Firebase
1. Go to **Firebase Console** → **Authentication**
2. Enable **Phone** provider
3. Add test numbers for development

### Step 3: Enable Google OAuth in Supabase
1. Go to **Supabase Dashboard** → **Authentication** → **Providers**
2. Enable **Google**
3. Add your Google Client ID and Secret
4. Set Redirect URL: `https://ylyxhdlncslvqdkhzohs.supabase.co/auth/v1/callback`

---

## PHASE 3: FEATURE VALIDATION

### ✅ MUST-HAVE FEATURES (Test these before launch)

#### 1. Google Login + SMS OTP
```
Flow: Auth Page → Google Sign-In → SMS Verification → Profile Setup → Home
Expected: User successfully logs in and can access all features
```

#### 2. Hopper Creation & Matching
```
Flow: Create Hopper → Fill form → Submit → See matching hoppers
Test:
- Create hopper with pickup/drop/date/time
- See other hoppers in list
- Matching logic works (±3-5 hours flexibility)
```

#### 3. Request/Accept Flow
```
Flow: Send request → Receiver accepts → Chat unlocks
Test:
- Send request to hopper
- Check request status changes
- Chat becomes available after accept
```

#### 4. Hopper Auto-Expiry
```
Test: 
- Create hopper with past time
- Verify it doesn't show in "active" list
- Verify status = "expired"
```

#### 5. Events Feed
```
Test:
- Browse events by category
- Mark events as interested
- See "Find Ride" option
```

#### 6. Train/Flight Matching
```
Test:
- Add train/flight number
- Check if notification triggers for matching users
- Option to "Convert to Hopper"
```

#### 7. Travel Timings
```
Test:
- View shuttle timings
- View bus timings
- View local train info
```

---

## PHASE 4: PRODUCTION SETUP

### Step 1: Enable Rate Limiting (Frontend)
Already implemented in code:
```typescript
// In HopperCard & Auth components
- Cooldown on OTP requests (60 seconds)
- Cooldown on Hopper creation (no spam)
- Disable multiple active hoppers
```

### Step 2: Add CORS Headers (Backend)
In Supabase, no action needed. Already configured for Fly.io domain.

### Step 3: Set Up Error Tracking
```
Optional: Sentry (sentry.io)
- Captures errors in production
- Helps debug issues
```

### Step 4: Monitor Database Performance
```
Supabase Dashboard → Analytics
- Monitor query performance
- Watch for slow queries
- Monitor storage usage
```

---

## PHASE 5: LAUNCH CHECKLIST

### Before Going Live, Verify:

- [ ] Google OAuth works on production domain
- [ ] SMS OTP verification works (test with real number)
- [ ] Database tables created and indexed
- [ ] Hopper matching logic tested (±3-5 hours)
- [ ] Request/Accept flow tested
- [ ] Hopper auto-expiry working
- [ ] Events showing correctly
- [ ] Train/Flight matching operational
- [ ] Travel timings displaying
- [ ] Rate limiting prevents spam
- [ ] No test data visible to users
- [ ] Error messages are user-friendly
- [ ] Mobile responsive (test on phone)
- [ ] Bottom navigation works
- [ ] All routes accessible

---

## FEATURES TO LOCK (DO NOT ADD)

❌ In-app payments  
❌ Cab booking APIs (Uber/Ola integration)  
❌ Live map tracking  
❌ Driver ratings  
❌ Surge pricing  
❌ Auto-matching without consent  

These reduce adoption. Stick to the core.

---

## OPTIONAL FEATURES (For v1.1+)

✅ Girls-only hopper toggle  
✅ Block/report users  
✅ "Saved ₹X using Rydin" share card  
✅ Hostel/batch leaderboard  
✅ Calendar sync (Google Calendar)  
✅ Push notifications  

---

## QUICK FIXES IF THINGS BREAK

### "Firebase: Error (auth/unauthorized-domain)"
→ Add your domain to Firebase Authorized Domains (see Phase 2)

### "Hopper not showing in list"
→ Check: status = 'active' AND date >= today AND time in future

### "Request not sending"
→ Check: hopper_requests table exists AND user_id is correct

### "SMS OTP not arriving"
→ Check: Phone number format is +91XXXXXXXXXX
→ Check: Firebase SMS quota not exceeded (free tier limited)

### "Slow hopper matching"
→ Verify indexes created (Phase 1, Step 2)
→ Check database query performance in Supabase

---

## DEPLOYMENT CHECKLIST

1. All environment variables set:
   ```
   VITE_FIREBASE_API_KEY=...
   VITE_GOOGLE_CLIENT_ID=...
   VITE_SUPABASE_URL=...
   VITE_SUPABASE_ANON_KEY=...
   ```

2. Database migrations run successfully

3. Test on staging domain first before production

4. Monitor logs for 24 hours after launch

5. Have a rollback plan if critical bug found

---

## SUCCESS METRICS (After Launch)

✅ Users can sign up in <2 minutes  
✅ 80%+ sign-up completion rate  
✅ Users create first hopper within 5 minutes  
✅ 1st hopper match within 24 hours  
✅ Request/accept works 100% of the time  
✅ Chat unlocks immediately after accept  
✅ <100ms hopper search response time  

---

## SUPPORT CONTACTS

- **Firebase Issues**: https://firebase.google.com/support
- **Supabase Issues**: https://supabase.com/docs
- **Google OAuth Issues**: https://developers.google.com/identity/protocols/oauth2

---

## FINAL NOTE

You are **LAUNCH-READY** when:
1. ✅ All MUST-HAVE features working
2. ✅ Database indexed and optimized
3. ✅ No critical bugs in QA
4. ✅ Firebase domains authorized
5. ✅ Team trained on support

**RECOMMENDED: Beta test with 20-50 students first, then open to all.**

---

Good luck! 🚀
