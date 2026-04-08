# THE CULTIVAR — Plug Board Script Package
## Version 1.0 | Setup & Developer Notes

---

## WHAT'S IN THIS PACKAGE

| Script                            | Job                                                               |
|-----------------------------------|-------------------------------------------------------------------|
| TheCultivar_PlugBoard_Main.lsl    | Vendor logic, pricing, payment, bag delivery, HUD notifications   |
| TheCultivar_PlugBoard_Display.lsl | Slot prim visuals, quality colors, open/closed sign               |

---

## PRIM LINK STRUCTURE

| Link  | What it is                                                   |
|-------|--------------------------------------------------------------|
| 1     | Root — board frame/body — Main script goes here              |
| 2–9   | Listing slot prims (up to 8 slots, one bag per slot)         |
| 10    | Open/Closed sign prim                                        |

Display script goes in the root prim alongside Main.
Both scripts communicate via llMessageLinked on channel 4000.

Slot prims (links 2–9) should be simple flat panels or small mesh
frames that sit on the board face. They'll light up with quality
colors when stocked.

---

## HOW TO STOCK

1. Rez the board on your land
2. Open the board's inventory (right-click → Edit → Contents tab)
3. Drag bag objects from your inventory into the board
4. The board detects the new bags via CHANGED_INVENTORY and updates automatically
5. Touch the board → Set Prices → pick each slot and set a price
6. Board is now live

**Bag naming requirement:**
Bags must follow the naming format set by the Bagging Table:
```
TC_Bag_[Size]:[strain]:[quality]:[packager]:[weight]g
```
Example: `TC_Bag_Eighth:OG Kush:loud:FarmerJoe:7g`

Bags created with the Cultivar Bagging Table are automatically
named in this format. Manually named bags will also work as long
as they follow the convention exactly.

---

## HOW BUYING WORKS

```
Buyer touches board
       ↓
Browse menu shows all priced listings
       ↓
Buyer picks a listing → confirmation dialog
       ↓
Buyer right-clicks board → Pay → enters price
       ↓
Board verifies payment, gives bag, pays seller
       ↓
Seller's HUD receives TC_SALE_COMPLETE notification
       ↓
Board updates display — sold slot cleared
```

If the board is paid without an active browse selection, the
payment is refunded automatically. This prevents accidents.

---

## PRICING

Prices are stored in llLinksetData keyed by slot index (`price_0`,
`price_1`, etc.). They survive sim restarts — you don't need to
reprice after a relog.

Available price presets: L$50, L$75, L$100, L$150, L$200, L$300,
L$400, L$500, L$750, L$1000, L$1500.

Unpriced listings are visible to the owner but hidden from buyers.
This lets you stock the board and price later without showing
half-finished listings.

---

## BOARD STATS

Owner menu → Board Stats shows:
- Currently listed count
- Total bags sold (lifetime)
- Total L$ earned (lifetime)
- Total unique visitor touches

Stats persist in llLinksetData and survive restarts.

---

## SLOT VISUAL STATES

| State      | Color               | Glow   | Hover Text         |
|------------|---------------------|--------|--------------------|
| Empty      | Grey                | None   | Blank              |
| Unpriced   | Quality color (dim) | Low    | "[ unpriced ]"     |
| For Sale   | Quality color       | Active | Strain, weight, price |
| Just Sold  | Yellow flash        | Bright | "SOLD" (2 seconds) |

Quality glow ring colors match the rest of The Cultivar product line:
- Reggie → earthy brown/tan
- Mids   → amber/yellow
- Loud   → green
- Exotic → purple

---

## OPEN / CLOSED

Owner menu → Close Board / Open Board toggles availability.
When closed, buyers see a message and can't browse.
The sign prim (link 10) shows green "OPEN" or red "CLOSED".
Pricing and stocking still works while closed.

---

## PERMISSIONS FOR STOCKED BAGS

Bags inside the board need:
- **Copy: YES** — so the board can give one to the buyer
- **Transfer: YES** — so the buyer receives it

If bags are No-Copy, the board will still give them but they'll
be removed from its inventory on sale (correct behavior for
limited/no-copy items). The CHANGED_INVENTORY event will fire
and the board will rebuild its listing automatically.

---

## HUD INTEGRATION

When a sale completes, the board sends:
```
TC_SALE_COMPLETE|[price]|[buyerName]
```
...to the seller's HUD on their private channel.

The HUD_Comms script handles this by:
- Incrementing the seller's total_sold stat in HUD_Identity
- Displaying a sale notification to the owner

This is the same message the Bag object sends when it's sold
directly — they use identical formats so HUD_Identity only needs
one handler.

---

## WHAT'S NEXT

**Phase 3 is complete.** The full ecosystem is now:

✅ HUD (5 scripts)
✅ Plant / Pot System (3 scripts)
✅ Bagging Table (2 scripts + bag object)
✅ Weed Jar (3 scripts)
✅ Session Object (2 scripts)
✅ Plug Board (2 scripts)

**Phase 3 — Wearables & Crafting:**
- Rolling Table (joint, blunt, spliff crafting)
- Wearable dab rig, pipe, bong (attachment objects)
- Edibles crafting (brownies, gummies)
- Concentrate press
