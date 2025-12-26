# Changelog

All notable changes to SALFANET RADIUS will be documented in this file.

## [2.5.1] - 2025-12-13

### 🔧 Installer Scripts Update

#### Updated VPS Installation Scripts
**Files Modified:**
- `vps-install.sh` - Production VPS installer (with root access)
- `vps-install-local.sh` - Local VPS installer (with sudo)

**Changes:**
1. **Added REST Authorize Endpoint to FreeRADIUS Config**
   - Include `authorize` section in REST module configuration
   - Enable voucher validation BEFORE password authentication
   - Timeout set to 2 seconds for authorize endpoint
   - Prevents expired vouchers from authenticating

2. **Updated REST Module Configuration**
   ```bash
   rest {
       authorize {
           uri = "${..connect_uri}/api/radius/authorize"
           method = "post"
           body = "json"
           data = '{"username": "%{User-Name}", "nasIp": "%{NAS-IP-Address}"}'
           timeout = 2
       }
       post-auth { ... }
       accounting { ... }
   }
   ```

3. **Benefits:**
   - ✅ New installations automatically get voucher authorization feature
   - ✅ Expired vouchers blocked at FreeRADIUS level
   - ✅ Consistent with production configuration (Dec 13, 2025)
   - ✅ Security hardening out-of-the-box

**Installation Flow Updated:**
- Both scripts now configure REST authorize during FreeRADIUS setup
- Authorize endpoint called in FreeRADIUS `sites-enabled/default` authorize section
- Complete voucher validation system ready to use after installation

---

## [2.5.0] - 2025-12-13

### 🔒 Security Enhancement: FreeRADIUS Authorization Pre-Check for Expired Vouchers

#### Critical Bug Fix: Expired Vouchers Could Still Login
**Problem:**
- Voucher dengan status EXPIRED masih bisa login ke hotspot
- FreeRADIUS hanya check username/password di `radcheck` table
- Tidak ada validasi `expiresAt` sebelum authentication
- User melihat pesan "invalid username or password" bukan "account expired"
- Voucher expired tidak auto-disconnect dari active session
- Active sessions dari voucher tidak muncul di dashboard admin

**Impact:**
- 🔴 **CRITICAL SECURITY ISSUE**: User bisa tetap online dengan voucher kadaluarsa
- 🔴 **Poor UX**: Pesan error tidak jelas untuk user
- 🔴 **Revenue Loss**: Voucher gratis karena bisa digunakan selamanya
- 🔴 **Dashboard Inaccurate**: Admin tidak bisa monitor real sessions

---

### 🛠️ Solution Implemented

#### 1. REST Authorization Endpoint (Pre-Authentication Check)
**File Created:** `src/app/api/radius/authorize/route.ts`

FreeRADIUS sekarang call REST API **SEBELUM** proses authentication untuk validate voucher:

```typescript
export async function POST(request: NextRequest) {
  const { username } = await request.json();
  
  const voucher = await prisma.hotspotVoucher.findUnique({
    where: { code: username },
    include: { profile: true },
  });
  
  if (!voucher) {
    return NextResponse.json({
      success: true,
      action: "allow",
      message: "Not a voucher"
    });
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
  
  // Check 3: Active session timeout exceeded
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
  
  return NextResponse.json({
    success: true,
    action: "allow",
    status: voucher.status,
    expiresAt: voucher.expiresAt,
  });
}
```

**Key Features:**
- ✅ Check voucher status BEFORE password validation
- ✅ Auto-update status to EXPIRED if expiresAt passed
- ✅ Session timeout detection for active sessions
- ✅ Log rejection to `radpostauth` table for audit trail
- ✅ Return proper RADIUS attributes for MikroTik display

---

#### 2. FreeRADIUS REST Module Configuration
**File Modified:** `freeradius-config/mods-enabled-rest`

Added `authorize` section to REST module:

```
rest {
    tls {
        check_cert = no
        check_cert_cn = no
    }
    
    connect_uri = "http://localhost:3000"
    
    # NEW: Authorize pre-check
    authorize {
        uri = "${..connect_uri}/api/radius/authorize"
        method = "post"
        body = "json"
        data = "{ \"username\": \"%{User-Name}\", \"nasIp\": \"%{NAS-IP-Address}\" }"
        tls = ${..tls}
        timeout = 2
    }
    
    post-auth {
        uri = "${..connect_uri}/api/radius/post-auth"
        method = "post"
        body = "json"
        data = "{ \"username\": \"%{User-Name}\", \"reply\": \"%{reply:Packet-Type}\", \"nasIp\": \"%{NAS-IP-Address}\", \"framedIp\": \"%{Framed-IP-Address}\" }"
        tls = ${..tls}
    }
    
    accounting {
        uri = "${..connect_uri}/api/radius/accounting"
        method = "post"
        body = "json"
        data = "{ \"username\": \"%{User-Name}\", \"statusType\": \"%{Acct-Status-Type}\", \"sessionId\": \"%{Acct-Session-Id}\", \"nasIp\": \"%{NAS-IP-Address}\", \"framedIp\": \"%{Framed-IP-Address}\", \"sessionTime\": \"%{Acct-Session-Time}\", \"inputOctets\": \"%{Acct-Input-Octets}\", \"outputOctets\": \"%{Acct-Output-Octets}\" }"
        tls = ${..tls}
    }
    
    pool {
        start = 0
        min = 0
        max = 32
        spare = 1
        uses = 0
        lifetime = 0
        idle_timeout = 60
        connect_timeout = 3
    }
}
```

---

#### 3. FreeRADIUS Authorization Flow
**File Modified:** `freeradius-config/sites-enabled-default`

Added REST call in `authorize` section (after SQL, before PAP):

```
authorize {
    filter_username
    preprocess
    chap
    mschap
    digest
    suffix
    eap {
        ok = return
    }
    files
    -sql
    
    # CRITICAL: Call REST API to check voucher expiry
    rest
    
    -ldap
    expiration
    logintime
    pap
}
```

**Authentication Flow:**
```
1. User login → FreeRADIUS receives Access-Request
2. SQL check → Load user from radcheck (username/password)
3. REST authorize → Call /api/radius/authorize
   ├─ If expired → Return Auth-Type=Reject + Reply-Message
   └─ If valid → Continue to next step
4. PAP authentication → Validate password
5. Post-Auth → Log success/failure
6. Send Access-Accept/Reject to MikroTik
```

---

#### 4. Dashboard Active Sessions Fix
**File Modified:** `src/app/api/dashboard/stats/route.ts`

**Problem:** Query menggunakan `nasporttype = 'Wireless-802.11'` yang tidak selalu ada di radacct.

**Solution:** Check username di tabel `pppoeUser` vs `hotspotVoucher`:

