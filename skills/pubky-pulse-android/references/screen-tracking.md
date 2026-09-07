## Contents

- What the SDK provides
- Compose
- Activities: one registration for the whole app
- Fragments
- Navigation Component
- Mixed stacks and naming

## What the SDK provides

`Modifier.pulseScreen(name)` in the `pulse-android-compose` artifact is the only
screen-tracking API. It emits, keyed on composition lifetime:

| Event | Level | When | Attributes |
|---|---|---|---|
| `sdk:screen_appeared` | debug | the decorated node enters the composition | `screenName` |
| `sdk:screen_disappeared` | debug | it leaves the composition | `screenName`, `_duration_ms` |

Both are debug level, so they stay out of the default production view — query
development data, or filter by level, to see screen flow. `sdk:screen_disappeared` is
the more useful signal because it carries the duration; `sdk:screen_appeared` is what
reveals screens that were opened and never left.

There is no View-, Activity- or Fragment-based equivalent. The patterns below emit
the same two events by hand, so a View-based app lands in exactly the same dashboard
views as a Compose one. This is the one place to write `sdk:` messages — and the
reserved `_duration_ms` attribute — by hand: the values have to match what the
modifier emits, or the two halves of the app produce different-looking screen data.

## Compose

```kotlin
import org.pubky.pulse.android.compose.pulseScreen

@Composable
fun ProfileScreen() {
    Column(modifier = Modifier.pulseScreen("Profile")) {
        ProfileHeader()
        PostList()
    }
}
```

Attach it to the outermost node of each distinct screen — root `Column`, `Scaffold`
content, `LazyColumn` or `Box` — and to every navigation destination. Inner
composables never carry it.

## Activities: one registration for the whole app

`registerActivityLifecycleCallbacks` covers every Activity at once, so no screen can
be forgotten. Register it in `Application.onCreate()` right after `Pulse.configure`.

```kotlin
class PulseActivityScreenTracker : Application.ActivityLifecycleCallbacks {
    private val startedAt = mutableMapOf<String, Long>()

    private fun name(activity: Activity): String =
        activity::class.java.simpleName.removeSuffix("Activity")

    override fun onActivityResumed(activity: Activity) {
        val screen = name(activity)
        startedAt[screen] = SystemClock.uptimeMillis()
        Pulse.debug("sdk:screen_appeared", screenName = screen)
    }

    override fun onActivityPaused(activity: Activity) {
        val screen = name(activity)
        val began = startedAt.remove(screen)
        Pulse.debug("sdk:screen_disappeared", screenName = screen, attributes = mapOf(
            "_duration_ms" to began?.let { "${SystemClock.uptimeMillis() - it}" },
        ))
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
```

```kotlin
registerActivityLifecycleCallbacks(PulseActivityScreenTracker())
```

Resume/pause is the right pair: it matches "visible to the user" and fires on
multi-window and dialog transitions the way `onStart`/`onStop` do not. Deriving the
name from the class keeps it automatic; override it with a map or an interface on the
Activity when the class name is not what analytics should show.

## Fragments

For a single-Activity app whose screens are Fragments, register one
`FragmentLifecycleCallbacks` on the Activity's fragment manager instead — the same
appear/disappear pair, driven by `onFragmentResumed` and `onFragmentPaused`:

```kotlin
supportFragmentManager.registerFragmentLifecycleCallbacks(
    object : FragmentManager.FragmentLifecycleCallbacks() {
        private val startedAt = mutableMapOf<String, Long>()

        override fun onFragmentResumed(fm: FragmentManager, f: Fragment) {
            val screen = f::class.java.simpleName.removeSuffix("Fragment")
            startedAt[screen] = SystemClock.uptimeMillis()
            Pulse.debug("sdk:screen_appeared", screenName = screen)
        }

        override fun onFragmentPaused(fm: FragmentManager, f: Fragment) {
            val screen = f::class.java.simpleName.removeSuffix("Fragment")
            val began = startedAt.remove(screen)
            Pulse.debug("sdk:screen_disappeared", screenName = screen, attributes = mapOf(
                "_duration_ms" to began?.let { "${SystemClock.uptimeMillis() - it}" },
            ))
        }
    },
    true,   // recursive: includes child fragment managers
)
```

Skip dialog and bottom-sheet fragments that are not really screens, or the counts
double up: filter on the class, or keep an allow-list of screen fragments.

Do not combine this with the Activity tracker on the same app, or every fragment
navigation produces two overlapping screen views. Pick the layer that represents a
screen in this app.

## Navigation Component

With a single Activity and either Fragment or Compose destinations, a destination
listener is the cleanest source of truth — the label comes from the graph rather than
a class name:

```kotlin
navController.addOnDestinationChangedListener { _, destination, _ ->
    val screen = destination.label?.toString() ?: destination.displayName
    Pulse.debug("sdk:screen_appeared", screenName = screen)
}
```

Track the previous destination and its start time to emit the matching
`sdk:screen_disappeared` with `_duration_ms`. With Compose destinations,
`Modifier.pulseScreen` on each screen composable is simpler and already handles both
halves — use one or the other, never both.

## Mixed stacks and naming

An app migrating to Compose usually has both. Instrument each screen exactly once:
Compose destinations via the modifier, the remaining Activities or Fragments via a
lifecycle callback that skips the ones already covered (a marker interface, or an
allow-list, keeps the check honest).

Names are PascalCase human labels, consistent across the app: `Home`, `Profile`,
`Order Detail`, `Signup Step 1`. `screenName` is a dashboard filter, so a rename
splits history — pick names once and keep them.
