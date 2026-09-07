## Contents

- Why a watch needs its own delivery path
- On the watch
- On the iPhone host
- Cold-launch race
- What not to build
- Reading watch data

## Why a watch needs its own delivery path

watchOS suspends an app within seconds of backgrounding, cellular signal is
intermittent, and there is no background-task grant a library can take. The SDK
therefore tries three transports per batch, in order, delivering through exactly one
of them:

1. **Direct HTTP** to the ingest endpoint, gated by the network monitor. A cellular
   watch with signal ships in real time.
2. **`WCSession.transferUserInfo` to the paired iPhone** when the watch is offline or
   HTTP has exhausted its retries. This is itself an OS-managed persistent queue: it
   survives watch suspension, reboot and Bluetooth disconnection, and wakes the
   iPhone app to deliver when the devices are back in range.
3. **On-disk queue** for a watch with no paired iPhone at all.

Server-side deduplication on the event id covers the rare case where HTTP succeeded
but the response was lost and the batch later retried over WatchConnectivity.

## On the watch

Configure exactly as on iOS. There is no separate watch API — events, errors, steps,
metrics and attachments all behave identically.

```swift
import PubkyPulse
import SwiftUI

@main
struct WorkoutWatchApp: App {
    init() {
        try? Pulse.configure(
            endpoint: "https://ingest.pulse.pubky.org",
            apiKey: "pulse_client_…",
            attributionEnabled: false
        )
    }

    var body: some Scene { WindowGroup { ContentView() } }
}
```

The SDK activates `WCSession.default` on the watch side and claims the delegate
slot — a watch app has no other valid consumer of it.

## On the iPhone host

The iPhone app owns its own `WCSessionDelegate`; the SDK never claims it. Add one
line to the existing `didReceiveUserInfo` callback:

```swift
import WatchConnectivity
import PubkyPulse

final class PhoneSessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if Pulse.handleWatchUserInfo(userInfo) { return }
        // … existing handling for payloads that are not ours
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
```

`handleWatchUserInfo` returns `true` when it recognized and consumed a Pubky Pulse
envelope, `false` otherwise — so the rest of the delegate keeps running for
everything else.

If the app uses WatchConnectivity for nothing else, register the minimal delegate at
launch:

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    private let sessionDelegate = PhoneSessionDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if WCSession.isSupported() {
            WCSession.default.delegate = sessionDelegate
            WCSession.default.activate()
        }
        return true
    }
}
```

## Cold-launch race

iOS may launch the iPhone app cold purely to deliver a watch payload, before the
app's own `Pulse.configure(...)` has run. `handleWatchUserInfo` buffers those events
internally and drains them once configuration completes, so nothing is lost — as
long as `configure` really is called early, in `App.init` or
`didFinishLaunchingWithOptions`.

## What not to build

- **Re-pairing detection.** The OS wakes the iPhone and delivers queued events when
  the watch is back in range.
- **Chunking.** WatchConnectivity payloads are chunked and delivered in order, so
  timestamps stay monotonic.
- **Suspension handling.** Anything handed to `transferUserInfo` is OS-owned.
- **Deduplication.** The server dedupes retries.

## Reading watch data

Watch events arrive with `environment: "watchos"`, distinct from `ios`, `ipados` and
`macos`, while the app row's platform stays `apple` — same app, same bundle id, same
client key. Filter by environment in `pubky-pulse:query-events` to slice watch
traffic; no separate app is needed.