```typescript
// OLD (BROKEN):
activeSessionsHotspot = await prisma.radacct.count({
  where: {
    acctstoptime: null,
    acctupdatetime: { gte: tenMinutesAgo },
    nasporttype: 'Wireless-802.11', // ❌ Not reliable
  },
});

// NEW (FIXED):
const pppoeSessions = await prisma.radacct.findMany({
  where: {
    acctstoptime: null,
    acctupdatetime: { gte: tenMinutesAgo },
  },
  select: { username: true },
});

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

**Result:**
- ✅ Semua hotspot sessions sekarang muncul di dashboard
- ✅ Accurate PPPoE vs Hotspot session count
- ✅ No dependency on nasporttype field

---

#### 5. Enhanced Voucher Sync Cronjob
**File Modified:** `src/lib/cron/voucher-sync.ts`

**Improvements:**
1. **Better Logging Per Voucher:**
```typescript
const expiredVouchers = await prisma.$queryRaw<Array<{code: string; id: string}>>`
  SELECT code, id FROM hotspot_vouchers
  WHERE status = 'ACTIVE'
    AND expiresAt < UTC_TIMESTAMP()
`

console.log(`[CRON] Found ${expiredVouchers.length} expired vouchers to process`)

let expiredCount = 0
for (const voucher of expiredVouchers) {
  try {
    // 1. Remove from RADIUS authentication tables
    await prisma.radcheck.deleteMany({
      where: { username: voucher.code }
    })
    await prisma.radusergroup.deleteMany({
      where: { username: voucher.code }
    })
    
    // 2. Check for active session
    const activeSession = await prisma.radacct.findFirst({
      where: { username: voucher.code, acctstoptime: null },
    })
    
    if (activeSession) {
      console.log(`[CRON] Voucher ${voucher.code} has active session, will be disconnected by CoA`)
    }
    
    expiredCount++
    console.log(`[CRON] Voucher ${voucher.code} removed from RADIUS (expired)`)
  } catch (err) {
    console.error(`[CRON] Error processing expired voucher ${voucher.code}:`, err)
  }
}
```

2. **Auto-Disconnect via CoA:**
```typescript
// Update status to EXPIRED
const expiredResult = await prisma.$executeRaw`
  UPDATE hotspot_vouchers
  SET status = 'EXPIRED'
  WHERE status = 'ACTIVE'
    AND expiresAt < NOW()
`

// Disconnect expired sessions via CoA
let disconnectedCount = 0
try {
  const coaResult = await disconnectExpiredSessions()
  disconnectedCount = coaResult.disconnected
} catch (coaErr) {
  console.error('[CoA] Error:', coaErr)
}
```

3. **Improved History Logging:**
```typescript
await prisma.cronHistory.update({
  where: { id: history.id },
  data: {
    status: 'success',
    completedAt,
    duration: completedAt.getTime() - startedAt.getTime(),
    result: `Synced ${syncedCount} vouchers, expired ${expiredCount} vouchers, disconnected ${disconnectedCount} sessions`,
  },
})
```

---

### 📊 MikroTik Log Messages

**Before Fix:**
```
login failed: invalid username or password
```

**After Fix:**
```
login failed: Your account has expired
login failed: Session timeout
```

---

### 🎯 Technical Implementation Details

#### FreeRADIUS Package Requirements
```bash
apt-get install freeradius-rest
```

#### REST Module Loading
Module `rlm_rest.so` must be available at:
```
/usr/lib/freeradius/rlm_rest.so
```

#### Configuration Files
1. `/etc/freeradius/3.0/mods-enabled/rest` - REST API endpoints
2. `/etc/freeradius/3.0/sites-enabled/default` - Authorization flow
3. `/var/www/salfanet-radius/src/app/api/radius/authorize/route.ts` - Validation logic

#### Database Tables Used
- `hotspot_vouchers` - Voucher status, expiresAt
- `radcheck` - RADIUS username/password
- `radusergroup` - User group membership
- `radacct` - Active sessions tracking
- `radpostauth` - Authentication log (success/failure)

---

### ✅ Testing Checklist

- [x] Expired voucher rejected before authentication
- [x] Reply-Message "Your account has expired" sent to MikroTik
- [x] Message displayed in MikroTik log
- [x] Active sessions visible in admin dashboard
- [x] Voucher sync cronjob processes expired vouchers
- [x] CoA disconnect for expired active sessions
- [x] radpostauth logging for audit trail
- [x] No false positives (valid vouchers still work)
- [x] Performance: 2-second timeout for authorize check

---

### 📝 Files Modified Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `src/app/api/radius/authorize/route.ts` | **CREATED** | Pre-authentication voucher validation endpoint |
| `freeradius-config/mods-enabled-rest` | Modified | Added authorize section with 2s timeout |
| `freeradius-config/sites-enabled-default` | Modified | Call REST in authorize flow after SQL |
| `src/app/api/dashboard/stats/route.ts` | Modified | Fixed hotspot session counting logic |
| `src/lib/cron/voucher-sync.ts` | Enhanced | Better logging, cleanup, and disconnect |

---

### 🚀 Deployment Notes

**VPS Environment:**
- IP: 103.67.244.131
- FreeRADIUS: v3.0.26 (with rlm_rest module)
- Next.js: v16.0.7
- PM2: Process manager
- MySQL: 8.0.44

**Restart Sequence:**
```bash
# 1. Update Next.js code
cd /var/www/salfanet-radius
npm run build

# 2. Update FreeRADIUS config
cp freeradius-config/mods-enabled-rest /etc/freeradius/3.0/mods-enabled/rest
cp freeradius-config/sites-enabled-default /etc/freeradius/3.0/sites-enabled/default

# 3. Test FreeRADIUS config
freeradius -CX

# 4. Restart services
systemctl restart freeradius
pm2 restart all --update-env
```

---

### 🔍 Monitoring & Debugging

**Check Authorization Logs:**
```sql
SELECT * FROM radpostauth 
WHERE authdate > NOW() - INTERVAL 1 HOUR 
ORDER BY authdate DESC;
```

**Check Expired Vouchers:**
```sql
SELECT code, status, expiresAt 
FROM hotspot_vouchers 
WHERE status = 'EXPIRED' 
AND expiresAt > NOW() - INTERVAL 1 DAY;
```

**FreeRADIUS Debug Mode:**
```bash
systemctl stop freeradius
freeradius -X
```

**REST API Test:**
```bash
curl -X POST http://localhost:3000/api/radius/authorize \
  -H "Content-Type: application/json" \
  -d '{"username": "553944"}'
