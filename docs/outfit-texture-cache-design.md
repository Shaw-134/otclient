# Outfit composited-texture cache — design (not yet implemented)

Status: design only, reviewed against real `src/client/creature.cpp`. No
code lands with this doc — the Kemet OT Notion Task Tracker card
("Pre-compile OTClient outfit textures into memory cache", Phase 1, Low)
correctly declined a naive implementation before, since a naive cache is
wrong without accounting for facing/pattern/addon/mount state. This
closes that gap with a concrete spec; actual implementation still needs
visual QA against a running client, which isn't possible from a headless
environment — a human must verify this renders correctly before it ships.

## What's actually expensive today

`Creature::internalDraw` (creature.cpp:364-489) redoes masked color
compositing every frame for every visible creature with body-color
outfit tinting: for each addon-active `yPattern`, `datType->draw()` is
called once for the base sprite plus up to 4 more times
(`SpriteMaskYellow/Red/Green/Blue`, `CompositionMode::MULTIPLY`) tinted
by head/body/legs/feet color. `ThingType::getTexture()` already caches
the raw sprite atlas once — what's not cached is the *composited* result
per creature per frame.

## Cache key

```cpp
struct OutfitCacheKey {
    uint16_t lookType;
    uint16_t lookMount;      // 0 if no mount
    uint8_t  head, body, legs, feet;
    uint8_t  addons;         // m_outfit.getAddons() bitmask
    uint8_t  patternX;       // m_numPatternX (facing)
    uint8_t  patternY;       // yPattern (addon slot)
    uint8_t  patternZ;       // m_numPatternZ
    uint8_t  animPhase;      // getCurrentAnimationPhase()
    bool operator==(const OutfitCacheKey&) const = default;
};
```

All the fields that currently vary the render output go in the key —
this makes the cache content-addressed, so a creature's own state change
just produces a cache miss for the new key rather than needing manual
per-creature invalidation.

## Where it plugs in, and what must NOT be cached

- Intercept in `internalDraw`'s `drawCreature` lambda (creature.cpp:415),
  right before the masked-compositing loop (lines 428-434). On a cache
  hit, skip straight to drawing the cached texture via
  `g_drawPool.addTexturedRect`/equivalent; on a miss, render the existing
  masked-compositing sequence into an offscreen `FrameBuffer` once,
  cache the result, then draw it.
- **Bypass the cache entirely when `hasShader()` is true** (the
  `useFramebuffer` branch at creature.cpp:413/439-449). Shaders can read
  per-frame uniforms (time, light, mount-id per the commented-out
  `MOUNT_ID_UNIFORM` example at line 402-405) — caching their output
  would freeze a shader that's meant to be dynamic. This mirrors the
  existing `bindFrameBuffer`/`releaseFrameBuffer` pattern already in this
  file, which is explicit per-frame scratch, not a persisted cache — a
  correct implementation must not conflate the two.
- The cache must only cover the **base outfit + color-mask compositing**
  (the `drawCreature` lambda's own output). Mounts (lines 398-409) and
  the up-to-5 `game_paperdolls` layers (lines 393-394, 452-453, drawn
  before/after the base outfit — some paperdolls render behind the body,
  some above) stay outside the cache and keep drawing every frame in
  their existing order.
- Because `g_drawPool` defers draw commands rather than issuing them
  immediately, the masked-compositing render-to-texture pass has to
  happen in an isolated framebuffer pass (same pattern as the existing
  `bindFrameBuffer(destFB.size())` call) before the resulting texture is
  handed to the draw pool as a normal textured quad — you cannot record
  `CompositionMode::MULTIPLY` masking steps directly into the deferred
  pool and expect them cached as one unit.
- Cached framebuffer size must come from the real sprite bounds
  (`datType->getSize().area()`, `datType->getExactHeight()` — same
  calculation already used at creature.cpp:440-441 for the shader
  framebuffer path), not a fixed tile size — outfits aren't always
  32x32.

## Eviction

Global LRU keyed on `OutfitCacheKey` → cached texture/framebuffer handle.
**Suggested starting cap: 512 entries** — this is an estimate (a full
screen of ~50 distinct players × ~4 facings × a few active anim phases
lands around that order of magnitude), not measured against this
client's real VRAM budget. Per this project's standing rule against
presenting invented numbers as verified fact, treat 512 as a tunable
starting point to profile against, not a final answer — same caveat
already applied to every placeholder combat-balance number in
`BALANCE_NOTES.md`.

## Invalidation

None needed per-creature beyond normal LRU eviction, since the key is
derived from full render state — a genuine outfit/addon/color/mount
change just produces a new key (old entries age out via LRU, they don't
need to be actively deleted). Only a few *global* events require a full
cache clear: sprite/`ThingTypeManager` reloads, GL context loss, and
`g_textures.clear()` calls.

## Review provenance

Design drafted via Gemini (`gemini-flash-latest`, direct API call — see
`/root/Bloxer-Kemet/GEMINI_DELEGATION_LOG.md`, 2026-08-10 entry) working
from the exact real code excerpts above, verified claim-by-claim against
this file before writing this doc. Accepted as-is except the eviction
cap, which is called out above as an unverified placeholder rather than
silently presented as measured.

## What's still needed before this ships

1. Implementation of the cache class + the `internalDraw` integration
   above.
2. Real profiling on a running client to validate (or replace) the
   512-entry cap.
3. Visual QA on a running OTClient — confirm outfits/mounts/paperdolls
   still render correctly frame-to-frame, including addon toggles and
   color changes — not possible from this headless environment.
