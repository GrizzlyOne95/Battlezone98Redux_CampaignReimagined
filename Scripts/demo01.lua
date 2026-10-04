-- DemoMission: stock BZR / Lua 5.1 benchmark port.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/DemoMission.cpp
-- Source blob: 3c4eb4adec163a57f7055f1af752a483dddc8169.
-- Native aliases: demo01, demo. This is the benchmark Execute(), despite the
-- stale source comment describing misn01 as a training mission.
-- Map integration: load this as demo01.lua using a LuaMission map. Preserve
-- the original paths/ODFs. Label the original map objects with native sequence
-- numbers 5..8 as demo_keep_5..demo_keep_8 before running the port.
-- LIMITATION: stock Lua has no GetSeqNo; labels are an explicit map adaptation,
-- not a claim that labels or iterator order equal native sequence numbers.
-- No matching demo01.bzn/.trn exists in the destination source tree; this file
-- does not silently replace misn01 or invent a benchmark map.
-- Native StartProfiler, fopen/fprintf and QuickExit have no stock Lua binding.
-- Completion displays the source calculation as simulation updates/second,
-- then calls SucceedMission; it does not write bzbench.des or exit the process.
-- Update counts are not a measured Redux renderer FPS.
-- Full original source, including all comments, #else cleanup and unused
-- MoveObject helper, is preserved verbatim below for cut-content recovery.

local function NewState()
    return {
        camera1 = false, camera2 = false, start_done = false,
        lost = false, first_start = false, angle = 3,
        camera_time = -99999, cycle_count = 0, frame_count = 0,
        cycle_time = 0, time = 0, keep = {},
        -- PORT FIX: explicit state replaces native unions whose arrays are
        -- too short (floats 5 vs 6, handles 12 vs 17, ints 5 vs 6). LuaMission
        -- saves/remaps the entire table, including cycle_time and all handles;
        -- this repairs save corruption without changing Execute's live flow.
        -- Unused training fields remain named for reconstruction.
        hop_in = false, first_objective = false, second_objective = false,
        third_objecitve = false, combat_start = false, combat_start2 = false,
        start_path1 = false, start_path2 = false, start_path3 = false,
        start_path4 = false, hint1 = false, hint2 = false,
        done_message = false, jump_start = false,
        repeat_time = 0, forgiveness = 0, jump_done = 0,
        num_reps = 0, on_point = 0,
        -- Unused native get_in_me/target2 and p1..p4 remain nil.
    }
end
local M = NewState()
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Alive(h) return Valid(h) and IsAlive(h) end