```

---

## [2.4.5] - 2025-12-10

### 🎨 UI/UX Improvements: Voucher Template Preview & Dashboard Traffic Monitor

#### 1. Mobile Responsive Voucher Template Preview
**Problem:**
- Preview voucher pada tampilan mobile tidak responsif
- Voucher cards terlalu kecil dan terpotong di layar mobile
- Layout voucher tidak optimal untuk mobile viewing
- Posisi voucher tidak berurutan (single code vs username/password)

**Solution:**
Optimized voucher template preview for mobile devices with responsive CSS and better layout handling.

**Changes:**

1. **Mobile Media Queries (≤640px):**
   ```css
   @media (max-width: 640px) {
     .voucher-preview-container { 
       display: flex !important; 
       flex-direction: column !important; 
       padding: 0 8px !important; 
       gap: 10px !important; 
     }
     .voucher-card { 
       display: block !important; 
       width: calc(100% - 16px) !important; 
       max-width: none !important; 
       margin: 0 auto 10px auto !important; 
     }
     .voucher-single { order: 1; }
     .voucher-dual { order: 2; }
   }
   ```

2. **Tablet Media Queries (641px - 1024px):**
   ```css
   @media (min-width: 641px) and (max-width: 1024px) {
     .voucher-card { width: calc(33.33% - 8px) !important; }
   }
   ```

3. **Desktop (≥1025px):**
   ```css
   @media (min-width: 1025px) {
     .voucher-card { width: 155px !important; }
   }
   ```

4. **React State for Mobile Detection:**
   ```typescript
   const [isMobile, setIsMobile] = useState(false);
   
   useEffect(() => {
     const handleResize = () => setIsMobile(window.innerWidth <= 640);
     handleResize();
     window.addEventListener('resize', handleResize);
     return () => window.removeEventListener('resize', handleResize);
   }, []);
   ```

5. **Dynamic Container Styles:**
   ```typescript
   style={{
     display: 'flex',
     flexDirection: isMobile ? 'column' : 'row',
     flexWrap: isMobile ? 'nowrap' : 'wrap',
     gap: isMobile ? '12px' : '6px',
   }}
   ```

**Files Modified:**
- `src/app/admin/hotspot/template/page.tsx` - Mobile responsive DEFAULT_TEMPLATE & preview container

**Result:**
- ✅ Voucher preview responsive di semua device
- ✅ Voucher cards tidak terpotong di mobile
- ✅ Layout vertikal di mobile dengan gap yang tepat
- ✅ Single-code voucher tampil di atas, dual (username/password) di bawah
- ✅ Preview button tetap tampil di semua device

---

#### 2. Dashboard Traffic Monitor UI Improvements
**Problem:**
- Font judul "Traffic Monitor MikroTik" terlalu besar
- Indikator "Live" tidak diperlukan
- Dropdown Router dan Interface terlalu besar dan horizontal
- Layout selector tidak optimal

**Solution:**
Optimized Traffic Monitor section with smaller fonts and vertical selector layout.

**Changes:**

1. **Title Font Size Reduced:**
   ```tsx
   // Before
   <h3 className="text-lg font-semibold">Traffic Monitor MikroTik</h3>
   
   // After  
   <h3 className="text-base font-semibold">Traffic Monitor MikroTik</h3>
   ```

2. **Live Indicator Removed:**
   ```tsx
   // Removed completely
   <div className="flex items-center gap-2">
     <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
     <span className="text-xs text-gray-500">Live</span>
   </div>
   ```

3. **Dropdown Selectors - Vertical Layout:**
   ```tsx
   // Before: Horizontal layout
   <div className="flex items-center gap-3">
   
   // After: Vertical layout (Router above, Interface below)
   <div className="flex flex-col items-start gap-2">
   ```

4. **Dropdown Styling Optimized:**
   ```tsx
   // Before
   className="text-xs px-3 py-1.5 ..."
   
   // After
   className="text-[11px] px-2.5 py-1.5 ..."
   ```

**Files Modified:**
- `src/components/TrafficChartMonitor.tsx` - Header title, selectors layout, Live indicator removed

**Result:**
- ✅ Judul lebih compact dengan font-size base
- ✅ Live indicator dihilangkan (cleaner UI)
- ✅ Dropdown Router di atas, Interface di bawah (vertikal)
- ✅ Dropdown lebih kecil dengan font 11px
- ✅ Layout lebih rapi dan profesional

---

## [2.4.4] - 2025-12-09

### 🎨 Voucher Template Print Optimization

#### Enhanced Print Layout & Voucher Sizing
**Problem:**
- Voucher template print size was too small and hard to read
- Print preview didn't match template preview
- Space between vouchers was inconsistent
- Font sizes were too small for printing
- Cards didn't fill A4 page properly

**Solution:**
Optimized voucher template for A4 portrait printing with better sizing and readability.

**Changes:**

1. **Template Default Sizing:**
   - Card height: 70px → 100px (30% larger)
   - Header font: 8px → 12px
   - Code label: 6px → 8px
   - Code text: 11px → 13px
   - Username/Password label: 6px → 10px
   - Footer padding: 2px 4px → 10px 15px
   - Footer font: 8px → 10px

2. **Print Layout:**
   - Portrait A4 optimization: 5 columns × 10 rows
   - Margin adjusted: 0.5% horizontal, 0.2% vertical bottom
   - Space-between distribution for full page coverage
   - Consistent voucher spacing across all rows

3. **Database Template Update:**
   - Default template updated to match new sizing
   - Router name display from actual NAS/router database
   - Support for username/password different credentials

**Files Modified:**
- `src/app/admin/hotspot/template/page.tsx` - Updated DEFAULT_TEMPLATE
- `src/lib/utils/templateRenderer.ts` - Enhanced print CSS with space-between
- Database: `voucher_templates` - Updated default compact template

**Print Preview:**
- 50 vouchers per A4 page (5×10 grid)
- Better readability with larger fonts
- Consistent card heights and spacing
- Full page coverage from top to bottom

---

## [2.4.3] - 2025-12-09

### 🚀 MikroTik Rate Limit Format Support

#### Full Burst Limit Configuration
**Problem:**
- Hotspot and PPPoE profiles only supported simple rate format (e.g., "5M/5M")
- No way to configure burst rate, burst threshold, priority, or minimum rate
- Admins had to manually configure advanced QoS in MikroTik after sync

**Solution:**
Both profile types now support full MikroTik rate limit format with all advanced parameters.

**Format Specification:**
```
rx-rate[/tx-rate] [rx-burst-rate[/tx-burst-rate]] [rx-burst-threshold[/tx-burst-threshold]] [rx-burst-time[/tx-burst-time]] [priority] [rx-rate-min[/tx-rate-min]]
```

**Examples:**
- Simple: `5M/5M` (basic download/upload speed)
- With burst: `2M/2M 4M/4M 2M/2M 8 0/0` (burst to 4M when below 2M threshold)
- Full format: `10M/10M 15M/15M 8M/8M 5 1M/1M` (all parameters configured)

**Changes:**

1. **Hotspot Profile Form**
   - Replaced separate `downloadSpeed` and `uploadSpeed` number inputs
   - Single `speed` text input with monospace font
   - Placeholder: "1M/1500k 0/0 0/0 8 0/0"
   - Helper text explaining full format

2. **PPPoE Profile Form**
   - Added optional `rateLimit` field to interface
   - Replaced `downloadSpeed`/`uploadSpeed` grid with single `rateLimit` input
   - Monospace font for better readability
   - Placeholder: "1M/1500k 0/0 0/0 8 0/0"
   - Helper text with format documentation
   - Backward compatible with existing profiles (auto-converts to new format)

**Technical Details:**
```typescript
// PPPoE Profile Interface
interface PPPoEProfile {
  rateLimit?: string; // Full MikroTik format
  downloadSpeed: number; // Legacy field (still used for backward compatibility)
  uploadSpeed: number;   // Legacy field
}

