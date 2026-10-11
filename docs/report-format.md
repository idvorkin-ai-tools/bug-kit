# Report format

[Back to BugKit](../README.md).

`Documents/bugs.jsonl` has one line per report, newest last. Keys are sorted, and paths are relative to Documents.

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
| `id` | UUID; the key for the seen-store, the issue marker and the inbox |
| `reported_at` | ISO 8601 UTC with milliseconds |
| `app`, `bundle`, `build`, `commit` | which build; `commit` is from `BugKitCommit`, else "unknown" |
| `device` | hardware model and OS, never the device's user-given name |
| `screen`, `note` | where it happened, and what the user typed |
| `log`, `session_t_ms` | the session log's path and the moment in it |
| `screenshot`, `folder`, `files` | the screenshot, the report's folder `bugs/<yyyyMMdd-HHmmss>[-n]`, and the app's extra files |
| `context` | whatever the app attaches, as JSON values |

Optional UI diagnostics add `interactions.jsonl` and `accessibility.json` to the report folder and `files` array. Automatic listener crash records use a stable `crash:<sha256>` ID, `kind: crash`, and a local diagnostic-file path; they do not modify the device’s `bugs.jsonl`. See [listener operations](ops/listener.md#automatic-crash-discovery).
