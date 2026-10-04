-- EvolveMission: stock BZR / Lua 5.1, standalone survival mission.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/evolvemission.cpp
-- Source blob: e53413c1824f2dd4a38de8912e4d6ebe6067707e
-- The complete original source is archived below, including every comment.
-- Integration: select evolve.lua in the original mission's LuaMission setup.
-- No map, ODF, or shipping configuration is changed by this port.

local MAXATTACKERSPERSPAWN = 20
local RESTARTROUND = 3
-- Zero-based rounds preserve native thresholds and the vehicle restart index.
local attackRounds = {
    [0] = {wait=5, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="pilot_%d", attacker="cspilo"},
    {wait=0, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="sold_%d", attacker="cssolda"},
    {wait=0, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="sniper_%d", attacker="cssold"},
    {wait=30, invehicleWait=true, nowait=false, numunits=3, onlyone=false, spawnPrefix="spawn_%d", attacker="cvfigh"},
    {wait=10, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="spawn_%d", attacker="cvltnk"},
    {wait=10, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="spawn_%d", attacker="cvtnk"},
    {wait=10, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="spawn_%d", attacker="cvhraz"},
    {wait=10, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="spawn_%d", attacker="cvwalk"},
    {wait=10, invehicleWait=false, nowait=false, numunits=3, onlyone=false, spawnPrefix="spawn_%d", attacker="cvhtnk"},
}
local spawnitems = {
    {wait=30, initround=0, attackplayer=false, spawnpoint="repair", item="aprepaa"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="ammo", item="apammoa"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apmini_1", item="apmini"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apmini_2", item="apmini"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apstab_1", item="apstab"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apstab_2", item="apstab"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apsstb_1", item="apsstb"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apsstb_2", item="apsstb"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apflsh_1", item="apflsh"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="apflsh_2", item="apflsh"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="aptagg_1", item="apbolt"},
    {wait=30, initround=0, attackplayer=false, spawnpoint="aptagg_2", item="apbolt"},
    {wait=30, initround=4, attackplayer=true, spawnpoint="cover_1", item="csuserb"},
    {wait=30, initround=4, attackplayer=true, spawnpoint="cover_2", item="csuserb"},
    {wait=30, initround=4, attackplayer=true, spawnpoint="cover_3", item="csuserb"},
    {wait=30, initround=4, attackplayer=true, spawnpoint="cover_4", item="csuserb"},
}
local function NewState()
    local s = {
        lost=false, startup=true, stateTimer=99999, deadTimer=0,
        currentAttackers={}, diedAttackers={}, numOfCurrentAttackers=0,
        item={}, itemTimer={}, itemUnlocked={}, score=0, round=0,
        maxroundattackers=0, invehicle=false,
        bestscore=0, orgbestscore=0, orgbesttime=0,
    }
    -- BUG FIX: native Load initializes deadTimer to 99999 with all floats.
    -- Zero arms the intended two-second grace period even on an early death;
    -- living-player behavior and the subsequent two-second exit delay are unchanged.
    for i=1,#spawnitems do s.itemTimer[i]=99999 end
    return s
end

local M = NewState()
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Alive(h) return Valid(h) and IsAlive(h) end
local function AttackPlayer(h)
    -- PORT FIX: skip commands on removed handles (including already scored
    -- attackers). Valid actors retain the native default command priority.
    if Valid(h) and Valid(M.user) then Attack(h, M.user) end
end
local function Remove(h) if Valid(h) then RemoveObject(h) end end
local function ScoreKill()
    M.score=M.score+1
    if M.score>M.bestscore then
        M.bestscore=M.score
        SetMaxScrap(1,M.bestscore)
    end
    SetScrap(1,M.score)
end
local function CreateAttackerRound()
    M.numOfCurrentAttackers=0
    while true do
        local r=attackRounds[M.round]
        local roundmax=r.onlyone and 1 or M.maxroundattackers
        for i=1,r.numunits do
            local path=string.format(r.spawnPrefix,i)
            for j=1,roundmax do
                local idx=M.numOfCurrentAttackers+1
                M.numOfCurrentAttackers=idx
                M.diedAttackers[idx]=false
                M.currentAttackers[idx]=BuildObject(r.attacker,2,path)
                AttackPlayer(M.currentAttackers[idx])
            end
        end
        if r.nowait then M.round=M.round+1 else break end
    end
end
function Start() M=NewState() end
function AddObject(h) end -- Native handler is empty.
function Save() return M end
function Load(state) if state then M=state end end

local function FinishRun()
    local currenttime=GetCockpitTimer()
    M.resultValues={M.score, math.floor(currenttime/60), currenttime%60,
        M.orgbestscore, math.floor(M.orgbesttime/60), M.orgbesttime%60}
    -- STOCK LIMITATION: no fopen/fread/fwrite or CheckCheater(UserProfile...) API.
    -- orgbestscore/time use native missing-file defaults (0); no persistent
    -- record is read/written and this comparison is NOT a verified high score.
    -- SucceedMission has no native third 'values' argument. Keep both debrief
    -- names and expose the six values in saved state and one objective instead.
    -- Native file access/cheat/debrief code is preserved in the source archive.
    local better=M.orgbestscore<M.score or
        (M.orgbestscore==M.score and currenttime<M.orgbesttime)
    ClearObjectives()
    AddObjective("evolve_result", "white", 4, string.format(
        "Score: %d  Time: %d:%02d  Baseline: %d (%d:%02d)\nPersistent records and cheat qualification unavailable in stock Lua.",
        unpack(M.resultValues)))
    SucceedMission(GetTime()+2, better and "sammywin.des" or "sammylse.des")
    M.lost=true
end

function Update(dt)
    M.user=GetPlayerHandle() -- assigns the player a handle every frame
    local now=GetTime()
    if not M.lost and not Alive(M.user) then
        if M.deadTimer~=0 then
            if M.deadTimer<now then FinishRun(); return end
        else M.deadTimer=now+2 end
    elseif M.lost then return
    else M.deadTimer=0 end

    if M.startup then
        SetScrap(1,0)
        SetPilot(1,10)
        SetMaxScrap(1,M.bestscore)
        StartCockpitTimerUp(0)
        M.olduser=M.user
        M.score=0
        M.startup=false
        M.invehicle=false
        M.round=0
        M.stateTimer=0
        M.maxroundattackers=1
        for i,s in ipairs(spawnitems) do
            M.item[i]=nil
            M.itemUnlocked[i]=s.initround<=M.round
            M.itemTimer[i]=M.itemUnlocked[i] and 1 or 0
        end
        CreateAttackerRound() -- Native initial five-second 'wait' is unused.
    elseif M.stateTimer~=0 then
        if M.stateTimer==1 and attackRounds[M.round].invehicleWait then
            if M.invehicle then M.stateTimer=now+attackRounds[M.round].wait end
        elseif M.stateTimer<now then
            CreateAttackerRound()
            M.stateTimer=0
        end
    else
        local alldead=true
        if M.user~=M.olduser and Valid(M.user) then
            for i=1,M.numOfCurrentAttackers do AttackPlayer(M.currentAttackers[i]) end
            for i,s in ipairs(spawnitems) do
                if s.attackplayer and Alive(M.item[i]) then AttackPlayer(M.item[i]) end
            end
        end
        -- BUG FIX: native 'else { alldead=0; }' belongs to !diedAttackers,
        -- not !IsAlive. It advances with live unscored attackers and then
        -- stalls on already scored ones. Only living attackers block the next
        -- wave; score each death once. This restores the intended clear-wave
        -- gate without changing wave order, delays, spawn counts, or scoring.
        for i=1,M.numOfCurrentAttackers do
            if not M.diedAttackers[i] then
                if not Alive(M.currentAttackers[i]) then
                    Remove(M.currentAttackers[i])
                    M.diedAttackers[i]=true
                    ScoreKill()
                else alldead=false end
            end
        end
        for i,s in ipairs(spawnitems) do
            if s.attackplayer and M.item[i] and not Alive(M.item[i]) then
                Remove(M.item[i])
                M.item[i]=nil
                ScoreKill()
            end
        end
        if alldead then
            M.round=M.round+1
            if M.round>=9 then
                M.round=RESTARTROUND
                if M.maxroundattackers<MAXATTACKERSPERSPAWN then
                    M.maxroundattackers=M.maxroundattackers+1
                end
            end
            local r=attackRounds[M.round]
            if r.invehicleWait then M.stateTimer=1
            elseif r.wait~=0 then M.stateTimer=now+r.wait
            else CreateAttackerRound() end
        end
    end
    for i,s in ipairs(spawnitems) do
        if M.itemTimer[i]==0 then
            if not Alive(M.item[i]) and (M.itemUnlocked[i] or s.initround<=M.round) then
                -- PORT FIX: save the native initround=0 mutation in mission
                -- state rather than the static table. Unlocked cover remains
                -- unlocked after wave wrap AND save/load; restarts reset it.
                M.itemUnlocked[i]=true
                M.itemTimer[i]=now+s.wait
            end
        elseif M.itemTimer[i]<now then
            M.itemTimer[i]=0
            M.item[i]=BuildObject(s.item,s.attackplayer and 2 or 1,s.spawnpoint)
            if s.attackplayer then AttackPlayer(M.item[i]) end
        end
    end
    -- Native repeatedly restarts its object-list iterator after removing scrap.
    -- Collect first, then remove: no mutation of a live stock Lua iterator.
    local scrap={}
    for h in AllObjects() do
        if Valid(h) and string.sub(GetOdf(h),1,5)=="npscr" then
            scrap[#scrap+1]=h
        end
    end
    for _,h in ipairs(scrap) do Remove(h) end
    if M.user~=M.olduser then
        M.olduser=M.user
        -- Native means 'player handle has ever changed', not IsCraft(user).
        -- Preserve the latch, including hop-out/vehicle swaps and grace-period
        -- null handles; changing this would change the vehicle-wave gate.
        M.invehicle=true
    end
end

--[====[
ORIGINAL C++ SOURCE (verbatim; includes all comments and native-only behavior)
#include "GameCommon.h"
#include "AiCommon.h"
#include "AiMission.h"
#include "AiProcess.h"
#include "PowerUp.h"
#include "ScriptUtils.h"


#define MAXATTACKERSPERSPAWN		20
#define MAXCURRENTATTACKERS			(7 * MAXATTACKERSPERSPAWN)

extern "C"
{
BOOL CheckCheater(LONG playOptions);
}


struct {
	float wait;
	int invehicleWait, nowait, numunits, onlyone;
	char *spawnPrefix;
	char *attacker;

} attackRounds[] = 
{
	{ 5.0,  0, 0, 3, 0, "pilot_%d",  "cspilo" },
	{ 0.0,  0, 0, 3, 0, "sold_%d",   "cssolda" },
	{ 0.0,  0, 0, 3, 0, "sniper_%d", "cssold" },
	{ 30.0, 1, 0, 3, 0, "spawn_%d",  "cvfigh" },
	{ 10.0, 0, 0, 3, 0, "spawn_%d",  "cvltnk" },
	{ 10.0, 0, 0, 3, 0, "spawn_%d",  "cvtnk" },
	{ 10.0, 0, 0, 3, 0, "spawn_%d",  "cvhraz" },
	{ 10.0, 0, 0, 3, 0, "spawn_%d",  "cvwalk" },
	{ 10.0, 0, 0, 3, 0, "spawn_%d",  "cvhtnk" }
};

#define MAXROUNDS	(sizeof(attackRounds) / sizeof(attackRounds[0]))
#define RESTARTROUND		3



struct {
	float wait;
	int   initround;
	int   attackplayer;
	char *spawnpoint;
	char *item;
}
spawnitems[] = 
{
	{ 30.0, 0, 0, "repair",   "aprepaa" },
	{ 30.0, 0, 0, "ammo",		  "apammoa" },
	{ 30.0, 0, 0, "apmini_1", "apmini" },
	{ 30.0, 0, 0, "apmini_2", "apmini" },
	{ 30.0, 0, 0, "apstab_1", "apstab" },
	{ 30.0, 0, 0, "apstab_2", "apstab" },
	{ 30.0, 0, 0, "apsstb_1", "apsstb" },
	{ 30.0, 0, 0, "apsstb_2", "apsstb" },
	{ 30.0, 0, 0, "apflsh_1", "apflsh" },
	{ 30.0, 0, 0, "apflsh_2", "apflsh" },
	{ 30.0, 0, 0, "aptagg_1", "apbolt" },
	{ 30.0, 0, 0, "aptagg_2", "apbolt" },
	{ 30.0, 4, 1, "cover_1",  "csuserb" },
	{ 30.0, 4, 1, "cover_2",  "csuserb" },
	{ 30.0, 4, 1, "cover_3",  "csuserb" },
	{ 30.0, 4, 1, "cover_4",  "csuserb" },
};


#define MAXITEMS	(sizeof(spawnitems) / sizeof(spawnitems[0]))



/*
	EvolveMission
*/

class EvolveMission : public AiMission {
	DECLARE_RTIME(EvolveMission)
public:
	EvolveMission();
	~EvolveMission();

	virtual bool Load(file fp);
	virtual bool PostLoad(void);
	virtual bool Save(file fp);

	void createAttackerRound(void);

	virtual void Update(void);

	virtual void AddObject(GameObject *gameObj);

private:
	void Setup();
	void Execute();
	void AddObject(Handle h);

	// bools
	union {
		struct {
			bool
				// have we lost?
				lost, 
				
				b_last;
		};
		bool b_array[1];
	};

	// floats
	union {
		struct {
			float
				stateTimer,  // timer to say when the next state starts
				itemTimer[MAXITEMS],
				deadTimer,

				f_last;
		};
		float f_array[2 + MAXITEMS];
	};

	// handles
	union {
		struct {
			Handle
				// the user
				user,
				olduser,

				currentAttackers[MAXCURRENTATTACKERS],

				item[MAXITEMS],

				// place holder
				h_last;
		};
		Handle h_array[2 + MAXCURRENTATTACKERS + MAXITEMS];
	};

	// integers
	union {
		struct {
			int
				startup,
				diedAttackers[MAXCURRENTATTACKERS],
				numOfCurrentAttackers,
				score,
				round,
				maxroundattackers,
				invehicle,
				bestscore,
				orgbestscore,
				orgbesttime,

				i_last;
		};
		int i_array[9 + MAXCURRENTATTACKERS];
	};
};

IMPLEMENT_RTIME(EvolveMission)

EvolveMission::EvolveMission()
{
}

EvolveMission::~EvolveMission()
{
}

bool EvolveMission::Load(file fp)
{
	if (missionSave) 
	{
		int i;

		// init bools
		int b_count = &b_last - b_array;
		_ASSERTE(b_count == SIZEOF(b_array));
		for (i = 0; i < b_count; i++)
			b_array[i] = false;

		// init floats
		int f_count = &f_last - f_array;
		_ASSERTE(f_count == SIZEOF(f_array));
		for (i = 0; i < f_count; i++)
			f_array[i] = 99999.0f;

		// init handles
		int h_count = &h_last - h_array;
		_ASSERTE(h_count == SIZEOF(h_array));
		for (i = 0; i < h_count; i++)
			h_array[i] = 0;

		// init ints
		int i_count = &i_last - i_array;
		_ASSERTE(i_count == SIZEOF(i_array));
		for (i = 0; i < i_count; i++)
			i_array[i] = 0;

		Setup();
		return AiMission::Load(fp);
	}

	bool ret = true;

	// bools
	int b_count = &b_last - b_array;
	_ASSERTE(b_count == SIZEOF(b_array));
	ret = ret && in(fp, b_array, sizeof(b_array));

	// floats
	int f_count = &f_last - f_array;
	_ASSERTE(f_count == SIZEOF(f_array));
	ret = ret && in(fp, f_array, sizeof(f_array));

	// Handles
	int h_count = &h_last - h_array;
	_ASSERTE(h_count == SIZEOF(h_array));
	ret = ret && in(fp, h_array, sizeof(h_array));

	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && in(fp, i_array, sizeof(i_array));

	ret = ret && AiMission::Load(fp);
	return ret;
}

bool EvolveMission::PostLoad(void)
{
	if (missionSave)
		return AiMission::PostLoad();

	bool ret = true;

	int h_count = &h_last - h_array;
	for (int i = 0; i < h_count; i++)
		h_array[i] = ConvertHandle(h_array[i]);

	ret = ret && AiMission::PostLoad();

	return ret;
}

bool EvolveMission::Save(file fp)
{
	if (missionSave)
		return AiMission::Save(fp);

	bool ret = true;

	// bools
	int b_count = &b_last - b_array;
	_ASSERTE(b_count == SIZEOF(b_array));
	ret = ret && out(fp, b_array, sizeof(b_array), "b_array");

	// floats
	int f_count = &f_last - f_array;
	_ASSERTE(f_count == SIZEOF(f_array));
	ret = ret && out(fp, f_array, sizeof(f_array), "f_array");

	// Handles
	int h_count = &h_last - h_array;
	_ASSERTE(h_count == SIZEOF(h_array));
	ret = ret && out(fp, h_array, sizeof(h_array), "h_array");

	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && out(fp, i_array, sizeof(i_array), "i_array");

	ret = ret && AiMission::Save(fp);
	return ret;
}

void EvolveMission::AddObject(GameObject *gameObj)
{
	AddObject(gameObj->GetHandle());
	AiMission::AddObject(gameObj);
}

void EvolveMission::AddObject(Handle h)
{
}

void EvolveMission::Update(void)
{
	AiMission::Update();
	Execute();
}








void EvolveMission::Setup()
{
	startup = 1;
	numOfCurrentAttackers = 0;


	FILE *bscorefile;

	bestscore = orgbestscore = orgbesttime = 0;

	bscorefile = fopen("emission.bst", "rb");
	if(bscorefile)
	{
		fread(&bestscore, sizeof(bestscore), 1, bscorefile);
		orgbestscore = bestscore;

		fread(&orgbesttime, sizeof(orgbesttime), 1, bscorefile);

		fclose(bscorefile);
	}
}

void EvolveMission::Execute()
{
	int i = 0;

	user = GetPlayerHandle(); //assigns the player a handle every frame

	if(!lost && !IsAlive(user))
	{
		if(deadTimer)
		{
			if(deadTimer < GetTime())
			{
				int currenttime = GetCockpitTimer();
				int bestmin, bestsec, currentmin, currentsec;

				int values[6];

				bestmin = orgbesttime / 60;
				bestsec = orgbesttime % 60;
				currentmin = currenttime / 60;
				currentsec = currenttime % 60;

				if(!CheckCheater(UserProfile.playOption) && (orgbestscore < score || (orgbestscore == score && currenttime < orgbesttime)))
				{
					FILE *bscorefile;

					// save emission.bst file
					bscorefile = fopen("emission.bst", "wb");
					if(bscorefile)
					{
						fwrite(&score, sizeof(score), 1, bscorefile);
						fwrite(&currenttime, sizeof(currenttime), 1, bscorefile);
						fclose(bscorefile);
					}

					values[0] = score;
					values[1] = currentmin;
					values[2] = currentsec;
					values[3] = orgbestscore;
					values[4] = bestmin;
					values[5] = bestsec;

					SucceedMission(GetTime() + 2.0, "sammywin.des", values);
				}
				else
				{
					values[0] = score;
					values[1] = currentmin;
					values[2] = currentsec;
					values[3] = orgbestscore;
					values[4] = bestmin;
					values[5] = bestsec;

					SucceedMission(GetTime() + 2.0, "sammylse.des", values);
				}

				lost = TRUE;
				return;
			}
		}
		else
		{
			deadTimer = GetTime() + 2;
		}
	}
	else if(lost)
	{
		return;
	}
	else
	{
		deadTimer = 0;
	}

	if(startup)
	{
		SetScrap(1,0);
		SetPilot(1,10);

		SetMaxScrap(1, bestscore);

		StartCockpitTimerUp(0);
		olduser = user;

		score = 0;
		startup = 0;

		invehicle = 0;

		round = 0;
		stateTimer = 0;
		maxroundattackers = 1;

		for(i = 0; i < MAXITEMS; i++)
		{
			item[i] = 0;

			if(spawnitems[i].initround <= round)
			{
				itemTimer[i] = 1;
			}
			else
			{
				itemTimer[i] = 0;
			}
		}

		createAttackerRound();
	}
	else if(stateTimer)
	{
		if(stateTimer == 1 && attackRounds[round].invehicleWait)
		{
			if(invehicle)
			{
				stateTimer = GetTime() + attackRounds[round].wait;
			}
		}
		else if(stateTimer < GetTime())
		{
			createAttackerRound();
			stateTimer = 0;
		}
	}
	else
	{
		int alldead = 1;

		if(numOfCurrentAttackers && user != olduser && user != 0)
		{
			for(i = 0; i < numOfCurrentAttackers; i++)
			{
				Attack(currentAttackers[i], user);
			}
		}

		if(user != olduser && user != 0)
		{
			for(i = 0; i < MAXITEMS; i++)
			{
				if(spawnitems[i].attackplayer && item[i] && IsAlive(item[i]))
				{
					Attack(item[i], user);
				}
			}
		}


		for(i = 0; i < numOfCurrentAttackers; i++)
		{
			if(!diedAttackers[i])
			{
				if(!IsAlive(currentAttackers[i]))
				{
					RemoveObject(currentAttackers[i]);

					diedAttackers[i] = 1;
					score++;

					if(score > bestscore)
					{
						bestscore = score;
						SetMaxScrap(1, bestscore);
					}

					SetScrap(1, score);
				}
				else
				{
					alldead = 0;
				}
			}
		}


		for(i = 0; i < MAXITEMS; i++)
		{
			if(spawnitems[i].attackplayer && item[i] && !IsAlive(item[i]))
			{
				RemoveObject(item[i]);
				item[i] = 0;
				score++;

				if(score > bestscore)
				{
					bestscore = score;
					SetMaxScrap(1, bestscore);
				}

				SetScrap(1, score);
			}
		}

		if(alldead)
		{
			round++;
			
			if(round >= MAXROUNDS)
			{
				round = RESTARTROUND;

				if(maxroundattackers < MAXATTACKERSPERSPAWN)
				{
					maxroundattackers++;
				}
			}

			if(attackRounds[round].invehicleWait)
			{
				stateTimer = 1;
			}
			else if(attackRounds[round].wait)
			{
				stateTimer = GetTime() + attackRounds[round].wait;
			}
			else
			{
				createAttackerRound();
			}
		}
	}

	for(i = 0; i < MAXITEMS; i++)
	{
		if(itemTimer[i] == 0)
		{
			if(!item[i] || !IsAlive(item[i]))
			{
				if(spawnitems[i].initround <= round)
				{
					spawnitems[i].initround = 0;
					itemTimer[i] = GetTime() + spawnitems[i].wait;
				}
			}
		}
		else if(itemTimer[i] < GetTime())
		{
			itemTimer[i] = 0;
			item[i] = BuildObject(spawnitems[i].item, spawnitems[i].attackplayer ? 2 : 1, spawnitems[i].spawnpoint);

			if(spawnitems[i].attackplayer)
			{
				Attack(item[i], user);
			}
		}
	}

	bool done = FALSE;

	while(!done)
	{
		ObjectList &list = *GameObject::objectList;

		done = TRUE;

		// remove scrap
		for (ObjectList::iterator oi = list.begin(); oi != list.end(); oi++) 
		{
			GameObject *o = *oi;
			if(memcmp(&o->GetClass()->cfg, "npscr", 5) == 0)
			{
				RemoveObject(GameObjectHandle::Find(o));
				done = FALSE;
				break;
			}
		}
	}

	if(user != olduser)
	{
		olduser = user;
		invehicle = 1;
	}
}



void EvolveMission::createAttackerRound(void)
{
	int i, j, idx, roundmax;
	char buffer[30];

	numOfCurrentAttackers = 0;

	while(1)
	{
		if(attackRounds[round].onlyone)
		{
			roundmax = 1;
		}
		else
		{
			roundmax = maxroundattackers;
		}
		

		for(i = 0, idx = numOfCurrentAttackers; i < attackRounds[round].numunits; i++)
		{
			sprintf(buffer, attackRounds[round].spawnPrefix, i + 1);

			for(j = 0; j < roundmax; j++, idx++)
			{
				diedAttackers[idx] = 0;
				currentAttackers[idx] = BuildObject(attackRounds[round].attacker, 2, buffer);
				Attack(currentAttackers[idx], user);
			}
		}
		
		numOfCurrentAttackers += (attackRounds[round].numunits * roundmax);

		if(attackRounds[round].nowait)
		{
			round++;
		}
		else
		{
			break;
		}
	}
}

]====]