// Edit handler converts legacy to new format
rateLimit: profile.rateLimit || `${profile.downloadSpeed}M/${profile.uploadSpeed}M`
```

**Files Modified:**
- `src/app/admin/hotspot/profile/page.tsx` - Rate limit input with full format support
- `src/app/admin/pppoe/profiles/page.tsx` - Added rateLimit field and input

**Benefits:**
- ✅ Complete control over bandwidth management from web interface
- ✅ Support for burst speed configurations
- ✅ Priority and minimum rate guarantees
- ✅ No manual MikroTik configuration needed after sync
- ✅ Backward compatible with simple format
- ✅ Matches MikroTik RouterOS native format

**MikroTik Parameters Explained:**
- **rx-rate/tx-rate**: Normal download/upload speed (required)
- **rx-burst-rate/tx-burst-rate**: Maximum burst speed when allowed
- **rx-burst-threshold/tx-burst-threshold**: Traffic threshold to allow burst
- **rx-burst-time**: How long burst can be sustained (seconds)
- **priority**: QoS priority (1-8, lower = higher priority)
- **rx-rate-min/tx-rate-min**: Guaranteed minimum bandwidth

---

## [2.4.2] - 2025-12-08

### 🎯 Agent Management Enhancement

#### Bulk Operations & Enhanced Tracking
**New Features:**

1. **Bulk Selection with Checkboxes**
   - Checkbox "Select All" in table header
   - Individual checkbox for each agent
   - Counter displays number of selected agents
   - Visual feedback for selections

2. **Bulk Delete Agents**
   - Delete multiple agents simultaneously
   - Confirmation modal before deletion
   - Parallel deletion for better performance
   - Success/failure notifications

3. **Bulk Status Change**
   - Change status of multiple agents at once
   - Modal with Active/Inactive options
   - Applies to all selected agents
   - Instant UI update after change

4. **Login Tracking Column**
   - New "Login Terakhir" column in agent table
   - Shows last login timestamp from agent portal
   - Format: DD MMM YYYY, HH:MM
   - Displays "Belum login" if never logged in
   - Auto-updates when agent logs in

5. **Voucher Stock Column**
   - New "Stock" column showing available vouchers
   - Real-time count of vouchers with WAITING status
   - Format: "X voucher"
   - Helps monitor agent inventory

6. **Status Management in Edit Modal**
   - Dropdown to change agent status when editing
   - Options: Active or Inactive
   - Only visible in edit mode (not create mode)
   - Integrated with existing edit form

**Technical Implementation:**
```typescript
// Bulk operations with parallel processing
Promise.all(selectedAgents.map(id => 
  fetch(`/api/hotspot/agents?id=${id}`, { method: 'DELETE' })
));

// Stock calculation
voucherStock = vouchers.filter(v => v.status === 'WAITING').length;

// Login tracking
await prisma.agent.update({
  where: { id },
  data: { lastLogin: new Date() }
});
```

**Database Changes:**
```sql
-- New column added to agents table
ALTER TABLE `agents` ADD COLUMN `lastLogin` DATETIME(3) NULL;
```

**Files Modified:**
- `src/app/admin/hotspot/agent/page.tsx` - UI with bulk operations
- `src/app/api/hotspot/agents/route.ts` - API with lastLogin & voucherStock
- `src/app/api/agent/login/route.ts` - Login timestamp tracking
- `prisma/schema.prisma` - Added lastLogin field
- `prisma/migrations/20251208135232_add_agent_last_login/migration.sql`

**Deployment:**
- ✅ VPS Production: 103.67.244.131
- ✅ Database migration successful
- ✅ Build: 142 routes compiled
- ✅ PM2: Online (57.4mb memory)
- ✅ API tested and verified

**Benefits:**
- 🚀 Faster agent management with bulk operations
- 📊 Better visibility of agent activity and inventory
- 🎯 Improved UX for admin operations
- ⚡ No performance impact on existing features

---

## [2.4.1] - 2025-12-08

### 🔒 Security Updates

#### Critical Security Patch - React Server Components
**Issue:**
- Critical security vulnerability in React Server Components (CVE-2024-XXXXX)
- Affects Next.js applications using React 19.x
- Potential XSS and data exposure risks

**Solution:**
- Updated Next.js from 16.0.6 → **16.0.7** (includes security patches)
- Updated React from 19.2.0 → **19.2.1** (patched version)
- Updated React-DOM from 19.2.0 → **19.2.1** (patched version)

**Reference:**
- https://react.dev/blog/2025/12/03/critical-security-vulnerability-in-react-server-components

**Files Modified:**
- `package.json` - Updated dependency versions
- `package-lock.json` - Updated dependency tree

**Build Status:**
- ✅ Local build: Compiled successfully in 29.0s
- ✅ VPS build: Compiled successfully in 18.3s
- ✅ PM2 status: Online (60.8mb memory)
- ✅ All 142 routes working correctly

**Result:**
- ✅ Application secured against critical vulnerability
- ✅ Turbopack optimization maintained
- ✅ No breaking changes
- ✅ Production deployment successful

---

## [2.4.0] - 2025-12-08

### 🎨 UI/UX Improvements

#### 1. Dashboard Layout Optimization
**Changes:**
- Stats cards grid changed from 4 columns to 5 columns for better space utilization
- Card sizes reduced with optimized padding (p-3 → p-2.5) and smaller fonts
- Traffic Monitor repositioned from bottom to top (directly below stats cards)
- Gap between cards reduced for more compact layout

**Result:**
- ✅ All 5 stat cards visible in one row on desktop
- ✅ Traffic monitoring more prominent and accessible
- ✅ Cleaner, more efficient dashboard layout

#### 2. Dark Mode as Default Theme
**Changes:**
- Default theme changed from light to dark mode
- Theme preference saved in localStorage for persistence
- First-time users automatically see dark mode
- Toggle theme functionality preserved with localStorage sync

**Implementation:**
```typescript
// Default state changed to true
const [darkMode, setDarkMode] = useState(true);

// Initialize with dark mode if no preference saved
if (!savedTheme) {
  setDarkMode(true);
  document.documentElement.classList.add('dark');
  localStorage.setItem('theme', 'dark');
}
```

**Files Modified:**
- `src/app/admin/layout.tsx` - Dark mode default initialization
- `src/app/admin/page.tsx` - Stats grid layout (5 columns)

### 🐛 Bug Fixes

#### 3. Hotspot Voucher Count Accuracy
**Problem:** 
- Expired vouchers incorrectly counted as active users
- Total voucher count included kadaluarsa (expired) vouchers
- Misleading statistics showing higher user counts

**Solution:**
```typescript
// Only count non-expired vouchers
hotspotUserCount = await prisma.hotspotVoucher.count({
  where: {
    OR: [
      { expiresAt: null }, // No expiry date
      { expiresAt: { gte: now } } // Not yet expired
    ]
  }
});

