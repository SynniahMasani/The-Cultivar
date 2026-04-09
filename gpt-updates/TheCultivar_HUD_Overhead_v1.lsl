// ================================================================
// THE CULTIVAR - HUD Overhead Relay
// Version: 1.0
// Shows session text over the owner's avatar while in session.
// Clears on session end / stop.
// ================================================================

integer CHAN_COMMS = 200;
integer CHAN_UI    = 100;

string g_overheadText = "";
vector g_overheadColor = <0.4, 0.9, 0.4>;
float  g_overheadAlpha = 1.0;

updateOverhead()
{
    llSetText(g_overheadText, g_overheadColor, g_overheadAlpha);
}

clearOverhead()
{
    g_overheadText = "";
    llSetText("", ZERO_VECTOR, 0.0);
}

default
{
    state_entry()
    {
        clearOverhead();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER) llResetScript();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != CHAN_COMMS && num != CHAN_UI) return;

        list parts = llParseString2List(msg, ["|"], []);
        string cmd = llList2String(parts, 0);

        if (cmd == "SESSION_OVERHEAD")
        {
            g_overheadText = llDumpList2String(llList2List(parts, 1, -1), "|");
            if (g_overheadText == "") clearOverhead();
            else updateOverhead();
        }
        else if (cmd == "SESSION_ENDED" || cmd == "SMOKE_STOPPED")
        {
            clearOverhead();
        }
    }
}