function Start()
    M = NewState()
    local missing = false
    for seq = 5, 8 do
        local h = GetHandle("demo_keep_" .. seq)
        if Valid(h) then M.keep[#M.keep + 1] = h else missing = true end
    end
    if missing then
        DisplayMessage("Demo port: label native map objects 5-8 demo_keep_5..demo_keep_8 for faithful cleanup.")
    end
end
function Save() return M end
function Load(state)
    if state ~= nil then M = state end
end

local function Order(command, h, destination)
    -- PORT FIX: failed spawns/deleted destinations must not receive native
    -- handle commands. Successful spawns keep the source's default priority.
    if Valid(h) and (type(destination) == "string" or Valid(destination)) then
        command(h, destination)
    end
end

local function KillStuff()
    local user = GetPlayerHandle()
    local protected = {}
    for _, h in ipairs(M.keep) do protected[h] = true end
    local remove = {}
    -- PORT FIX: snapshot before removal, rather than resetting/mutating a live
    -- iterator. This removes every eligible object exactly once; user, the
    -- four authored keep handles and team 3 retain the source exemptions.
    -- IsValid includes live noncombat objects such as scrap; IsAlive would
    -- incorrectly filter those out of the native object-list cleanup.
    for h in AllObjects() do
        if Valid(h) and h ~= user and not protected[h] and GetTeamNum(h) ~= 3 then
            remove[#remove + 1] = h
        end
    end
    for _, h in ipairs(remove) do
        if Valid(h) then
            SetTeamNum(h, 3)
            RemoveObject(h)
        end
    end
end

local function AdvanceAngle(maximum)
    if GetTime() > M.camera_time then
        M.camera_time = GetTime() + 7
        M.angle = M.angle + 1
        if M.angle > maximum then M.angle = 0 end
    end
end

local function FinishBenchmark()
    M.lost = true
    local elapsed = GetTime() - M.time
    -- PORT FIX: zero elapsed time can occur after immediate failed spawns;
    -- guard the report's division only. No cycle or camera timing changes.
    local rate = elapsed > 0 and M.frame_count / elapsed or 0
    M.total_time, M.average_update_rate = elapsed, rate
    DisplayMessage(string.format("Battlezone Benchmark Test: total time %.6f; average simulation updates/s %.6f. Created by George Collins.", elapsed, rate))
    CameraFinish()
    -- PORT ADAPTATION: ordinary mission completion replaces QuickExit.
    -- No generated debrief filename is supplied because stock Lua cannot
    -- produce addon/bzbench.des. The source's disabled SucceedMission is below.
    SucceedMission(GetTime() + 1)
end

function Update(timestep)
    -- PORT FIX: QuickExit never returned in the native mission. Once the Lua
    -- replacement ends the benchmark, do not keep incrementing cycle_count
    -- or damaging build2 while waiting for the completion screen.
    if M.lost then return end
    M.frame_count = M.frame_count + 1
    -- spawn_point go_path
    if not M.start_done then
        M.cycle_time = GetTime()
        if not M.first_start then
            M.first_start = true
            M.time = GetTime()
            CameraReady()
        end
        -- Native: int flags = 0; StartProfiler(flags); no stock Lua equivalent.
        M.target = BuildObject("avdemo", 1, "spawn_point")
        Order(Goto, M.target, "go_path")
        M.start_done, M.camera1 = true, true
        M.foe1 = BuildObject("svhraz", 2, "foe1") -- foe1 foe2 foe3
        M.foe2 = BuildObject("svltnk", 2, "foe2")
        M.foe3 = BuildObject("svltnk", 2, "foe2")
        M.foe4 = BuildObject("svrckt", 2, "foe2")
        M.friend1 = BuildObject("avhraz", 1, "friend1")
        M.art1 = BuildObject("avartl", 1, "art1")
        M.build1 = BuildObject("sbcomm", 2, "build1")
        M.build2 = BuildObject("sbspow", 2, "build2")
        M.build3 = BuildObject("sbhang", 2, "build3")
        M.build4 = BuildObject("sblpow", 2, "build4")
        M.build5 = BuildObject("sbhqcp", 2, "build5")
        M.build6 = BuildObject("sbwpow", 2, "build6")
        M.build7 = BuildObject("sbwpow", 2, "build7")
        M.build8 = BuildObject("sbwpow", 2, "build8")
        Order(Goto, M.foe1, M.build1)
        Order(Goto, M.foe2, M.build1)
        Order(Goto, M.foe3, M.build1)
        Order(Goto, M.foe4, M.build1)
        Order(Follow, M.friend1, M.target)
    end
    if M.camera1 then
        -- PORT FIX: omit unused user/target position dereferences and guard
        -- camera subjects. A destroyed target still ends this cycle below;
        -- intact targets retain the same shots and strict > timer checks.
        if Valid(M.target) then
            if M.angle == 0 then CameraObject(M.target, 0, 800, -1500, M.target)
            elseif M.angle == 1 then CameraObject(M.target, -1500, 800, 0, M.target)
            elseif M.angle == 2 then CameraObject(M.target, 0, 800, 1500, M.target) end
        end
        AdvanceAngle(2)
        if Valid(M.foe1) and Valid(M.target) and GetDistance(M.foe1, M.target) < 200 then
            M.camera1, M.camera2 = false, true
            Order(Attack, M.art1, M.foe1)
        end
        -- Source repeats the timer check here. Keep it, though the first
        -- check normally moved camera_time into the future.
        AdvanceAngle(2)
    end
    -- Independent if, not elseif: camera2 can run on its transition frame.
    if M.camera2 then
        -- Preserve native 50 damage per Update, not damage per second.
        if Alive(M.build2) then Damage(M.build2, 50) end
        if Valid(M.target) then
            if M.angle == 0 then CameraPath("camera1", 1000, 0, M.target)
            elseif M.angle == 1 then
                if Alive(M.foe1) then CameraObject(M.target, -600, 400, 0, M.foe1)
                elseif Alive(M.foe2) then CameraObject(M.target, -600, 400, 0, M.foe2) end
            end
        end
        AdvanceAngle(1)
    end
    if not Alive(M.target) or GetTime() > M.cycle_time + 55 then
        M.cycle_count = M.cycle_count + 1
        if M.cycle_count > 4 then -- (!EndProfiler(flags))
            FinishBenchmark()
        else
            -- kill everything and restart (#if 1 in source).
            KillStuff()
            M.start_done, M.camera1, M.camera2 = false, false, false
            -- angle/camera_time/first_start/time/frame_count deliberately carry
            -- over between cycles, exactly as in native Execute.
        end
    end
end

--[====[
ORIGINAL DemoMission.cpp (including disabled and native-only code):
#include "GameCommon.h"

#include "..\fun3d\PowerUp.h"
#include "..\fun3d\ScriptUtils.h"

#include "..\terrain\terrain.h"


extern void QuickExit(void);

/*
DemoMission
*/

// used by (misn01.bzn) as first training mission

#include "..\fun3d\AiMission.h"

class DemoMission : public AiMission {
	DECLARE_RTIME(DemoMission)
public:
	DemoMission(void);
	~DemoMission();
	
	virtual bool Load(file fp);
	virtual bool PostLoad(void);
	virtual bool Save(file fp);
	
	virtual void Update(void);
	
	void Setup(void);
	void Execute(void);
	
private:
	// bools
	union {
		struct {
			bool
				camera1,
				camera2,
				start_done,
				hop_in,
				first_objective,
				second_objective,
				third_objecitve,
				combat_start,
				combat_start2,
				start_path1,
				start_path2,
				start_path3,
				start_path4,
				hint1,
				hint2,
				done_message,
				jump_start,
				lost,
				first_start,
				b_last;
		};
		bool b_array[19];
	};
	
	// floats
	union {
		struct {
			float
				camera_time,
				repeat_time,
				forgiveness,
				jump_done,
				time,
				cycle_time,
				f_last;
		};
		float f_array[5];
	};
	
	// object handles
	union {
		struct {
			Handle
				get_in_me,
				target,
				target2,
				foe1,
				foe2,
				foe3,
				foe4,
				friend1,
				art1,
				build1,
				build2,
				build3,
				build4,
				build5,
				build6,
				build7,
				build8,
				h_last;
		};
		Handle h_array[12];
	};
	
	// path pointers
	union {
		struct {
			AiPath
				*p1,
				*p2,
				*p3,
				*p4,
				*p_last;
		};
		AiPath *p_array[4];
	};
	
	// integers
	union {
		struct {
			int
				cycle_count,
				frame_count,
				angle,
				aud,
				num_reps,
				on_point,
				i_last;
		};
		int i_array[5];
	};
};

IMPLEMENT_RTIME(DemoMission)

static class DemoMissionClass : AiMissionClass {
public:
	DemoMissionClass(char *name) : AiMissionClass(name)
	{
	}
	int Matches(char *matches)
	{
		if (strcmp(matches, name) == 0)
			return TRUE;
		if (strcmp(matches, "demo") == 0)
			return TRUE;
		return FALSE;
	}
	AiMission *Build(void)
	{
		return new DemoMission;
	}
} DemoMissionClass("demo01");

DemoMission::DemoMission(void)
{
}

DemoMission::~DemoMission()
{	
}

bool DemoMission::Load(file fp)
{
	if (missionSave) {
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
	
	// path pointers
	int p_count = &p_last - p_array;
	_ASSERTE(p_count == SIZEOF(p_array));
	for (int i = 0; i < p_count; i++)
		ret = ret && in_ptr(fp, (void **)&p_array[i], sizeof(p_array[0]), "p_array", this);
	
	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && in(fp, i_array, sizeof(i_array));
	
	ret = ret && AiMission::Load(fp);
	return ret;
}

bool DemoMission::PostLoad(void)
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

bool DemoMission::Save(file fp)
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
	
	// path pointers
	int p_count = &p_last - p_array;
	_ASSERTE(p_count == SIZEOF(p_array));
	for (int i = 0; i < p_count; i++)
		ret = ret && out_ptr(fp, (void **)&p_array[i], sizeof(p_array[0]), "p_array");
	
	// ints
	int i_count = &i_last - i_array;
	_ASSERTE(i_count == SIZEOF(i_array));
	ret = ret && out(fp, i_array, sizeof(i_array), "i_array");
	
	ret = ret && AiMission::Save(fp);
	return ret;
}

void DemoMission::Update(void)
{
	AiMission::Update();
	Execute();
}

void DemoMission::Setup(void)
{
	camera1=false;
	camera2=false;
	angle=3;
	camera_time=-99999.0f;
	lost=false;
	first_start=false;
	
	cycle_count=0;
	start_done=false;
	frame_count=0;
}

#define MOVE_TOP 98568.0f
#define MOVE_LEFT 4142.0f
#define MOVE_RIGHT 4989.0f
#define MOVE_BOTTOM 97327.0f

static float moveX = MOVE_LEFT;
static float moveZ = MOVE_TOP;

static void MoveObject(GameObject *o)
{
	float height;
	Terrain_GetHeightAndNormal(moveX, moveZ, &height, NULL);
	VECTOR_3D pos = { moveX, height + 10.0f, moveZ };
	o->SetOrigin(pos);
	o->SetTeam(3);
	switch (o->GetClass()->class_id) {
	case CLASS_ID_PERSON:
	case CLASS_ID_VEHICLE:
	case CLASS_ID_HELICOPTER:
		{
			AiProcess *process = o->GetAIProcess();
			delete process;
		}
		break;
	}
	moveX += (MOVE_RIGHT - MOVE_LEFT) / 50.0f;
	if (moveX > MOVE_RIGHT) {
		moveX = MOVE_LEFT;
		moveZ += (MOVE_BOTTOM - MOVE_TOP) / 50.0f;
	}
}

static bool MovedObject(GameObject *o)
{
	return (o->GetTeam() == 3);
}

static void KillStuff(void)
{
	GameObject *user = GameObject::GetUser();
	ObjectList::iterator i;
	ObjectList &list = *GameObject::objectList;
	for (i = list.begin(); i != list.end(); i++)
	{
		GameObject *o = *i;
		if (o == user)
			continue;
		if (o == NULL)
			continue;
		if (o->flags & OBJ_GAMEFLAG_DESTROYED)
			continue;
		switch (o->GetSeqNo()) {
		case 5:
		case 6:
		case 7:
		case 8:
			continue;
		}
		if (!MovedObject(o))
		{
			o->SetTeam(3);
			o->Remove();
			i = list.begin();
		}
	}
}

void DemoMission::Execute(void)
{
	
	frame_count++;
	GameObject *userObj = GameObject::GetUser();
	// spawn_point go_path
	
	if (!start_done)
	{
		
		int flags = 0;
		cycle_time=GetTime();
		if (!first_start)
		{
			first_start=true;
			time=GetTime();
			CameraReady();
		}
		StartProfiler(flags);
		target=BuildObject("avdemo",1,"spawn_point");
		Goto(target,"go_path");
		start_done=true;
		camera1=true;
		foe1=BuildObject("svhraz",2,"foe1");  // foe1 foe2 foe3
		foe2=BuildObject("svltnk",2,"foe2");
		foe3=BuildObject("svltnk",2,"foe2");
		foe4=BuildObject("svrckt",2,"foe2");
		friend1=BuildObject("avhraz",1,"friend1");
		art1=BuildObject("avartl",1,"art1");
		build1=BuildObject("sbcomm",2,"build1");
		build2=BuildObject("sbspow",2,"build2");
		build3=BuildObject("sbhang",2,"build3");
		build4=BuildObject("sblpow",2,"build4");
		build5=BuildObject("sbhqcp",2,"build5");
		build6=BuildObject("sbwpow",2,"build6");
		build7=BuildObject("sbwpow",2,"build7");
		build8=BuildObject("sbwpow",2,"build8");
		Goto(foe1,build1);
		Goto(foe2,build1);
		Goto(foe3,build1);
		Goto(foe4,build1);
		Follow(friend1,target);
		
	}
	if (camera1)
	{
		GameObject *targetObj=GameObjectHandle::GetObj(target);
		VECTOR_3D userPos = userObj->GetPosition();
		VECTOR_3D targetPos = targetObj->GetPosition();
		switch (angle) {
		case 0:
			CameraObject(target,0,800,-1500,target);
			break;
		case 1:
			CameraObject(target,-1500,800,0,target);
			break;
		case 2:
			CameraObject(target,0,800,1500,target);
			break;
		}
		if (GetTime()>camera_time)
		{
			camera_time=GetTime()+7.0f;
			angle=angle+1;
			if (angle>2)
			{
				angle=0;
			}
		}
		
		
		if (GetDistance(foe1,target)<200.0f)
		{
			camera1=false;
			camera2=true;
			Attack(art1,foe1);
		}
		if (GetTime()>camera_time)
		{
			camera_time=GetTime()+7.0f;
			angle=angle+1;
			if (angle>2)
			{
				angle=0;
			}
		}
	}
	if (camera2)
	{
		if (IsAlive(build2)) {
			Damage(build2,50);
		}
		switch (angle)
		{
		case 0:
			CameraPath("camera1",1000,0,target);
			break;
		case 1:
			if (IsAlive(foe1))
			{	
				CameraObject(target,-600,400,0,foe1);
			}	
			else
				if (IsAlive(foe2)) CameraObject(target,-600,400,0,foe2);
				break;
		}
		if (GetTime()>camera_time)
		{
			camera_time=GetTime()+7.0f;
			angle=angle+1;
			if (angle>1)
			{
				angle=0;
			}
		}
		
	}
	if ((!IsAlive(target)) || (GetTime()>cycle_time+55.0f))
	{
		cycle_count++;
		if  (cycle_count>4) //(!EndProfiler(flags))
		{
			if (!lost)
			{
				FILE *fd=fopen("addon\\bzbench.des","w+");
				fprintf(fd,"Battlezone Benchmark Test \n\n");
				float tottime=GetTime()-time;
				fprintf(fd,"Total time : %f \n",tottime);
				fprintf(fd,"Average frame rate : %f \n\n",frame_count/tottime);
				fprintf(fd,"This benchmark was created by George Collins.\n");
				fclose(fd);
				// SucceedMission(GetTime()+1.0f,"bzbench.des");
				lost=true;
				QuickExit();
			}	
		}
		else 
		{
			// kill everything and restart
#if 1
			KillStuff();
#else
			if (IsAlive(foe1))	RemoveObject(foe1);
			if (IsAlive(foe2)) RemoveObject(foe2);
			if (IsAlive(foe3)) RemoveObject(foe3);
			if (IsAlive(foe4)) RemoveObject(foe4);
			if (IsAlive(build1)) RemoveObject(build1);
			if (IsAlive(build2)) RemoveObject(build2);
			if (IsAlive(build3)) RemoveObject(build3);
			if (IsAlive(build4)) RemoveObject(build4);
			if (IsAlive(build5)) RemoveObject(build5);
			if (IsAlive(build6)) RemoveObject(build6);
			if (IsAlive(build7)) RemoveObject(build7);
			if (IsAlive(build8)) RemoveObject(build8);
			if (IsAlive(art1)) RemoveObject(art1);
#endif
			start_done=false;
			camera1=false;
			camera2=false;
		}
		
	}
	
 }
 
]====]
