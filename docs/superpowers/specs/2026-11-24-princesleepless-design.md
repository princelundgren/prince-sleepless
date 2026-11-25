---
status: building
governs: [PrinceSleepless/**, PrinceSleeplessCore/**, scripts/**, .github/workflows/**, .github/dependabot.yml]
verified: 2026-11-25
---

# PrinceSleepless: design

A macOS menu bar app that keeps a MacBook awake with the lid closed, on battery and with no external
display, so long-running work such as coding agents keeps going, and lets the Mac sleep again on a
timer, a schedule, a battery floor or Low Power Mode.

## Why

With the lid closed, on battery and with no external display, a MacBook sleeps even while an app
holds a sleep assertion (`caffeinate`, KeepingYouAwake). The one setting that overrides the lid is
`pmset -a disablesleep 1`, which sets `SleepDisabled` on the IORegistry's `IOPMrootDomain` and needs
root. It is undocumented: `man pmset` doesn't list it, so a macOS update could drop it. `pmset`
saves it to `/Library/Preferences/com.apple.PowerManagement.plist` (`SystemPowerSettings` →
`SleepDisabled`), so it may survive a restart; this design doesn't rely on either answer. The kernel
publishes `SleepDisabled` (a boolean) only once a client has set it, so a missing key reads as 0
(`IOPMrootDomain::setProperties` in xnu).

Sleepless (github.com/Aboudjem/Sleepless, MIT) wraps it in a menu bar switch, but:

- it is ad-hoc signed, so a downloaded copy can't be opened on a Mac whose management profile
  disables Gatekeeper's override (`com.apple.systempolicy.managed` `DisableOverride`);
- it gets root through a sudoers drop-in, and nothing turns sleep back on if the app crashes;
- it polls every 60 s for its whole life, starting a `pmset -g` process each time, even while off;
- its panel shows every control at once.

Success: on a managed Mac, the owner flips one switch, closes the lid, and the agents keep running
until the timer, the schedule, the battery floor or Low Power Mode ends it, after which the Mac
sleeps normally.

## Goals

- **On/off** from a large disc in the panel, with one status line under it.
- **Auto-off timer** picked in the panel: until turned off, 30 min, 1 h, 2 h, 4 h, or until a time
  of day; a live countdown in the status line.
- **Schedule:** a start and end time of day and the weekdays it applies, each boundary acting
  ("Automatic") or sending a notification with Turn On / Turn Off actions ("Notify me"); rules
  under "The schedule".
- **Battery floor** (default 20 %) turns it off on battery, always. **Low Power Mode** (the rule on
  by default) turns it off when it comes on during a run on battery; switching on by hand while
  Low Power Mode is on works (owner, 2026-11-24). After either, it stays off when the charger
  returns or Low Power Mode ends, and a notification says why (owner, 2026-11-24).
- **A flag it didn't set is adopted:** found on (set by hand with `pmset`, or by another app), it
  shows as on, and every auto-off rule and the crash safety apply to it (owner, 2026-11-24).
- **Crash safety:** if the app quits, crashes or is killed while on, sleep is turned back on. The
  one gap: a run whose helper died and couldn't be made to guard it again, which the app shows
  ("The helper", Crash safety).
- **Restarts clear it; one setting brings it back at login:** "Stay on after a restart", off by
  default. Every boot starts with the flag at 0. With the setting on, an app that was on when the
  Mac restarted or shut down switches on again when it launches at login, with every rule armed
  (owner, 2026-11-24).
- **No cost while off:** no polling, no subprocesses, no resident helper; the app wakes only for a
  schedule boundary, a wake from sleep, a clock or time-zone change, or the user. (Like any app
  that has drawn SwiftUI, it also gets the GPU driver's 3 s `MemoryPoolDecay` wakeup once its panel
  has opened; that is the system's, not the app's.)
- **Little cost while on:** the battery is read once when a check is due, not on every battery
  update (owner, 2026-11-24).
- **Opens on a managed Mac:** signed with Developer ID, notarized, updated through Sparkle.
- **Open source under MIT**, public from the first commit.

## Non-goals

- Keeping the display awake or simulating activity.
- An App Store build: the sandbox can't run a privileged helper.
- Intel Macs and macOS before 26.
- Users without an admin account: approving a launch daemon needs an admin (`SMAppService.h`).
- A Mac whose sleep is disabled for good, such as a desktop server: every boot clears its flag. The
  README says not to install it there.
- Limiting it to admin accounts: any account that runs the app can switch it, which on a
  single-user MacBook is the owner (owner, 2026-11-24).
- A watchdog in the helper for a hung app: a hung app still shows on, so the user doesn't believe
  the Mac can sleep, and the helper stays a process with one boolean to guard.

## Anti-goals: it fails even if it works

- The Mac is left unable to sleep when the user believes the app is off.
- The app itself drains the battery it is meant to protect.
- It needs a sudoers file, a shell string or any privileged code path other than the helper below.

## Prior art

- **Sleepless:** the mechanism (`pmset disablesleep`, a read-back of the flag) and the safety nets
  (timer, battery floor, Low Power Mode, a manual switch-on winning over Low Power Mode). Rebuilt,
  not forked: none of its code is copied; the README credits it.
- **The author's other menu bar apps:** the panel's design language, the schedule, and the battery
  check (one IOKit read when a check is due); written out below.
- **prince-clockin** (`princelundgren/prince-clockin`): the repository layout, release pipeline
  and public-repository rules.
- Amphetamine's closed-display mode is reported to fail on Apple Silicon; KeepingYouAwake and
  `caffeinate` can't override the lid.

## Approaches

1. **Fork Sleepless.** Working on day one, but its hand-laid AppKit panel, build script and
   self-signed release would all be replaced. Rejected.
2. **Rebuild on the owner's app structure** with Sleepless as the reference. **Chosen** (owner,
   2026-11-24).

How root is reached:

1. **A sudoers drop-in** allowing only `pmset -a disablesleep 0|1`, as Sleepless does. Little code,
   but an app editing sudoers is a workaround, and a crashed app leaves sleep off.
2. **A privileged helper registered with `SMAppService.daemon(plistName:)`** (macOS 13+), approved
   once by an admin in System Settings → Login Items. Apple's supported path; the helper accepts
   only the signed app and can restore sleep when the app dies. **Chosen** (owner, 2026-11-24). A
   management profile's `com.apple.servicemanagement` payload pre-approves listed items rather than
   blocking others; on a managed Mac checked before this design, a third-party root helper runs.

How a restart is handled:

1. **The helper restores the flag at boot** from a root-owned record. Rejected (owner, 2026-11-24):
   nothing guards the flag between boot and login, and if launch at login is later turned off the
   Mac never sleeps again with no app showing. On a FileVault Mac the disk unlocks at login anyway.
2. **The helper clears the flag at every boot; the app switches on again at login.** **Chosen.**

## How it works

### Repository

`princelundgren/prince-sleepless`, public, MIT, laid out like prince-clockin:

- `PrinceSleepless/`: the app and helper targets, generated by XcodeGen from `project.yml`; the
  `.xcodeproj` is not committed.
- `PrinceSleeplessCore/`: a Swift package with every decision that can be tested without the
  system: the schedule, the timer, the auto-off rules, the battery check's spacing, the controller
  that turns events into commands, the helper's guard count and boot check, the status text; and
  the two system reads the app and the helper share, the sleep flag and the boot session.
- `scripts/`, `docs/superpowers/specs/` (this file), `AGENTS.md`, `README.md`, `LICENSE`.

Bundle IDs: `com.princelundgren.princesleepless` and, for the helper,
`com.princelundgren.princesleepless.helper`, which is also its launchd `Label`, Mach service name
and executable name.

### The helper

- Shipped inside the app, which lives in `/Applications` (`SMAppService.h`'s advice for a daemon
  that starts at boot). Its launchd plist in `Contents/Library/LaunchDaemons/` has `Label`,
  `BundleProgram`, a `MachServices` entry and `RunAtLoad`, and no `EnvironmentVariables`.
- **Registration** happens only on a user action: switching on, or switching off a flag found on.
  An unasked registration would show macOS's "background item added" notice. While its status is
  `.requiresApproval` (or `.notFound` after a failed registration) the status line reads "Approve
  in Login Items" and a click on it opens System Settings; approval has no callback, so the app
  re-reads the status on each panel open, and the user taps the disc again once approved.
- **After an update:** `SMAppService.h` says a changed helper executable "must be re-registered or
  it may not launch", and recommends `unregister` first; `unregister` kills a running helper. So
  when the stored build number differs from the app's, the app calls `unregister(completionHandler:)`
  and then `register()` while the flag is off: at launch, or at the next switch-off.
- **Who may connect:** `NSXPCListener.setConnectionCodeSigningRequirement(_:)` (macOS 13) on the
  listener, so any other process is refused "before consulting the delegate". The requirement, in
  Release builds, is Developer ID's designated-requirement shape, bound to the helper's own team:

  ```
  identifier "com.princelundgren.princesleepless" and anchor apple generic
    and certificate 1[field.1.2.840.113635.100.6.2.6] exists
    and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
    and certificate leaf[subject.OU] = "<team>"
  ```

  `<team>` comes from the helper's own signature (`SecCodeCopySelf`, then
  `SecCodeCopySigningInformation`, key `kSecCodeInfoTeamIdentifier`); with no team the listener
  never resumes. Debug builds drop the two Developer ID lines (Apple Development certificates) and
  keep the identifier, `anchor apple generic` and the team: never an identifier alone, which any
  ad-hoc signature can claim.
- **Its interface** (Bools and Ints only):
  - `protocolVersion`: an Int; the app refuses to call a helper whose version differs, and
    re-registers it once the flag is off;
  - `keepAwake`: sets the flag to 1 if it isn't, and guards this connection; the same call adopts a
    flag that is already on;
  - `allowSleep`: sets the flag to 0 and stops guarding this connection.
  It sets the flag by running `/usr/bin/pmset` with an argument list (`-a disablesleep 1` or `0`),
  never a shell string, and confirms it by reading `SleepDisabled` back; a mismatch is a `false`
  reply, which the app shows as "Couldn't change sleep" and logs. The app reads the flag itself
  through IOKit, so the helper has no read call.
- **Crash safety**, state-based, all on one serial queue:
  - the helper counts the connections that guard; when the last one is invalidated (the app quit,
    crashed or was killed), it sets the flag to 0 if `SleepDisabled` reads 1;
  - on SIGTERM it does the same before exiting (a `DispatchSource` signal source, with
    `signal(SIGTERM, SIG_IGN)` at the top of `main`, since a dispatch source installs no handler);
  - if the helper dies while on, the app's `interruptionHandler` reconnects and sends `keepAwake`
    again at once; an invalidated connection is replaced with a new one, which sends it the same
    way. If that re-guard fails, the run stays on with its timer but unguarded, its battery and
    Low Power Mode rules stop, and the app shows "Couldn't change sleep"; each panel open then
    re-guards it the same way, keeping its timer and schedule;
  - with no guarding connection and the flag at 0, it exits a few seconds after its last reply;
    launchd starts it on the next request.
- **At boot:** `RunAtLoad` also runs the job at registration, approval and re-registration
  (`man launchd.plist`), so the helper keeps one value in a root-owned file: the last
  `kern.bootsessionuuid` it saw (`/Library/Application Support/PrinceSleepless/`, directory 0700,
  file 0600, written atomically). Before resuming its listener it compares: a different UUID is a
  new boot, and it sets the flag to 0; a missing file is a registration, not a boot, so a flag the
  user is about to adopt stays. Either way it then stores the current UUID, unless a clear failed,
  so the next launch retries it. A file that won't decode counts as a new boot. With
  `kern.bootsessionuuid` unreadable, it logs and exits without resuming. A failed store is logged
  as a fault and the helper carries on; the file keeps its last value, so while stores keep
  failing, a missing file means no boot clears the flag and a stale one means every launch does.
  The boot check runs before the team lookup, so it clears the flag even when the listener won't
  resume.

### The app

- **State** comes from the system, not from memory: the app reads `SleepDisabled` from
  `IOPMrootDomain` through IOKit, without root and without a subprocess. There are two states, on
  and off, and on is either protected (the helper guards it) or not: not yet approved ("Approve in
  Login Items"), or a re-guard after the helper died failed (Crash safety, above).
- **When it reads the flag:** at launch, on each panel open, after each change it makes, on
  `NSWorkspace.didWakeNotification`, while on at each power-source event, and on each timer or
  schedule event. A read while a helper call is outstanding waits for the last reply: the
  controller ignores it, since the flag may still change, and the read after that reply counts.
  The builder tests whether powerd's notify(3) key
  `com.apple.system.powermanagement.prefschange` (not in a public header) fires when the flag
  changes; if it does, the app observes it always, which costs nothing while idle. Without it, a
  flag set by someone else while the app runs shows only at the next of those moments.
- **Found on, the flag is adopted:** with the helper approved, the app sends `keepAwake`, arms the
  battery and Low Power Mode rules, and runs no timer until the user picks one. Found on with the
  helper not approved, it shows "On · Approve in Login Items". At the first launch of a new boot
  session, a flag found on is left over from before the boot (the helper's boot check may not have
  run yet): the app sends `allowSleep` instead, unless the restart rule below switches it on. With
  the helper not approved it can't, so it shows the flag as it does any flag found on.
- **The auto-off rules** are checked on every power-source event and every Low Power Mode event,
  which can arrive in either order (Low Power Mode can be set per power source and come on at the
  moment of unplugging):
  - the battery floor, on battery: always switches off, and refuses a switch-on;
  - Low Power Mode coming on during a run, on battery: switches off; a manual switch-on while it is
    already on works and stays on; a schedule's start doesn't switch on while it is on;
  - each switch-off sends one notification with the reason, and the app stays off.
- **Battery**, while on:
  - notify(3) `kIOPSNotifyPowerSource` through `notify_register_dispatch` fires only when the Mac
    moves between charger and battery (`IOPowerSources.h`: "a more efficient choice"); not
    `IOPSNotificationCreateRunLoopSource`, which "fires fairly frequently while discharging";
  - on the charger, nothing else runs;
  - on battery, one `IOPSCopyPowerSourcesInfo` snapshot gives the charge, the source and
    `kIOPSTimeToEmptyKey` (minutes; −1 while unknown) together; then one one-shot timer, with a wide
    tolerance, goes to about half the estimated time until the floor, at least a minute out; on
    fire, read again. While the estimate is unknown, the next read is a few minutes out. The checks
    come closer only as the floor nears.
- **Low Power Mode:** `NSProcessInfoPowerStateDidChange`, posted on a global queue, so handled on
  the main actor, and `ProcessInfo.isLowPowerModeEnabled`. Registered only while on.
- **Timer:** one one-shot timer to the end time, with a tolerance of at most 30 s, recomputed after
  a wake and a clock or time-zone change. The countdown in the status line refreshes once a second
  only while the panel is open. Picking a duration while off switches on.
- **App Nap:** while on, the app holds a `ProcessInfo` activity with
  `.userInitiatedAllowingIdleSystemSleep`, so its timers aren't delayed; plain `.userInitiated`
  would also add an idle-sleep assertion.
- **Notifications** through `UNUserNotificationCenter`, its delegate set before launch returns:
  the "Notify me" reminders, a notice when an auto-off rule switches it off, and, at the next
  launch, a notice when the helper restored sleep because the app died. The app tells a crash
  from a quit by a marker it writes on `applicationWillTerminate`. Authorization is requested the
  first time a schedule or an auto-off rule could notify.
- **Restarts:** on `NSWorkspace.willPowerOffNotification` (a logout, restart or shutdown) while on,
  the app records "on at power-off" with the current `kern.bootsessionuuid` and its timer's end. At
  launch it switches on again, through the normal path with every rule armed, only if "Stay on
  after a restart" is set, "on at power-off" is recorded, and the boot session differs (so a
  logout or a cancelled shutdown doesn't count). A saved timer end resumes, or switches off at once
  if it has passed. A run the schedule started stays the schedule's, so its window's end still
  switches it off. Every switch-off and every launch clears the record.
- **Launch at login** through `SMAppService.mainApp`, off by default; turning on "Stay on after a
  restart" turns it on too, and the setting does nothing while launch at login is off.
- **Updates while on:** Sparkle's `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`
  holds the relaunch until the user switches off; the panel's update row says it installs then.
  Sparkle doesn't call it in every case (for example when the app isn't relaunching), so a quit
  for an update can still end a run, and the crash safety then turns sleep back on.
- **Settings values** read from `UserDefaults` are clamped to the ranges Settings offers.
- **Logging** through `os.Logger`, one subsystem for the app and the helper; no telemetry,
  analytics or crash reporting. The README gives the `log show --predicate` line to read it.

### The schedule

- One window: a start time, an end time (an end before the start means the next day; the window
  belongs to the weekday it starts on) and the weekdays it applies. A start equal to the end is
  refused in Settings.
- One timer to the next boundary, with a tolerance of at most 30 s, recomputed after each one
  fires, after a wake, and after a clock or time-zone change. While off with no schedule set, the
  app holds no timer.
- Each boundary acts once: the app saves the last boundary it acted on; a boundary at or before it
  does nothing, and within one window only its start and then its end act, so the repeated hour of
  a daylight-saving fall-back night acts once.
- **Automatic:** the start switches on; the end switches off a run that the start switched on, or
  that the user switched on inside the window with a timer. A run the user switched on "until
  turned off" stays on past the end. **Notify me:** each boundary sends a notification whose Turn
  On or Turn Off action does that, whatever the current state.
- **Catch-up** after a wake, a clock or time-zone change, a launch, or a boundary timer that fires
  late: only the latest missed boundary counts. A start whose window has already ended is skipped;
  inside a window, Automatic switches on.
- **What overrides it:** a manual switch-off, the timer's end, or an auto-off rule, inside a window
  holds until the next window's start; the hold is saved, so a relaunch inside the window keeps it.
  A start while the battery floor or Low Power Mode holds stays off, with the reason. An Automatic
  start with the helper not approved sends a notification asking for approval.
- **With a timer:** whichever ends first switches off.

### The panel

280 pt wide, no title row:

```
            ╭────────╮
            │   👁   │     disc: brand colour + glow when on
            ╰────────╯
       ⏱ Awake · off in 1:42
   [ ∞ ] [30m] [1h] [2h] [4h] [⏰]
   ────────────────────────────────
   ⚙︎                            ⏻
```

- A 72 pt circle is the switch: SF Symbol `eye` off, `eye.fill` on, the brand colour and a soft glow
  (shadow radius 10, 0.35 alpha) on, a 1.04 scale and a pointing-hand cursor on hover, a `.bounce`
  symbol effect on toggle.
- One status line under it, fixed at 20 pt so the panel never jumps: "Off", "Awake", "Awake · off
  in 1:42", "Auto-off at 18:00", "Auto-on at 08:00", "Turned off: battery at 20 %", "Couldn't
  change sleep", "Approve in Login Items", "On · Approve in Login Items". A click on it opens
  System Settings when it asks for approval, else the schedule in Settings when a schedule is set.
- The duration row is a row of buttons, not a SwiftUI `Menu`: on macOS 27 the first `Menu` opened
  in a menu bar popover is cancelled within about 35 ms, with no known fix. The last button picks
  a time of day with a compact `DatePicker`.
- A divider, then the footer: a gear (Settings) left, a power symbol (Quit) right; a Sparkle
  "Update ready" row above it when one is downloaded.
- The menu bar icon: `eye` off, `eye.fill` on, and a variant on battery while on.

### Settings

Swaps into the panel with a Back button: the schedule (start, end, weekdays, Automatic or Notify
me), the battery floor slider, the Low Power Mode toggle (on), "Stay on after a restart" (off),
launch at login, the helper's status, Check for Update, the version and a GitHub link.

### Release

- Based on prince-clockin's `release.yml`: on a version tag on `main`, build, sign with Developer
  ID, notarize with `notarytool`, staple, and publish the DMG and the Sparkle appcast under
  `https://updates.princelundgren.com/princesleepless/`.
- Unlike prince-clockin's, it signs the helper first: Developer ID, `--options runtime --timestamp`,
  its identifier from the `Info.plist` embedded in its binary; and it drops prince-clockin's Apple
  Events entitlement check. Neither the app nor the helper carries an entitlement.
- CI checks the signed app: `codesign --verify --strict -R '=<the listener requirement>'` on the
  app, with the requirement taken from the same source the helper compiles; the helper's team equals
  the app's; both have the hardened runtime flag and neither has
  `com.apple.security.cs.disable-library-validation` or
  `com.apple.security.cs.allow-dyld-environment-variables`.
- **The release gates are repository settings**, set before any secret: the `release` environment
  deploys only from tags `v*`; a tag ruleset limits creating, moving and deleting `v*` tags to the
  admin; every outside contributor's pull request waits for approval; the cloud role's OIDC trust
  names this repository's `release` environment. A leaked signing certificate or Sparkle key would
  let an update reach a root daemon on every user's Mac.
- Secrets in that environment, set again from the password manager: GitHub can't copy secrets
  between repositories. The Developer ID certificate, App Store Connect key and Sparkle key are
  reused where they can hold the new app.
- CI on GitHub-hosted macOS runners (prince-clockin's own VM runner is registered to that repo
  alone); actions pinned by full commit SHA; Dependabot for Actions and the core package; CodeQL
  for Swift and the workflows.

## Left to the builder

- The brand colour, the exact SF Symbol variants and the copy of each status line, within the
  design language above.
- The battery check's exact spacing and the unknown-estimate interval, within "about half the
  time to the floor, at least a minute".
- The XPC protocol's exact shape and the helper's state file name.
- Confirming on macOS 26 and 27, before building what depends on each: that the helper runs at
  boot and clears the flag; whether the `prefschange` notify key fires on a flag change; what
  revoking approval does to a running helper; whether an unregister and register after each update
  asks an admin to approve again or shows the "background item added" notice.
