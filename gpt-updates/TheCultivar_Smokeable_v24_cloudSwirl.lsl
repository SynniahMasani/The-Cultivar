// ================================================================
// THE CULTIVAR  -  Smokeable Object Script
// Version: 2.4 Cloud Swirl
// Adds dense cloud smoke with tier colors and guaranteed detach
// ================================================================

string g_quality = "reggie";
string g_itemType = "joint";
integer g_duration = 300;
integer g_attached = FALSE;
integer g_hasDetachPerm = FALSE;
integer g_hudChannel;

vector tierStart(string q)
{
    if(q=="exotic") return <1.0,0.2,0.9>;
    if(q=="loud")   return <0.9,0.1,0.1>;
    if(q=="mids")   return <0.2,0.8,0.2>;
    return <0.45,0.30,0.15>;
}

vector tierEnd(string q)
{
    if(q=="exotic") return <0.2,0.9,1.0>;
    if(q=="loud")   return <1.0,0.4,0.2>;
    if(q=="mids")   return <0.4,1.0,0.4>;
    return <0.55,0.40,0.20>;
}

startCloud()
{
    llParticleSystem([
        PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_ANGLE_CONE,
        PSYS_PART_FLAGS,
            PSYS_PART_INTERP_COLOR_MASK |
            PSYS_PART_INTERP_SCALE_MASK |
            PSYS_PART_EMISSIVE_MASK |
            PSYS_PART_WIND_MASK,

        PSYS_PART_START_COLOR, tierStart(g_quality),
        PSYS_PART_END_COLOR,   tierEnd(g_quality),

        PSYS_PART_START_ALPHA, 0.8,
        PSYS_PART_END_ALPHA,   0.0,

        PSYS_PART_START_SCALE, <0.12,0.12,0>,
        PSYS_PART_END_SCALE,   <0.75,0.75,0>,

        PSYS_PART_MAX_AGE,     6.0,

        PSYS_SRC_BURST_RATE,   0.05,
        PSYS_SRC_BURST_PART_COUNT, 8,
        PSYS_SRC_BURST_SPEED_MIN, 0.05,
        PSYS_SRC_BURST_SPEED_MAX, 0.20,

        PSYS_SRC_ACCEL, <0,0,0.03>,
        PSYS_SRC_OMEGA, <0,0,1.6>,
        PSYS_SRC_ANGLE_BEGIN, 0.0,
        PSYS_SRC_ANGLE_END,   0.65
    ]);
}

stopAndDetach()
{
    llParticleSystem([]);
    llSetTimerEvent(0.0);
    if(g_hasDetachPerm) llDetachFromAvatar();
    llSleep(0.2);
    llDie();
}

default
{
    attach(key id)
    {
        if(id)
        {
            g_attached = TRUE;
            startCloud();
            llSetTimerEvent((float)g_duration);
        }
        else
        {
            llParticleSystem([]);
        }
    }

    timer()
    {
        stopAndDetach();
    }

    listen(integer c,string n,key id,string msg)
    {
        if(msg=="TC_END_SMOKE") stopAndDetach();
    }
}