// Active vouchers: Used AND not expired
hotspotActiveUserCount = await prisma.hotspotVoucher.count({
  where: {
    firstLoginAt: { not: null },
    OR: [
      { expiresAt: null },
      { expiresAt: { gte: now } }
    ]
  }
});
```

**Files Modified:**
- `src/app/api/dashboard/stats/route.ts` - Voucher counting logic

**Result:**
- ✅ Total vouchers: Only valid (non-expired) vouchers
- ✅ Active vouchers: Only used AND valid vouchers
- ✅ Accurate business statistics

### 📊 Features

#### 4. Real-Time Traffic Monitoring with Charts
**New Feature:**
- MikroTik interface traffic monitoring with real-time graphs
- Area charts showing Download/Upload bandwidth in Mbps
- Router and interface selection filters
- Auto-refresh every 3 seconds with 60-second history

**Implementation:**
- Created `TrafficChartMonitor.tsx` component with Recharts
- Traffic API at `/api/dashboard/traffic` using node-routeros
- Interface selection required before displaying graphs
- Supports multiple routers with dropdown selection

**Features:**
- 📈 Real-time bandwidth graphs (Download: blue, Upload: red)
- 🔄 Auto-refresh every 3 seconds
- 🎯 Router and interface selectors
- 📊 Shows last 20 data points (1 minute history)
- 💾 Traffic rate calculation (RX/TX in Mbps)
- 📱 Responsive layout with activity sidebar

**Files Added:**
- `src/components/TrafficChartMonitor.tsx` - Main component
- Updated `src/app/admin/page.tsx` - Dashboard integration

**Result:**
- ✅ Visual bandwidth monitoring
- ✅ Easy interface selection
- ✅ Historical traffic trends
- ✅ Professional monitoring UI

#### 5. Separated PPPoE and Hotspot Statistics
**Enhancement:**
- Dashboard now shows separate counts for PPPoE users and Hotspot vouchers
- Active sessions separated by type (PPPoE vs Hotspot)
- Clearer business intelligence for different service types

**Implementation:**
```typescript
// Separate user counts
pppoeUsers: { value: number, change: null },
hotspotVouchers: { value: number, active: number, change: null },

// Separate active sessions
activeSessions: { 
  value: number, 
  pppoe: number, 
  hotspot: number, 
  change: null 
}
```

**Result:**
- ✅ PPPoE Users: Separate card
- ✅ Hotspot Vouchers: Shows total and active count
- ✅ Active Sessions: Breakdown by type (using nasporttype field)

### 🔧 Technical Improvements

#### 6. MikroTik API Integration
**Implementation:**
- Router configuration uses custom API port from database (router.port field)
- Connection handling with proper error management
- Support for multiple routers in single deployment
- 5-second connection timeout for reliability

**Database Schema:**
```typescript
router.port // API port (default 8728)
router.apiPort // SSL API port (default 8729)
```

**Files Modified:**
- `src/app/api/dashboard/traffic/route.ts` - API implementation

---

## [2.3.1] - 2025-12-07

### 🐛 Bug Fixes

#### 1. Voucher Timezone Display Issues
**Problem:** 
- Voucher `createdAt` showing UTC time (05:01) instead of WIB (12:01)
- Voucher `firstLoginAt` and `expiresAt` showing +7 hours offset (19:24 instead of 12:24)

**Root Cause:**
1. **createdAt Issue:** PM2 environment missing `TZ` variable → `new Date()` returns UTC
2. **firstLoginAt/expiresAt Issue:** Prisma adds 'Z' suffix → browser interprets as UTC → adds +7 hours
3. Database stores UTC (Prisma default), FreeRADIUS stores WIB (server local time)

**Solution:**
1. **PM2 Environment Fix:**
   - Added `TZ: 'Asia/Jakarta'` to `ecosystem.config.js` env block
   - Result: `new Date()` now returns WIB time correctly

2. **API Timezone Conversion:**
   - `createdAt`/`updatedAt`: Convert from UTC to WIB using `formatInTimeZone`
   - `firstLoginAt`/`expiresAt`: Already WIB from FreeRADIUS, remove 'Z' suffix only
   
**Files Modified:**
- `ecosystem.config.js` - Added `TZ: 'Asia/Jakarta'` to env
- `src/app/api/hotspot/voucher/route.ts` - Timezone-aware date formatting

**Result:**
- ✅ Voucher Generated time: Shows correct WIB
- ✅ Voucher First Login: Shows correct WIB (no +7 offset)
- ✅ Voucher Valid Until: Shows correct WIB

#### 2. Cron Job System Improvements
**Problems Fixed:**

1. **Auto Isolir Error:** "nowWIB is not defined"
   - Missing timezone utility imports in `voucher-sync.ts`
   
2. **No Disconnect Sessions Job:** 
   - Expired vouchers remained active in RADIUS
   - No automatic CoA (Change of Authorization) disconnect

3. **Activity Log Cleanup Missing Result:**
   - Execution history showed no result message

**Solutions Implemented:**

1. **Fixed Auto Isolir:**
   - Added imports: `nowWIB, formatWIB, startOfDayWIBtoUTC, endOfDayWIBtoUTC`

2. **Created Disconnect Sessions Job:**
   - New function `disconnectExpiredVoucherSessions()`
   - Runs every 5 minutes
   - Sends CoA Disconnect-Request to RADIUS for expired vouchers
   - Records cron history with result count

3. **Fixed Activity Log Cleanup:**
   - Modified `cleanOldActivities()` to record cron_history
   - Returns message: "Cleaned X old activities (older than 30 days)"

4. **Enhanced Frontend Cron Page:**
   - Added `typeLabels` for all 10 job types
   - Added success notification handlers
   - Improved Execution History table

**Files Modified:**
- `src/lib/cron/voucher-sync.ts` - Fixed imports, added disconnect function
- `src/lib/cron/config.ts` - Added disconnect_sessions job
- `src/lib/activity-log.ts` - Modified cleanOldActivities
- `src/app/api/cron/route.ts` - Added disconnect_sessions handler
- `src/app/admin/settings/cron/page.tsx` - Enhanced UI

**Cron Jobs Status (10 Total):**
- ✅ `voucher_sync` - Sync vouchers (every 5 min)
- ✅ `disconnect_sessions` - Disconnect expired sessions (every 5 min) **NEW**
- ✅ `agent_sales` - Update agent sales (daily 1 AM)
- ✅ `auto_isolir` - Auto suspend overdue (hourly)
- ✅ `invoice_generation` - Generate invoices (daily 2 AM)
- ✅ `payment_reminder` - Payment reminders (daily 8 AM)
- ✅ `whatsapp_queue` - WA message queue (every 10 min)
- ✅ `expired_voucher_cleanup` - Delete old vouchers (daily 3 AM)
- ✅ `activity_log_cleanup` - Clean old logs (daily 2 AM)
- ✅ `session_cleanup` - Clean old sessions (daily 4 AM)

#### 3. Dashboard Statistics Not Showing (Revenue Rp 0, Users 0)
**Problem:** Dashboard menampilkan Rp 0 revenue dan 0 total users padahal ada transaksi di database.

**Root Cause:**
- Date range calculation menggunakan timezone conversion yang kompleks dan tidak konsisten
- Query menggunakan `date: { gte: startOfMonth, lte: now }` yang tidak match dengan timestamp UTC di database
- JavaScript `new Date(2025, 11, 1)` di server WIB (UTC+7) membuat "Dec 1 00:00 WIB" → internally "Nov 30 17:00 UTC"
- Transaksi stored sebagai UTC (e.g., `2025-12-06T14:15:17.000Z`) tidak ter-capture dengan benar

**Solution:**
- Simplified date boundary calculation tanpa complex offset
- Changed query dari `lte: now` menjadi `lt: startOfNextMonth` untuk consistent month boundaries
- Updated last month query menggunakan `lt: startOfMonth` instead of `lte: endOfLastMonth`
- Removed manual timezone offset calculations, let JavaScript handle local→UTC conversion

**Files Modified:**
- `src/app/api/dashboard/stats/route.ts` (Lines 24-47, 161-185, 197-207)

**Result:**
- ✅ Revenue: Rp 0 → Rp 3,000
- ✅ Total Users: 0 → 1
- ✅ Transaction Count: 0 → 1
- ✅ Date Range: Nov 30 17:00 UTC - Dec 31 17:00 UTC (Dec 1-31 WIB)

**Technical Details:**
```typescript
// Before (WRONG):
const startOfMonth = new Date(year, month, 1, 0, 0, 0);
date: { gte: startOfMonth, lte: now }

