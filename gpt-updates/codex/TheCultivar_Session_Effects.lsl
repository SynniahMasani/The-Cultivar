// ================================================================
// THE CULTIVAR  -  Session Object Effects Script
// Version: 1.2
// Hidden logic-anchor mode with overhead text relay.
// No visible floating centerpiece, no ambient particles.
// ================================================================

integer SCHAN_CORE    = 3000;
integer SCHAN_EFFECTS = 3100;

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

default
{
    state_entry()
    {
        hideSessionObject();
    }

    link_message(integer sender_num, integer num, string msg, key id)
    {
        if (num != SCHAN_EFFECTS) return;

        list parts = llParseString2List(msg, ["|"], []);
        string cmd = llList2String(parts, 0);

        if (cmd == "SESSION_START")
            hideSessionObject();
        else if (cmd == "SESSION_END")
            hideSessionObject();
        else if (cmd == "PASS_EFFECT")
            return;
        else if (cmd == "QUALITY")
            return;
    }
}
