# RaceTimer iOS App — Implementation Plan

## 1. Problem & Goals

Build an iOS app that times riders on a downhill mountain bike race course.
Multiple "race officials" each run the app on an iPhone:

- **Start official** — sends riders off and starts each rider's timer.
- **Checkpoint officials** (0+) — record the instant each rider passes their checkpoint.
- **Finish official** — records the instant each rider crosses the finish.

At the end of the session, all devices sync over the local network, the app
reconciles checkpoint events to riders, and computes per-rider split and total
times. The app must support manual correction of mis-assigned, missed, or
spurious checkpoints, and handle the rare case where one rider passes another.

## 2. Key Decisions (confirmed)

| Area | Decision |
|---|---|
| Platform | iPhone only, latest 2–3 iOS versions, portrait-first |
| Tech stack | SwiftUI + Swift Concurrency, SwiftData for persistence |
| Sync between devices | Peer-to-peer via MultipeerConnectivity (offline at venue) |
| Roster | Pre-loaded roster supported, plus on-the-fly additions |
| Checkpoint capture UX | Auto-assign to next-expected rider with one-tap override |
| Course model | Single fixed course per session, configured at setup |
| Multiple runs | Supported per rider, treated as independent (no aggregation in v1) |
| Time sync | Device wall-clock; warn user if devices appear desynced |
| Export | CSV, shareable PDF, formatted email |

## 3. Domain Model

```
Session
  id, name, date, courseName, notes
  checkpoints: [Checkpoint]   // ordered, includes implicit Start (index 0) and Finish (last)
  riders:      [Rider]
  runs:        [Run]

Checkpoint
  id, indexInCourse, name (e.g. "Split 1", "Finish")

Rider
  id, firstName, bibNumber?, lastName?, category?, notes?
  // At least one of {bibNumber, lastName} should be present for disambiguation,
  // but only firstName is strictly required by the model.

Run
  id, riderId, status (scheduled|started|finished|incomplete|dnf|dns)
  events: [CheckpointEvent]
  // The start time is simply the CheckpointEvent at the start checkpoint
  // (index 0). No separate startTimestamp field on Run.

CheckpointEvent
  id, runId, checkpointId, timestamp (Date, UTC),
  recordedByDeviceId, autoAssignedRiderId?, manualOverride: Bool,
  ignored: Bool, deleted: Bool, note?

Device / Official
  deviceId (stable UUID), displayName, role (start|checkpoint|finish|observer),
  assignedCheckpointId?
```

Invariants:
- A `Run`'s effective times are derived from its non-deleted, non-ignored
  `CheckpointEvent`s sorted by `checkpointId.index`.
- A run is `incomplete` if any non-final checkpoint is missing and not ignored,
  OR the finish event is missing.
- Reordering riders at a checkpoint = reassigning the `runId` on a
  `CheckpointEvent` (via override).

## 4. Architecture

```
App
├── Models (SwiftData @Model classes mirroring §3)
├── Services
│   ├── SessionStore         (SwiftData CRUD, derived results)
│   ├── ClockService         (now(), drift detection vs peers)
│   ├── PeerSyncService      (MultipeerConnectivity transport)
│   ├── SyncEngine           (CRDT-ish merge: see §6)
│   ├── ExportService        (CSV, PDF via PDFKit, email via MFMailComposeVC)
│   └── RoleCoordinator      (which role this device is acting as)
├── Features (SwiftUI views + view models)
│   ├── SessionSetup         (create/load session, define course, manage roster)
│   ├── RoleSelection        (pick role + checkpoint)
│   ├── StartLine            (queue, "Send Rider" button, start timer)
│   ├── CheckpointCapture    (big "Pass" button, auto-assign + override sheet)
│   ├── FinishLine           (variant of CheckpointCapture for the last checkpoint)
│   ├── LiveResults          (running list of riders, splits, status)
│   ├── ReviewAndCorrect     (reorder, reassign, delete, ignore, mark incomplete)
│   └── Export               (CSV / PDF / email share)
└── App entry & navigation
```

## 5. UX Flows

### 5.1 Start official
1. Queue shows next-up riders (from roster + ad-hoc adds).
2. Big "Send Rider" button. Optional countdown (configurable, e.g. 5s).
3. On tap, creates a `Run` in `started` state and records a `CheckpointEvent`
   at the start checkpoint (index 0) with the current timestamp. The start
   event is the run's "start time" — no separate field on `Run`.
