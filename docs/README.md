[README_HUD.md](https://github.com/user-attachments/files/25544595/README_HUD.md)
# THE CULTIVAR — HUD Script Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script              | Job                                                                 |
|---------------------|---------------------------------------------------------------------|
| HUD_Identity.lsl    | Player profile, lifetime stats, strain history, rep score           |
| HUD_Inventory.lsl   | All carried items — seeds, flower, rolled items, bags, consumables  |
| HUD_Comms.lsl       | ALL external communication with world objects and other HUDs        |
| HUD_Animation.lsl   | Avatar animation playback — idle, puff, pass                        |
| HUD_UI.lsl          | Button touches, dialog menus, display updates                       |

All 5 scripts live **inside the same HUD object** and talk to each other
via llMessageLinked on shared internal channels.

---

## INTERNAL CHANNEL MAP

These integers are defined at the top of every script. Never change them
mid-project or scripts will stop hearing each other.

| Channel | Owner        | Purpose                                         |
|---------|--------------|-------------------------------------------------|
| 100     | UI           | Button presses, menu events, display updates    |
| 200     | Comms        | External relay — world objects, other HUDs      |
| 300     | Inventory    | Add/remove/query items                          |
| 400     | Identity     | Player data, stats, rep                         |
| 500     | Animation    | Start/stop/switch animations                    |

---

## HUD PRIM SETUP

Your HUD linkset needs these named prims for the touch system to work.
Name each button prim exactly as shown:

- btn_smoke
- btn_inventory
- btn_grow
- btn_session
- btn_pass
- btn_stats
- btn_store

The root prim name doesn't matter — any unlabeled touch opens the main menu.

---

## ANIMATIONS REQUIRED (store in HUD object inventory)

The animation script (v1.1+) is gender-aware. It detects the avatar's body
shape type (`OBJECT_BODY_SHAPE_TYPE`) and appends `_female` or `_male` to
every animation name before playing it. If the gendered variant is not found
in inventory it falls back to the non-gendered base name automatically.

You can ship a HUD with only one set (e.g. all `_female`) and it will work
for everyone — players with a male body shape just get the fallback.

**Idle Anims (loop while smoking) — provide both variants per quality tier:**

| Base name (fallback)         | Female variant                      | Male variant                      |
|------------------------------|-------------------------------------|-----------------------------------|
| smoke_joint_reggie_idle      | smoke_joint_reggie_idle_female      | smoke_joint_reggie_idle_male      |
| smoke_joint_mids_idle        | smoke_joint_mids_idle_female        | smoke_joint_mids_idle_male        |
| smoke_joint_loud_idle        | smoke_joint_loud_idle_female        | smoke_joint_loud_idle_male        |
| smoke_joint_exotic_idle      | smoke_joint_exotic_idle_female      | smoke_joint_exotic_idle_male      |
| smoke_blunt_reggie_idle      | smoke_blunt_reggie_idle_female      | smoke_blunt_reggie_idle_male      |
| smoke_blunt_mids_idle        | smoke_blunt_mids_idle_female        | smoke_blunt_mids_idle_male        |
| smoke_blunt_loud_idle        | smoke_blunt_loud_idle_female        | smoke_blunt_loud_idle_male        |
| smoke_blunt_exotic_idle      | smoke_blunt_exotic_idle_female      | smoke_blunt_exotic_idle_male      |
| smoke_pipe_reggie_idle       | smoke_pipe_reggie_idle_female       | smoke_pipe_reggie_idle_male       |
| smoke_pipe_mids_idle         | smoke_pipe_mids_idle_female         | smoke_pipe_mids_idle_male         |
| smoke_pipe_loud_idle         | smoke_pipe_loud_idle_female         | smoke_pipe_loud_idle_male         |
| smoke_pipe_exotic_idle       | smoke_pipe_exotic_idle_female       | smoke_pipe_exotic_idle_male       |
| smoke_bong_reggie_idle       | smoke_bong_reggie_idle_female       | smoke_bong_reggie_idle_male       |
| smoke_bong_mids_idle         | smoke_bong_mids_idle_female         | smoke_bong_mids_idle_male         |
| smoke_bong_loud_idle         | smoke_bong_loud_idle_female         | smoke_bong_loud_idle_male         |
| smoke_bong_exotic_idle       | smoke_bong_exotic_idle_female       | smoke_bong_exotic_idle_male       |

**Action Anims (one-shot) — provide both variants:**

| Base name (fallback) | Female variant        | Male variant        | Duration   |
|----------------------|-----------------------|---------------------|------------|
| smoke_puff           | smoke_puff_female     | smoke_puff_male     | ~2.5 s     |
| pass_give            | pass_give_female      | pass_give_male      | ~2.0 s     |
| pass_receive         | pass_receive_female   | pass_receive_male   | ~2.0 s     |

**Fallback chain:** gendered variant → base name → `smoke_joint_reggie_idle[_gender]` → `smoke_joint_reggie_idle` → owner message if still missing.

---

## OBJECTS THAT MUST BE IN HUD INVENTORY

- TC_SessionObject  (the object rezzed at player feet when a session starts)

---

## EXTERNAL COMMUNICATION PROTOCOL

All world objects (plants, jars, tables) communicate with the HUD on a
**private channel derived from the owner's UUID**:

```
channel = (integer)("0x" + first 6 chars of owner UUID) * -1
```

This is calculated in HUD_Comms.lsl (derivePrivateChannel function).
All world object scripts must use the same formula to find their owner's HUD.

World objects send messages in this format:
```
TC_COMMAND|param1|param2|...
```

All TC_ prefixed commands are from world objects.
All internal commands (no prefix) are between HUD scripts.

---

## DATA PERSISTENCE

Both Identity and Inventory use **llLinksetDataWrite** for persistence.
This means player data and inventory survive:
- Sim restarts
- Relog
- Re-rez of the HUD

Keys used:
- id_name, id_smoked, id_grown, id_passed, id_sold, id_fav,
  id_history, id_rep, id_joined  (Identity script)
- inv_data  (Inventory script — full serialized inventory string)

---

## INVENTORY ITEM FORMAT

Items are stored as a strided list (stride = 5) serialized to a string.
Delimiter between fields: ~
Delimiter between items: ^

Field order per item:
1. itemType     (joint, flower_raw, seed_raw, bag_eighth, etc.)
2. strainName   (OG Kush, Blue Dream, etc.)
3. quality      (reggie, mids, loud, exotic)
4. quantity     (integer)
5. packager     (avatar name who grew/rolled/bagged it)

---

## WHAT'S NEXT (future scripts to build on this foundation)

1. **Plant/Pot Object** — grow system, timer, harvest flow
2. **Bagging Table** — flower → bag crafting
3. **Interactive Jar** — display storage, session dispensing
4. **Session Object** — rezzed by HUD, syncs group animations
5. **Plug Board** — player-run vendor, llGiveMoney transactions
6. **Crafting Table** — rolling, edibles, concentrates

Each of these will use the same TC_ protocol to talk back to this HUD.

---

## KNOWN LIMITATIONS / TODO

- Pass menu flow (HUD_UI.lsl) shares the smoke menu temporarily.
  A future update should separate pass flow with a dedicated state flag.
- Favorite strain tracking is currently "last smoked."
  A future version should track count per strain and pick the highest.
- Session invite accept dialog in HUD_UI.lsl uses an inline listen.
  Should be moved to a proper handler for cleanliness.
- Store URL in HUD_UI.lsl (btn_store) needs to be replaced with
  your actual marketplace URL before release.
