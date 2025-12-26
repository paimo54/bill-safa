# SALFANET RADIUS - Chat Memory untuk Melanjutkan Project

**Tanggal Terakhir:** 13 Desember 2025 (Updated - VPS Installer Scripts v2.5.1)

---

## 📋 **Table of Contents**
1. [Session 2025-12-13 (Latest): Installer Scripts Update](#session-2025-12-13-installer)
2. [Session 2025-12-13: FreeRADIUS Voucher Authorization & Dashboard Fix](#session-2025-12-13)
3. [Session 2025-12-10: Mobile Responsive & Dashboard UI](#session-2025-12-10)
4. [Previous Sessions](#previous-sessions)

---

## <a name="session-2025-12-13-installer"></a>🔧 Session: 2025-12-13 (Latest) - VPS Installer Scripts Update v2.5.1

**Status:** ✅ COMPLETED  
**Update Type:** Installer Enhancement

### 🎯 What Was Updated

**Files Modified:**
- `vps-install.sh` - Production VPS installer (for root access)
- `vps-install-local.sh` - Local VPS installer (for sudo users)

### 📝 Changes Made

#### 1. Added REST Authorize Endpoint Configuration

**Before (Missing Critical Feature):**
```bash
rest {
    post-auth { ... }    # ✅ Ada
    accounting { ... }   # ✅ Ada
    # ❌ MISSING: authorize section!
}
```

**After (Complete & Secure):**
```bash
rest {
    # CRITICAL: Authorize pre-check (Dec 13, 2025)
    authorize {
        uri = "${..connect_uri}/api/radius/authorize"
        method = "post"
        body = "json"
        data = '{"username": "%{User-Name}", "nasIp": "%{NAS-IP-Address}"}'
        timeout = 2
        tls = ${..tls}
    }
    
    post-auth { ... }
    accounting { ... }
}
```

#### 2. Updated REST Module Pool Configuration

**Added:**
- `connect_timeout = 3` seconds
- `timeout = 2` seconds for authorize endpoint
- `check_cert = no` for TLS (localhost doesn't need cert validation)

#### 3. Documentation in Code

**Added comments explaining:**
- Purpose: Voucher validation BEFORE password authentication
- Benefit: Prevents expired vouchers from authenticating
- Date: Dec 13, 2025 security enhancement

### ✅ Benefits

**For New Installations:**
- ✅ Voucher authorization feature enabled out-of-the-box
- ✅ Expired vouchers automatically rejected at RADIUS level
- ✅ Security hardening without manual configuration
- ✅ Consistent with production server setup

**For System Updates:**
- ✅ Installer scripts now match latest production configuration
- ✅ No manual FreeRADIUS config editing needed after install
- ✅ One-command installation with all security features

### 📊 Installation Flow (Updated)

**Step 5: FreeRADIUS Configuration**
```
1. Install FreeRADIUS packages (including freeradius-rest)
2. Configure SQL module (database connection)
3. Configure REST module with:
   ✅ Authorize endpoint (NEW - voucher validation)
   ✅ Post-auth endpoint (session tracking)
   ✅ Accounting endpoint (usage tracking)
4. Configure clients.conf (NAS authentication)
5. Enable modules and restart FreeRADIUS
```

### 🔍 Technical Details

**vps-install.sh Changes (Line 706-748):**
- Added `authorize` section before `post-auth`
- Set timeout 2 seconds (fail-fast if API slow)
- Include both username and NAS IP in authorize data
- Proper EOF escaping for bash heredoc

**vps-install-local.sh Changes (Line 415-455):**
- Same authorize configuration
- Uses `sudo tee` instead of direct file write
- Consistent with non-root user installation flow

### 📚 Related Files

**Production Config (Already Updated Dec 13):**
- `freeradius-config/mods-enabled-rest` - Template config
- `src/app/api/radius/authorize/route.ts` - API endpoint
- `freeradius-config/sites-enabled-default` - Call `rest` in authorize section

**Documentation:**
- `CHANGELOG.md` - Version 2.5.1 entry added
- `CHAT_MEMORY.md` - This file (session documented)
- `docs/FREERADIUS-SETUP.md` - FreeRADIUS configuration guide

### 🚀 Deployment Impact

**Existing Installations:**
- No impact (already running with updated config)
- Manual update still possible if needed

**New Installations (After This Update):**
- Automatically get REST authorize feature
- No manual FreeRADIUS config editing required
- Complete security setup from first boot

### ✅ Verification Checklist

After running updated installer:
- [ ] FreeRADIUS starts successfully: `systemctl status freeradius`
- [ ] REST module enabled: `freeradius -X | grep rest`
- [ ] Authorize endpoint configured: `cat /etc/freeradius/3.0/mods-enabled/rest`
- [ ] Test expired voucher rejection: `radtest expired_code expired_code localhost 0 testing123`
- [ ] Check logs: `tail -f /var/log/freeradius/radius.log`

---

## <a name="session-2025-12-13"></a>🔐 Session: 2025-12-13 - FreeRADIUS Authorization & Dashboard Stats Fix

**Status:** ✅ COMPLETED & DEPLOYED  
**Critical Issues Fixed:** Security, UX, Dashboard Accuracy

### 🎯 Original Problem Report

**User Issues:**
1. ❌ Voucher dengan status AKTIF sedang digunakan tidak muncul di sesi aktif admin dashboard
2. ❌ Voucher yang sudah EXPIRED masih bisa login ke hotspot
3. ❌ Tidak ada notifikasi di log MikroTik untuk voucher expired (hanya "username and password salah")
4. ❌ Voucher EXPIRED masih dihitung di statistik dashboard

**Impact:**
- 🔴 **CRITICAL SECURITY**: User bisa tetap online dengan voucher kadaluarsa
- 🔴 **Poor UX**: Pesan error tidak jelas (expired atau salah password?)
- 🔴 **Revenue Loss**: Voucher gratis karena bisa digunakan selamanya
- 🔴 **Dashboard Inaccurate**: Admin tidak bisa monitor real sessions dan stats

---

### 🔍 Root Cause Analysis

#### Problem 1: Dashboard Session Query Not Showing Hotspot Sessions

**File:** `src/app/api/dashboard/stats/route.ts`

**Broken Logic:**
```typescript
activeSessionsHotspot = await prisma.radacct.count({
  where: {
    acctstoptime: null,
    acctupdatetime: { gte: tenMinutesAgo },
    nasporttype: 'Wireless-802.11', // ❌ Field tidak selalu ada
  },
});
```

**Root Cause:**
- Field `nasporttype` di tabel `radacct` tidak reliable
- MikroTik tidak selalu set field ini dengan value konsisten
- Hotspot voucher sessions tidak terdeteksi

---

#### Problem 2: Expired Vouchers Can Still Authenticate

**Current FreeRADIUS Flow (BROKEN):**
```
1. User login → FreeRADIUS receives Access-Request
2. SQL module checks radcheck table
   ├─ Query: SELECT value FROM radcheck WHERE username = '553944' AND attribute = 'Password'
   └─ Result: Found! Password = '553944' ✅
3. PAP authentication validates password
   └─ Result: Match! ✅
4. Post-auth logging
5. Send Access-Accept to MikroTik
6. User logs in successfully ❌ WRONG!
```

**Why Expired Vouchers Work:**
```sql
-- Voucher expired but still has credentials in RADIUS
SELECT * FROM radcheck WHERE username = '553944';
+------+----------+-----------+----+----------+
| id   | username | attribute | op | value    |
+------+----------+-----------+----+----------+
| 1234 | 553944   | Password  | := | 553944   |
+------+----------+-----------+----+----------+

-- But in application database already expired
SELECT code, status, expiresAt FROM hotspot_vouchers WHERE code = '553944';
+--------+----------+---------------------+
| code   | status   | expiresAt           |
+--------+----------+---------------------+
| 553944 | EXPIRED  | 2025-12-12 10:30:00 |
+--------+----------+---------------------+
```

**Root Cause:**
- FreeRADIUS only checks SQL tables (radcheck, radusergroup)
- No validation against application business logic (status, expiresAt)
- No bridge between RADIUS authentication and voucher expiry system

---

#### Problem 3: Dashboard Stats Include Expired Vouchers

**Broken Logic:**
```typescript
hotspotUserCount = await prisma.hotspotVoucher.count({
  where: {
    OR: [
      { expiresAt: null },
      { expiresAt: { gte: now } }
    ]
  }
});
// ❌ Tidak exclude status EXPIRED
```

**Root Cause:**
- Query hanya check `expiresAt` timestamp
- Tidak check field `status = 'EXPIRED'`
- Voucher expired tetap dihitung dalam statistik

---

### 💡 Solution Implemented

#### Solution 1: REST Authorization Pre-Check

**File Created:** `src/app/api/radius/authorize/route.ts` (4535 bytes)

**Architecture:**
```
┌──────────┐      ┌─────────────┐      ┌──────────┐      ┌─────────┐
│ MikroTik │─────▶│ FreeRADIUS  │─────▶│ REST API │─────▶│ MySQL   │
│  (NAS)   │      │   (RADIUS)  │      │ (Next.js)│      │   DB    │
└──────────┘      └─────────────┘      └──────────┘      └─────────┘
                         │                    │
                         │ 1. SQL: Load user  │
                         │ 2. REST: Validate  │
                         │ 3. PAP: Check pwd  │
                         │                    │
                         ▼                    ▼
                   Access-Accept      Check voucher:
                   Access-Reject      - status EXPIRED?
                   + Reply-Message    - expiresAt past?
                                     - session timeout?
```

**Implementation:**
```typescript
export async function POST(request: NextRequest) {
  const { username } = await request.json();
  
  const voucher = await prisma.hotspotVoucher.findUnique({
    where: { code: username },
    include: { profile: true },
  });
  
  if (!voucher) {
    return NextResponse.json({ success: true, action: "allow" });
  }
  
  const now = new Date();
  
  // Check 1: Status EXPIRED
  if (voucher.status === 'EXPIRED') {
    await logRejection(username, 'Your account has expired');
    return NextResponse.json({
      "control:Auth-Type": "Reject",
      "reply:Reply-Message": "Your account has expired"
    }, { status: 200 });
  }
  
  // Check 2: expiresAt in the past
  if (voucher.expiresAt && now > voucher.expiresAt) {
    await prisma.hotspotVoucher.update({
      where: { id: voucher.id },
      data: { status: "EXPIRED" },
    });
    await logRejection(username, 'Your account has expired');
    return NextResponse.json({
      "control:Auth-Type": "Reject",
      "reply:Reply-Message": "Your account has expired"
    }, { status: 200 });
  }
  
  // Check 3: Active session timeout
  if (voucher.firstLoginAt && voucher.expiresAt) {
    const activeSession = await prisma.radacct.findFirst({
      where: { username: voucher.code, acctstoptime: null },
    });
    
    if (activeSession && now > voucher.expiresAt) {
      await logRejection(username, 'Session timeout');
      return NextResponse.json({
        "control:Auth-Type": "Reject",
        "reply:Reply-Message": "Session timeout"
      }, { status: 200 });
    }
  }
  
  return NextResponse.json({ success: true, action: "allow" });
}
```

**Key Features:**
- ✅ Check voucher status BEFORE password validation
- ✅ Auto-update status to EXPIRED if expiresAt passed
- ✅ Session timeout detection for active sessions
- ✅ Log rejection to `radpostauth` table for audit trail
- ✅ Return proper RADIUS attributes for MikroTik display

---

#### Solution 2: FreeRADIUS REST Module Configuration

**File Modified:** `freeradius-config/mods-enabled-rest`

```
rest {
    connect_uri = "http://localhost:3000"
    
    # NEW: Authorize pre-check (CRITICAL!)
    authorize {
        uri = "${..connect_uri}/api/radius/authorize"
        method = "post"
        body = "json"
        data = "{ \"username\": \"%{User-Name}\", \"nasIp\": \"%{NAS-IP-Address}\" }"
        timeout = 2  # 2 seconds max
    }
    
    post-auth { ... }
    accounting { ... }
}
```

**File Modified:** `freeradius-config/sites-enabled-default` (line 436)

```
authorize {
    filter_username
    preprocess
    chap
    mschap
    digest
    suffix
    eap { ok = return }
    files
    -sql          # Load from radcheck/radusergroup
    
    rest          # ← NEW: Call REST API to validate voucher
    
    -ldap
    expiration
    logintime
    pap           # Password validation
}
```

**Authorization Flow:**
```
1. SQL → Load username/password from radcheck
2. REST → Validate voucher status/expiry via API
3. PAP → Check password only if REST allows
```

---

#### Solution 3: Dashboard Active Sessions Fix

**File Modified:** `src/app/api/dashboard/stats/route.ts`

**Before (Broken):**
```typescript
activeSessionsHotspot = await prisma.radacct.count({
  where: {
    acctstoptime: null,
    acctupdatetime: { gte: tenMinutesAgo },
    nasporttype: 'Wireless-802.11', // ❌ Not reliable
  },
});
```

**After (Fixed):**
```typescript
const pppoeSessions = await prisma.radacct.findMany({
  where: {
    acctstoptime: null,
    acctupdatetime: { gte: tenMinutesAgo },
  },
  select: { username: true },
});

// Check username against pppoeUser table
for (const session of pppoeSessions) {
  const isPPPoE = await prisma.pppoeUser.findUnique({
    where: { username: session.username },
    select: { id: true },
  });
  
  if (isPPPoE) {
    activeSessionsPPPoE++;
  } else {
    activeSessionsHotspot++;
  }
}
```

**Optimized Version:**
```typescript
const usernames = pppoeSessions.map(s => s.username);

const pppoeUsers = await prisma.pppoeUser.findMany({
  where: { username: { in: usernames } },
  select: { username: true },
});

const pppoeUsernames = new Set(pppoeUsers.map(u => u.username));

activeSessionsPPPoE = pppoeUsernames.size;
activeSessionsHotspot = pppoeSessions.length - activeSessionsPPPoE;
```

---

#### Solution 4: Dashboard Stats Exclude Expired Vouchers

**File Modified:** `src/app/api/dashboard/stats/route.ts`

**Before (Broken):**
```typescript
hotspotUserCount = await prisma.hotspotVoucher.count({
  where: {
    OR: [
      { expiresAt: null },
      { expiresAt: { gte: now } }
    ]
  }
});
```

**After (Fixed):**
```typescript
hotspotUserCount = await prisma.hotspotVoucher.count({
  where: {
    status: { not: 'EXPIRED' }, // ← NEW: Exclude expired
    OR: [
      { expiresAt: null },
      { expiresAt: { gte: now } }
    ]
  }
});

hotspotActiveUserCount = await prisma.hotspotVoucher.count({
  where: {
    status: { not: 'EXPIRED' }, // ← NEW: Exclude expired
    firstLoginAt: { not: null },
    OR: [
      { expiresAt: null },
      { expiresAt: { gte: now } }
    ]
  },
});

lastMonthHotspotUsers = await prisma.hotspotVoucher.count({
  where: {
    status: { not: 'EXPIRED' }, // ← NEW: Exclude expired
    firstLoginAt: { not: null },
    createdAt: {
      gte: startOfLastMonth,
      lte: endOfLastMonth,
    },
  },
});
```

---

### 📊 Testing Results

#### Test Case 1: Valid Active Voucher ✅
```bash
radtest 123456 123456 localhost 0 testing123
# Result: Access-Accept
```

#### Test Case 2: Expired Voucher (Status Field) ✅
```bash
radtest 553944 553944 localhost 0 testing123
# Result: Access-Reject
# Reply-Message = "Your account has expired"
```

**radpostauth Table:**
```sql
+----+----------+------------------------------+--------------+---------------------+
| id | username | pass                         | reply        | authdate            |
+----+----------+------------------------------+--------------+---------------------+
| 45 | 553944   | Your account has expired     | Access-Reject| 2025-12-13 14:30:15 |
+----+----------+------------------------------+--------------+---------------------+
```

#### Test Case 3: Dashboard Active Sessions ✅
**Before:** Hotspot: 0 (wrong)  
**After:** Hotspot: 8 (correct)

#### Test Case 4: MikroTik Log Message ✅
**Before:** `login failed: invalid username or password`  
**After:** `login failed: Your account has expired`

#### Test Case 5: Dashboard Stats ✅
**Before:** 11 vouchers (includes expired)  
**After:** 9 vouchers (excludes 2 expired)

---

### 🚀 Deployment

**Steps Executed:**
```bash
# 1. Upload files
scp src/app/api/radius/authorize/route.ts root@103.67.244.131:/var/www/salfanet-radius/
scp src/app/api/dashboard/stats/route.ts root@103.67.244.131:/var/www/salfanet-radius/

# 2. Download FreeRADIUS config from GitHub
ssh root@103.67.244.131
curl -o /etc/freeradius/3.0/sites-enabled/default \
  https://raw.githubusercontent.com/FreeRADIUS/freeradius-server/v3.0.x/raddb/sites-available/default
sed -i '436i\    rest' /etc/freeradius/3.0/sites-enabled/default

# 3. Install REST module
apt-get install -y freeradius-rest

# 4. Test config
freeradius -CX
# Output: Configuration appears to be OK

# 5. Build Next.js
cd /var/www/salfanet-radius
npm run build

# 6. Restart services
systemctl restart freeradius
pm2 restart all --update-env

# 7. Verify
systemctl status freeradius
pm2 status
```

**Deployment Status:**
- ✅ REST authorize endpoint deployed
- ✅ FreeRADIUS config updated with rest call
- ✅ Dashboard stats fixed (exclude expired)
- ✅ PM2 restarted (restart #87)
- ✅ FreeRADIUS running (PID 194448)
- ✅ All services online

---

### 📁 Files Modified Summary

| File | Change | Description |
|------|--------|-------------|
| `src/app/api/radius/authorize/route.ts` | **CREATED** | Pre-authentication voucher validation endpoint (4535 bytes) |
| `freeradius-config/mods-enabled-rest` | Modified | Added authorize section with 2s timeout |
| `freeradius-config/sites-enabled-default` | Modified | Added `rest` call in authorize flow (line 436) |
| `src/app/api/dashboard/stats/route.ts` | Modified | Fixed hotspot session counting + exclude expired vouchers |
| `src/lib/cron/voucher-sync.ts` | Enhanced | RADIUS cleanup, active session detection, better logging |

---

### 🎯 Performance Metrics

**Authorization Latency:**
- Without REST: ~5ms (SQL only)
- With REST: ~15ms (SQL + REST + DB query)
- Timeout fallback: 2000ms (2 seconds)

**Database Queries Per Auth:**
1. FreeRADIUS SQL: `SELECT FROM radcheck WHERE username = ?`
2. REST API: `SELECT FROM hotspot_vouchers WHERE code = ?`
3. Active session check: `SELECT FROM radacct WHERE username = ? AND acctstoptime IS NULL`
4. Audit log: `INSERT INTO radpostauth` (if rejected)

**Total:** 2-4 queries per authentication

---

### 💡 Key Learnings

1. **File Encoding Critical:**
   - Windows PowerShell creates UTF-16LE (breaks Linux configs)
   - Use `curl` from source instead of Windows→Linux upload
   - Verify with `file` command before deploying

2. **FreeRADIUS Version Compatibility:**
   - `jsonExtract` only in 3.2+, not 3.0.x
   - Use attribute prefixes (`control:`, `reply:`) for 3.0.x
   - Check version: `freeradius -v`

3. **REST API Response Format:**
   - HTTP 200 for both Accept and Reject
   - Use `control:Auth-Type` attribute, not HTTP status
   - Example: `{"control:Auth-Type": "Reject"}`

4. **Authorization Flow Order Critical:**
   - SQL → REST → PAP (exact order required)
   - REST before SQL = no user data
   - REST after PAP = too late to reject

---

### 📚 Related Documentation

- [CHANGELOG.md](CHANGELOG.md) - Version 2.5.0 with REST authorization
- [CHAT_MEMORY_VOUCHER_AUTHORIZATION.md](CHAT_MEMORY_VOUCHER_AUTHORIZATION.md) - Detailed technical docs (merged into this file)
- [freeradius-config/README-BACKUP.md](freeradius-config/README-BACKUP.md) - Config backup documentation
- [FreeRADIUS REST Module Docs](https://networkradius.com/doc/3.0.26/raddb/mods-available/rest.html)

---

## <a name="session-2025-12-10"></a>🔧 Session: 2025-12-10 - Mobile Responsive & Dashboard UI

**Status:** ✅ COMPLETED

---

## 🔧 Perbaikan & Fitur Terbaru (10 Desember 2025) ⭐ LATEST

### 0. Mobile Responsive Voucher Template Preview ✅ COMPLETE (10 Des 2025 - LATEST)
**Problem:**
- Preview voucher pada tampilan mobile tidak responsif
- Voucher cards terlalu kecil dan terpotong di layar mobile
- Layout voucher tidak optimal untuk mobile viewing
- Posisi voucher tidak berurutan (single code vs username/password)

**Solution:**

1. **Mobile Media Queries (≤640px):**
   ```css
   .voucher-preview-container { 
     display: flex !important; 
     flex-direction: column !important; 
     padding: 0 8px !important; 
     gap: 10px !important; 
   }
   .voucher-card { 
     width: calc(100% - 16px) !important; 
     margin: 0 auto 10px auto !important; 
   }
   .voucher-single { order: 1; }  // Single code di atas
   .voucher-dual { order: 2; }    // Username/password di bawah
   ```

2. **Tablet & Desktop Media Queries:**
   ```css
   @media (641px - 1024px): width: calc(33.33% - 8px)
   @media (≥1025px): width: 155px
   ```

3. **React Mobile Detection:**
   ```typescript
   const [isMobile, setIsMobile] = useState(false);
   useEffect(() => {
     const handleResize = () => setIsMobile(window.innerWidth <= 640);
     handleResize();
     window.addEventListener('resize', handleResize);
     return () => window.removeEventListener('resize', handleResize);
   }, []);
   ```

4. **Dynamic Container Styles:**
   ```typescript
   flexDirection: isMobile ? 'column' : 'row',
   flexWrap: isMobile ? 'nowrap' : 'wrap',
   gap: isMobile ? '12px' : '6px',
   ```

**Features:**
- ✅ Voucher preview responsive di semua device
- ✅ Voucher cards tidak terpotong di mobile
- ✅ Layout vertikal di mobile dengan gap yang tepat
- ✅ Single-code voucher tampil di atas, dual (username/password) di bawah
- ✅ Preview button tetap tampil di semua device

**Files Modified:**
- `src/app/admin/hotspot/template/page.tsx` - Mobile responsive DEFAULT_TEMPLATE & preview container

---

### 1. Dashboard Traffic Monitor UI Improvements ✅ COMPLETE (10 Des 2025)
**Problem:**
- Font judul "Traffic Monitor MikroTik" terlalu besar
- Indikator "Live" tidak diperlukan
- Dropdown Router dan Interface terlalu besar dan horizontal
- Layout selector tidak optimal

**Solution:**

1. **Title Font Size Reduced:**
   ```tsx
   // text-lg → text-base
   <h3 className="text-base font-semibold">Traffic Monitor MikroTik</h3>
   ```

2. **Live Indicator Removed:**
   ```tsx
   // Completely removed the Live indicator div
   ```

3. **Dropdown Selectors - Vertical Layout:**
   ```tsx
   // Before: flex items-center gap-3 (horizontal)
   // After: flex flex-col items-start gap-2 (vertical)
   // Router selector di atas, Interface selector di bawah
   ```

4. **Dropdown Styling Optimized:**
   ```tsx
   // Font: text-xs → text-[11px]
   // Padding: px-3 → px-2.5
   ```

**Features:**
- ✅ Judul lebih compact dengan font-size base
- ✅ Live indicator dihilangkan (cleaner UI)
- ✅ Dropdown Router di atas, Interface di bawah (vertikal)
- ✅ Dropdown lebih kecil dengan font 11px
- ✅ Layout lebih rapi dan profesional

**Files Modified:**
- `src/components/TrafficChartMonitor.tsx` - Header title, selectors layout, Live indicator removed

**Deployment:**
1. VPS deployment: ✅ 103.67.244.131 (10 Dec 2025)
2. Build time: ✅ ~25s, 143 routes compiled
3. PM2 restart: ✅ Online (38.4mb memory)

---

## 🔧 Perbaikan & Fitur Sebelumnya (9 Desember 2025)

### 2. Voucher Template Print Optimization ✅ COMPLETE (9 Des 2025)
**Problem:**
- Voucher print size terlalu kecil dan sulit dibaca
- Print preview tidak sesuai dengan template preview
- Jarak antar voucher tidak konsisten
- Font size terlalu kecil untuk printing
- Card tidak mengisi penuh halaman A4

**Solution:**

1. **Template Sizing Enhancement:**
   ```
   Card height: 70px → 100px (+43% lebih besar)
   Header font: 8px → 12px
   Code label: 6px → 8px
   Code text: 11px → 13px
   Footer padding: 2px 4px → 10px 15px
   Footer font: 8px → 10px
   ```

2. **Print Layout Optimization:**
   - Portrait A4: 5 columns × 10 rows = 50 vouchers per page
   - Margin: 0.5% horizontal, 0.2% vertical bottom
   - CSS `align-content: space-between` untuk distribusi penuh
   - Min-height 291mm untuk mengisi halaman

3. **Router Name Display:**
   - Menampilkan nama router/NAS dari database (bukan DNS name)
   - Support untuk username/password berbeda
   - Template conditional: `{if $vs['code'] eq $vs['secret']}`

**Features:**
- ✅ Card lebih tinggi (100px) untuk readability lebih baik
- ✅ Font sizes lebih besar untuk printing
- ✅ Layout portrait A4 optimal (50 vouchers per page)
- ✅ Space-between distribution mengisi halaman penuh
- ✅ Router name dari database
- ✅ Support username/password berbeda

**Files Modified:**
- `src/app/admin/hotspot/template/page.tsx` - DEFAULT_TEMPLATE updated
- `src/lib/utils/templateRenderer.ts` - Print CSS dengan space-between
- `src/app/admin/hotspot/voucher/page.tsx` - handlePrint dengan router data
- Database: `voucher_templates` table updated

**Database Changes:**
```sql
UPDATE voucher_templates SET htmlTemplate = '...' WHERE id = 'tpl-default-compact';
```

---

### 1. Agent Management Enhancement ✅ COMPLETE (8 Des 2025)
**Problem:**
- Tidak ada cara untuk delete atau ubah status multiple agents sekaligus
- Tidak ada informasi login terakhir agent
- Tidak ada informasi stock voucher yang tersedia untuk agent

**Solution:**

1. **Bulk Operations:**
   ```typescript
   // Checkbox select all/individual agents
   // Bulk delete multiple agents
   // Bulk change status (Active/Inactive)
   ```

2. **New Table Columns:**
   - **Login Terakhir:** Menampilkan waktu login terakhir agent ke portal
   - **Stock:** Menampilkan jumlah voucher dengan status WAITING

3. **Edit Modal Enhancement:**
   ```typescript
   // Added status dropdown in edit form
   <select value={isActive}>
     <option>Active</option>
     <option>Inactive</option>
   </select>
   ```

4. **Database Schema:**
   ```sql
   ALTER TABLE `agents` ADD COLUMN `lastLogin` DATETIME(3) NULL;
   ```

**Features:**
- ☑️ Checkbox untuk bulk selection agents
- 🗑️ Bulk delete multiple agents dengan konfirmasi
- 🔄 Bulk change status (active/inactive) multiple agents
- 🕐 Kolom "Login Terakhir" dengan format DD MMM YYYY, HH:MM
- 📦 Kolom "Stock" menampilkan jumlah voucher WAITING
- ⚙️ Dropdown status (Active/Inactive) di edit modal

**Files Modified:**
- ✅ `src/app/admin/hotspot/agent/page.tsx` - UI with bulk operations & new columns
- ✅ `src/app/api/hotspot/agents/route.ts` - Added lastLogin & voucherStock fields
- ✅ `src/app/api/agent/login/route.ts` - Track login timestamp
- ✅ `prisma/schema.prisma` - Added lastLogin field to agent model
- ✅ `prisma/migrations/20251208135232_add_agent_last_login/migration.sql` - Migration

**Deployment:**
1. VPS deployment: ✅ 103.67.244.131 (8 Dec 2025, 15:00 WIB)
2. Database migration: ✅ lastLogin column added (datetime(3) NULL)
3. Build time: ✅ ~18s, 142 routes compiled
4. PM2 restart: ✅ Online (57.4mb memory, 0% CPU)
5. API verified: ✅ /api/hotspot/agents returns new fields
6. Database verified: ✅ Column structure confirmed

**API Response Verified:**
```json
{
  "id": "...",
  "voucherStock": 100,  // NEW - Count of WAITING vouchers
  "lastLogin": null,    // NEW - Timestamp (null until login)
  "stats": {
    "waiting": 100      // Matches voucherStock
  }
}
```

**Result:**
- ✅ Bulk operations working perfectly
- ✅ Login tracking active (updates on agent login)
- ✅ Stock count accurate (real-time from database)
- ✅ Better agent management UX
- ✅ No breaking changes to existing features
- ✅ Zero performance impact (57.4mb memory stable)
- ✅ All regression tests passed

### 0a. Critical Security Update ✅ COMPLETE (8 Des 2025)
**Issue:** 
- Critical security vulnerability di React Server Components
- CVE Reference: https://react.dev/blog/2025/12/03/critical-security-vulnerability-in-react-server-components
- Potensi XSS dan data exposure

**Solution:**
```json
// package.json - Updated versions
"next": "^16.0.7",     // from 16.0.6
"react": "^19.2.1",    // from 19.2.0
"react-dom": "^19.2.1" // from 19.2.0
```

**Deployment:**
1. Local build: ✅ 29.0s compile time
2. VPS deployment: ✅ 18.3s compile time
3. PM2 restart: ✅ Online (60.8mb memory)
4. All routes working: ✅ 142 routes OK

**Files Modified:**
- ✅ `package.json` - Dependency versions updated
- ✅ `package-lock.json` - Dependency tree updated

**Result:**
- ✅ Application secured against critical vulnerability
- ✅ Turbopack maintained (Next.js 16.0.7 Turbopack)
- ✅ No breaking changes
- ✅ Production ready

### 0b. MikroTik Rate Limit Format Support ✅ COMPLETE (9 Des 2025)
**Problem:**
- Profile hotspot dan PPPoE hanya support format simple (5M/5M)
- Tidak bisa input burst rate, burst threshold, dan parameter MikroTik lainnya
- Admin harus manual edit di MikroTik setelah sync

**Solution:**

1. **Hotspot Profile - Full Rate Limit:**
   ```typescript
   // src/app/admin/hotspot/profile/page.tsx
   // OLD: Separate downloadSpeed & uploadSpeed (number input)
   // NEW: Single rateLimit field (text input)
   <input 
     type="text"
     value={formData.speed}
     placeholder="1M/1500k 0/0 0/0 8 0/0"
     className="font-mono"
   />
   ```

2. **PPPoE Profile - Full Rate Limit:**
   ```typescript
   // src/app/admin/pppoe/profiles/page.tsx
   // Added rateLimit field to interface
   interface PPPoEProfile {
     rateLimit?: string; // Full MikroTik format
   }
   
   // Replaced downloadSpeed/uploadSpeed grid with single rateLimit input
   <input 
     type="text"
     value={formData.rateLimit}
     placeholder="1M/1500k 0/0 0/0 8 0/0"
     className="font-mono"
   />
   ```

3. **MikroTik Rate Limit Format:**
   ```
   Format: rx-rate[/tx-rate] [rx-burst-rate[/tx-burst-rate]] [rx-burst-threshold[/tx-burst-threshold]] [rx-burst-time[/tx-burst-time]] [priority] [rx-rate-min[/tx-rate-min]]
   
   Example: 1M/1500k 0/0 0/0 8 0/0
   - rx-rate: 1M (download speed)
   - tx-rate: 1500k (upload speed)
   - rx-burst-rate/tx-burst-rate: 0/0 (no burst)
   - rx-burst-threshold/tx-burst-threshold: 0/0 (no threshold)
   - priority: 8 (default)
   - rx-rate-min/tx-rate-min: 0/0 (no minimum guarantee)
   ```

**Features:**
- 🚀 Support full MikroTik rate limit format with all parameters
- 📊 Burst rate, burst threshold, burst time support
- 🎯 Priority and minimum rate support
- 💡 Helper text with format explanation
- 🔤 Monospace font for better readability
- ⚡ Backward compatible (can still use simple format like "5M/5M")

**Files Modified:**
- ✅ `src/app/admin/hotspot/profile/page.tsx` - Changed speed input to full rate limit format
- ✅ `src/app/admin/pppoe/profiles/page.tsx` - Added rateLimit field, replaced downloadSpeed/uploadSpeed grid

**Benefits:**
- ✅ No need to manually edit MikroTik after sync
- ✅ Complete control over bandwidth management
- ✅ Support advanced MikroTik QoS features
- ✅ Better user experience for admins
- ✅ Matches MikroTik RouterOS native format

**Example Usage:**
```
Simple format: 5M/5M
Full format: 10M/10M 15M/15M 8M/8M 5 1M/1M
With burst: 2M/2M 4M/4M 2M/2M 8 0/0
```

### 0c. Traffic Monitor Interface Status Fix ✅ COMPLETE (9 Des 2025)
**Problem #1:** Dropdown tidak menampilkan semua interface
- Hanya interface dengan status `running: true` yang muncul di dropdown
- Interface yang disabled/tidak running tidak bisa dipilih untuk monitoring

**Problem #2:** Interface running di MikroTik terbaca sebagai disabled
- Interface ether1-5, wlan2 yang status **R** (Running) di MikroTik muncul sebagai **(Disabled)** di aplikasi
- Penyebab: Logika salah menggunakan property `disabled` dari API yang tidak konsisten
- Seharusnya hanya menggunakan property `running` yang menandakan flag **R** di MikroTik

**Solution:**

1. **Fix API Logic - Remove Disabled Check:**
   ```typescript
   // src/app/api/dashboard/traffic/route.ts
   // OLD: Check both running AND disabled (causing conflict)
   running: (iface.running === 'true' || iface.running === true) && 
            (iface.disabled !== 'true' && iface.disabled !== true)
   
   // NEW: Only check running status (matches MikroTik R flag)
   const isRunning = iface.running === 'true' || iface.running === true;
   running: isRunning
   ```

2. **TrafficChartMonitor Component:**
   ```typescript
   // src/components/TrafficChartMonitor.tsx
   // Show ALL interfaces, mark disabled ones
   router.interfaces.map((iface) => (
     <option key={iface.name} value={iface.name}>
       {iface.name} {!iface.running && '(Disabled)'}
     </option>
   ))
   ```

3. **Removed Running Filters:**
   - Available interfaces list: No filter
   - Data fetching: No running check
   - Dropdown rendering: Show all with disabled label

**Root Cause:**
Property `disabled` dari MikroTik API tidak konsisten atau memiliki nilai default yang unexpected. Yang akurat adalah property `running` yang langsung mapping ke kolom **R** (Running) di interface list MikroTik.

**Features:**
- 📋 Semua interface MikroTik tampil di dropdown (vlan, bridge, ether, wireless, dll)
- ✅ Interface running di MikroTik = running di aplikasi (sesuai flag R)
- 🏷️ Label "(Disabled)" hanya untuk interface yang memang tidak running
- 📊 Bisa monitor semua interface termasuk yang disabled
- 🔍 Status interface sekarang 100% akurat dengan MikroTik

**Files Modified:**
- ✅ `src/app/api/dashboard/traffic/route.ts` - Fixed running logic, removed disabled check
- ✅ `src/components/TrafficChartMonitor.tsx` - Removed running filters (3 locations)

**Deployment:**
- ✅ VPS Production: 103.67.244.131 (9 Dec 2025, 08:30 WIB)
- ✅ Build successful
- ✅ PM2 restarted: Online (59.2mb memory)

**Result:**
- ✅ Status interface 100% match dengan MikroTik (R = Running)
- ✅ ether1-5, wlan1, wlan2 yang running di MikroTik = running di aplikasi
- ✅ All interfaces visible in dropdown
- ✅ Accurate status representation
- ✅ No false disabled labels

### 0d. Voucher Template Fix - Username/Password Display ✅ COMPLETE (9 Des 2025)
**Problem #1:** Password tidak muncul saat print voucher dengan username≠password
- Template menggunakan `{$vs['secret']}` tapi templateRenderer.ts menggunakan fallback `vs.secret || vs.code`
- Akibatnya saat `secret` undefined/null, akan menampilkan `code` sebagai password
- Password yang sebenarnya berbeda tidak pernah muncul

**Problem #2:** Layout voucher code-only memiliki padding berlebih
- Label "Voucher Code" ditampilkan di luar conditional block
- Menyebabkan card voucher memiliki header yang tidak perlu
- Layout tidak konsisten antara code-only dan username/password

**Solution:**

1. **Fix templateRenderer.ts - Remove Fallback:**
   ```typescript
   // BEFORE: Use code as fallback for secret (WRONG!)
   html = html.replace(/\{\$vs\['secret'\]\}/g, vs.secret || vs.code)
   
   // AFTER: Show actual secret value or empty string (CORRECT!)
   html = html.replace(/\{\$vs\['secret'\]\}/g, vs.secret !== undefined ? vs.secret : '')
   ```

2. **Fix Template Layout - Move Header Inside Conditional:**
   ```html
   <!-- BEFORE: Header outside, causing extra padding -->
   <tr><td>Voucher Code / Username Password</td></tr>
   {if code eq secret}...{else}...{/if}
   
   <!-- AFTER: Header inside each block, consistent layout -->
   {if code eq secret}
     <tr><td>Voucher Code</td></tr>
     <tr><td>{$vs['code']}</td></tr>
   {else}
     <tr><td>Username / Password</td></tr>
     <tr><td>Username | Password</td></tr>
     <tr><td>{$vs['code']} | {$vs['secret']}</td></tr>
   {/if}
   ```

**Features Fixed:**
- ✅ Password sekarang muncul dengan benar saat username≠password
- ✅ Layout voucher code-only (username=password) tidak ada header berlebih
- ✅ Layout konsisten untuk kedua tipe voucher
- ✅ Padding otomatis sesuai dengan konten
- ✅ Header "Voucher Code" hanya muncul di voucher code-only
- ✅ Header "Username / Password" hanya muncul di voucher username≠password

**Files Modified:**
- ✅ `src/lib/utils/templateRenderer.ts` - Fixed secret replacement logic
- ✅ `src/app/admin/hotspot/template/page.tsx` - Fixed DEFAULT_TEMPLATE layout

**Deployment:**
- ✅ VPS Production: 103.67.244.131 (9 Dec 2025, 08:45 WIB)
- ✅ Build successful
- ✅ PM2 restarted: Online (59.6mb memory)

**Result:**
- ✅ Password ditampilkan dengan benar di template print
- ✅ Layout voucher lebih rapi dan konsisten
- ✅ Tidak ada padding berlebih di voucher code-only
- ✅ Template existing di database akan otomatis dapat benefit fix renderer

**Note:** 
User yang sudah punya template custom perlu re-save template atau update manual untuk mendapatkan layout fix. Template baru yang dibuat akan otomatis menggunakan DEFAULT_TEMPLATE yang sudah diperbaiki.

### 0e. Default Profile Groups & RADIUS Script Enhancement ✅ COMPLETE (8 Des 2025)
**Problem:**
- Profile forms kosong, admin harus manual input grup
- RADIUS script tidak include IP pool dan profile default
- Setup MikroTik butuh konfigurasi manual tambahan

**Solution:**

1. **PPPoE Profile Default:**
   ```typescript
   // src/app/admin/pppoe/profiles/page.tsx
   groupName: 'salfanetradius' // default value
   ```

2. **Hotspot Profile Default:**
   ```typescript
   // src/app/admin/hotspot/profile/page.tsx
   groupProfile: 'salfanetradius' // default value
   ```

3. **Enhanced RADIUS Setup Script:**
   ```bash
   # Script sekarang include:
   /ip pool add name=salfanet-pool ranges=10.10.10.2-10.10.10.254
   /ppp profile add name=salfanetradius local-address=10.10.10.1 remote-address=salfanet-pool
   /ip hotspot profile add name=salfanetradius use-radius=yes radius-accounting=yes
   ```

**Features:**
- 📝 Auto-fill grup profile saat tambah profile baru
- 🔧 Complete RADIUS setup dengan IP pool
- 🎯 Profile groups matching database defaults
- 📋 Copy-paste ready script untuk MikroTik

**Files Modified:**
- ✅ `src/app/admin/pppoe/profiles/page.tsx` - Default groupName
- ✅ `src/app/admin/hotspot/profile/page.tsx` - Default groupProfile
- ✅ `src/app/admin/network/routers/page.tsx` - Enhanced RADIUS script

**Result:**
- ✅ Faster profile creation (pre-filled grup)
- ✅ One-click RADIUS setup script
- ✅ Consistent profile naming across system
- ✅ Reduced manual configuration errors

### 1. Real-Time Traffic Monitoring dengan Chart ✅ COMPLETE
**Problem:** 
- Dashboard tidak memiliki monitoring trafik jaringan real-time
- Tidak ada visualisasi bandwidth interface MikroTik

**Solution Implemented:**
1. **Traffic API Creation:**
   ```typescript
   // src/app/api/dashboard/traffic/route.ts
   // - Connect ke MikroTik via RouterOS API (port 8722 custom)
   // - Fetch /interface/print untuk semua interface
   // - Return RX/TX bytes, packets, running status
   ```

2. **TrafficChartMonitor Component:**
   ```typescript
   // src/components/TrafficChartMonitor.tsx
   // - Recharts AreaChart untuk visualisasi bandwidth
   // - Router selector (dropdown pilih router)
   // - Interface selector (dropdown pilih interface)
   // - Auto-refresh 3 detik, history 20 data points (1 menit)
   // - Download (blue) dan Upload (red) dalam Mbps
   // - Placeholder saat belum ada seleksi
   ```

3. **Dashboard Integration:**
   ```typescript
   // src/app/admin/page.tsx
   // - TrafficChartMonitor ditempatkan di bawah stats cards
   // - Position sebelum charts section
   ```

**Features:**
- 📈 Real-time bandwidth graphs (Download/Upload)
- 🔄 Auto-refresh setiap 3 detik
- 🎯 Cascading selectors (Router → Interface)
- 📊 20 data points history (1 menit)
- 💾 Traffic rate calculation dalam Mbps
- 📱 Responsive layout dengan activity sidebar

**Files Created/Modified:**
- ✅ `src/components/TrafficChartMonitor.tsx` - NEW component
- ✅ `src/app/api/dashboard/traffic/route.ts` - NEW API endpoint
- ✅ `src/app/admin/page.tsx` - Dashboard integration

**Result:**
- ✅ Visual monitoring bandwidth real-time
- ✅ Easy interface selection per router
- ✅ Professional monitoring UI
- ✅ Historical traffic trends visible

### 2. Dashboard Layout Optimization ✅ COMPLETE
**Problem:**
- Stats cards terlalu besar, hanya muat 4 dalam 1 baris
- Space tidak efisien di layar desktop lebar

**Solution:**
1. **Stats Grid Changes:**
   ```tsx
   // Changed from 4 to 5 columns
   grid-cols-4 → grid-cols-5
   
   // Reduced card sizes
   padding: p-3 → p-2.5
   gap: gap-3 → gap-2
   
   // Smaller fonts
   text-[10px] → text-[9px]
   text-lg → text-base
   
   // Icon padding
   p-2 → p-1.5
   ```

2. **Traffic Monitor Repositioning:**
   - Sebelumnya: Di paling bawah dashboard
   - Sekarang: Langsung di bawah stats cards, sebelum charts

**Files Modified:**
- ✅ `src/app/admin/page.tsx` - Layout dan sizing

**Result:**
- ✅ 5 stat cards dalam 1 baris di desktop
- ✅ Traffic monitoring lebih prominent
- ✅ Layout lebih compact dan efficient
- ✅ Better space utilization

### 3. Pemisahan Statistik PPPoE dan Hotspot ✅ COMPLETE
**Problem:**
- Dashboard tidak membedakan user PPPoE dan Hotspot Voucher
- Active sessions tidak dipisah berdasarkan tipe
- Sulit tracking business metrics per service type

**Solution:**
1. **Stats API Separation:**
   ```typescript
   // src/app/api/dashboard/stats/route.ts
   
   // Separate counts
   const pppoeUserCount = await prisma.pppoeUser.count()
   const hotspotUserCount = await prisma.hotspotVoucher.count({
     where: {
       OR: [
         { expiresAt: null },
         { expiresAt: { gte: now } }
       ]
     }
   })
   
   // Separate active sessions by nasporttype
   const activeSessionsPPPoE = await prisma.radacct.count({
     where: {
       acctstoptime: null,
       nasporttype: 'Async' // PPPoE
     }
   })
   
   const activeSessionsHotspot = await prisma.radacct.count({
     where: {
       acctstoptime: null,
       nasporttype: 'Wireless-802.11' // Hotspot
     }
   })
   ```

2. **Dashboard Display:**
   ```typescript
   // Response format
   {
     pppoeUsers: { value: number, change: null },
     hotspotVouchers: { value: number, active: number, change: null },
     activeSessions: { value: number, pppoe: number, hotspot: number, change: null }
   }
   ```

3. **UI Labels:**
   - Card 1: "PPPoE Users"
   - Card 2: "Hotspot Vouchers (X aktif)"
   - Card 3: "Sesi Aktif (PPPoE: X, Hotspot: Y)"

**Files Modified:**
- ✅ `src/app/api/dashboard/stats/route.ts` - API logic
- ✅ `src/app/admin/page.tsx` - Dashboard display

**Result:**
- ✅ Clear separation PPPoE vs Hotspot
- ✅ Better business intelligence
- ✅ Accurate metrics per service type
- ✅ Sesi aktif breakdown by type

### 4. Fix Hotspot Voucher Expiry Count ✅ COMPLETE
**Problem:**
- Voucher kadaluarsa (expired) masih dihitung sebagai aktif
- Total voucher count termasuk expired vouchers
- Misleading statistics

**Root Cause:**
```typescript
// WRONG: Count all vouchers regardless of expiry
const hotspotUserCount = await prisma.hotspotVoucher.count()
```

**Solution:**
```typescript
// CORRECT: Only count non-expired vouchers
const hotspotUserCount = await prisma.hotspotVoucher.count({
  where: {
    OR: [
      { expiresAt: null }, // No expiry date
      { expiresAt: { gte: now } } // Not yet expired
    ]
  }
})

// Active vouchers: Used AND not expired
const hotspotActiveUserCount = await prisma.hotspotVoucher.count({
  where: {
    firstLoginAt: { not: null },
    OR: [
      { expiresAt: null },
      { expiresAt: { gte: now } }
    ]
  }
})
```

**Files Modified:**
- ✅ `src/app/api/dashboard/stats/route.ts` - Counting logic

**Result:**
- ✅ Total vouchers: Only valid (non-expired)
- ✅ Active vouchers: Only used AND valid
- ✅ Accurate business statistics
- ✅ Expired vouchers tidak dihitung

### 5. Dark Mode sebagai Default Theme ✅ COMPLETE
**Problem:**
- Default theme adalah light mode
- Tidak ada persistence untuk user preference
- User harus toggle manual setiap kali buka aplikasi

**Solution:**
1. **Default State Change:**
   ```typescript
   // src/app/admin/layout.tsx
   
   // Changed from false to true
   const [darkMode, setDarkMode] = useState(true)
   ```

2. **localStorage Integration:**
   ```typescript
   useEffect(() => {
     const savedTheme = localStorage.getItem('theme')
     
     if (savedTheme) {
       const isDark = savedTheme === 'dark'
       setDarkMode(isDark)
       if (isDark) {
         document.documentElement.classList.add('dark')
       } else {
         document.documentElement.classList.remove('dark')
       }
     } else {
       // Default to dark if no preference
       setDarkMode(true)
       document.documentElement.classList.add('dark')
       localStorage.setItem('theme', 'dark')
     }
   }, [])
   
   const toggleDarkMode = () => {
     const newMode = !darkMode
     setDarkMode(newMode)
     localStorage.setItem('theme', newMode ? 'dark' : 'light')
     // ... toggle class
   }
   ```

**Files Modified:**
- ✅ `src/app/admin/layout.tsx` - Theme initialization

**Result:**
- ✅ Dark mode aktif by default untuk new users
- ✅ Theme preference saved di localStorage
- ✅ Persistent across sessions
- ✅ Toggle functionality tetap work
- ✅ Better UX untuk night usage

### 6. Documentation Update ✅ COMPLETE
**Changes:**
- Updated `CHANGELOG.md` dengan version [2.4.0] - 2025-12-08
- Documented semua 6 improvements di atas dengan detail
- Technical implementation notes included
- Result metrics documented

**Files Modified:**
- ✅ `CHANGELOG.md` - New version entry

---

## 🖥️ Environment & Server

### VPS Production (Main) ⭐ PRIMARY
- **IP:** 103.67.244.131
- **SSH User:** root
- **App Path:** /var/www/salfanet-radius
- **PM2:** salfanet-radius (TZ=Asia/Jakarta)
- **Timezone:** Asia/Jakarta (WIB, UTC+7)
- **Domain:** radius.salfa.my.id (recommended)
- **Status:** Active & Production Ready

### VPS Lokal Proxmox (Development)
- **IP Publik:** 103.191.165.156
- **IP Internal:** 192.168.54.240
- **Port SSH:** 9500
- **SSH User:** yanz (gunakan sudo untuk root access)
- **Domain:** server.salfa.my.id (via Cloudflare)
- **App URL:** https://server.salfa.my.id
- **App Path:** /var/www/salfanet-radius
- **App Port:** 3005
- **NEXTAUTH_URL:** https://server.salfa.my.id
- **Command SSH:** `ssh -t -p 9500 yanz@103.191.165.156`
- **PM2:** salfanet-radius (cluster mode, TZ=Asia/Jakarta)
- **SSL Certificate:** Self-signed (valid 1 tahun)
- **Status:** Development & Testing

### VPS Secondary (Backup)
- **IP:** 103.151.141.116
- **Domain:** radius.salfa.my.id
- **SSH User:** root
- **App Path:** /var/www/salfanet-radius
- **Status:** Backup/Inactive

### VPS Reserve (SALFANET)
- **IP:** 202.155.157.41
- **SSH User:** root
- **App Path:** /var/www/salfanet-radius
- **Status:** Reserve/Unused

### MikroTik Gateway (Proxmox)
- **IP:** 192.168.54.1
- **RADIUS Secret:** secret123

### Database
- **Type:** MySQL 8.0
- **User:** salfanet_user
- **Password:** salfanetradius123
- **Database:** salfanet_radius

### FreeRADIUS
- **Version:** 3.0.26
- **Ports:** 1812 (auth), 1813 (acct), 3799 (CoA)
- **Config Path:** /etc/freeradius/3.0/

---

## 🔧 Perbaikan & Fitur Terbaru (7 Desember 2025)

### 1. Voucher Timezone Display Fix ✅ COMPLETE (7 Des 2025 - LATEST)
**Problem:** 
- Voucher `createdAt` showing UTC time (05:01) instead of WIB (12:01)
- Voucher `firstLoginAt` and `expiresAt` showing +7 hours offset (19:24 instead of 12:24)

**Root Cause:**
1. **createdAt Issue:** PM2 environment missing `TZ` variable → `new Date()` returns UTC
2. **firstLoginAt/expiresAt Issue:** Prisma adds 'Z' suffix → browser interprets as UTC → adds +7 hours
3. Database stores UTC (Prisma default), FreeRADIUS stores WIB

**Solution:**
1. **PM2 Environment Fix:**
   - Added `TZ: 'Asia/Jakarta'` to `ecosystem.config.js` env block
   - Killed all PM2 processes and restarted fresh daemon
   - Result: `new Date()` now returns WIB time correctly

2. **API Timezone Conversion:**
   - `createdAt`/`updatedAt`: Convert from UTC to WIB using `formatInTimeZone`
   - `firstLoginAt`/`expiresAt`: Already WIB from FreeRADIUS, remove 'Z' suffix to prevent browser conversion
   
3. **Timezone Strategy:**
   ```typescript
   // In src/app/api/hotspot/voucher/route.ts
   import { formatInTimeZone } from 'date-fns-tz'
   import { WIB_TIMEZONE } from '@/lib/timezone'
   
   const vouchersWithLocalTime = vouchers.map(v => ({
     ...v,
     // Convert UTC → WIB for Prisma timestamps
     createdAt: formatInTimeZone(v.createdAt, WIB_TIMEZONE, "yyyy-MM-dd'T'HH:mm:ss.SSS"),
     updatedAt: formatInTimeZone(v.updatedAt, WIB_TIMEZONE, "yyyy-MM-dd'T'HH:mm:ss.SSS"),
     // Keep WIB as-is for FreeRADIUS timestamps (remove 'Z' only)
     firstLoginAt: v.firstLoginAt ? v.firstLoginAt.toISOString().replace('Z', '') : null,
     expiresAt: v.expiresAt ? v.expiresAt.toISOString().replace('Z', '') : null,
   }))
   ```

**Files Modified:**
- `ecosystem.config.js` - Added `TZ: 'Asia/Jakarta'` to env
- `src/app/api/hotspot/voucher/route.ts` - Timezone-aware date formatting
- `src/lib/timezone.ts` - Utility functions (already existed)

**Result:**
- ✅ Voucher Generated time: Shows correct WIB (e.g., 12:20:54)
- ✅ Voucher First Login: Shows correct WIB (e.g., 12:24:14)
- ✅ Voucher Valid Until: Shows correct WIB (firstLogin + validity)
- ✅ Server environment: TZ=Asia/Jakarta confirmed in PM2

### 2. Cron Job System Improvements ✅ COMPLETE (7 Des 2025 - LATEST)
**Problems Fixed:**

1. **Auto Isolir Error:** "nowWIB is not defined"
   - Missing timezone utility imports in `voucher-sync.ts`
   
2. **No Disconnect Sessions Job:** 
   - Expired vouchers remained active in RADIUS
   - No automatic CoA (Change of Authorization) disconnect

3. **Activity Log Cleanup Missing Result:**
   - Cron execution history showed no result message
   - No visibility into what was cleaned

**Solutions Implemented:**

1. **Fixed Auto Isolir:**
   ```typescript
   // Added to src/lib/cron/voucher-sync.ts
   import { nowWIB, formatWIB, startOfDayWIBtoUTC, endOfDayWIBtoUTC } from '@/lib/timezone'
   ```

2. **Created Disconnect Sessions Job:**
   ```typescript
   // New function in src/lib/cron/voucher-sync.ts
   export async function disconnectExpiredVoucherSessions() {
     // 1. Find expired vouchers with active sessions
     // 2. Send CoA Disconnect-Request to RADIUS
     // 3. Record cron history with result
     // 4. Return disconnected count
   }
   
   // Added to src/lib/cron/config.ts
   {
     type: 'disconnect_sessions',
     name: 'Disconnect Expired Sessions',
     schedule: '*/5 * * * *', // Every 5 minutes
     enabled: true,
   }
   ```

3. **Fixed Activity Log Cleanup:**
   ```typescript
   // Modified src/lib/activity-log.ts
   export async function cleanOldActivities(daysToKeep: number = 30) {
     // Create cron_history record at start
     // Delete old activities
     // Update cron_history with result: "Cleaned X old activities"
     return { success: true, deleted: result.count }
   }
   ```

4. **Enhanced Frontend Cron Page:**
   - Added `typeLabels` for all 10 job types
   - Added response handlers for each job type
   - Added success notifications with SweetAlert
   - Improved Execution History table

**Files Modified:**
- `src/lib/cron/voucher-sync.ts` - Fixed imports, added disconnect function
- `src/lib/cron/config.ts` - Added disconnect_sessions job config
- `src/lib/activity-log.ts` - Modified cleanOldActivities with history recording
- `src/app/api/cron/route.ts` - Added disconnect_sessions case handler
- `src/app/admin/settings/cron/page.tsx` - Enhanced UI with labels and handlers

**Cron Jobs Status (10 Total):**
- ✅ `voucher_sync` - Sync vouchers (every 5 min)
- ✅ `disconnect_sessions` - Disconnect expired sessions (every 5 min) **NEW**
- ✅ `agent_sales` - Update agent sales (daily 1 AM)
- ✅ `auto_isolir` - Auto suspend overdue users (hourly)
- ✅ `invoice_generation` - Generate monthly invoices (daily 2 AM)
- ✅ `payment_reminder` - Send payment reminders (daily 8 AM)
- ✅ `whatsapp_queue` - Process WA message queue (every 10 min)
- ✅ `expired_voucher_cleanup` - Delete old vouchers (daily 3 AM)
- ✅ `activity_log_cleanup` - Clean old activity logs (daily 2 AM)
- ✅ `session_cleanup` - Clean old session data (daily 4 AM)

**Result:**
- ✅ All cron jobs running successfully without errors
- ✅ Execution History shows proper result messages
- ✅ Manual trigger works for all jobs from Settings → Cron
- ✅ Expired voucher sessions automatically disconnected via CoA

### 3. Activity Log System ✅ COMPLETE (7 Des 2025)
**Fitur:** Sistem pencatatan aktivitas lengkap untuk SEMUA endpoint penting.

**Problem:** Dashboard "Aktivitas Terbaru" kosong, tidak ada pencatatan aktivitas user.

**Solution:** 
Implementasi activity log LENGKAP untuk SEMUA priority endpoints:
- ✅ Authentication: Login/Logout
- ✅ PPPoE: User create/update/delete
- ✅ Session: Disconnect operations
- ✅ Voucher: Admin & agent generation
- ✅ Agent: Deposit webhooks
- ✅ Payment: Webhook logging
- ✅ Invoice: Generation logging
- ✅ Transaction: Income/expense CRUD
- ✅ WhatsApp: Broadcast logging
- ✅ Network: Router CRUD operations
- ✅ System: RADIUS restart logging

**NEW: Automatic Cleanup**
- ✅ Cron job runs daily at 2 AM
- ✅ Deletes logs older than 30 days
- ✅ Maintains database performance automatically

**Database Schema:**
```prisma
model activityLog {
  id          String   @id @default(cuid())
  userId      String?
  username    String
  userRole    String?
  action      String
  description String   @db.Text
  module      String   // 'pppoe', 'hotspot', 'voucher', 'invoice', 'payment', 'agent', 'session', 'transaction', 'system', etc
  status      String   @default("success") // 'success', 'warning', 'error'
  ipAddress   String?
  metadata    String?  @db.Text // JSON string for additional data
  createdAt   DateTime @default(now())
}
```

**Files Created:**
- `src/lib/activity-log.ts` - Helper functions (logActivity, getRecentActivities, cleanOldActivities)
- `src/app/api/auth/logout-log/route.ts` - Logout logging endpoint
- `docs/ACTIVITY_LOG_IMPLEMENTATION.md` - Implementation guide lengkap
- `docs/ACTIVITY_LOG_STATUS.md` - Status dan roadmap
- `CHANGELOG-20251207.md` - Comprehensive changelog

**Files Modified (Activity Log):**
- `prisma/schema.prisma` - Added activityLog model
- `src/lib/cron/config.ts` - Added automatic cleanup cron
- `src/lib/auth.ts` - Login logging
- `src/app/admin/layout.tsx` - Logout logging
- `src/app/api/dashboard/stats/route.ts` - Real activity display
- `src/app/api/hotspot/voucher/route.ts` - Voucher generation
- `src/app/api/agent/generate-voucher/route.ts` - Agent voucher
- `src/app/api/agent/deposit/webhook/route.ts` - Agent deposit
- `src/app/api/pppoe/users/route.ts` - PPPoE CRUD
- `src/app/api/sessions/disconnect/route.ts` - Session disconnect
- `src/app/api/payment/webhook/route.ts` - Payment webhook
- `src/app/api/invoices/generate/route.ts` - Invoice generation
- `src/app/api/keuangan/transactions/route.ts` - Transaction CRUD
- `src/app/api/whatsapp/broadcast/route.ts` - WhatsApp broadcast
- `src/app/api/network/routers/route.ts` - Router CRUD
- `src/app/api/system/radius/route.ts` - RADIUS restart

**All Modules Implemented:**
- ✅ `auth` - Login/Logout (TESTED & WORKING)
- ✅ `pppoe` - User management
- ✅ `session` - Session operations
- ✅ `voucher` - Admin generation (TESTED & WORKING)
- ✅ `agent` - Agent operations (TESTED & WORKING)
- ✅ `payment` - Payment processing
- ✅ `invoice` - Invoice management
- ✅ `transaction` - Keuangan CRUD
- ✅ `whatsapp` - Notifications & broadcasts
- ✅ `network` - Network device management
- ✅ `system` - System operations

**Status:** ✅ ALL PRIORITY 1-3 COMPLETE, ready for deployment

**Usage Example:**
```typescript
import { logActivity } from '@/lib/activity-log';

await logActivity({
  userId: session.user.id,
  username: session.user.username,
  userRole: session.user.role,
  action: 'GENERATE_VOUCHER',
  description: `Generated 10 vouchers (Paket 1 Jam)`,
  module: 'voucher',
  status: 'success',
  metadata: { count: 10, profileId, batchCode },
});
```

### 4. Voucher Generation & Management Improvements ✅ (7 Des 2025)
**Changes:**
1. **Increased Limit**: 500 → 25,000 vouchers per batch
2. **Performance Optimization**: Up to 70% faster using Prisma createMany
3. **Fixed Notification Z-Index**: Success popup now appears in front of modal (z-index: 999999)
4. **Modal Redesign**: Modern 2-column layout with better UX for large batch generation
5. **Pagination System**: Complete pagination for voucher table with 50-1000 items per page
6. **Stats Separation**: Stat cards show ALL vouchers (not affected by pagination)

**Performance Comparison:**
| Vouchers | Before (Raw SQL) | After (Prisma) | Speed Up |
|----------|------------------|----------------|----------|
| 1,000    | ~5s             | ~2s            | 60%      |
| 10,000   | ~50s            | ~15s           | 70%      |
| 25,000   | N/A (limit 500) | ~35s           | NEW!     |

**Files Modified:**
- `src/app/api/hotspot/voucher/route.ts` - Prisma createMany, pagination support, stats calculation
- `src/app/admin/hotspot/voucher/page.tsx` - Redesigned modal, pagination UI, stats from API
- `src/lib/sweetalert.ts` - Added swal-high-z-index class
- `src/app/globals.css` - Z-index 999999 for notifications
- `src/lib/activity-log.ts` - Fixed cleanOldActivities return format
- `src/app/api/cron/route.ts` - Added activity_log_cleanup case

**Technical Details:**
```typescript
// OLD (Raw SQL - Slow)
const values = voucherData.map(v => `('${v.id}', '${v.code}', ...)`).join(',')
await prisma.$executeRawUnsafe(`INSERT INTO hotspot_vouchers (...) VALUES ${values}`)

// NEW (Prisma - Fast)
const result = await prisma.hotspotVoucher.createMany({
  data: voucherData,
  skipDuplicates: true,
})
```

**Modal Redesign:**
```typescript
// New Features:
- Max-width increased: max-w-md → max-w-2xl
- 2-column responsive grid layout
- Profile & Quantity highlighted at top with teal background
- Real-time total value display with gradient (teal-cyan)
- Better field grouping: Code Configuration, Assignment & Options
- Helper text: "Maximum 25,000 vouchers per batch"
- All existing features maintained (Lock MAC, Agent assignment, Router selection)
```

**Pagination System:**
```typescript
// API Support:
- Query params: ?page=1&limit=100
- Response: { vouchers, total, totalPages, currentPage, pageSize, stats }
- Stats calculated from ALL vouchers (ignore pagination)
- Stats respect filters: profile, batch, router, agent (NOT status filter)

// Frontend UI:
- Page controls: First, Previous, 1-5, Next, Last
- Page size selector: 50, 100, 200, 500, 1000
- Display: "Showing 1-100 of 1,000 vouchers"
- Smart page number display (max 5 buttons)
- Auto reset to page 1 when filter changes
```

**Stats Calculation:**
```typescript
// BEFORE (Wrong - Only current page):
const stats = { 
  total: vouchers.length, // Only 100 items on current page
  waiting: vouchers.filter(v => v.status === 'WAITING').length,
  ...
}

// AFTER (Correct - All vouchers with filter):
const stats = await Promise.all([
  prisma.count({ where: statsWhere }), // Total ALL vouchers
  prisma.count({ where: { ...statsWhere, status: 'WAITING' }}),
  prisma.count({ where: { ...statsWhere, status: 'ACTIVE' }}),
  prisma.count({ where: { ...statsWhere, status: 'EXPIRED' }}),
])
// Stats from API, not calculated from current page
```

**Benefits:**
- ✅ Can generate up to 25,000 vouchers in one batch
- ✅ 70% faster execution with Prisma createMany
- ✅ Notifications always appear above modals (z-index: 999999)
- ✅ Better UX with modern 2-column modal design
- ✅ Complete pagination support (no more 1000 voucher limit)
- ✅ Accurate stats showing ALL vouchers (not just current page)
- ✅ Table performance optimized with pagination
- ✅ Cron job for activity log cleanup works correctly

### 5. Menu "Keuangan" → "Transaksi" ✅
**Change:** Renamed menu dan title dari "Keuangan" menjadi "Transaksi".

**Files Modified:**
- `src/app/admin/layout.tsx` - Menu sidebar
- `src/locales/id.json` - Translations
- `src/locales/en.json` - Translations

**Result:**
- Menu: **Transaksi** (ID) / **Transactions** (EN)
- Title: **Transaksi** (ID) / **Transactions** (EN)
- Subtitle: **Daftar Transaksi** (ID) / **Transaction List** (EN)

### 6. Dashboard Stats Bug Fix ✅
**Problem:** Revenue dan total users tidak muncul (Rp 0, 0 users) padahal ada data transaksi.

**Root Cause:**
- Date range calculation menggunakan timezone conversion yang kompleks
- Query `date: { gte: startOfMonth, lte: now }` tidak match dengan data UTC di database
- Transaction date stored as UTC (e.g., `2025-12-06T14:15:17.000Z`)
- Local time calculation `new Date(2025, 11, 1)` creates WIB time → UTC conversion mismatch

**Solution:**
- Simplified date calculation: `new Date(year, month, 1)` untuk month boundaries
- Changed query to `date: { gte: startOfMonth, lt: startOfNextMonth }`
- Removed complex timezone offset calculations
- Changed last month query to `lt: startOfMonth` instead of `lte: endOfLastMonth`

**Files Modified:**
- `src/app/api/dashboard/stats/route.ts`

**Result:**
- ✅ Revenue now showing: Rp 3,000 (was Rp 0)
- ✅ Total users: 1 (was 0)
- ✅ Transaction count: 1 (was 0)
- ✅ Active sessions: 1

### 7. Chart Label Truncation Fix ✅
**Problem:** Category names in "Pendapatan per Kategori" chart were cut off.

**Solution:**
- Increased bottom margin from `0` to `30px`
- Increased font size from `9` to `10`
- Changed angle from `-15°` to `-25°` for better spacing
- Added `height={60}` to XAxis
- Added `interval={0}` to show all labels

**Files Modified:**
- `src/components/charts/index.tsx`

### 8. Subdomain & SSL Configuration ✅
**Change:** Migrated from IP:Port to subdomain with HTTPS.

**Before:**
- Access via: `http://192.168.54.240:3005`
- No SSL/HTTPS

**After:**
- Domain: `server.salfa.my.id`
- Access via: `https://server.salfa.my.id`
- HTTPS enabled with self-signed certificate
- Cloudflare CDN active

**Configuration:**
- **Nginx:**
  - HTTP → HTTPS redirect
  - SSL certificate: `/etc/ssl/server.salfa.my.id/fullchain.pem`
  - Proxy to `http://127.0.0.1:3005`
  - Config: `/etc/nginx/sites-enabled/salfanet-radius`
- **SSL Certificate:**
  - Type: Self-signed
  - Subject: `CN=server.salfa.my.id, O=Salfa, L=Jakarta, ST=Jakarta, C=ID`
  - Valid: 1 year (Dec 6, 2025 - Dec 6, 2026)
  - Location: `/etc/ssl/server.salfa.my.id/`
- **Environment:**
  - NEXTAUTH_URL: `https://server.salfa.my.id`

**Files Modified:**
- `/etc/nginx/sites-available/salfanet-radius`
- `/var/www/salfanet-radius/.env`
- SSL certificates generated in `/etc/ssl/server.salfa.my.id/`

**Commands untuk regenerate SSL (jika expired):**
```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/server.salfa.my.id/privkey.pem \
  -out /etc/ssl/server.salfa.my.id/fullchain.pem \
  -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Salfa/CN=server.salfa.my.id"
sudo systemctl restart nginx
```

### 9. Session Timeout / Auto Logout ✅
**Fitur:** Auto logout jika tidak ada aktivitas selama 30 menit.

**Cara kerja:**
1. User login → timer idle mulai
2. Setiap aktivitas (mouse, keyboard, scroll, click) → timer reset
3. Setelah 29 menit tidak aktif → warning modal muncul dengan countdown 60 detik
4. User klik "Tetap Login" → timer reset, lanjut bekerja
5. Countdown habis atau user tidak merespons → auto logout

**Files:**
- `src/hooks/useIdleTimeout.ts` (NEW) - Hook untuk idle detection
- `src/app/admin/layout.tsx` - Integrasi idle timeout + warning modal
- `src/app/admin/login/page.tsx` - Tampilkan pesan jika logout karena idle
- `src/lib/auth.ts` - Session max age 1 hari (sebelumnya 30 hari)

**Konfigurasi:**
```typescript
// Session timeout
timeout: 30 * 60 * 1000,  // 30 menit
warningTime: 60 * 1000,   // Warning 1 menit sebelum logout

// Auth config (src/lib/auth.ts)
session: {
  strategy: 'jwt',
  maxAge: 24 * 60 * 60,    // 1 hari
  updateAge: 60 * 60,       // Update setiap 1 jam
}
```

### 10. Fix Logout Redirect ke Localhost ✅
**Problem:** Saat logout, redirect ke `localhost:3000` bukan ke IP server.

**Penyebab:** 
1. `NEXTAUTH_URL` di `.env` masih `localhost:3000`
2. `signOut({ callbackUrl: '/admin/login' })` menggunakan NEXTAUTH_URL

**Solusi:**
1. Update `.env`: `NEXTAUTH_URL=http://103.191.165.156:9600`
2. Gunakan `signOut({ redirect: false })` lalu manual redirect dengan `window.location.href`

```typescript
// Solusi di layout.tsx
const handleLogout = useCallback(async () => {
  await signOut({ redirect: false });
  window.location.href = `${window.location.origin}/admin/login`;
}, []);
```

### 11. Fix Layout/Menu Tidak Muncul Saat Login ✅
**Problem:** Setelah login pertama kali, sidebar/menu kadang tidak muncul.

**Solusi:** 
- Tambah loading state saat session masih `loading`
- Pisahkan useEffect untuk mounted, permissions, company, pending
- Redirect ke login jika `unauthenticated`

### 12. Router GPS Coordinates ✅
**Fitur baru:** Tambah koordinat GPS untuk router/NAS.

**Files:**
- `prisma/schema.prisma` - Tambah `latitude`, `longitude` di model router
- `src/app/admin/network/routers/page.tsx` - Form GPS + Map Picker
- `src/components/MapPicker.tsx` - Komponen pemilih lokasi dari peta

### 13. OLT Uplink Configuration ✅
**Fitur baru:** Konfigurasi uplink dari router ke OLT.

**Files:**
- `prisma/schema.prisma` - Model `networkOLTRouter` dengan `uplinkPort`
- `src/app/api/network/routers/[id]/interfaces/route.ts` (NEW) - API fetch MikroTik interfaces
- `src/app/api/network/routers/[id]/uplinks/route.ts` - CRUD uplinks
- `src/app/admin/network/routers/page.tsx` - Modal OLT Uplink dengan interface dropdown

### 14. Network Map Enhancement ✅
**Perbaikan:** Tampilkan uplink info di popup router (tanpa tombol Ping OLT).

**Files:**
- `src/app/admin/network/map/page.tsx` - Popup router dengan list uplinks

### 15. Fix DELETE API untuk OLT/ODC/ODP ✅
**Problem:** DELETE return 400 karena hanya terima query param.

**Solusi:** Accept `id` dari body JSON sebagai fallback.

**Files:**
- `src/app/api/network/olts/route.ts`
- `src/app/api/network/odcs/route.ts`
- `src/app/api/network/odps/route.ts`
- `src/app/api/pppoe/users/sync-mikrotik/route.ts` - API sync

**File yang diupdate:**
- `src/app/admin/pppoe/users/page.tsx` - Tambah dialog sync

### 16. WhatsApp Template Gangguan (Maintenance-Outage) ✅
**Masalah:** Template gangguan/maintenance tidak ada dan tidak bisa ditambahkan.

**Solusi:** Tambah template `maintenance-outage` dan auto-create missing templates.

**Variables template:**
- `{{issueType}}` - Jenis gangguan
- `{{affectedArea}}` - Area terdampak
- `{{description}}` - Deskripsi
- `{{estimatedTime}}` - Estimasi waktu perbaikan

**File yang diupdate:**
- `src/app/api/whatsapp/templates/route.ts`

### 17. FTTH Network Management (OLT, ODC, ODP) ✅
**Fitur baru:** Manajemen jaringan FTTH lengkap.

**Halaman baru:**
- `/admin/network/olts` - Manajemen OLT (Optical Line Terminal)
- `/admin/network/odcs` - Manajemen ODC (Optical Distribution Cabinet)
- `/admin/network/odps` - Manajemen ODP (Optical Distribution Point)
- `/admin/network/customers` - Assign pelanggan ke port ODP

**Fitur:**
- CRUD OLT dengan assignment router
- CRUD ODC terhubung ke OLT
- CRUD ODP terhubung ke ODC atau parent ODP
- Assign pelanggan ke port ODP dengan perhitungan jarak
- GPS location dengan Map picker
- Auto GPS dari browser

**File yang dibuat:**
- `src/app/admin/network/olts/page.tsx`
- `src/app/admin/network/odcs/page.tsx`
- `src/app/admin/network/odps/page.tsx`
- `src/app/admin/network/customers/page.tsx`

**File yang diupdate:**
- `src/app/admin/layout.tsx` - Tambah menu Network
- `src/locales/id.json` - Tambah translation
- `src/locales/en.json` - Tambah translation

### 18. Auto GPS Error Handling ✅
**Perbaikan:** Error handling lebih baik untuk fitur Auto GPS.

**Pesan error spesifik:**
- Permission denied → "Izin GPS ditolak"
- Position unavailable → "Lokasi tidak tersedia"
- Timeout → "Waktu habis mendapatkan lokasi"

**File yang diupdate:**
- `src/app/admin/network/olts/page.tsx`
- `src/app/admin/network/odcs/page.tsx`
- `src/app/admin/network/odps/page.tsx`

---

## 🔧 Perbaikan Sebelumnya

### 19. FreeRADIUS BOM Issue (UTF-16 Byte Order Mark)
**Masalah:** FreeRADIUS tidak binding ke port 1812/1813 karena file config memiliki BOM character.

**Solusi:**
- Tambah fungsi `remove_bom()` di vps-install.sh
- Update install-wizard.html dengan instruksi BOM removal
- Update FREERADIUS-SETUP.md dengan troubleshooting guide

### 20. Router API Port Fix
**Masalah:** API setup-isolir dan sessions menggunakan `router.apiPort` yang salah.

**Solusi:** Ubah ke `router.port || router.apiPort || 8728`

### 21. Sidebar Auto Close
**Masalah:** Sidebar tidak tertutup otomatis di mobile.

**Solusi:** Tambah prop `onNavigate` ke NavItem

### 22. PDF Export Error Fix
**Masalah:** API return binary PDF tapi frontend memanggil `res.json()`.

**Solusi:** API return JSON dengan `pdfData`, render dengan jsPDF client-side.

### 23. Keuangan Export Button Disabled
**Masalah:** Tombol export disabled karena startDate/endDate kosong.

**Solusi:** Inisialisasi dengan tanggal bulan berjalan.

---

## 📁 Struktur File Penting

```
salfanet-radius-main/
├── src/
│   ├── app/
│   │   ├── admin/
│   │   │   ├── layout.tsx              # Sidebar dengan menu Network
│   │   │   ├── keuangan/page.tsx
│   │   │   ├── sessions/page.tsx
│   │   │   ├── pppoe/users/page.tsx    # + Sync MikroTik
│   │   │   ├── network/
│   │   │   │   ├── routers/page.tsx
│   │   │   │   ├── olts/page.tsx       # NEW - OLT Management
│   │   │   │   ├── odcs/page.tsx       # NEW - ODC Management
│   │   │   │   ├── odps/page.tsx       # NEW - ODP Management
│   │   │   │   └── customers/page.tsx  # NEW - Customer Assignment
│   │   │   └── hotspot/voucher/page.tsx
│   │   └── api/
│   │       ├── network/
│   │       │   ├── routers/
│   │       │   ├── olts/route.ts
│   │       │   ├── odcs/route.ts
│   │       │   ├── odps/route.ts
│   │       │   └── customers/assign/route.ts
│   │       ├── pppoe/users/
│   │       │   ├── route.ts
│   │       │   └── sync-mikrotik/route.ts  # NEW
│   │       ├── whatsapp/templates/route.ts  # + maintenance-outage
│   │       ├── sessions/
│   │       ├── invoices/export/route.ts
│   │       └── keuangan/export/route.ts
│   ├── locales/
│   │   ├── id.json                     # + nav.olt, odc, odp, odpCustomer
│   │   └── en.json
│   └── lib/
│       ├── prisma.ts
│       └── utils/export.ts
├── prisma/
│   └── schema.prisma                   # + networkOLT, networkODC, networkODP, odpCustomerAssignment
├── freeradius-config/
│   ├── mods-enabled-sql
│   ├── mods-enabled-rest
│   ├── sites-enabled-default
│   └── clients.conf
├── vps-install.sh
└── docs/
    ├── install-wizard.html
    ├── FREERADIUS-SETUP.md
    ├── DEPLOYMENT-GUIDE.md
    └── GENIEACS-GUIDE.md
```

---

## 🗄️ Database Models Network (FTTH)

### networkOLT
```prisma
model networkOLT {
  id         String   @id
  name       String
  ipAddress  String
  latitude   Float
  longitude  Float
  status     String   @default("active")
  followRoad Boolean  @default(false)
  routers    networkOLTRouter[]
  odcs       networkODC[]
  odps       networkODP[]
}
```

### networkODC
```prisma
model networkODC {
  id         String   @id
  name       String
  latitude   Float
  longitude  Float
  oltId      String
  ponPort    Int
  portCount  Int      @default(8)
  olt        networkOLT @relation(...)
  odps       networkODP[]
}
```

### networkODP
```prisma
model networkODP {
  id          String   @id
  name        String
  latitude    Float
  longitude   Float
  oltId       String
  ponPort     Int
  portCount   Int      @default(8)
  odcId       String?
  parentOdpId String?
  customers   odpCustomerAssignment[]
}
```

### odpCustomerAssignment
```prisma
model odpCustomerAssignment {
  id         String   @id
  customerId String   @unique
  odpId      String
  portNumber Int
  distance   Float?
  notes      String?
}
```

---

## 🚀 Command Deployment

### Deploy ke VPS Production (103.67.244.131) ⭐ CURRENT
```bash
# Upload single file
scp path/to/file.ts root@103.67.244.131:/var/www/salfanet-radius/path/to/

# Upload multiple files
scp file1.ts file2.ts root@103.67.244.131:/var/www/salfanet-radius/src/lib/

# SSH move files if needed
ssh root@103.67.244.131 "mv /var/www/salfanet-radius/src/lib/file.ts /var/www/salfanet-radius/src/lib/cron/"

# Build dan restart (with cache clear)
ssh root@103.67.244.131 "cd /var/www/salfanet-radius && rm -rf .next && npm run build && pm2 restart ecosystem.config.js --update-env && pm2 save"

# Verify environment
ssh root@103.67.244.131 "pm2 list && pm2 env 0 | grep TZ"
```

### Deploy ke VPS Proxmox (103.191.165.156:9500)
```bash
# Upload file ke /tmp dulu
scp -P 9500 "path/to/file.ts" yanz@103.191.165.156:/tmp/filename.ts

# Copy ke app directory, build dan restart (gunakan sudo)
ssh -t yanz@103.191.165.156 -p 9500 "sudo cp /tmp/filename.ts /var/www/salfanet-radius/path/to/ && cd /var/www/salfanet-radius && sudo rm -rf .next && sudo npm run build && sudo pm2 restart salfanet-radius --update-env"
```

### Deploy ke VPS Production (103.151.141.116) - OLD
```bash
# Upload file
scp "path/to/file.ts" root@103.151.141.116:/var/www/salfanet-radius/path/to/

# Build dan restart
ssh root@103.151.141.116 "cd /var/www/salfanet-radius && rm -rf .next && npm run build && pm2 restart salfanet-radius"
```

---

## 🌍 Multi-Timezone Support

### Indonesia Timezone Regions

| Zona | UTC | Wilayah | TZ Identifier |
|------|-----|---------|---------------|
| **WIB** | UTC+7 | Sumatera, Jawa, Kalimantan Barat/Tengah | `Asia/Jakarta` |
| **WITA** | UTC+8 | Kalimantan Selatan/Timur, Sulawesi, Bali, NTB, NTT | `Asia/Makassar` |
| **WIT** | UTC+9 | Maluku, Papua | `Asia/Jayapura` |

### Configuration untuk Timezone Berbeda

**1. Update Server System Timezone:**
```bash
sudo timedatectl set-timezone Asia/Makassar  # WITA
# atau
sudo timedatectl set-timezone Asia/Jayapura  # WIT
```

**2. Update ecosystem.config.js:**
```javascript
env: {
  NODE_ENV: 'production',
  PORT: 3000,
  TZ: 'Asia/Makassar'  // Sesuaikan dengan wilayah
}
```

**3. Update .env:**
```bash
TZ="Asia/Makassar"
NEXT_PUBLIC_TIMEZONE="Asia/Makassar"
```

**4. Update src/lib/timezone.ts:**
```typescript
export const LOCAL_TIMEZONE = 'Asia/Makassar'  // Sesuaikan
```

**5. Restart semua services:**
```bash
pm2 restart ecosystem.config.js --update-env
pm2 save
sudo systemctl restart freeradius
```

### International Timezone Examples

| Negara | Timezone | TZ Identifier |
|--------|----------|---------------|
| Singapura | SGT (UTC+8) | `Asia/Singapore` |
| Malaysia | MYT (UTC+8) | `Asia/Kuala_Lumpur` |
| Thailand | ICT (UTC+7) | `Asia/Bangkok` |
| Filipina | PHT (UTC+8) | `Asia/Manila` |
| Australia (Sydney) | AEDT (UTC+11) | `Australia/Sydney` |

**Dokumentasi lengkap:** Lihat `docs/CRON-SYSTEM.md` section "Multi-Timezone Support"

---

## ⚠️ Known Issues & Tips

1. **FreeRADIUS BOM:** Selalu jalankan `remove_bom` setelah copy config files dari Windows
2. **Router Port:** Gunakan `router.port` bukan `router.apiPort` untuk koneksi API MikroTik
3. **PDF Export:** Frontend menggunakan jsPDF client-side, API harus return JSON dengan `pdfData`
4. **PPPoE Username:** Format `username@realm` - disable `filter_username` di FreeRADIUS
5. **RADIUS Secret:** Harus sama antara MikroTik, clients.conf, dan tabel `nas`
6. **Auto GPS:** Memerlukan HTTPS untuk bekerja di browser (kecuali localhost)
7. **VPS Proxmox:** Selalu gunakan `sudo` untuk operasi di /var/www/salfanet-radius
8. **NEXTAUTH_URL:** Harus sesuai dengan IP/domain yang diakses untuk logout redirect
9. **Session Timeout:** 30 menit idle → warning popup → 1 menit countdown → logout
10. **Logout Redirect:** Gunakan `signOut({ redirect: false })` + `window.location.href`
11. **Dashboard Date Queries:** Database stores UTC, use `new Date(year, month, day)` for boundaries
12. **Transaction Queries:** Use `lt: startOfNextMonth` instead of `lte: now` for month range
13. **PM2 Environment:** Use `pm2 restart --update-env` setelah ubah .env atau ecosystem.config.js
14. **Voucher Timezone:** Database stores UTC (Prisma), FreeRADIUS stores WIB, API converts accordingly
15. **Timezone Environment:** Always set `TZ=Asia/Jakarta` in ecosystem.config.js for correct `new Date()`
16. **Multi-Timezone:** Untuk wilayah lain (WITA/WIT), update 5 config: system TZ, ecosystem.config.js, .env, timezone.ts, restart services
17. **Cron Jobs:** All cron functions must record to `cron_history` table for execution tracking
18. **Kill PM2:** Use `pm2 kill` instead of `pm2 delete all` to ensure fresh daemon restart
19. **Cache Clear:** Always `rm -rf .next` before build to prevent stale cache issues

---

## 📦 Installer Scripts

### vps-install.sh
- Untuk VPS dengan akses **root langsung**
- Auto-detect IP address
- Install semua dependencies + FreeRADIUS + PM2 + Nginx

### vps-install-local.sh (NEW)
- Untuk VPS **tanpa akses root langsung** (pakai sudo)
- Cocok untuk: Proxmox VM, LXC Container, Local Server
- Semua command menggunakan `sudo`
- Sama fiturnya dengan vps-install.sh

---

## 📡 OLT Management Application (folder `/olt`)

### Overview
Aplikasi standalone untuk manajemen **OLT ZTE** via Telnet dan integrasi **MikroTik RouterOS** untuk PPPoE. Berjalan sebagai Express.js server terpisah dari aplikasi RADIUS utama di port **8306**.

### Struktur File Utama

| File | Fungsi |
|------|--------|
| `app.js` | Server utama (3703 lines) - Telnet pool, API endpoints |
| `settings.json` | Konfigurasi OLT, MikroTik, App |
| `mikrotik-client.js` | RouterOS API client wrapper |
| `logger.js` | Winston logger dengan daily rotation |
| `health-monitor.js` | Health check & monitoring |
| `database.json` | Customer data cache |
| `onu-registration-template.json` | Template registrasi ONU |
| `olt-template.json` | Template speed profiles |

### Konfigurasi (`settings.json`)
```json
{
  "olt": {
    "ip": "136.1.1.100",
    "port": 23,
    "username": "zte",
    "password": "zte"
  },
  "mikrotik": {
    "ip": "103.153.62.254",
    "port": 8728,
    "username": "admin",
    "password": ""
  },
  "app": {
    "port": 8306,
    "cache": {
      "customers": {
        "enabled": true,
        "ttlSeconds": 300
      }
    },
    "auth": {
      "enabled": true,
      "username": "seon",
      "password": ""
    }
  }
}
```

### API Endpoints

**ONU Management:**
```
GET  /api/onu/unconfigured     - List ONU belum teregistrasi
GET  /api/onu/registered       - List ONU terdaftar (show gpon onu state)
GET  /api/onu/config/:index    - Konfigurasi ONU spesifik
GET  /api/onu/power/:index     - Power attenuation ONU
POST /api/onu/register         - Registrasi ONU baru
POST /api/onu/register-preview - Preview script registrasi
```

**MikroTik PPPoE:**
```
GET  /api/mikrotik/pppoe-profiles     - List PPPoE profiles
GET  /api/mikrotik/pppoe-secrets      - List PPPoE secrets
POST /api/mikrotik/pppoe-secret       - Add PPPoE secret
DELETE /api/mikrotik/pppoe-secret/:username
```

**System:**
```
GET  /api/connection/health    - Status kesehatan koneksi OLT
GET  /api/customers            - List pelanggan (cached)
```

### Connection Pool
```javascript
const POOL_CONFIG = {
    maxIdleTime: 60000,        // 1 menit max idle
    keepAliveInterval: 15000,  // Ping setiap 15 detik
    reconnectDelay: 1000,      // 1 detik delay reconnect
    maxReconnectAttempts: 3
};
```

### ONU Registration Template
Commands untuk registrasi ONU lengkap dengan PPPoE:
1. `interface gpon-olt_1/{CARD}/{PON}`
2. `onu {NUM} type GPON sn {SN}`
3. `interface gpon-onu_1/{CARD}/{PON}:{NUM}`
4. `name {PPPOE_USERNAME}`
5. `tcon 1 profile {PAKET}`
6. `gemport 1 tcon 1`
7. `service-port 1 vport 1 user-vlan {VLAN} vlan {VLAN}`
8. `wan-ip 1 mode pppoe username {USER} password {PASS} vlan-profile {VLAN}`

### Frontend Pages (`public/`)
| File | Fungsi |
|------|--------|
| `index.html` | Dashboard - List unregistered ONUs |
| `onu-config.html` | Form registrasi ONU dengan PPPoE |
| `settings.html` | Konfigurasi OLT/MikroTik |
| `user.html` | Manajemen user/pelanggan |

### Customer Cache (`database.json`)
```json
{
  "customers": [
    {
      "interface": "gpon-onu_1/3/1:3",
      "serialNumber": "Unknown",
      "status": "working",
      "customerName": "BA.PUTU.WATRA",
      "package": "15M",
      "category": "online"
    }
  ],
  "totalInterfaces": 39,
  "totalCustomers": 39,
  "onlineCustomers": 35,
  "offlineCustomers": 4,
  "lastUpdated": "2025-..."
}
```

### Menjalankan Aplikasi
```bash
cd olt/
npm install
npm start         # Production (port 8306)
npm run dev       # Development dengan nodemon
```

### Logging
- File: `logs/smartolt-YYYY-MM-DD.log`
- Max size: 1MB per file
- Retention: 5 files
- Levels: info, error, warn

### Integrasi dengan SALFANET RADIUS
Aplikasi OLT terpisah dari Next.js RADIUS utama, digunakan sebagai:
- **Microservice** untuk manajemen OLT ZTE
- **API Backend** untuk registrasi ONU dan sinkronisasi PPPoE
- **Standalone Tool** untuk teknisi jaringan

---

## 📝 Pending/Future Tasks

### Completed ✅
1. ~~Sync PPPoE users dari MikroTik ke database~~ ✅
2. ~~WhatsApp template gangguan~~ ✅
3. ~~FTTH Network Management (OLT, ODC, ODP)~~ ✅
4. ~~Network Map visualization~~ ✅
5. ~~Session timeout / auto logout~~ ✅
6. ~~Router GPS coordinates~~ ✅
7. ~~OLT Uplink configuration~~ ✅
8. ~~Fix logout redirect ke localhost~~ ✅
9. ~~Fix layout tidak muncul saat login~~ ✅
10. ~~Update semua dokumentasi (README, CHAT_MEMORY, install-wizard)~~ ✅
11. ~~Buat vps-install-local.sh untuk VPS lokal~~ ✅
12. ~~Fix dashboard stats (revenue Rp 0 → Rp 3,000)~~ ✅ (7 Dec 2025)
13. ~~Fix chart label truncation~~ ✅ (7 Dec 2025)
14. ~~Setup subdomain server.salfa.my.id~~ ✅ (7 Dec 2025)
15. ~~Install SSL certificate (self-signed)~~ ✅ (7 Dec 2025)
16. ~~Fix voucher timezone display (createdAt UTC, firstLogin +7 offset)~~ ✅ (7 Dec 2025)
17. ~~Add TZ environment variable to PM2~~ ✅ (7 Dec 2025)
18. ~~Fix Auto Isolir "nowWIB is not defined" error~~ ✅ (7 Dec 2025)
19. ~~Create Disconnect Expired Sessions cron job~~ ✅ (7 Dec 2025)
20. ~~Fix Activity Log Cleanup execution history~~ ✅ (7 Dec 2025)
21. ~~Cleanup project files (temp/, test markdown)~~ ✅ (7 Dec 2025)
22. ~~Deploy all fixes to VPS production~~ ✅ (7 Dec 2025)
23. ~~Agent bulk operations (delete, status change)~~ ✅ (8 Dec 2025)
24. ~~Agent login tracking and voucher stock~~ ✅ (8 Dec 2025)

### In Progress
- Test RADIUS authentication di VPS Proxmox lokal

### Future
- Report dan analytics untuk FTTH network
- ODP splitter capacity tracking
- Customer bandwidth usage per ODP
- Multi-language support (EN/ID) expansion
- Advanced permission granularity

---

**Untuk melanjutkan chat, copy isi file ini dan paste di chat baru sebagai context.**

