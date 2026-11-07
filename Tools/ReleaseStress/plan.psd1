# Release-stress plan. Edited as data: add a step here, no code change needed.
#
# Every step: Name (unique), Group, Do, plus per-kind keys. A Group starts and ends on the main menu
# (the runner verifies it, and backs out if a step fails; the rest of that group is then SKIPped).
#
# Do kinds:
#   click     T = button name on the active screen (use the harness: enumerate with the uiperf trigger
#             "__ENUMERATE__" and read openshim.log to find names). Waits for the shell transition.
#             Budget = name of an entry in Budgets (default Transition). Expect='none' = no transition expected.
#   back      T = Back button name, or omitted for the shell back (__BACK__). Budget defaults to BackOut.
#   clickxy   X,Y in the 1280x720 client area. Only for list boxes the harness cannot address.
#   text      Text = characters typed into the focused field.   key  VK = virtual key code.
#   wait      Seconds.   snapshot  Label.
#   mission   T = launch button (default Launch), PlayS = seconds of play (default MissionPlaySeconds),
#             LoadBudgetS. Waits for load, plays, ESC > Abort Mission, waits for the main menu, snapshots.
#
# Budgets are wall seconds from sending the trigger to the last shell "transition end" line.
@{
    Settings = @{ Width = '1280'; Height = '720' }

    Budgets = @{
        Transition         = 4      # ordinary screen change
        Heavy              = 12     # screens that scan files/maps/lobbies (Instant Action, campaign list, MP staging)
        BackOut            = 1.0    # backing out of a screen (campaign back-out took 23 s before a fix)
        MissionLoad        = 60     # Launch -> first frame
        MissionExit        = 15     # Abort Mission -> main menu
        MenuReadyCold      = 180    # launch on an empty shader cache -> usable main menu
        MenuReadyWarm      = 150
        Quit               = 30     # Exit Game -> process gone
        HangSeconds        = 45     # window unresponsive this long = hang (stacks, kill, FAIL)
        UnresponsiveSeconds = 5     # any single unresponsive stretch longer than this fails the step
        MissionPlaySeconds = 60
        MinFps             = 20     # BZLogger "Min FPS" line after a mission load
        GrowthPrivateMB    = 250    # growth between first and last mission return that fails if also monotonic
        GrowthHandles      = 200
        GrowthGdi          = 50
        GrowthUser         = 50
        GrowthThreads      = 20
    }

    Steps = @(
        # ---------------------------------------------------------------- Options
        @{ Group = 'options'; Name = 'opt_open';   Do = 'click'; T = 'Options_MainScreen' }
        @{ Group = 'options'; Name = 'opt_play';   Do = 'click'; T = 'Play' }
        @{ Group = 'options'; Name = 'opt_play_back';  Do = 'back'; T = 'Back' }
        @{ Group = 'options'; Name = 'opt_gfx';    Do = 'click'; T = 'Graphic' }
        @{ Group = 'options'; Name = 'opt_gfx_back';   Do = 'back'; T = 'Back' }
        @{ Group = 'options'; Name = 'opt_audio';  Do = 'click'; T = 'Audio' }
        @{ Group = 'options'; Name = 'opt_audio_back'; Do = 'back'; T = 'Back' }
        @{ Group = 'options'; Name = 'opt_input';  Do = 'click'; T = 'Input' }
        @{ Group = 'options'; Name = 'opt_input_back'; Do = 'back'; T = 'Back' }
        @{ Group = 'options'; Name = 'osh_open';   Do = 'click'; T = 'OpenShimSettingsMenuButton' }
        @{ Group = 'options'; Name = 'osh_video';    Do = 'click'; T = 'OpenShimHub_Video' }
        @{ Group = 'options'; Name = 'osh_video_back';    Do = 'back' }
        @{ Group = 'options'; Name = 'osh_lighting'; Do = 'click'; T = 'OpenShimHub_Lighting' }
        @{ Group = 'options'; Name = 'osh_lighting_back'; Do = 'back' }
        @{ Group = 'options'; Name = 'osh_audio';    Do = 'click'; T = 'OpenShimHub_Audio' }
        @{ Group = 'options'; Name = 'osh_audio_back';    Do = 'back' }
        @{ Group = 'options'; Name = 'osh_hud';      Do = 'click'; T = 'OpenShimHub_HUD' }
        @{ Group = 'options'; Name = 'osh_hud_back';      Do = 'back' }
        @{ Group = 'options'; Name = 'osh_controls'; Do = 'click'; T = 'OpenShimHub_Controls' }
        @{ Group = 'options'; Name = 'osh_controls_back'; Do = 'back' }
        @{ Group = 'options'; Name = 'osh_gameplay'; Do = 'click'; T = 'OpenShimHub_Gameplay' }
        @{ Group = 'options'; Name = 'osh_gameplay_back'; Do = 'back' }
        @{ Group = 'options'; Name = 'osh_fixes';    Do = 'click'; T = 'OpenShimHub_Fixes' }
        @{ Group = 'options'; Name = 'osh_fixes_back';    Do = 'back' }
        @{ Group = 'options'; Name = 'osh_network';  Do = 'click'; T = 'OpenShimHub_Network' }
        @{ Group = 'options'; Name = 'osh_network_back';  Do = 'back' }
        @{ Group = 'options'; Name = 'osh_system';   Do = 'click'; T = 'OpenShimHub_System' }
        @{ Group = 'options'; Name = 'osh_system_back';   Do = 'back' }
        @{ Group = 'options'; Name = 'osh_hub_back'; Do = 'back'; T = 'OpenShimHub_Back' }
        @{ Group = 'options'; Name = 'opt_close';  Do = 'back'; T = 'Back' }

        # -------------------------------------------------- Main-menu side screens
        @{ Group = 'mainmenu_pages'; Name = 'mods_open';  Do = 'click'; T = 'Mods' }
        @{ Group = 'mainmenu_pages'; Name = 'mods_back';  Do = 'back' }
        @{ Group = 'mainmenu_pages'; Name = 'ach_open';   Do = 'click'; T = 'openAchievements' }
        @{ Group = 'mainmenu_pages'; Name = 'ach_back';   Do = 'back' }

        # ------------------------------------------------------------- Multiplayer
        # LAN (no sign-in) host; a launch needs a 2nd player, so the staging screen is the end of the road solo.
        @{ Group = 'multiplayer'; Name = 'mp_open';       Do = 'click'; T = 'MultiPlayer_MainScreen'; Budget = 'Heavy' }
        @{ Group = 'multiplayer'; Name = 'mp_lan';        Do = 'click'; T = 'OpenShimPreLobby_LocalTools' }
        @{ Group = 'multiplayer'; Name = 'mp_host_start'; Do = 'click'; T = 'OpenShimLAN_Host'; Budget = 'Heavy' }
        @{ Group = 'multiplayer'; Name = 'mp_continue';   Do = 'click'; T = 'OpenShimPreLobby_Continue'; Budget = 'Heavy' }
        @{ Group = 'multiplayer'; Name = 'mp_create';     Do = 'click'; T = 'Create'; Expect = 'none'; SettleS = 1.5 }
        @{ Group = 'multiplayer'; Name = 'mp_name';       Do = 'text';  Text = 'StressGame' }
        @{ Group = 'multiplayer'; Name = 'mp_staging';    Do = 'click'; T = 'RightAlertButton'; Budget = 'Heavy' }
        @{ Group = 'multiplayer'; Name = 'mp_pick_map';   Do = 'clickxy'; X = 320; Y = 135; SettleS = 2 }
        @{ Group = 'multiplayer'; Name = 'mp_ready';      Do = 'click'; T = 'Create'; Expect = 'none'; SettleS = 2 }
        @{ Group = 'multiplayer'; Name = 'mp_idle';       Do = 'wait'; Seconds = 10 }
        @{ Group = 'multiplayer'; Name = 'mp_staging_back'; Do = 'back'; T = 'Back'; Budget = 'Transition' }
        @{ Group = 'multiplayer'; Name = 'mp_lounge_back';  Do = 'back'; T = 'Back'; Budget = 'Transition' }
        @{ Group = 'multiplayer'; Name = 'mp_lan_again';  Do = 'click'; T = 'OpenShimPreLobby_LocalTools' }
        @{ Group = 'multiplayer'; Name = 'mp_host_stop';  Do = 'click'; T = 'OpenShimLAN_Stop'; Expect = 'none'; SettleS = 2 }
        @{ Group = 'multiplayer'; Name = 'mp_lan_back';   Do = 'back'; T = 'OpenShimLAN_Back' }
        @{ Group = 'multiplayer'; Name = 'mp_prelobby_back'; Do = 'back'; T = 'OpenShimPreLobby_Back'; Budget = 'Transition' }

        # ------------------------------------------------------------ Single Player
        @{ Group = 'singleplayer'; Name = 'sp_open';      Do = 'click'; T = 'SinglePlayer_MainScreen' }
        @{ Group = 'singleplayer'; Name = 'sp_options';   Do = 'click'; T = 'Options_SinglePlayer' }
        @{ Group = 'singleplayer'; Name = 'sp_options_back'; Do = 'back'; T = 'Back' }
        @{ Group = 'singleplayer'; Name = 'sp_instant';   Do = 'click'; T = 'Instant'; Budget = 'Heavy' }
        @{ Group = 'singleplayer'; Name = 'sp_instant_back'; Do = 'back' }
        @{ Group = 'singleplayer'; Name = 'sp_tro';       Do = 'click'; T = 'TRO'; Budget = 'Heavy' }
        @{ Group = 'singleplayer'; Name = 'sp_tro_back';  Do = 'back' }
        @{ Group = 'singleplayer'; Name = 'sp_usa';       Do = 'click'; T = 'USAMission_SinglePlayer' }
        @{ Group = 'singleplayer'; Name = 'sp_usa_back';  Do = 'back' }
        @{ Group = 'singleplayer'; Name = 'sp_bd';        Do = 'click'; T = 'BDMission_SinglePlayer' }
        @{ Group = 'singleplayer'; Name = 'sp_bd_back';   Do = 'back' }
        @{ Group = 'singleplayer'; Name = 'sp_ussr';      Do = 'click'; T = 'USSRMission_SinglePlayer' }
        @{ Group = 'singleplayer'; Name = 'sp_ussr_back'; Do = 'back' }
        @{ Group = 'singleplayer'; Name = 'sp_ch';        Do = 'click'; T = 'CHMission_SinglePlayer' }
        @{ Group = 'singleplayer'; Name = 'sp_ch_back';   Do = 'back' }
        @{ Group = 'singleplayer'; Name = 'sp_training';  Do = 'click'; T = 'trainingMission_SinglePlayer' }
        @{ Group = 'singleplayer'; Name = 'sp_training_back'; Do = 'back' }
        @{ Group = 'singleplayer'; Name = 'sp_load';      Do = 'click'; T = 'LoadMission_SinglePlayer' }
        @{ Group = 'singleplayer'; Name = 'sp_load_back'; Do = 'back' }
        # Custom Campaign list > Campaign Reimagined > enter, then back out twice (23 s back-out regression guard)
        @{ Group = 'singleplayer'; Name = 'sp_campaigns'; Do = 'click'; T = 'CampaignLaunch'; Budget = 'Heavy' }
        @{ Group = 'singleplayer'; Name = 'sp_camp_pick_cr'; Do = 'clickxy'; X = 427; Y = 276; SettleS = 1.5 }
        @{ Group = 'singleplayer'; Name = 'sp_camp_enter_cr'; Do = 'click'; T = 'Launch'; Budget = 'Heavy' }
        @{ Group = 'singleplayer'; Name = 'sp_camp_enter_back'; Do = 'back'; T = 'Back' }
        @{ Group = 'singleplayer'; Name = 'sp_camp_list_back'; Do = 'back'; T = 'Back' }
        @{ Group = 'singleplayer'; Name = 'sp_back';      Do = 'back'; T = 'Back_SinglePlayer' }

        # ---------------------------------------------------------------- Missions
        # 1. stock campaign (NSDF mission 1)
        @{ Group = 'mission_stock'; Name = 'ms_sp';     Do = 'click'; T = 'SinglePlayer_MainScreen' }
        @{ Group = 'mission_stock'; Name = 'ms_usa';    Do = 'click'; T = 'USAMission_SinglePlayer' }
        @{ Group = 'mission_stock'; Name = 'mission_stock'; Do = 'mission'; T = 'Launch' }
        # 2. CR campaign, first mission
        @{ Group = 'mission_cr1'; Name = 'mc1_sp';      Do = 'click'; T = 'SinglePlayer_MainScreen' }
        @{ Group = 'mission_cr1'; Name = 'mc1_list';    Do = 'click'; T = 'CampaignLaunch'; Budget = 'Heavy' }
        @{ Group = 'mission_cr1'; Name = 'mc1_pick';    Do = 'clickxy'; X = 427; Y = 276; SettleS = 1.5 }
        @{ Group = 'mission_cr1'; Name = 'mc1_enter';   Do = 'click'; T = 'Launch'; Budget = 'Heavy' }
        @{ Group = 'mission_cr1'; Name = 'mission_cr1'; Do = 'mission'; T = 'Launch' }
        # 3. CR campaign, second mission (MissionpageDn)
        @{ Group = 'mission_cr2'; Name = 'mc2_sp';      Do = 'click'; T = 'SinglePlayer_MainScreen' }
        @{ Group = 'mission_cr2'; Name = 'mc2_list';    Do = 'click'; T = 'CampaignLaunch'; Budget = 'Heavy' }
        @{ Group = 'mission_cr2'; Name = 'mc2_pick';    Do = 'clickxy'; X = 427; Y = 276; SettleS = 1.5 }
        @{ Group = 'mission_cr2'; Name = 'mc2_enter';   Do = 'click'; T = 'Launch'; Budget = 'Heavy' }
        @{ Group = 'mission_cr2'; Name = 'mc2_next';    Do = 'click'; T = 'MissionpageDn'; Expect = 'none'; SettleS = 1.5 }
        @{ Group = 'mission_cr2'; Name = 'mission_cr2'; Do = 'mission'; T = 'Launch' }
        # 4. CR Black Dog campaign (its missions are the co-op-capable ports, played solo)
        @{ Group = 'mission_crbd'; Name = 'mb_sp';      Do = 'click'; T = 'SinglePlayer_MainScreen' }
        @{ Group = 'mission_crbd'; Name = 'mb_list';    Do = 'click'; T = 'CampaignLaunch'; Budget = 'Heavy' }
        @{ Group = 'mission_crbd'; Name = 'mb_pick';    Do = 'clickxy'; X = 427; Y = 240; SettleS = 1.5 }
        @{ Group = 'mission_crbd'; Name = 'mb_enter';   Do = 'click'; T = 'Launch'; Budget = 'Heavy' }
        @{ Group = 'mission_crbd'; Name = 'mission_crbd'; Do = 'mission'; T = 'Launch' }
        # 5. Instant Action
        @{ Group = 'mission_instant'; Name = 'mi_sp';   Do = 'click'; T = 'SinglePlayer_MainScreen' }
        @{ Group = 'mission_instant'; Name = 'mi_instant'; Do = 'click'; T = 'Instant'; Budget = 'Heavy' }
        @{ Group = 'mission_instant'; Name = 'mi_pick'; Do = 'clickxy'; X = 430; Y = 180; SettleS = 1.5 }
        @{ Group = 'mission_instant'; Name = 'mission_instant'; Do = 'mission'; T = 'Launch' }
    )
}
