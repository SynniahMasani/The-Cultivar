// ================================================================
// THE CULTIVAR  -  Session Object Effects Script
// Version: 1.1
// Handles: Hidden-logic-anchor behavior for the session object.
// Keeps session logic alive while suppressing the visible floating
// centerpiece so the held smoke is the only visible prop.
// ================================================================

integer SCHAN_CORE    = 3000;
integer SCHAN_EFFECTS = 3100;

string  g_quality  = "reggie";
integer g_active   = FALSE;

hideSessionObject()
{
    integer links = llGetNumberOfPrims();
    integer i;
    for (i = 1; i <= links; i++)
    {
        llSetLinkAlpha(i, 0.0, ALL_SIDES);
        llSetLinkPrimitiveParamsFast(i, [PRIM_GLOW, ALL_SIDES, 0.0]);
        llLinkParticleSystem(i, []);
    }
    llSetText("", ZERO_VECTOR, 0.0);
}

onSessionStart(string quality)
{
    g_quality = quality;
    g_active  = TRUE;
    hideSessionObject();
}

onSessionEnd()
{
    g_active = FALSE;
    hideSessionObject();
}

default
{
    state_entry()
    {
        hideSessionObject();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != SCHAN_EFFECTS) return;

        list   parts = llParseString2List(msg, ["|"], []);
        string cmd   = llList2String(parts, 0);

        if (cmd == "SESSION_START")
            onSessionStart(llList2String(parts, 1));
        else if (cmd == "SESSION_END")
            onSessionEnd();
        else if (cmd == "PASS_EFFECT")
            return;
        else if (cmd == "QUALITY")
            g_quality = llList2String(parts, 1);
    }
}
