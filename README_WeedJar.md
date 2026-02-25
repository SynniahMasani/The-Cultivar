# THE CULTIVAR — Weed Jar Script Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script                          | Job                                                              |
|---------------------------------|------------------------------------------------------------------|
| TheCultivar_WeedJar_Main.lsl    | Core jar logic — fill level, strain data, menus, HUD comms      |
| TheCultivar_WeedJar_Attach.lsl  | Temp-attach system — rezzes and attaches smokeable to hand       |
| TheCultivar_Smokeable.lsl       | Lives inside each joint/blunt — handles attachment and particles |

---

## PRIM LINK STRUCTURE

| Link | What it is                                             |
|------|--------------------------------------------------------|
| 1    | Root — jar body mesh                                   |
| 2    | Fill level mesh (Z-scaled by fill percentage)          |
| 3    | Lid mesh                                               |
| 4    | Particle emitter (idle wisps + smoke burst on use)     |
| 5    | Quality glow ring (color and glow change by tier)      |

The fill mesh (link 2) should be a simple cylinder or bud-texture plane
sitting inside the jar. Its Z scale is adjusted programmatically:
- Full (100%) : 0.08m tall
- Empty (0%)  : 0.001m (invisible)

Adjust the base height value `0.08` in `updateVisuals()` to match your mesh.

---

## JAR TYPES

| Type     | Capacity | Notes                                     |
|----------|----------|-------------------------------------------|
| Standard | 28g      | One oz. Default jar.                      |
| Premium  | 56g      | Two oz. Set g_jarType = "premium" on rez. |

Set the jar type by changing `g_jarType` default value in the script,
or by adding a second script that writes `jar_type` to llLinksetData
before the main script initializes.

---

## SMOKEABLE ASSETS (place in JAR object inventory)

Each must be a separate object with `TheCultivar_Smokeable.lsl` inside.
Permissions: Copy/Transfer, No Modify.

| Asset Name                | When Used                  |
|---------------------------|----------------------------|
| TC_Smoke_Joint_Reggie     | Reggie quality joint       |
| TC_Smoke_Joint_Mids       | Mids quality joint         |
| TC_Smoke_Joint_Loud       | Loud quality joint         |
| TC_Smoke_Joint_Exotic     | Exotic quality joint       |
| TC_Smoke_Blunt_Reggie     | Reggie quality blunt       |
| TC_Smoke_Blunt_Mids       | Mids quality blunt         |
| TC_Smoke_Blunt_Loud       | Loud quality blunt         |
| TC_Smoke_Blunt_Exotic     | Exotic quality blunt       |

The attach script defaults to "Joint" type. Change `g_smokeType` in
TheCultivar_WeedJar_Attach.lsl to "Blunt" for blunt-style jars.
You can add more types (Pipe, Bong) following the same naming pattern.

---

## TEMP-ATTACH SYSTEM

When a player takes from the jar:
1. WeedJar_Main tells WeedJar_Attach: `ATTACH|smokerKey|strain|quality`
2. Attach script selects the right smokeable asset by quality
3. Rezzes the smokeable near the smoker's position
4. Smokeable listens on a temp channel for `TC_ATTACH_TO` instructions
5. Smokeable calls `llAttachToAvatarTemp(ATTACH_RHAND)` — no inventory clutter
6. Smoke particles and sound play on the attachment
7. After 120 seconds the smokeable detaches and self-destructs

**Important:** `llAttachToAvatarTemp` only works when the object is
owned by the avatar being attached to. Since the jar owner rezzes the
smokeable, it works for the owner. For group/open access mode where
non-owners take from the jar, the smokeable is given to their inventory
instead and they wear it manually. This is an LSL limitation.

**No-rez zones:** The attach script attempts to rez and handles failure
gracefully by falling back to `llGiveInventory`.

---

## ACCESS MODES

| Mode       | Who Can Take      | How to Set              |
|------------|-------------------|-------------------------|
| Owner Only | Just you          | Default                 |
| Group      | Same SL group     | Set group on the object |
| Open       | Anyone on parcel  | Use carefully!          |

---

## FILL LEVEL DISPLAY

The hover text shows a visual bar:
```
████████ Full      (75–100%)
██████░░ Half      (50–74%)
████░░░░ Low       (25–49%)
██░░░░░░ Almost    (10–24%)
░░░░░░░░ Last Bit  (1–9%)
```

The quality glow ring color codes:
- Reggie → earthy brown
- Mids   → amber/yellow
- Loud   → green
- Exotic → purple

---

## LOADING THE JAR

Two ways to fill the jar:

**From Flower (raw harvest):**
Touch jar → Load Flower → pick strain from HUD inventory.
The jar consumes flower_raw directly via TC_REMOVE_ITEM.

**From Bag:**
Coming in a future update — bags will have a "Load Into Jar" option
that transfers the bag contents directly. The bag script already has
this button stub in its owner menu.

---

## SOUNDS REQUIRED (place in jar object inventory)

| Sound Name    | When It Plays                |
|---------------|------------------------------|
| jar_open      | When a player takes a hit    |
| smoke_inhale  | On the smokeable attachment  |

---

## SMOKE COOLDOWN

Default cooldown between takes is 8 seconds (`SMOKE_COOLDOWN`).
Prevents spam-clicking. Adjust in TheCultivar_WeedJar_Main.lsl.

---

## WHAT'S NEXT

Next object to build: **Session Object**
The session object is rezzed by the HUD when a player sparks a
session. It handles group invites, syncs animations across all
participants, and works with the jar in session mode so everyone
in the circle can take from it naturally.
