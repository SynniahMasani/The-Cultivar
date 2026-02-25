# THE CULTIVAR — Phase 4 Expansion Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script                          | Object               | What It Does                                         |
|---------------------------------|----------------------|------------------------------------------------------|
| TheCultivar_StashBox.lsl        | TC_StashBox          | Lockable display storage for jars and bags           |
| TheCultivar_GrowLight.lsl       | TC_GrowLight         | Speed bonus broadcaster for nearby plants            |
| TheCultivar_DropMachine.lsl     | TC_DropMachine       | HTTP polling terminal for limited strain seed drops  |

**Plant Update:** `TheCultivar_Plant_Grow.lsl` has been updated to v1.1 with the grow light listener. Replace the grow script in your existing pots.

---

## STASH BOX

A display case for your stash. Owner drops bags and jars inside,
visitors can browse the contents. Looks good on a shelf.

### Prim Link Structure
| Link  | What it is                                  |
|-------|---------------------------------------------|
| 1     | Box body (root)                             |
| 2–5   | Display window prims (4 visible slots)      |
| 6     | Lock indicator prim                         |
| 7     | Particle emitter (ambient wisp when stocked)|

### How Stocking Works
Drop any `TC_Bag_*` or `TC_WeedJar_*` objects into the box inventory.
The box reads them on `CHANGED_INVENTORY` and rebuilds the display.
Display slots light up with quality colors. If you have more than 4
items the last slot shows "+ N more...".

The lock indicator (link 6) shows green 🔓 when unlocked, red 🔒
when locked. Visitor touch behavior:
- **Unlocked** — visitor sees a browse menu and can read contents
- **Locked** — visitor gets a "this box is locked" message

### Owner Menu
Touch the box while wearing your HUD to get the owner menu:
- Lock / Unlock
- View Contents (with item picker to take things back)

### Item Permissions
Items need **Transfer** permissions if you want to give them to
visitors. **Copy** permissions let you give without losing your own
copy — better for display boxes you want to keep stocked.

---

## GROW LIGHT

Cuts stage duration on nearby plants. Three tiers with increasing
speed bonuses. Auto mode runs on SLT schedule (6am–10pm).

### How It Works
Every 60 seconds the light runs `llSensor` to detect nearby objects
named `TC_Plant*` or `TC_Pot*`. For each plant found it broadcasts
`TC_LIGHT_BONUS` on channel `-999111222`. The plant grow script
(v1.1) listens on that channel and reduces its remaining stage time.

**Bonus applies once per stage** — the plant sets a flag when it
receives the bonus and clears it when the stage advances. You can't
stack multiple lights on the same plant.

**Owner-only bonus** — the plant only accepts a light bonus from a
light that shares the same owner. Prevents griefing.

### Tiers
| Tier          | Stage Duration Reduction |
|---------------|--------------------------|
| Standard      | -15%                     |
| LED Panel     | -25%                     |
| Full Spectrum | -35%                     |

### Power Modes
| Mode | Behavior                                     |
|------|----------------------------------------------|
| ON   | Always scanning and broadcasting             |
| OFF  | No scan, no bonus                            |
| AUTO | On 6am–10pm SLT, off overnight               |

### Prim Link Structure
| Link | What it is                          |
|------|-------------------------------------|
| 1    | Light body / hood (root)            |
| 2    | Bulb prim (glows, point light)      |
| 3    | Beam cone prim (downward, alpha)    |
| 4    | Status indicator prim               |

### Plant Script Update Required
Replace `TheCultivar_Plant_Grow.lsl` in your existing pots with
the v1.1 version. Changes:
- Adds `GROW_LIGHT_CHAN` listener on startup
- Adds `g_lightBonusApplied` flag (resets each stage)
- Handles `TC_LIGHT_BONUS` with brief golden glow feedback

---

## STRAIN DROP MACHINE

