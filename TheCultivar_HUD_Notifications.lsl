// ================================================================
// THE CULTIVAR  -  HUD Notifications Script
// Version: 1.0
// Handles: Player notifications delivered via llInstantMessage.
//          Notification preferences stored in shared linkset data.
//
// Notification types:
//   harvest_ready   -  plant reached stage 4
//   sale_made       -  plug board sale completed
//   drop_live       -  drop machine activated
//   session_invite  -  session invite received (if player misses dialog)
//
// Preferences: stored as "notif_<type>" = "1" (on) or "0" (off)
//   Defaults to enabled (on) if no preference is stored.
//
// To toggle a pref, send on CHAN_UI:
//   NOTIF_PREF|type|1   (enable)
//   NOTIF_PREF|type|0   (disable)
// ================================================================

integer CHAN_UI = 100;

key g_ownerKey;

// ----------------------------------------------------------------
// Returns 1 if the given notification type is enabled
// Defaults to enabled when no preference is stored yet
// ----------------------------------------------------------------
integer notifEnabled(string notifType)
{
    string val = llLinksetDataRead("notif_" + notifType);
    if (val == "") return TRUE;
    return (integer)val;
}

// ================================================================
default
{
    state_entry()
    {
        g_ownerKey = llGetOwner();
    }

    on_rez(integer start_param)  { llResetScript(); }
    changed(integer c)           { if (c & CHANGED_OWNER) llResetScript(); }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != CHAN_UI) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        // ---- Deliver a notification ----
        // NOTIFY|type|message
        if (cmd == "NOTIFY")
        {
            string notifType = llList2String(parts, 1);
            string text      = llList2String(parts, 2);
            if (notifEnabled(notifType))
                llInstantMessage(g_ownerKey,
                    "[THE CULTIVAR] " + text);
        }

        // ---- Toggle a notification preference ----
        // NOTIF_PREF|type|value  (value: "1"=on, "0"=off)
        else if (cmd == "NOTIF_PREF")
        {
            string notifType = llList2String(parts, 1);
            string val       = llList2String(parts, 2);
            llLinksetDataWrite("notif_" + notifType, val);
            string onOff = "enabled";
            if (val == "0") onOff = "disabled";
            llOwnerSay("Notifications for '" + notifType + "' " + onOff + ".");
        }
    }
}