// After (CORRECT):
const startOfMonth = new Date(year, month, 1);
const startOfNextMonth = new Date(year, month + 1, 1);
date: { gte: startOfMonth, lt: startOfNextMonth }
```

#### 4. Chart Label Truncation in Category Revenue Bar Chart
**Problem:** Category names di chart "Pendapatan per Kategori" terpotong.

**Solution:**
- Increased bottom margin: `0` → `30px`
- Increased font size: `9` → `10`
- Adjusted angle: `-15°` → `-25°` untuk spacing yang lebih baik
- Added `height={60}` to XAxis component
- Added `interval={0}` to force show all labels

**Files Modified:**
- `src/components/charts/index.tsx` (CategoryBarChart component, Lines 122-133)

### 🌐 Infrastructure & DevOps

#### 3. Subdomain Migration & SSL Configuration
**Change:** Migrate dari IP:Port ke subdomain dengan HTTPS support.

**Before:**
- URL: `http://192.168.54.240:3005`
- No SSL/HTTPS
- Direct IP access

**After:**
- URL: `https://server.salfa.my.id`
- HTTPS enabled with SSL certificate
- Cloudflare CDN proxy active
- Professional domain access

**Configuration Changes:**

**Nginx Configuration** (`/etc/nginx/sites-enabled/salfanet-radius`):
```nginx
server {
    listen 80;
    server_name server.salfa.my.id;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name server.salfa.my.id;
    
    ssl_certificate /etc/ssl/server.salfa.my.id/fullchain.pem;
    ssl_certificate_key /etc/ssl/server.salfa.my.id/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location / {
        proxy_pass http://127.0.0.1:3005;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Environment Variable** (`.env`):
```bash
NEXTAUTH_URL=https://server.salfa.my.id
```

**SSL Certificate:**
- Type: Self-signed certificate
- Subject: `CN=server.salfa.my.id, O=Salfa, L=Jakarta, ST=Jakarta, C=ID`
- Valid Period: 1 year (Dec 6, 2025 - Dec 6, 2026)
- Location: `/etc/ssl/server.salfa.my.id/`

**Generate SSL Certificate Command:**
```bash
sudo mkdir -p /etc/ssl/server.salfa.my.id
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/server.salfa.my.id/privkey.pem \
  -out /etc/ssl/server.salfa.my.id/fullchain.pem \
  -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Salfa/CN=server.salfa.my.id"
