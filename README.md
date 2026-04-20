# NeoSapien Intern Assessment — Cross-Device File Sharing (Flutter)

Mobile-only anonymous file transfer: **short-code addressing**, **Supabase** relay (Postgres + Storage + Realtime), optional **same-subnet** acceleration on Android. Submitted for the **NeoSapien Mobile / Flutter Developer Intern** assessment (see internal brief for full rubric).

---

## Submission deliverables (checklist)

| Deliverable | Where / how |
|-------------|-------------|
| **Installable Android build** | `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` (use signed build if reviewers require it). |
| **Source code** | This repository: [github.com/aavvvacado/NeoSapien-Assignment-](https://github.com/aavvvacado/NeoSapien-Assignment-) (or zip via Google Drive if preferred). |

| **README** | This file: run instructions, devices tested, architecture, transport rationale, platform channels, **Section 3** coverage, limitations, AI usage. |

**iOS:** This submission is **Android-first** (see limitations). iOS is not the primary evaluated surface.

---

## How to run locally

### Prerequisites

- Flutter SDK matching `pubspec.yaml` (`sdk: ^3.10.4`).
- Android toolchain for device/emulator builds.
- Supabase project with **Anonymous Auth** enabled.

### Backend (Supabase)

1. Create a project at [supabase.com](https://supabase.com).
2. **Authentication → Providers → Anonymous** — enable anonymous sign-in.
3. In **SQL Editor**, run `docs/supabase_setup.sql` (tables, RLS, realtime publication, storage bucket seed).
4. **Storage:** create a **private** bucket named `transfers` (or set `SUPABASE_STORAGE_BUCKET` in `.env` to match).

### App configuration

1. Copy **`.env.example`** → **`.env`** and set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_STORAGE_BUCKET`.
2. Or use defines only:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

If Supabase env is missing, the app may run in an **unconfigured** mode without live transfers.

### Build APK

```bash
flutter build apk --release
```

---



## Architecture (client → relay → storage)

```text
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter (Material + BLoC)                    │
│   Pages ◄──► BLoC ◄──► Use cases ◄──► Repositories               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌───────────────┐     ┌─────────────────────┐   ┌───────────────────┐
│ Supabase Auth │     │ Supabase Postgres    │   │ Supabase Storage   │
│ (anonymous)   │     │ users, short_codes,  │   │ private bucket     │
└───────────────┘     │ transfers, files, RLS│   │ `transfers/` keys  │
        │             └──────────┬───────────┘   └─────────┬─────────┘
        │                        │ Realtime + REST        │ HTTPS
        └────────────────────────┴────────────────────────┘
                                 │
                     TLS (HTTPS + WSS) to Supabase

        Optional (Android): LAN peer path
        └─► UDP multicast discovery + TCP (see NearbyTransportService)
            Falls back to cloud if discovery/transfer fails.
```

**Aggregate transfer lifecycle:**  
`initiated` → `uploading` → `uploaded` → `notifying` → `downloading` → `completed` | `failed` | `cancelled` | `expired`

**Layers:** UI → BLoC → use cases → repositories → `SupabaseTransferDataSource` / identity datasource → **Android `MethodChannel`** `neosapien/native_bridge` (`MainActivity.kt`) for picker, MediaStore saves, notifications, foreground transfer UI.

---

## Transport choice and rationale

| Requirement | Approach |
|---------------|----------|
| Works across distance / NAT | **Supabase** as relay: Postgres for metadata and state; **Storage** for binaries. No assumption of same LAN. |
| Near-real-time when online | **Postgres Realtime** subscriptions + **broadcast channels** (“pokes”) to prompt snapshot refresh within a couple of seconds. |
| Binaries | **HTTPS** upload stream; **signed URLs** for download. |
| **★ TLS** | All Supabase client traffic uses **TLS** (HTTPS + secure WebSocket). |
| Why not WebRTC as primary | WebRTC minimizes latency for peer media but adds signaling/NAT complexity. Here the priority is a **clear relay model**, DB-backed progress, and simpler review defense while still meeting “across the world.” |

**★ Offline recipient:** Rows stay in Postgres until **`ttl_expires_at`** (default **24 hours**). Behavior = **queue with TTL** (not reject-on-offline).

**★ Incoming while app is closed (Android):** **Notification** + optional deep link (`transfer_id` consumed on cold start). Not a separate **FCM** product integration in this repo.

---

## Short codes: collisions, ambiguity, invalid codes

### Issued codes (generation)

- **Length:** `AppConstants.shortCodeLength` (**8**).
- **Alphabet:** `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` — **excludes I, O, 0, 1** to avoid visual ambiguity.
- **★ Collisions:** `short_codes.code` is **PRIMARY KEY**; `users.short_code` is **UNIQUE**. Client retries generation on rare collision; cache restore uses `_restoreOrReassignCode` in `SupabaseIdentityDataSource`.

### Typed recipient codes (sender)

1. **Normalize:** `trim()` + `toUpperCase()` before any network call.
2. **★ Syntax gate (fail fast):** `ShortCodeInputValidator` enforces **6–8** characters, each in the same alphabet as generation. Rejects impossible codes (e.g. **`0`/`1`/`I`/`O`**, wrong length) **before** Supabase — reduces enumeration noise and bad UX.
3. **★ Server lookup:** `short_codes` table lookup; empty or null `uid` → **`invalid_recipient_code`** → clear “Invalid recipient code” in UI.
4. **Stale transfer guard:** Changing the recipient field **clears** `activeTransferId` so the app **never** reuses a previous transfer’s id after the user edits the code (fixes accidental send to wrong recipient).

**Not implemented:** word-style handles (`swift-otter-42`) — alphanumeric only.

### Self-send

**Blocked** in `createTransfer` (`self_send_not_allowed`) with an explicit user message.

### Identity persistence (app data cleared / reinstall)

- **Supabase anonymous user** + rows in `users` / `short_codes` live in the project.
- **Local cache** (`SharedPreferences`) stores last short code for fast restore.
- **Tradeoff:** Clear app data → new anonymous session → typically **new code** unless reclaim path succeeds; documented for reviewers.

---

## Platform channel bonus (not Pigeon)

| Topic | Detail |
|--------|--------|
| **Mechanism** | **`MethodChannel`** `neosapien/native_bridge` → **`MainActivity.kt`**. |
| **Implemented** | `ACTION_OPEN_DOCUMENT` multi-pick, **MediaStore** / Downloads-style save paths, **ACTION_SEND** share sheet, foreground transfer notification wiring, incoming / heads-up notifications, multicast lock helper, optional battery settings intent, free-space query. |
| **With more time** | **Pigeon** for typed contracts; **iOS** parity (native document picker + Photos/Files save) instead of `file_picker` fallbacks. |

---

## Section 3 — Edge cases (assessment rubric)

Starred **★** items are those the brief marks as must-work in the build; others are design / partial / documented gaps.

### Identity and addressing

| Item | Status | Notes |
|------|--------|--------|
| Native file picker (Android) | **Handled** | `ACTION_OPEN_DOCUMENT` in Kotlin; bytes staged via cache paths. |
| Native picker (iOS) | **Partial** | `file_picker` / fallbacks — not custom `UIDocumentPickerViewController`. |
| Save to gallery / Downloads | **Handled (Android)** | MediaStore + relative paths; collision-safe names. |
| Native share sheet | **Handled (Android)** | MethodChannel share. |
| Background transfer | **Partial** | Android **foreground service** hooks; not full iOS URLSession background. |
| Nearby transport | **Partial** | Multicast + TCP same-subnet path, **cloud fallback**; not Wi‑Fi Direct / BLE. |
| **★ Short-code collisions** | **Handled** | DB uniqueness + client retry + restore/reassign. |
| **★ Invalid recipient code** | **Handled** | Syntax validation + `short_codes` lookup; stale `activeTransferId` cleared on code change. |
| Ambiguous characters | **Handled** | Excluded from alphabet; input validator rejects illegal chars. |

### Transport, files, device conditions

| Item | Status | Notes |
|------|--------|--------|
| **★ Recipient offline** | **Handled** | Queue until TTL (24h). |
| **★ Network drops** | **Partial** | Retries + backoff; **per-file** resume when file row is complete **with** `local_saved_path` on receiver; not full HTTP ranged chunk resume for one partial object. |
| Sender killed mid-upload | **Partial** | WorkManager worker is **scaffold** only. |
| Duplicate delivery | **Handled** | Dedupe by **transfer id** / file row ids in UI notifications. |
| Metered / cellular | **Handled** | Large transfer warnings (pick vs send thresholds — see code). |
| **★ Large files** | **Handled** | **1 GB** ceiling; streaming upload/download + SHA-256 streaming. |
| **★ Multiple files** | **Handled** | Per-file + aggregate progress; one file failure does not abort entire policy (see datasource). |
| Unusual MIME / extensionless | **Handled (Android)** | Native MIME map + fallbacks. |
| Empty files | **Handled** | Filtered at picker. |
| Filename conflicts on save | **Handled** | Unique name resolution in download path. |
| Corrupted transfer | **Handled** | SHA-256 verify vs stored hash. |
| **★ Permission denial** | **Partial** | Android degrades gracefully in several paths; iOS not primary. |
| Scoped storage | **Handled (Android)** | MediaStore / app dirs — not arbitrary public paths. |
| OEM battery killers | **Acknowledged** | Settings shortcut on Android; full mitigation not claimed. |
| App killed under memory pressure | **Partial** | Best-effort recovery worker placeholder. |
| **★ Incoming while app closed** | **Partial** | Notifications + deep link (Android); not FCM stack. |
| **★ TLS** | **Handled** | Supabase client. |
| Content privacy / abuse | **Documented** | Anyone with a code can **initiate** a transfer; receiver gets **accept (download) / decline** on incoming UI and notifications; light rate-limit delay on send. **Not** a persistent block list or contact-only send model. |
| At-rest on relay | **Documented** | Supabase Storage + project settings; brief-level AES claims depend on provider. |
| Short-code guessability | **Mitigated** | **8** chars from **32-symbol** alphabet (≈ **41 bits**). |
| Cancel long operations | **Handled** | Cancel transfer path. |
| Errors user-actionable | **Handled** | `AppErrorMapper` / `TransferUserMessages` — avoid raw `Exception: null`. |
| State survives rotation / background | **Partial** | BLoC + DB state; full process-death replay not complete. |

### Scope discipline (what we stubbed or skipped)

OK to stub per brief: **analytics, billing, polished onboarding copy**. **Cross-platform parity:** **Android shipped properly**; iOS not half-shipped as primary. **Not built:** messaging, read receipts, groups.

---

## Known bugs and limitations (honesty for reviewers)

We would rather lose polish points than oversell stability. These are real gaps in **this** tree.

- **Android-first:** iOS lacks the Kotlin `MethodChannel` depth; several flows lean on `file_picker` and partial paths.
- **Process death / background:** `TransferRecoveryWorker` is largely **scaffold**—do not assume uploads or downloads **fully** resume after the OS kills the app mid-transfer.
- **HTTP resume:** Retries are oriented around **whole Storage objects** and completed file rows, not ranged/chunked resume inside a single partial upload.
- **Notifications without FCM:** Incoming handling uses **local** notification wiring after the app has run; there is **no** Firebase Cloud Messaging pipeline, so reliability when the app has never been opened on the receiver is not something we claim.
- **State after aggressive kill:** BLoC + Supabase state cover normal rotation and backgrounding, but **full** “reopen after death and pick up exactly where the UI left off” is only **partial** (see Section 3 table).
- **LAN acceleration:** Same-subnet path is **multicast discovery + TCP**, not Wi‑Fi Direct or BLE; some networks, VPNs, or OEM Wi‑Fi policies can block or flake discovery—we **fall back to cloud**, but LAN is best-effort.
- **Word-style codes:** Not implemented (alphanumeric short codes only).
- **Abuse / privacy:** Anonymous codes mean anyone who guesses or obtains a code can **start** a transfer toward that user; the receiver still **chooses accept (download) or decline** per incoming transfer (`IncomingTransferBloc` / incoming UI). Rate limiting remains **light**; there is **no** long-lived block list or “only these senders” allow list.

---

## AI tool usage

- **Tools:** **Cursor** (agent / chat in the IDE) and **Google Gemini** for a large share of **UI layout**, **screen structure**, and **boilerplate** (feature folders, BLoC wiring, repetitive widgets, early README drafting).
- **What stayed human / we overrode the model on:** Anything correctness-critical or easy for an LLM to get subtly wrong: **streaming upload/download**, **SHA-256** and verify paths, **Kotlin `MethodChannel`** (`MainActivity.kt`) and Android notifications / foreground hooks, **Supabase** datasource logic (including transfer lifecycle, dedupe, and edge cases we fixed while integrating), **short-code** normalization/validation and **`activeTransferId`** clearing when the recipient field changes, **`AppErrorMapper` / user-facing messages**, and **`docs/supabase_setup.sql`** (tables, RLS, Realtime). When a suggestion would have been a shortcut (e.g. “just read the whole file into memory” or hand-wavy error handling), we **rejected or rewrote** it for this assessment.

---

## License / attribution

Assessment submission for NeoSapien. **Do not publish** the employer’s confidential assessment brief text.
