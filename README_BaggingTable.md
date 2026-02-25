# THE CULTIVAR — Bagging Table Script Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script                            | Job                                                              |
|-----------------------------------|------------------------------------------------------------------|
| TheCultivar_BaggingTable_Main.lsl | Core table logic — HUD comms, menus, flower consumption, bag giving |
| TheCultivar_Bag.lsl               | Lives inside each physical bag object the player receives        |
| HUD_Comms_Patch_Notes.lsl         | Reference file — all patches have been applied to HUD scripts    |

---

## BAG OBJECT INVENTORY REQUIRED

The table must contain these objects in its inventory.
Each must have Copy/Transfer permissions (no Modify is fine).
Each must contain TheCultivar_Bag.lsl.

| Object Name       | Weight | Cost   |
|-------------------|--------|--------|
| TC_Bag_Dime       | 1g     | 1g flower  |
| TC_Bag_Eighth     | 4g     | 4g flower  |
| TC_Bag_Quarter    | 7g     | 7g flower  |
| TC_Bag_Half       | 14g    | 14g flower |
| TC_Bag_Oz         | 28g    | 28g flower |

---

## HOW THE FLOW WORKS

```
Player touches table
       ↓
Table pings TC_OBJECT_PING_CHAN (-111222333)
       ↓
HUD_Comms hears ping → sends TC_REGISTER to table on channel 0
       ↓
Table has owner's private channel
       ↓
Table sends TC_INVENTORY_REQUEST|flower_raw|tableKey on private channel
       ↓
HUD_Comms → HUD_Inventory → filtered flower list back to table
       ↓
Player picks strain + bag size → confirms
       ↓
Table sends TC_REMOVE_ITEM on private channel
       ↓
HUD removes flower → sends TC_REMOVE_OK (or TC_REMOVE_FAIL) to table
       ↓
Table gives bag object to player + sends TC_ADD_ITEM to HUD inventory
       ↓
Player receives physical bag in their SL inventory
```

---

## BAG OBJECT DATA FORMAT

Strain data is stored in the bag object's Description field:

```
strain:quality:packager:weightg:forSale:price
```

Example: `OG Kush:loud:FarmerJoe:7g:0:0`

This makes the bag self-contained and survives transfers between players.

---

## BAG STATES

**Personal** — Only the owner can interact with it.
Can be loaded into a jar or passed to another player.

**For Sale** — Anyone can buy it by paying the bag object directly.
Owner sets the price from the owner menu (L$50–L$1000 presets).
Paying the object triggers the money() event which handles the transaction.
Owner gets paid, buyer gets the bag, bag self-destructs.

---

## HOVER TEXT COLOR CODING

| Quality | Color       |
|---------|-------------|
| Reggie  | Grey        |
| Mids    | Yellow      |
| Loud    | Green       |
| Exotic  | Purple      |

---

## HUD UPDATES APPLIED (v1.1)

The following changes were applied to the HUD scripts as part of
this package. HUD version bumps to 1.1.

**TheCultivar_HUD_Comms.lsl:**
- Added TC_OBJECT_PING_CHAN constant
- Added ping channel listener in startListening()
- Added TC_PING handler → responds with TC_REGISTER to world objects
- Added TC_INVENTORY_REQUEST handler
- Added TC_ADD_ITEM handler
- Added TC_REMOVE_ITEM handler
- Updated REMOVE_SUCCESS/FAIL to notify requesting world objects
- Added RAW_INVENTORY forwarder to requesting world objects

**TheCultivar_HUD_Inventory.lsl:**
- Updated REQUEST_RAW_INVENTORY to accept filterType and reqObjKey
- Supports filtered inventory dumps (e.g. flower_raw only)

---

## SOUNDS REQUIRED (place in table object inventory)

| Sound Name   | When It Plays                   |
|--------------|---------------------------------|
| bag_rustle   | When a bag is successfully made |

---

## WHAT'S NEXT

Next object to build: **Interactive Weed Jar**
The jar uses the same TC_PING registration flow.
It displays fill level visually, is strain-aware,
and integrates with the session system.