An in-world terminal that polls your HTTP server for active limited
strain drops. When a drop is live, players can claim one free seed
pack. Server tracks claims to prevent doubles.

### Prim Link Structure
| Link | What it is                         |
|------|------------------------------------|
| 1    | Terminal body (root)               |
| 2    | Screen prim                        |
| 3    | Strain preview prim                |
| 4    | Particle emitter (hype effect)     |
| 5    | Countdown display prim             |

### Setup
1. Set `SERVER_BASE` at the top of the script to your server URL
2. Drop seed objects into the machine inventory
3. Name them **exactly** matching the strain name (e.g. `Runtz`, `Lemon Cherry Gelato`)
4. Set them to Copy/Transfer so the machine can give them repeatedly
5. Rez the machine on your land

### Server API Spec

**GET `/drops/current`**
Response (JSON):
```json
{
  "active": true,
  "strain": "Lemon Cherry Gelato",
  "quality": "exotic",
  "remaining": 47,
  "endsAt": 1735689600,
  "dropId": "drop_20260101_lcg"
}
```
If no active drop:
```json
{ "active": false }
```

**POST `/drops/claim`**
Request body (JSON):
```json
{
  "dropId": "drop_20260101_lcg",
  "avatarKey": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "avatarName": "FarmerJoe Resident",
  "region": "The Cultivar",
  "timestamp": 1735689600
}
```
Success response:
```json
{ "success": true }
```
Failure response:
```json
{ "success": false, "reason": "already_claimed" }
```
Reason codes the machine handles:
- `already_claimed` — avatar already got this drop
- `drop_ended` — drop expired between poll and claim
- `sold_out` — ran out between poll and claim

### Server Implementation Notes
The server needs to:
1. Store active drops (strain, quality, remaining count, end time, drop ID)
2. Store a claims table keyed by `(dropId, avatarKey)` with unique constraint
3. On claim: check the unique constraint, decrement remaining atomically,
   return appropriate reason on failure
4. Protect against replay attacks — timestamp should be within ±60 seconds

Simple stack: Node.js + SQLite is plenty for this volume. The machine
polls every 60 seconds and claims are low-frequency events.

### Sounds Required
| Sound Name   | When                           |
|--------------|--------------------------------|
| drop_claimed | After successful seed delivery |

---

## COMPLETE ECOSYSTEM — PHASE 4 STATUS

| Phase   | Object             | Scripts  | Status  |
|---------|--------------------|----------|---------|
| Phase 1 | HUD                | 5        | ✅ Done |
| Phase 1 | Plant / Pot        | 3 → v1.1 | ✅ Done |
| Phase 2 | Bagging Table      | 2 + bag  | ✅ Done |
| Phase 2 | Weed Jar           | 3        | ✅ Done |
| Phase 2 | Session Object     | 2        | ✅ Done |
| Phase 2 | Plug Board         | 2        | ✅ Done |
| Phase 3 | Rolling Table      | 1        | ✅ Done |
| Phase 3 | Edibles Bench      | 1        | ✅ Done |
| Phase 3 | Wearable Pieces    | 1        | ✅ Done |
| Phase 4 | Stash Box          | 1        | ✅ Done |
| Phase 4 | Grow Light         | 1        | ✅ Done |
| Phase 4 | Drop Machine       | 1        | ✅ Done |

**Total: 23 scripts across 12 objects.**

---

## DEPLOYMENT ORDER

When setting up a new Cultivar location, deploy in this order
so each system is ready before the ones that depend on it:

1. HUD (worn by player — required for everything else)
2. Plant / Pot + Grow Light (grow room)
3. Bagging Table (processing)
4. Weed Jar (personal use)
5. Rolling Table + Edibles Bench (crafting)
6. Stash Box (storage/display)
7. Session Object (rezzed dynamically by HUD — no manual setup)
8. Plug Board (sales floor)
9. Drop Machine (events — only needed when running drops)
