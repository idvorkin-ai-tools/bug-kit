# Pairing

Part of the [BugKit stories](README.md). Igor, 2026-10-18: *"Then I can put pairing code everywhere and have
background authentication"*, then *"drop the key after 1 month; re-auth is easy if it's just a link from Larry on
Telegram"* and *one key per device for every service*. A device pairs once from a link Larry sends; every app of
Igor's on that device then uses the same key for every service on his box, until it expires 30 days later. The
contract with Larry's side (the codes, the redeem, the device registry) is in the design,
`~/tmp/agent/notes/2026-10-18-pairing-and-background-auth.md` §7. BugKit holds the client half: the link, the
redeem, the stored device and the words an app shows. No UI.

---

### User Story 040:

- **Summary:** Pair this device from a link Larry sends
- **From:** think-a-card-trainer's practice ledger (its story 070), the first app to use it
- **Status:** the client half is implemented in 64c0a7e (`PairingLink`, `PairingClient`, `PairedDevice`,
  `KeychainPairedDeviceStore`, `MemoryPairedDeviceStore`).
  - Verified on the host by `PairingTests`:
    - the link's code and https host are read, a link to any host but the app's box or any other link is refused,
      and neither the logged link nor the printed one has the code;
    - the redeem posts the code, the device and what it replaces;
    - expired, used, unknown, too many, unreachable and malformed are each their own error with its words, and an
      answer naming a service off the box is malformed;
    - the device round-trips and never prints its key.
  - Not yet run: the Keychain item in the shared access group (a device check in the first app), and a redeem
    against the box (waits on Larry's `/pair` routes).

#### Use Case:
- **As someone** who uses several of my own apps on one phone
- **I want to** tap one link Larry sends me on Telegram and have every one of those apps signed in
- **so that** I never paste a URL or a key again, and no key ever sits in a chat

#### Acceptance Criteria:
- **Scenario:** Pairing from the link
- **Given:** Larry sent `https://<box>/pair/<code>` and the box's page opened `<scheme>://pair?code=…&host=…` in one
  of my apps
- **When:** the app redeems the code
- **Then:**
  - the device gets its own key with its name, its expiry and the services it opens, kept in one Keychain item on
    this device only, which every app of mine on the device reads;
  - pairing again replaces the device's old key, and the box is told which one it replaces;
  - nothing logged or printed carries the code or the key: the link is logged with its code redacted.

- **Scenario:** A link that no longer works
- **Given:** the link expired (10 minutes), was used already, or is unknown
- **Then:** the app says so in plain words and to ask Larry for another; nothing stored changes.

- **Scenario:** The box is out of reach
- **Given:** the phone is off the tailnet
- **Then:** the app says it could not reach the box and to check Tailscale; the link still works for its 10 minutes.

---

### User Story 041:

- **Summary:** When the key runs out, ask Larry to pair again
- **From:** Igor's answer 2, 2026-10-18 (keys expire after one month)
- **Status:** `PairingStatus` is implemented in 64c0a7e. It is verified on the host by `PairingStatusTests`, which
  check each of the four scenarios' words and that expired, refused and unpaired need pairing. Each app owns what it
  stops sending and what it keeps in the meantime.

#### Use Case:
- **As someone** whose device key lasts a month
- **I want to** be told before it runs out and, once it has, told the one thing to do
- **so that** re-pairing is one tap on Larry's next link, and nothing I did meanwhile is lost

#### Acceptance Criteria:
- **Scenario:** Paired
- **Given:** the device is paired and its key expires in more than 3 days
- **Then:** the app shows *Paired as Igor's iPhone until Nov 17*.

- **Scenario:** About to expire
- **Given:** the key expires within 3 days
- **Then:** the app says how many days are left and that Larry will send a new link.

- **Scenario:** Expired or refused
- **Given:** the key's expiry has passed, or a service answered that it is expired, revoked or unknown
- **Then:** the app says *Ask Larry to pair again* and stops sending with that key; each app keeps what it would
  have sent until the device is paired again.

- **Scenario:** Not paired
- **Then:** the app says the device is not paired and to ask Larry to pair it.
