# On Deck App

A lightweight macOS menu bar app that shows live MLB game scores for your favorite team — right in the status bar.

## Features

- **Live scores** in the menu bar — updates every 30 seconds during active games
- **All game states** handled: upcoming, live, final, postponed, next-game, off-season
- **Team logos** replace text abbreviations in the status bar display
- **Standings popover** — click the menu bar item to open a full 30-team standings grid with today's game status for every team
- **Follow any team** — pick from all 30 MLB teams, organized by division; selection persists across launches
- **Launch at Login** toggle via the settings gear menu
- **Sleep resilience** — re-syncs immediately when the Mac wakes to correct timer drift
- **Error resilience** — suppresses transient failures; only shows a `·?` indicator after 3 consecutive fetch failures

## Menu Bar Display

| State | Example |
|---|---|
| Upcoming | `│ 🔵 vs ⚾ · 7:05 PM │` |
| Live | `│ ⚾ 3 – 1 🔵 · 7↑ │` |
| Final | `│ ⚾ 3 – 1 🔵 · W │` |
| Postponed | `│ 🔵 vs ⚾ · PPD │` |
| Next game | `│ 🔵 vs ⚾ · 4/29 · 7:05 PM │` |
| Off season | `│ 🔵 · Off Season │` |

## Requirements

- macOS 13 Ventura or later (the Launch at Login toggle uses `SMAppService`, introduced in macOS 13)
- Xcode 15 or later (to build from source)
- No third-party dependencies

## Building

```bash
# Open in Xcode
open "On Deck App.xcodeproj"
```

Then press **⌘R** to run, or **⌘B** to build. The app uses `NSApp.setActivationPolicy(.accessory)` so it runs as a background/menu-bar-only process with no Dock icon.

To build a release binary from the command line:

```bash
xcodebuild -project "On Deck App.xcodeproj" \
           -scheme "On Deck App" \
           -configuration Release \
           -derivedDataPath build
```

The compiled app lands at `build/Release/On Deck App.app`.

## Architecture

```
On Deck App/
├── main.swift                   # NSApplicationMain entry point
├── AppDelegate.swift            # Status bar item, polling loop, popover lifecycle
├── GameFetcher.swift            # MLB Stats API client + state machine
├── Models.swift                 # GameState, TodayGameStatus, team lookup tables
├── StandingsViewController.swift # Standings popover (NSPopover content)
└── TeamRowView.swift            # Per-team row in the standings grid
```

### Data Flow

```
Timer / wake event
      │
      ▼
GameFetcher.fetchCurrentState()
      │
      ├─(Live gamePk cached)──► fetchLiveFeed()  ──► .live / .final_
      │
      └─(no cached gamePk)───► schedule API
                                    │
                                    ├── "Live"    ──► fetchLiveFeed()
                                    ├── "Preview" ──► .upcoming
                                    ├── "Final"   ──► fetchNextGame()
                                    └── (none)    ──► fetchNextGame()
                                                           │
                                                      .nextGame / .offSeason
```

### Polling Intervals

| State | Interval |
|---|---|
| Live game | 30 seconds |
| Game starting within 30 minutes | 60 seconds |
| All other states | 5 minutes |

### Standings Popover

The popover fetches two requests in parallel when opened:

1. **Today's schedule** (hydrated with linescore) → live scores for all 30 teams
2. **Next 7 days** → next scheduled game for teams with no game today

The grid refreshes every 30 seconds while the popover is open and closes on any outside click via a global `NSEvent` monitor.

## Data Source

All game data is fetched from the official **MLB Stats API**:

| Endpoint | Used for |
|---|---|
| `statsapi.mlb.com/api/v1/schedule` | Today's game, next game lookup |
| `statsapi.mlb.com/api/v1.1/game/{pk}/feed/live` | Live score + inning |
| `statsapi.mlb.com/api/v1/standings` | Division standings (W-L records) |

The API is unauthenticated and publicly accessible.

## Team Selection

The selected team is stored in `UserDefaults` under the key `selectedTeamId`. The default is the New York Yankees (team ID `147`). Changing teams via the popover immediately updates the status bar logo and triggers a fresh data fetch.

## Tests

Unit tests live in `On Deck AppTests/`. Run them with **⌘U** in Xcode or:

```bash
xcodebuild test \
  -project "On Deck App.xcodeproj" \
  -scheme "On Deck App" \
  -destination "platform=macOS"
```

Key test targets:
- `TitleFormattingTests` — verifies the plain-text title formatting for all `GameState` variants
- `On_Deck_AppTests` — integration-level tests for `GameFetcher` parsing logic

## Known Limitations

- **Standings on first launch** — if the initial `fetchStandings` call fails (e.g., no network at launch), standings show teams in alphabetical order with no W-L records until a game goes final or the Mac sleeps and wakes.
- **Doubleheaders** — the first game of a doubleheader is shown; game 2 is picked up after game 1 reaches Final.
- **No push notifications** — the app polls on a timer; there is no push or background-refresh entitlement.
