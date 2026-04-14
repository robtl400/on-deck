# TODOS

## Standings retry on failure

**What:** If `fetchStandings` fails at launch AND no game goes Final AND no wake-from-sleep event fires, standings stay nil for the entire session. The popover works (logos + names) but teams appear in alphabetical order with no W-L records.

**Why:** Rare but possible — network outage at launch, or a day with no games. Fixable with a simple retry: if `latestStandings` is still nil after 5 minutes, try `fetchStandings` again.

**Pros:** Standings recover automatically without user action.

**Cons:** One extra timer to manage. Low priority since the failure window is small.

**Context:** Design doc chose "launch + wake + on-Final" as the three re-fetch triggers. A retry-after-5min would be a fourth trigger. Add to `handleWake`-equivalent logic or a separate `retryStandingsIfNeeded()` called from `scheduleNextRefresh`. Relevant after the popover redesign lands.

**Depends on:** Popover redesign.

---

## Loading signal on slow network (polish)

**What:** On a slow network, the popover opens with all `—` in the game info column for 2-3 seconds. A subtle loading indicator in the header bar could signal that data is in-flight rather than absent.

**Why:** A user unfamiliar with the app might think it's broken when they see a full grid of dashes. A small "Loading…" label or spinner near the gear button would clarify state.

**Pros:** Improves first-open experience on slow/mobile connections. Low effort (~20 lines).

**Cons:** May feel over-engineered for a personal utility. Network is usually fast enough that the loading state is imperceptible. Apple's native apps often tolerate this gap silently.

**Context:** The `—` placeholder is the correct idle state (Pass 2 spec). This TODO is purely about signaling the transition from "loading" to "loaded." Options: small `NSProgressIndicator` (spinning, 12pt) in the gear button area while `latestTodayGames == nil`; or a "Updating…" subtitle in the header that hides once data arrives.

**Depends on:** Popover redesign.
