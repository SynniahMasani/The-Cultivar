# THE CULTIVAR — Plant/Pot Script Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script                  | Job                                                                    |
|-------------------------|------------------------------------------------------------------------|
| Plant_Grow.lsl          | Core growth timer, strain data, stage logic, yield/quality calculation |
| Plant_Interaction.lsl   | Touch handler, all dialog menus, player action validation              |
| Plant_Persistence.lsl   | State save/load with sim-restart recovery and automatic fast-forward   |

All 3 scripts live **inside the same plant object** and talk to each other
via llMessageLinked on shared internal channels.

---

## INTERNAL CHANNEL MAP (plant-only, separate from HUD channels)

| Channel | Purpose                                              |
|---------|------------------------------------------------------|
| 1000    | Grow ↔ Interaction (stage updates, commands, status) |
| 1100    | Grow ↔ Persistence (save/load triggers)              |

---

## PRIM LINK STRUCTURE

Name or number your prims exactly as follows. Adjust link numbers in
Plant_Grow.lsl if your build differs.

| Link | What it is                                                       |
|------|------------------------------------------------------------------|
| 1    | Root prim (pot body)                                             |
| 2    | Plant mesh (scaled/modified at each growth stage)                |
| 3    | Particle emitter (hidden until harvest-ready, then sparkles)     |
| 4    | Water indicator light (green = watered, red = needs water)       |
| 5    | Fertilizer indicator light (yellow glow when fertilized)         |

---

## GROWTH STAGES

| Stage | Name          | Visual                  | Duration (by tier)                    |
|-------|---------------|-------------------------|---------------------------------------|
| 0     | Empty         | Pot only                | N/A                                   |
| 1     | Seedling      | Tiny sprout             | 1/4 of full cycle                     |
| 2     | Vegetative    | Medium plant            | 1/4 of full cycle (fertilize here)    |
| 3     | Flowering     | Full size               | 1/4 of full cycle                     |
| 4     | Harvest Ready | Full + sparkle glow     | Waits until player harvests           |

---

## GROW TIMES BY QUALITY TIER

| Tier   | Full Cycle | Per Stage   |
|--------|-----------|-------------|
| Reggie | 45 min    | ~11 min     |
| Mids   | 2 hours   | 30 min      |
| Loud   | 4 hours   | 1 hour      |
| Exotic | 8 hours   | 2 hours     |

Premium pot applies a 5% speed bonus to all stage durations.

---

## WATER MECHANICS

- Plant must be watered once per stage (stages 1–3) to advance.
- If a stage timer completes but the plant is not watered, it waits
  with a notification to the owner. No death, no yield loss from
  missing water — just a delay.
- Water resets each stage so the player needs to water 3 times total
  across a full grow cycle.

---

## FERTILIZER MECHANICS

- Applied during vegetative stage (stage 2) ONLY.
- One application per grow cycle.
- Basic fertilizer : +10% yield
- Premium fertilizer: +25% yield, -15% remaining stage time
- Exotic fertilizer : +50% yield, -15% remaining stage time, +1 quality tier at harvest

---

## STRAIN TABLE

| Strain              | Tier   | Yield Range |
|---------------------|--------|-------------|
| Schwag              | Reggie | 4–8g        |
| Zone                | Reggie | 3–7g        |
| Brown Frown         | Reggie | 3–6g        |
| Blue Dream          | Mids   | 8–14g       |
| Green Crack         | Mids   | 9–15g       |
| Gorilla Glue        | Mids   | 8–14g       |
| Sour Diesel         | Mids   | 9–16g       |
| OG Kush             | Loud   | 14–20g      |
| Wedding Cake        | Loud   | 15–22g      |
| Zkittlez            | Loud   | 14–21g      |
| Gelato              | Loud   | 15–22g      |
| Runtz               | Exotic | 20–28g      |
| Biscotti            | Exotic | 21–29g      |
| Jealousy            | Exotic | 20–28g      |
| Lemon Cherry Gelato | Exotic | 22–30g      |

---

## HOW THE PLANT TALKS TO THE HUD

The plant derives the owner's private HUD channel using the same
formula as HUD_Comms.lsl:

```
channel = (integer)("0x" + first 6 chars of owner UUID) * -1
```

On harvest, the plant sends directly to the owner's avatar key
on that derived channel:

```
TC_HARVEST_RESULT|strainName|quality|qty
```

The HUD_Comms script receives this and routes it to HUD_Inventory
and HUD_Identity automatically.

---

## SIM RESTART RECOVERY

Plant_Persistence.lsl stores state in two places:
1. llLinksetDataWrite (primary — survives restarts cleanly)
2. Object description field (backup — readable even if scripts break)

On restart, the persistence script:
1. Loads the saved state
2. Compares stageStartTime against the current Unix timestamp
3. Fast-forwards through any stages that completed while the sim was down
4. Forgives water requirements for stages that passed during downtime
5. Notifies the owner what stage their plant is at on relog

---

## ADDING NEW STRAINS

Edit the STRAIN_DATA list in Plant_Grow.lsl.
Each entry is exactly 5 fields (STRAIN_STRIDE = 5):
```
"Strain Name", qualityTier, yieldMin, yieldMax, "Flavor text."
```
Quality tiers: 0=Reggie, 1=Mids, 2=Loud, 3=Exotic

Also add the strain name to the simplified lookup list in
Plant_Interaction.lsl (the STRAIN_DATA list at the top of
showStrainMenu) so it appears in the planting menu.

---

## WHAT'S NEXT

Next object to build: **Bagging Table**
It receives flower_raw from the player's HUD inventory and
outputs physical bag objects (dime, eighth, quarter, oz)
with strain, quality, and packager data stamped in.
