# Overnight soak plan. Plain data; loop order is list order, repeated until -Hours runs out.
#
# Name   = mission stem. Route 'ini' needs a stem of 8 characters or fewer (the engine loads
#          <first 8 chars>.lua) and a Config\<Name>.ini deployed in mods\3686673790\.
# Route  = 'ini'    launch <Name>.bzn after temporarily setting mapType = "instant_action" in the mod's
#                   <Name>.ini (original renamed aside and restored). With "instant_action" the mission's
#                   own Lua and the CR runtime run (a plain "multiplayer" CLI launch runs without CR).
#          'direct' launch <Name>.bzn as is, no ini change (for a stock map or one already listed
#                   as instant action).
# Minutes = optional per-entry override of -MinutesPerMission.
#
# UNVERIFIED: that every entry below starts combat without player input. ch01cr and misns1cr were
# launched this way and ran (Docs/AGENT_KNOWLEDGE_BASE.md / BZR-OpenShim AGENT_TOOLING.md); the
# others are the same co-op-listed family and are untested here. Reorder or delete after the first
# morning summary. The player stays idle: nothing drives the player yet.
#
# Not supported yet: the crsetup slot route (a mission with a stem over 8 characters). Add it only
# if a long-stem mission is needed.
@{
    Missions = @(
        @{ Name = 'ch01cr';   Route = 'ini' }
        @{ Name = 'misns1cr'; Route = 'ini' }
        @{ Name = 'bd01cr';   Route = 'ini' }
        @{ Name = 'misns3cr'; Route = 'ini' }
        @{ Name = 'ch03cr';   Route = 'ini' }
        @{ Name = 'misns5cr'; Route = 'ini' }
    )
}
