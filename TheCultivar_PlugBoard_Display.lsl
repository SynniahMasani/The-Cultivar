// ================================================================
// THE CULTIVAR  -  Plug Board Display Script
// Version: 1.1
// Handles: Visual updates for each listing slot prim.
//          Kept separate from main so visual glitches never
//          interrupt payment processing or buyer menus.
//
// PRIM LINK STRUCTURE:
//   Link 1  (root)   : Board frame body  -  main script lives here
//   Links 2 - 9      : Listing slot prims (up to 8 slots)
//   Link 10          : Open/Closed sign prim
//   Link 11          : Profile_Pic  -  managed by Main script only
//   Link 12          : Frame  -  decorative, no script interaction
//
// NOTE: This script only writes to links 2-10. Links 11 and 12 are
//       never touched here.
//
// SLOT PRIM VISUAL STATES:
//   Empty slot     : grey, no glow, blank hover text
//   Unpriced slot  : quality color, dim glow, "Set Price" hover
//   Listed slot    : quality color, active glow, full listing hover
//   Sold out slot  : grey, no glow, "Sold Out" hover (brief)
//
// QUALITY COLORS:
//   Reggie  -> muted brown/tan    <0.55, 0.45, 0.3>
//   Mids    -> amber              <1.0,  0.85, 0.2>
//   Loud    -> green              <0.2,  0.85, 0.3>
//   Exotic  -> purple             <0.7,  0.3,  1.0>
// ================================================================

integer PCHAN_DISPLAY = 4000;

// Cached listing data parsed from UPDATE_DISPLAY message
// Stride 5: [strain, quality, packager, weightG, price]
list    g_slots;
integer SLOT_STRIDE = 5;
integer MAX_SLOTS   = 8;
integer g_boardOpen = TRUE;
integer g_count     = 0;
integer g_flashSlot = -1; // slot index pending clearSlot after sold flash

// Link numbers for slot prims and sign
integer FIRST_SLOT_LINK = 2;
integer SIGN_LINK       = 10;

// ----------------------------------------------------------------
// Quality color vector
// ----------------------------------------------------------------
vector qualColor(string quality)
{
    if (quality == "mids")   return <1.0,  0.85, 0.2>;
    if (quality == "loud")   return <0.2,  0.85, 0.3>;
    if (quality == "exotic") return <0.7,  0.3,  1.0>;
    return <0.55, 0.45, 0.3>; // reggie
}

// ----------------------------------------------------------------
// Quality tier short label for hover text
// ----------------------------------------------------------------
string qualLabel(string quality)
{
    if (quality == "mids")   return "Mids ?";
    if (quality == "loud")   return "Loud ??";
    if (quality == "exotic") return "Exotic ?";
    return "Reggie";
}

// ----------------------------------------------------------------
// Update a single slot prim (links 2 - 9)
// ----------------------------------------------------------------
updateSlot(integer slot, string strain, string quality,
           string packager, integer weight, integer price)
{
    integer linkNum = FIRST_SLOT_LINK + slot;

    vector col  = qualColor(quality);
    float  glow = 0.04;
    if (price > 0) glow = 0.12;

    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_COLOR, ALL_SIDES, col, 1.0,
        PRIM_GLOW,  ALL_SIDES, glow
    ]);

    string priceStr = "[ unpriced ]";
    if (price > 0) priceStr = "L$" + (string)price;
    string hoverText =
        qualLabel(quality) + "  " + strain + "\n" +
        (string)weight + "g  ?  by " + packager + "\n" +
        priceStr;

    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_TEXT, hoverText, col, 1.0
    ]);
}

// ----------------------------------------------------------------
// Clear a slot prim to empty state
// ----------------------------------------------------------------
clearSlot(integer slot)
{
    integer linkNum = FIRST_SLOT_LINK + slot;
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_COLOR, ALL_SIDES, <0.35, 0.35, 0.35>, 0.6,
        PRIM_GLOW,  ALL_SIDES, 0.0,
        PRIM_TEXT,  "", ZERO_VECTOR, 0.0
    ]);
}