4. Visible interval-since-last-start timer encourages spacing (configurable
   minimum gap warning, e.g. 30s).

### 5.2 Checkpoint / finish official
1. On role selection, picks which checkpoint they're staffing.
2. Main screen: large "Rider Passed" button + a panel showing the next 2–3
   expected riders (computed from start times + a moving average pace).
3. On tap: timestamp captured immediately, auto-assigned to top expected rider.
4. A toast/undo affordance lets the official tap the captured event to
   reassign to a different rider (override) within a few seconds — useful for
   handling passes.
5. Long-press / swipe on a recent event → delete (spurious capture).

### 5.3 Review & correct (any official, but typically end-of-session)
- Per-rider timeline view of all checkpoint events.
- Drag to reorder, tap to reassign rider, swipe to delete or ignore an event.
- Per-run status toggle: `complete | incomplete | dnf | dns`.

### 5.4 Export
- Choose runs (all / by category / individual).
- Generate CSV (rider, splits, total, status).
- Generate PDF results sheet (PDFKit).
- Compose pre-filled email with attachments via `MFMailComposeViewController`.

## 6. Sync & Conflict Resolution

Peer-to-peer over MultipeerConnectivity using a shared "session bonjour
service". Each device advertises its `deviceId` + role.

**Data model for sync:** each mutation is an event with
`(deviceId, lamportClock, wallClockTimestamp)`. Events:

- `RiderUpserted`
- `RunCreated`            (carries riderId; start time comes from the first CheckpointEvent)
- `CheckpointEventRecorded`
- `CheckpointEventEdited`  (reassign rider, delete, ignore)
- `RunStatusChanged`

Merge rules:
- All events are append-only in a per-device log; the local SwiftData store is
  a materialized projection.
- Last-writer-wins per `(entityId, field)` using Lamport clock, ties broken by
  `deviceId`.
- Deletes are tombstones (so re-sync doesn't resurrect).

Sync triggers:
- Continuous while peers are connected (best-effort live updates so other
  officials can see live results).
- Explicit "Sync now" action and an end-of-session "Final sync" wizard that
  shows which devices have / haven't merged yet.

## 7. Time Sync

- Use `Date()` (wall-clock) for all timestamps.
- On peer connect, exchange a small `(sentAt, receivedAt, replyAt)` ping
  exchange (NTP-style) to estimate skew; if any peer skew > threshold (e.g.
  500 ms), surface a non-blocking warning banner.
- Do not silently rewrite timestamps; only warn. Officials can manually adjust
  in Review if needed.

## 8. Persistence

- SwiftData store on each device, persisted across launches.
- One store, multiple `Session`s; the active session is selected on launch.
- Event log table is the source of truth for sync; projected entities are
  rebuilt deterministically from the log when needed.

## 9. Testing Strategy

- Unit tests for:
  - Results computation (splits, totals, status derivation).
  - Auto-assign expected-rider algorithm.
  - SyncEngine merge with shuffled event orderings (property-style).
  - Edit operations (delete/ignore/reassign) producing correct projections.
- Snapshot tests for CSV/PDF output.
- Manual multi-device test plan (2–3 iPhones) for peer sync.

## 10. Milestones (todos tracked in SQL)

1. **m1-skeleton** — Xcode project, SwiftUI app shell, navigation scaffold.
2. **m2-models** — SwiftData models + event log + projection logic.
3. **m3-session-setup** — Create session, define course/checkpoints, manage roster.
4. **m4-role-selection** — Pick role + checkpoint per device.
5. **m5-start-line** — Start-line UI, send-rider flow, run creation.
6. **m6-checkpoint-capture** — Capture + auto-assign + override UX.
7. **m7-results-engine** — Compute splits/totals/status from event log.
8. **m8-live-results** — Read-only live results view.
9. **m9-review-correct** — Reorder, reassign, delete, ignore, status toggle.
10. **m10-peer-sync** — MultipeerConnectivity transport + SyncEngine merge.
11. **m11-time-sync-check** — Peer skew detection + warning banner.
12. **m12-export** — CSV, PDF, email.
13. **m13-tests** — Unit + snapshot tests per §9.
14. **m14-polish** — Empty states, error handling, accessibility, haptics.

## 11. Open Questions / Future

- Apple Watch companion for checkpoint capture? (out of v1 scope)
- Multi-course / multi-stage sessions? (deferred)
- Cloud backup / cross-session history? (deferred)
- Live spectator view (web)? (deferred)
