# Copilot Instructions — RaceTimer

## Project overview

iOS app for timing riders on a downhill mountain bike race course. Multiple iPhones sync peer-to-peer over MultipeerConnectivity — one device per race official (start, checkpoint, finish). No internet required at the venue.

## Tech stack

- **SwiftUI** + **Swift Concurrency** (async/await, actors)
- **SwiftData** for on-device persistence
- **MultipeerConnectivity** for peer-to-peer sync
- **PDFKit** for results export; `MFMailComposeViewController` for email
- iPhone only, portrait-first, latest 2–3 iOS versions

## Build & test

```sh
# Build
xcodebuild -scheme RaceTimer -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run all tests
xcodebuild -scheme RaceTimer -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test class or method
xcodebuild -scheme RaceTimer -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RaceTimerTests/SyncEngineTests test
xcodebuild -scheme RaceTimer -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RaceTimerTests/SyncEngineTests/testMergeLastWriterWins test
```

## Architecture

```
App
├── Models/          SwiftData @Model classes (Session, Rider, Run, Checkpoint, CheckpointEvent)
├── Services/
│   ├── SessionStore         SwiftData CRUD + derived results
│   ├── ClockService         Wall-clock timestamps + peer drift detection
│   ├── PeerSyncService      MultipeerConnectivity transport layer
│   ├── SyncEngine           CRDT-style merge of append-only event logs
│   ├── ExportService        CSV, PDF, email generation
│   └── RoleCoordinator      Tracks which role this device is acting as
├── Features/        SwiftUI views + view models, one folder per feature
│   ├── SessionSetup/
│   ├── RoleSelection/
│   ├── StartLine/
│   ├── CheckpointCapture/
│   ├── FinishLine/
│   ├── LiveResults/
│   ├── ReviewAndCorrect/
│   └── Export/
└── App entry & navigation
```

## Domain model

- **Session** → has ordered **Checkpoint**s (index 0 = start, last = finish), **Rider**s, and **Run**s.
- **Run** → belongs to a Rider; its start time is the `CheckpointEvent` at checkpoint index 0 (no separate `startTimestamp` field).
- **CheckpointEvent** → the atomic unit of timing data. Has `timestamp`, `autoAssignedRiderId`, `manualOverride`, `ignored`, `deleted` flags.
- A Run's effective times are derived from its non-deleted, non-ignored CheckpointEvents sorted by checkpoint index.
- Deletes are tombstones, not physical deletes.

## Sync design

All mutations are modelled as append-only events in a per-device log. The SwiftData store is a materialized projection of the log.

Event types: `RiderUpserted`, `RunCreated`, `CheckpointEventRecorded`, `CheckpointEventEdited`, `RunStatusChanged`.

Each event carries `(deviceId, lamportClock, wallClockTimestamp)`. Merge rule: **last-writer-wins** per `(entityId, field)` using Lamport clock; ties broken by `deviceId`.

## Key conventions

- **Timestamps**: always `Date()` (wall-clock UTC). Never silently rewrite timestamps — only warn on detected skew (>500 ms between peers).
- **Auto-assign**: checkpoint captures auto-assign to the next expected rider (based on start order + moving average pace). Always provide a one-tap override.
- **Run status enum**: `scheduled | started | finished | incomplete | dnf | dns`.
- **Rider identity**: `firstName` is required; at least one of `{bibNumber, lastName}` should be present for disambiguation.
- **Feature structure**: each feature folder contains its SwiftUI views and corresponding view models. Keep views thin — business logic goes in Services or view models.

## Implementation
- When fixing bugs, ensure that tests exist which reproduce the behavior before implementing.
- After implementation, verify by running tests.

## Testing

- Unit tests for: results computation, auto-assign algorithm, SyncEngine merge (property-style with shuffled event orderings), edit operations producing correct projections.
- Snapshot tests for CSV/PDF output.
- Manual multi-device test plan for peer sync.

## Implementation plan

See `PLAN.md` at the repo root for the full implementation plan, domain model details, milestones, and open questions.