// ----------------------------------------------------------------
// Update the open/closed sign prim (link 10)
// ----------------------------------------------------------------
updateSign()
{
    if (g_boardOpen)
    {
        llSetLinkPrimitiveParamsFast(SIGN_LINK, [
            PRIM_COLOR, ALL_SIDES, <0.2, 0.9, 0.3>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.08,
            PRIM_TEXT,  "OPEN", <0.2, 0.9, 0.3>, 1.0
        ]);
    }
    else
    {
        llSetLinkPrimitiveParamsFast(SIGN_LINK, [
            PRIM_COLOR, ALL_SIDES, <0.8, 0.2, 0.2>, 1.0,
            PRIM_GLOW,  ALL_SIDES, 0.04,
            PRIM_TEXT,  "CLOSED", <0.8, 0.2, 0.2>, 1.0
        ]);
    }
}

// ----------------------------------------------------------------
// Full display refresh from serialized data
//
// Data format from main script:
//   "count|boardOpen|strain~quality~packager~weight~price|..."
// ----------------------------------------------------------------
parseAndRefresh(string data)
{
    list topParts = llParseString2List(data, ["|"], []);
    g_count     = (integer)llList2String(topParts, 0);
    g_boardOpen = (integer)llList2String(topParts, 1);
    g_slots     = [];

    integer i;
    for (i = 0; i < g_count; i++)
    {
        string slotStr = llList2String(topParts, 2 + i);
        list   fields  = llParseString2List(slotStr, ["~"], []);

        if (llGetListLength(fields) == 5)
        {
            g_slots += [
                llList2String(fields,  0),   // strain
                llList2String(fields,  1),   // quality
                llList2String(fields,  2),   // packager
                llList2Integer(fields, 3),   // weight
                llList2Integer(fields, 4)    // price
            ];
        }
    }

    // Refresh all slot prims
    for (i = 0; i < MAX_SLOTS; i++)
    {
        if (i < g_count)
        {
            integer base = i * SLOT_STRIDE;
            updateSlot(i,
                llList2String(g_slots,  base),
                llList2String(g_slots,  base + 1),
                llList2String(g_slots,  base + 2),
                llList2Integer(g_slots, base + 3),
                llList2Integer(g_slots, base + 4));
        }
        else
        {
            clearSlot(i);
        }
    }

    updateSign();
}

// ----------------------------------------------------------------
// Brief "SOLD" flash on a slot before clearing it
// Uses timer to avoid llSleep in link_message handler
// ----------------------------------------------------------------
flashSold(integer slot)
{
    integer linkNum = FIRST_SLOT_LINK + slot;
    llSetLinkPrimitiveParamsFast(linkNum, [
        PRIM_COLOR, ALL_SIDES, <0.9, 0.9, 0.2>, 1.0,
        PRIM_GLOW,  ALL_SIDES, 0.2,
        PRIM_TEXT,  "SOLD", <1.0, 1.0, 0.0>, 1.0
    ]);
    g_flashSlot = slot;
    llSetTimerEvent(2.0);
}

// ================================================================
default
{
    state_entry()
    {
        // Initialize all slots to empty on script start
        integer i;
        for (i = 0; i < MAX_SLOTS; i++)
            clearSlot(i);
        updateSign();
    }

    timer()
    {
        // Clear the slot that showed the "SOLD" flash
        if (g_flashSlot >= 0)
        {
            clearSlot(g_flashSlot);
            g_flashSlot = -1;
        }
        llSetTimerEvent(0.0);
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != PCHAN_DISPLAY) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (cmd == "UPDATE_DISPLAY")
        {
            // Full refresh
            parseAndRefresh(llGetSubString(msg, llSubStringIndex(msg, "|") + 1, -1));
        }

        else if (cmd == "FLASH_SOLD")
        {
            // Brief sold animation on a specific slot
            integer slot = (integer)llList2String(parts, 1);
            flashSold(slot);
        }

        else if (cmd == "BOARD_OPEN")
        {
            g_boardOpen = TRUE;
            updateSign();
        }

        else if (cmd == "BOARD_CLOSED")
        {
            g_boardOpen = FALSE;
            updateSign();
        }
    }
}