sudo chmod 600 /etc/ssl/server.salfa.my.id/privkey.pem
sudo chmod 644 /etc/ssl/server.salfa.my.id/fullchain.pem
```

**Services Restarted:**
- Nginx: `sudo systemctl restart nginx`
- PM2: `sudo pm2 restart salfanet-radius --update-env`

**DNS Configuration:**
- Domain: `server.salfa.my.id`
- DNS Provider: Cloudflare
- A Records point to Cloudflare IPs (proxy enabled)
- Cloudflare SSL/TLS Mode: Full (accepts self-signed from origin)

**Impact:**
- ✅ Secure HTTPS access
- ✅ Professional domain URL
- ✅ Cloudflare CDN protection
- ✅ NextAuth working properly with HTTPS

---

## [2.3.0] - 2025-12-06

### 🔒 Security & Session Management

#### 1. Session Timeout / Auto Logout
- **Idle Detection:** Auto logout setelah 30 menit tidak aktif
- **Warning Modal:** Peringatan 60 detik sebelum logout dengan countdown timer
- **Activity Tracking:** Mouse move, keypress, scroll, click, touch reset timer
- **Tab Visibility:** Timer pause saat tab tidak aktif, resume saat aktif kembali
- **Session Max Age:** Dikurangi dari 30 hari ke 1 hari untuk keamanan

**Files:**
- `src/hooks/useIdleTimeout.ts` (NEW) - Hook untuk idle detection
- `src/app/admin/layout.tsx` (UPDATED) - Integrasi idle timeout + warning modal
- `src/app/admin/login/page.tsx` (UPDATED) - Tampilkan pesan jika logout karena idle
- `src/lib/auth.ts` (UPDATED) - Session maxAge=1 hari, updateAge=1 jam

#### 2. Fix Logout Redirect ke Localhost
- **Problem:** Logout redirect ke localhost:3000 bukan server IP
- **Root Cause:** NEXTAUTH_URL masih localhost di .env
- **Solution:** Gunakan `signOut({ redirect: false })` + `window.location.href`

#### 3. Fix Layout Tidak Muncul Saat Login
- **Problem:** Menu/sidebar kadang tidak muncul setelah login
- **Solution:** Tambah loading state, pisahkan useEffects, proper redirect handling

### 📍 Router GPS Tracking

#### 4. Router GPS Coordinates
- Tambah kolom latitude/longitude di tabel router
- Map picker untuk memilih lokasi router
- Location search dengan autocomplete
- Tampilkan router di Network Map

**Files:**
- `prisma/schema.prisma` (UPDATED) - latitude, longitude di model router
- `src/app/admin/network/routers/page.tsx` (UPDATED) - Form GPS + Map
- `src/components/MapPicker.tsx` (UPDATED) - Support router locations

### 🔌 Network Enhancements

#### 5. OLT Uplink Configuration
- Konfigurasi uplink dari router ke OLT
- Fetch interface list dari MikroTik router
- Pilih port yang digunakan untuk uplink

**Files:**
- `src/app/api/network/routers/[id]/interfaces/route.ts` (NEW) - Fetch interfaces
- `src/app/api/network/routers/[id]/uplinks/route.ts` (UPDATED) - CRUD uplinks
- `src/app/admin/network/routers/page.tsx` (UPDATED) - Modal OLT Uplink

#### 6. Network Map Enhancement
- Tampilkan uplink info di popup router
- Marker untuk router dengan GPS coordinates
- Connection lines dari router ke OLT via uplinks

#### 7. Fix DELETE API untuk OLT/ODC/ODP
- Accept `id` dari body JSON sebagai fallback (sebelumnya hanya query param)

### 📦 Installer Scripts

#### 8. vps-install-local.sh (NEW)
- Installer untuk VPS tanpa akses root langsung (pakai sudo)
- Cocok untuk: Proxmox VM, LXC Container, Local Server
- Sama fiturnya dengan vps-install.sh

### 📚 Documentation Updates
- README.md - Fitur baru, changelog v2.3
- CHAT_MEMORY.md - Session timeout, logout fix, GPS tracking
- install-wizard.html - Session security, dual installer options

---

## [1.4.1] - 2025-12-06

### 🚀 New Features

#### 1. Network Map Page
- Visualisasi semua OLT, ODC, ODP di peta interaktif
- Filter berdasarkan OLT dan ODC
- Toggle visibility untuk setiap layer (OLT, ODC, ODP, Pelanggan, Koneksi)
- Garis koneksi antar perangkat (OLT-ODC, ODC-ODP)
- Statistik total perangkat dan port
- Legenda warna untuk setiap tipe perangkat

**Files:**
- `src/app/admin/network/map/page.tsx` (NEW)
- `src/app/admin/layout.tsx` (UPDATED - added Network Map menu)
- `src/locales/id.json` (UPDATED)
- `src/locales/en.json` (UPDATED)

### 🐛 Bug Fixes

#### 2. FreeRADIUS BOM (Byte Order Mark) Issue
- Fixed UTF-16 BOM detection and removal in config files
- Added `freeradius-rest` package to installation
- Updated REST module pool settings for lazy connection (start=0)
- Improved `remove_bom()` function to handle UTF-16 LE/BE encoding

**Files:**
- `vps-install.sh` (UPDATED)
- `freeradius-config/mods-enabled-rest` (UPDATED)
- `docs/install-wizard.html` (UPDATED - added BOM troubleshooting)

**Problem:** FreeRADIUS config files (especially clients.conf) might have UTF-16 BOM when uploaded from Windows, causing silent parse failure.

**Solution:** Enhanced installer to detect and convert UTF-16 to UTF-8, and remove all types of BOM markers.

---

## [1.4.0] - 2025-12-05

### 🚀 New Features

#### 1. Sync PPPoE Users dari MikroTik
- Import PPPoE secrets dari MikroTik router ke database
- Preview user sebelum import
- Pilih user yang ingin di-import
- Hitung jarak GPS untuk setiap user
- Sinkronisasi otomatis ke tabel RADIUS (radcheck, radusergroup, radreply)

**Files:**
- `src/app/api/pppoe/users/sync-mikrotik/route.ts` (NEW)
- `src/app/admin/pppoe/users/page.tsx` (UPDATED)

#### 2. WhatsApp Template Gangguan (Maintenance-Outage)
- Tambah template baru untuk notifikasi gangguan jaringan
- Auto-create missing templates
- Variables: `{{issueType}}`, `{{affectedArea}}`, `{{description}}`, `{{estimatedTime}}`

**Files:**
- `src/app/api/whatsapp/templates/route.ts` (UPDATED)

#### 3. FTTH Network Management
- **OLT Management** (`/admin/network/olts`)
  - CRUD OLT (Optical Line Terminal)
  - Assignment ke multiple router
  - GPS location dengan Map picker
  
- **ODC Management** (`/admin/network/odcs`)
  - CRUD ODC (Optical Distribution Cabinet)
  - Link ke OLT dengan PON port
  - Filter berdasarkan OLT
  
- **ODP Management** (`/admin/network/odps`)
  - CRUD ODP (Optical Distribution Point)
  - Connect ke ODC atau Parent ODP
  - Konfigurasi port count
  
- **Customer Assignment** (`/admin/network/customers`)
  - Assign pelanggan ke port ODP
  - Pencarian nearest ODP dengan perhitungan jarak
  - Lihat port yang tersedia

**Files:**
- `src/app/admin/network/olts/page.tsx` (NEW)
- `src/app/admin/network/odcs/page.tsx` (NEW)
- `src/app/admin/network/odps/page.tsx` (NEW)
- `src/app/admin/network/customers/page.tsx` (NEW)
- `src/app/admin/layout.tsx` (UPDATED - menu)
- `src/locales/id.json` (UPDATED - translations)
- `src/locales/en.json` (UPDATED - translations)

### 🔧 Improvements

#### Auto GPS Error Handling
- Pesan error spesifik untuk setiap jenis error GPS
- Feedback sukses saat GPS berhasil
- Timeout ditingkatkan ke 15 detik

**Files:**
- `src/app/admin/network/olts/page.tsx`
- `src/app/admin/network/odcs/page.tsx`
- `src/app/admin/network/odps/page.tsx`

---

## [1.3.1] - 2025-01-06

### 🔧 Fix: FreeRADIUS Config BOM Issue

#### Problem
- FreeRADIUS tidak binding ke port 1812/1813 pada instalasi fresh di Proxmox VPS
- SQL module menampilkan "Ignoring sql" dan tidak loading
- REST module tidak loading

#### Root Cause
- File konfigurasi FreeRADIUS memiliki UTF-16 BOM (Byte Order Mark) character di awal file
- BOM (0xFFFE) menyebabkan FreeRADIUS silent fail saat parsing config
- Ini terjadi jika file di-edit di Windows atau dengan editor yang menyimpan UTF-8/16 BOM

#### Solution
1. **Added BOM removal function** di `vps-install.sh`
   ```bash
   remove_bom() {
       sed -i '1s/^\xEF\xBB\xBF//' "$1"
   }
   ```

2. **Updated install-wizard.html** dengan instruksi BOM removal
3. **Updated FREERADIUS-SETUP.md** dengan troubleshooting guide
4. **Synced freeradius-config/** folder dari VPS production yang sudah berjalan

#### Files Changed
- `vps-install.sh` - Added BOM removal after copying config files
- `docs/install-wizard.html` - Added BOM warning and removal commands
- `docs/FREERADIUS-SETUP.md` - Added BOM troubleshooting section
- `freeradius-config/sites-enabled-default` - Updated from working VPS

#### Verification
```bash
# Check if file has BOM
xxd /etc/freeradius/3.0/mods-available/sql | head -1
# Good: starts with "7371 6c" (sql)
# Bad: starts with "fffe" or "efbb bf" (BOM)

# Verify FreeRADIUS binding
ss -tulnp | grep radiusd
# Should show ports 1812, 1813, 3799
```

---

## [1.3.0] - 2025-12-03

### 🎯 Major Fix: FreeRADIUS PPPoE & Hotspot Coexistence

#### Problem
- PPPoE users with `username@realm` format were getting Access-Reject
- REST API post-auth was failing for PPPoE users (voucher not found)

#### Solution
1. **Disabled `filter_username` policy** in FreeRADIUS
   - Location: `/etc/freeradius/3.0/sites-enabled/default` line ~293
   - Changed: `filter_username` → `#filter_username`
   - Reason: Policy was rejecting realm-style usernames without proper domain

2. **Added conditional REST for vouchers only**
   - Only call REST API for usernames WITHOUT `@`
   - PPPoE users (with `@`) skip REST and get authenticated via SQL only
   ```
   if (!("%{User-Name}" =~ /@/)) {
       rest.post-auth
   }
   ```

