# Report format

[Back to BugKit](../README.md).

`bugs.jsonl` under the storage root has one line per report, newest last. Keys are sorted, and paths are relative
to that root. The default root is app-container `Documents` on iOS/watchOS and app-specific Application Support on
macOS; see [macOS storage](integration.md#macos-storage-and-command-line-tools).

```json
{"app":"Exercise Analyzer","build":"1.0 (42)","bundle":"com.example.app","commit":"ab4f1a5",
 "context":{"exercise":"kettlebell-swing","playhead":12.5},"device":"iPhone18,1 iOS 27.0",
 "files":["bugs/20261010-143000/clip.mov"],"folder":"bugs/20261010-143000",
 "id":"6F1C…","log":"logs/swing-20261010-150000.jsonl","note":"counted 1 rep, there were 13",
 "reported_at":"2026-10-10T14:30:00.250Z","screen":"playback","screenshot":"bugs/20261010-143000/screen.png",
 "session_t_ms":84442}
```

(The example is wrapped here. On disk each report is one line.)

| Field | Meaning |
|---|---|
| `source`, `reason` | Optional automatic-report fields: `source: "auto"` and a stable app-defined reason. Omitted from manual reports. Automatic reports have no screenshot by default. |
| `id` | UUID; the key for the seen-store, the issue marker and the inbox |
| `reported_at` | ISO 8601 UTC with milliseconds |
| `app`, `bundle`, `build`, `commit` | which build; `commit` is from `BugKitCommit`, else "unknown" |
| `device` | hardware model and OS, never the device's user-given name |
| `screen`, `note` | where it happened, and what the user typed |
| `log`, `session_t_ms` | the session log's path and the moment in it |
| `screenshot`, `folder`, `files` | the screenshot, the report's folder `bugs/<yyyyMMdd-HHmmss>[-n]`, and the app's extra files |
| `context` | whatever the app attaches, as JSON values |

Optional UI diagnostics add `interactions.jsonl` and `accessibility.json` to the report folder and `files` array. Automatic listener crash records use a stable `crash:<sha256>` ID, `kind: crash`, and a local diagnostic-file path; they do not modify the device’s `bugs.jsonl`. See [listener operations](ops/listener.md#automatic-crash-discovery).

## Optional CloudKit envelope

The private `BugKitReport` record ID is the report UUID. Fields: `bundle` (String), `reportedAt` (Date), and
`payload` (CKAsset). Asset JSON has `version: 1`, the existing Codable `report`, and `files`, a mapping of
storage-root-relative paths to base64 file data. Declared files, screenshot and log must match the envelope's
paths; absolute/traversing/symlink-escaping paths are rejected. Limits are 100 files, 20 MB raw evidence and
30 MB encoded asset. Local reports and evidence remain unchanged. Mac imports publish `<UUID>/report.json`,
`<UUID>/files.json` (path → byte length) and `<UUID>/Documents/<path>` atomically; incomplete or mismatched
imports stay pending. Container/account bindings and upload receipts are local state, never report fields.
