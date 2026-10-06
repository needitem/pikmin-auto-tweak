# Pikmin Auto

Own-device automation for Pikmin Bloom (`com.nianticlabs.pikmin`), a rootless Theos tweak.
It drives the game's own client classes and RPC wrappers through the il2cpp runtime.

## Layers

Dependencies point downward only; each module has one reason to change.

| Layer | Path | Responsibility |
|---|---|---|
| App | `Sources/App` | `Tweak.mm` entry point · `Features.mm` registry (the one place to add a feature) · `Scheduler` (when passes run) · `FrameRate` |
| Passes | `Sources/Passes` | One decision procedure per feature (`FeedPass`, `HarvestPass`, …) + the GPS Wander dumps |
| Rpc | `Sources/Rpc` | `RpcClient`: builds and sends request protos; the only module that knows request shapes |
| Model | `Sources/Model` | Read-only snapshots of game state: roster, troop, nectar, petals, map objects, expeditions, location |
| Game | `Sources/Game` | Captured singletons (`GameContext`), hook table (`Hooks`), enum constants |
| IL2CPP | `Sources/IL2CPP` | Cached runtime bridge, the field table with name-based offset resolution (`Layout`), collection readers |
| Support | `Sources/Support` | Log, clocks, `PKBackoff`, settings |

## Rules the code follows

- **No game pointer outlives a pass.** Snapshots carry ids as `NSString`; managed strings are rebuilt where a request is built. Captured singletons are pinned with GC handles and replaced when the game hands over a new instance.
- **State reads are shared per frame** (`Support/Frame.h`). One scheduler tick (or one pass run from a switch) is a frame: the roster, squad, nectar and petal scans happen once and are shared by every pass in it, then dropped when the frame ends. Outside a frame nothing is cached. A pass that changes statuses calls `pkRosterInvalidate()`.
- **Fields are found by name** (`Layout.h`); the dump's offsets are a fallback only while the game build is unchanged. After a game update, unresolved fields fail closed and the scheduler pauses (`[layout]` lines in the log) instead of reading garbage.
- **Hooks capture, passes act.** Production hooks never call back into il2cpp from a game callback. Request-logging hooks exist only with `pa_debug`.
- **Every fire-and-forget request goes through `PKBackoff`** — no resend before the game can answer, longer waits when the target's state did not move.
- **No UI, no switches.** Every feature in `Features.mm` always runs; there is no overlay and nothing to toggle.
- **Foreground only.** Passes, the finder and the heartbeat run only while the app is active. Nothing in the tweak keeps the process alive in the background (no background location session); location updates stop when the app is backgrounded.
- **Paced and self-limiting.** The game answers every request on its main thread, so requests that arrive in bursts (harvest, feed, collect) are queued and released a quarter of a second apart (`pkRpcDefer`), and when the 1 s timer is seen firing late the passes and the queue hold off for a few seconds (`pkMainThreadCalm`). The first 75 s after launch are left to the game loading. The `[hb2]` heartbeat line shows the queue and the held ticks.
- **One pass, one file, one status line.** Pacing lives only in `Features.mm` / `Scheduler.mm`.

## Switches (`defaults` on the app)

| Key | Meaning |
|---|---|
| `pa_camsuppress` | keep the camera still while automating (default on) |
| `pa_fps` | frame-rate cap while automating (5–60; default 0 = no cap) |
| `pa_debug` | install request-logging hooks (needs a relaunch) |
| `pa_special`, `pa_special_id` | pinned special nectar (set from the game's own selection) |

Logs: `Documents/pa.log` (rotates at 1 MB to `pa.log.1`). `PKLOGC` formats its message lazily, so a status line whose key logged in the last two seconds costs nothing. Per-pass cost is in the `[hb]` line every minute as `total-ms/calls`.

## Build

```sh
export THEOS=~/theos
make            # or: make package
```
