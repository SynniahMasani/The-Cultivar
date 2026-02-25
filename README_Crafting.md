# THE CULTIVAR — Phase 3 Crafting Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script                          | Object It Goes In         | What It Does                                  |
|---------------------------------|---------------------------|-----------------------------------------------|
| TheCultivar_RollingTable.lsl    | TC_RollingTable           | Crafts joints, blunts, spliffs from flower    |
| TheCultivar_EdiblesBench.lsl    | TC_EdiblesBench           | Crafts brownies, gummies, drinks, concentrate |
| TheCultivar_WearablePiece.lsl   | TC_Pipe, TC_Bong, TC_DabRig | Persistent wearable with smoke FX            |

---

## ROLLING TABLE

### Crafting Ratios
| Item    | Flower Cost | Output |
|---------|-------------|--------|
| Joint   | 1g each     | 1 joint |
| Blunt   | 2g each     | 1 blunt |
| Spliff  | 1g each     | 1 spliff |

### Batch sizes
1, 3, 5, 10, 20 — up to maximum your flower allows.

### Prim Link Structure
| Link | What it is               |
|------|--------------------------|
| 1    | Table body (root)        |
| 2    | Rolling mat surface      |
| 3    | Particle emitter         |
| 4    | Completed item display prim |

Rolling mat (link 2) lights up with quality color during crafting,
then fades back. Display prim (link 4) shows "Nx Item / Strain"
for 3 seconds after a successful craft.

### Sounds Required
| Sound Name   | When                   |
|--------------|------------------------|
| rolling_done | After successful craft |

---

## EDIBLES & CONCENTRATE BENCH

### Crafting Ratios
| Item            | Flower Cost | Base Output | Loud Bonus | Exotic Bonus |
|-----------------|-------------|-------------|------------|--------------|
| Brownie         | 3g/batch    | 1           | +1         | +2           |
| Gummies (x8)    | 4g/batch    | 8           | +8         | +16          |
| Infused Drink   | 2g/batch    | 1           | +1         | +2           |
| Concentrate     | 5g/batch    | 1           | +1         | +2           |

Quality bonuses represent potency yield — loud and exotic flower
produces more output from the same amount because it's denser.
This gives the quality tiers real crafting value, not just cosmetic.

### Two Modes
**Edibles mode** — warm amber surface glow, steam particles  
**Press mode** — cool blue surface glow, vapor particles

### Prim Link Structure
| Link | What it is                  |
|------|-----------------------------|
| 1    | Bench body (root)           |
| 2    | Prep surface prim            |
| 3    | Burner/heat element          |
| 4    | Output tray                  |
| 5    | Particle emitter (steam/vapor) |

### Sounds Required
| Sound Name | When                               |
|------------|------------------------------------|
| cook_done  | After edibles craft completes      |
| press_done | After concentrate press completes  |

---

## WEARABLE PIECE (Pipe, Bong, Dab Rig)

### How It Works
These are **persistent wearables** — the player keeps them in inventory
and attaches them manually. Unlike the Smokeable temp-attach (which
is a disposable spawned by the jar), wearable pieces live in your
inventory permanently.

The piece doesn't consume flower. Instead it listens on the owner's
HUD channel and **reacts to TC_SMOKED events** — any time the player
smokes (from jar, rolling table output, edibles, etc.) the piece
fires its visual effects.

This means the piece always matches what the player is actually doing,
without needing a separate consume flow.

### Setting Up Each Object
The `PIECE_TYPE` constant at the top of the script must match the object:

```
// In TC_Pipe:
string PIECE_TYPE = "pipe";

// In TC_Bong:
string PIECE_TYPE = "bong";

// In TC_DabRig:
string PIECE_TYPE = "dab_rig";
```

Copy the script three times, change PIECE_TYPE in each, drop into
the corresponding object.

### Attachment Points
| Piece   | Attachment Point |
|---------|-----------------|
| Pipe    | Right Hand      |
| Bong    | Left Hand       |
| Dab Rig | Right Hand      |

### Visual Layers
| State            | Particles          | Bowl/Nail Glow |
|------------------|--------------------|----------------|
| Idle (no strain) | None               | Off            |
| Idle (strain set)| Faint wisp         | Very low       |
| Session mode     | Medium ambient     | Low            |
| Hit (TC_SMOKED)  | Full burst, 4–6s   | Bright flash   |

Dab rig gets a denser, longer hit burst to reflect concentrate potency.

### Owner Touch Menu
While wearing the piece, the player can touch it to:
- Toggle effects on/off (for photo mode or lag-sensitive areas)
- Clear the current strain (resets display)
- Detach the piece

### Sounds Required
| Sound Name | When                        |
|------------|-----------------------------|
| piece_hit  | On TC_SMOKED / hit burst    |

### Prim Link Structure
| Link | What it is                         |
|------|------------------------------------|
| 1    | Piece body (root)                  |
| 2    | Bowl/nail glow element              |
| 3    | Smoke emitter tip (if 3-prim build) |

If your mesh is single-prim, the particle system defaults to root.
Link 2 needs to exist for the bowl glow. Minimum: 2 linked prims.

---

## COMPLETE ECOSYSTEM — PHASE 3 STATUS

### All Objects Built
| Phase   | Object             | Scripts | Status |
|---------|--------------------|---------|--------|
| Phase 1 | HUD                | 5       | ✅ Done |
| Phase 1 | Plant / Pot        | 3       | ✅ Done |
| Phase 2 | Bagging Table      | 2 + bag | ✅ Done |
| Phase 2 | Weed Jar           | 3       | ✅ Done |
| Phase 2 | Session Object     | 2       | ✅ Done |
| Phase 2 | Plug Board         | 2       | ✅ Done |
| Phase 3 | Rolling Table      | 1       | ✅ Done |
| Phase 3 | Edibles Bench      | 1       | ✅ Done |
| Phase 3 | Wearable Pieces    | 1       | ✅ Done |

### Total Script Count: 21 scripts

---

## FULL ITEM FLOW

```
GROW    → flower_raw in HUD inventory
            │
            ├─→ ROLLING TABLE   → joint / blunt / spliff
            │                      → smoke with jar or HUD directly
            │
            ├─→ EDIBLES BENCH   → brownie / gummy / drink / concentrate
            │                      → smoke/consume with HUD
            │
            ├─→ BAGGING TABLE   → physical bag objects
            │                      → Plug Board for sale
            │                      → Weed Jar for personal/session use
            │
            └─→ WEED JAR        → smoke directly
                                   → open to group/session
```

### Phase 4 (Optional Expansion)
- Stash Box — lockable storage display for jars and bags
- Grow Light — attach to plant area for faster exotic growth
- Strain Drops — limited edition HTTP-delivered seeds
- Loyalty Group system — early access, exclusive strains
