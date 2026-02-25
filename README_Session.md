# THE CULTIVAR — Session Object Script Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script                          | Job                                                                 |
|---------------------------------|---------------------------------------------------------------------|
| TheCultivar_Session_Core.lsl    | Participant management, invites, passing, sync, teardown            |
| TheCultivar_Session_Effects.lsl | All visuals — ambient smoke, glow ring, ember pulse, pass beam      |

---

## SESSION OBJECT PRIM STRUCTURE

| Link | What it is                                              |
|------|---------------------------------------------------------|
| 1    | Root — ashtray/centerpiece mesh body                    |
| 2    | Ambient smoke emitter (rising column, quality-tinted)   |
| 3    | Glow ring (quality color, pulses while active)          |
| 4    | Pass effect emitter (directional beam on pass)          |
| 5    | Ember glow (slow breathing pulse, quality-colored)      |

---

## FULL SESSION LIFECYCLE

```
Host hits "Spark Session" on HUD
          ↓
HUD_UI rezzes TC_SessionObject near avatar
          ↓
Session object announces TC_SESSION_REZZED on TC_OBJECT_PING_CHAN
          ↓
HUD_Comms → HUD_UI: SESSION_OBJECT_READY
          ↓
HUD_UI shows strain quality picker to host
          ↓
Host picks quality → HUD_UI sends TC_SESSION_START to session object
          ↓
Session object adds host as participant #1
          ↓
Effects script starts ambient smoke + glow ring + ember pulse
          ↓
Session broadcasts TC_SESSION_INVITE every 30s on PUBLIC_SESSION_CHAN
          ↓
Nearby HUDs show invite dialog
          ↓
Players who accept → HUD sends TC_SESSION_JOIN on PUBLIC_SESSION_CHAN
          ↓
Session object adds them, syncs their animation via TC_SESSION_SYNC
          ↓
PASSING:
  Current holder clicks "Pass" on their HUD
  → HUD sends TC_PASS_REQUEST to session object on session channel
  → Session object shows pass menu (pick person or next in rotation)
  → TC_PASS_RECEIVED sent to new holder's HUD → receive animation
  → TC_PASS_GIVEN sent to old holder's HUD → give animation
  → Pass effect beam fires on session object
          ↓
SESSION ENDS when:
  Host ends it manually
  Everyone leaves
          ↓
TC_SESSION_END sent to all participant HUDs
→ All animations stop
→ All HUDs mark session as inactive
→ Session object dies
```

---

## PASSING SYSTEM

Two ways to pass:
- **Next In Rotation** — goes to the next person in join order (clockwise)
- **Named pass** — pick a specific person from the list

Only the current holder can pass. If someone who doesn't have it tries to pass, they get a message telling them who does.

Max 8 participants (limited by LSL dialog button count).

---

## HUD UPDATES IN THIS VERSION (v1.2)

**TheCultivar_HUD_Comms.lsl:**
- Added TC_SESSION_REZZED handler → forwards to UI as SESSION_OBJECT_READY
- Added TC_SESSION_JOINED handler → stores session object key, notifies UI
- Added TC_PASS_RECEIVED handler → triggers receive animation + stat update
- Added TC_PASS_GIVEN handler → triggers give animation
- Added TC_SESSION_MEMBER_JOIN/LEAVE → forwards to UI for notifications

**TheCultivar_HUD_UI.lsl:**
- Added g_sessionObjectKey variable
- Added showSessionStrainMenu() function
- Added SESSION_OBJECT_READY handler — shows quality picker, sends TC_SESSION_START
- Added session member join/leave notification handlers
- Added -55555 dialog channel handler for strain quality selection

---

## SOUNDS REQUIRED (place in session object inventory)

| Sound Name    | When It Plays                        |
|---------------|--------------------------------------|
| session_start | When host sparks the session         |
| session_end   | When the session ends                |
| pass_whoosh   | When the item is passed              |

---

## WHAT'S NEXT

Next object to build: **The Plug Board**
The player-run vendor. Stocked bags sit on it with prices set.
Anyone can browse and buy directly with L$.
Handles llGiveMoney transactions and TC_SALE_COMPLETE notifications.