3. **Fixed post-auth API**
   - Return success for unmanaged vouchers (backward compatibility)
   - Only process vouchers that exist in `hotspotVoucher` table

#### Files Changed
- `/etc/freeradius/3.0/sites-enabled/default` - Disabled filter_username, added conditional REST
- `src/app/api/radius/post-auth/route.ts` - Return success for unmanaged vouchers

#### Testing
```bash
# PPPoE user (with @) - should get Access-Accept
radtest 'user@realm' 'password' 127.0.0.1 0 testing123

# Hotspot voucher (without @) - should get Access-Accept
radtest 'VOUCHERCODE' 'password' 127.0.0.1 0 testing123
```

### 📦 Project Updates
- Added `freeradius-config/` directory with configuration backups
- Updated `vps-install.sh` with proper FreeRADIUS setup
- Added `docs/FREERADIUS-SETUP.md` documentation
- Updated `README.md` with comprehensive documentation
- Fresh database backup: `backup/salfanet_radius_backup_20251203.sql`

---

## [1.2.0] - 2025-12-03

### 🎯 Major Features

#### Agent Deposit & Balance System
- **Deposit System**: Agent can now top up balance via payment gateway (Midtrans/Xendit/Duitku)
- **Balance Management**: Agent balance is tracked and required before generating vouchers
- **Auto Deduction**: Voucher generation automatically deducts balance based on costPrice
- **Minimum Balance**: Admin can set minimum balance requirement per agent
- **Payment Tracking**: Track agent sales with payment status (PAID/UNPAID)

**Technical Details:**
- New table: `agent_deposits` for tracking deposits via payment gateway
- New fields: `agent.balance`, `agent.minBalance`
- Generate voucher checks balance before creating vouchers
- Webhook endpoint processes payment callbacks and updates balance
- Sales tracking includes payment status for admin reconciliation

**Workflow:**
1. Agent deposits via payment gateway → Balance increases
2. Agent generates vouchers → Balance deducted (costPrice × quantity)
3. Customer uses voucher → Commission recorded as UNPAID
4. Admin marks sales as PAID after agent payment

**Files Changed:**
- `prisma/schema.prisma` - Added agent deposit tables and balance fields
- `src/app/api/agent/deposit/create/route.ts` - NEW: Create deposit payment
- `src/app/api/agent/deposit/webhook/route.ts` - NEW: Handle payment callbacks
- `src/app/api/agent/generate-voucher/route.ts` - Added balance check and deduction
- `docs/AGENT_DEPOSIT_SYSTEM.md` - NEW: Complete implementation guide

**Database Changes:**
```sql
-- Add balance fields to agents
ALTER TABLE agents ADD balance INT DEFAULT 0;
ALTER TABLE agents ADD minBalance INT DEFAULT 0;

-- Create deposits table
CREATE TABLE agent_deposits (...);

-- Add payment tracking to sales
ALTER TABLE agent_sales ADD paymentStatus VARCHAR(191) DEFAULT 'UNPAID';
ALTER TABLE agent_sales ADD paymentDate DATETIME;
ALTER TABLE agent_sales ADD paymentMethod VARCHAR(191);
```

## [1.1.0] - 2025-12-03

### 🎯 Major Features

#### Sessions & Bandwidth Monitoring
- **Real-time Bandwidth**: Sessions page now fetches live bandwidth data directly from MikroTik API instead of relying on RADIUS interim-updates (which weren't being sent)
- **Session Disconnect**: Fixed disconnect functionality to use MikroTik API directly instead of CoA/radclient
- **Port Configuration**: Uses `router.port` field for MikroTik API connection (the forwarded port)

**Technical Details:**
- Hotspot: Uses `/ip/hotspot/active/print` for sessions, `/ip/hotspot/active/remove` for disconnect
- PPPoE: Uses `/ppp/active/print` for sessions, `/ppp/active/remove` for disconnect
- Traffic: Real-time bytes from `bytes-in` and `bytes-out` fields

**Files Changed:**
- `src/app/api/sessions/route.ts` - Added real-time bandwidth fetching
- `src/app/api/sessions/disconnect/route.ts` - Replaced CoA with MikroTik API

#### GenieACS Integration
- **Device Parsing**: Fixed GenieACS device data parsing to correctly extract device information
- **Virtual Parameters**: Properly reads VirtualParameters with `_value` property
- **Debug Endpoint**: Added `/api/settings/genieacs/debug` for troubleshooting

**Technical Details:**
- Device ID fields use underscore prefix: `_deviceId._Manufacturer`, `_deviceId._SerialNumber`
- Virtual Parameters format: `VirtualParameters.rxPower._value`, `VirtualParameters.ponMode._value`
- OUI extraction from device ID format: `DEVICE_ID-ProductClass-OUI-SerialNumber`

**Files Changed:**
- `src/app/api/settings/genieacs/devices/route.ts` - Fixed data extraction
- `src/app/api/settings/genieacs/debug/route.ts` - New debug endpoint

### 🐛 Bug Fixes

1. **Sessions Page**
   - Fixed: Bandwidth showing "0 B" for active sessions
   - Fixed: Disconnect button showing success but not actually disconnecting
   - Root cause: Using wrong port field (`apiPort` instead of `port`)

2. **GenieACS Page**
   - Fixed: Table columns showing empty/undefined values
   - Fixed: Device manufacturer, model, serial number not displaying
   - Root cause: Wrong path for accessing device properties

3. **Agent Voucher Generation**
   - Fixed: Vouchers not linked to agent account
   - Root cause: `agentId` not being saved when creating voucher
   - Impact: Agent sales tracking now works correctly

4. **GPS Auto Location**
   - Fixed: GPS Auto error on HTTP sites
   - Added: HTTPS requirement check with friendly error message
   - Added: Better error handling for permission denied, timeout, etc.
   - Files: `src/app/admin/pppoe/users/page.tsx`, `src/components/UserDetailModal.tsx`

### 📁 File Structure

```
Changes in this release:
├── src/app/api/sessions/
│   ├── route.ts              # Updated - real-time bandwidth
│   └── disconnect/route.ts   # Updated - MikroTik API disconnect
├── src/app/api/settings/genieacs/
│   ├── devices/route.ts      # Updated - device data parsing
│   └── debug/route.ts        # New - debug endpoint
└── README.md                 # Updated - changelog section
```

### 🔧 Configuration Notes

**Router Configuration:**
- `port` field: Used for MikroTik API connection (forwarded port, e.g., 44039)
- `apiPort` field: Legacy, not used for direct API calls
- `ipAddress` field: Public IP for API connection
- `nasname` field: Used for RADIUS NAS identification

**MikroTik Setup:**
- Ensure API service is enabled on router
- Forward API port (8728) to public IP if needed
- API user must have read/write permissions

---

## [1.0.0] - 2025-12-01

### Initial Release
- Full billing system for RTRW.NET ISP
- FreeRADIUS integration (PPPoE & Hotspot)
- Multi-router/NAS support
- Payment gateway integration (Midtrans, Xendit, Duitku)
- WhatsApp notifications
- Network mapping (OLT, ODC, ODP)
- Agent/reseller management
- Role-based permissions (53 permissions, 6 roles)
