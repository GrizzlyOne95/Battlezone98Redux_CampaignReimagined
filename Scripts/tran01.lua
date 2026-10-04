-- tran01.lua -- Training 1 / Combat Driving, stock BZR Lua 5.1.
-- Tran01Mission.cpp delegates to Misn01Mission.cpp; that is the implementation below.
-- Sources: GrizzlyOne95/Battlezone_Source, BZ1/from_bz2_dll_src/
-- Tran01Mission.cpp blob: 12aef54827c40bc2c4d19394d045cb7d9cbf7a43
-- Misn01Mission.cpp blob: b885c6f29f23db76812f73424f306e224dbb0de0
-- Uses the original misn01 map labels, paths, audio, objectives and result files.
-- No difficulty/QOL changes or external Lua/native modules are required.
-- Bind this script through the map's LuaMission configuration to run it.
-- The complete original sources (including ALL commented-out code) are below.

local s
local function Setup()
    s = {
        start_done = false, hop_in = false,
        first_objective = false, second_objective = false,
        third_objecitve = false, -- Original spelling; these three flags are unused.
        combat_start = false, combat_start2 = false,
        start_path1 = false, start_path2 = false,
        start_path3 = false, start_path4 = false,
        hint1 = false, hint2 = false, done_message = false,
        jump_start = false, lost = false,
        repeat_time = 0.0, forgiveness = 40.0, jump_done = 0.0,
        num_reps = 0, on_point = 0,
        p1 = "path_1", p2 = "path_2", p3 = "path_3", p4 = "path_5",
    }
    -- BUG FIX: C++ Setup leaves jump_done, on_point, aud and handles uninitialized.
    -- Initialize numbers to zero and handles/messages to nil. The active branches
    -- assign them before use, so valid mission sequencing and timing are unchanged.
end
Setup()

function Start()
    Setup() -- Original Setup, with first-update initialization kept in Update.
end

function Save()
    -- Persist all source state; LuaMission serializes handles/messages directly.
    -- Named paths replace C++ AiPath pointers; no ConvertHandle/PostLoad is needed.
    return s
end

function Load(state)
    if state ~= nil then
        s = state
    else
        Setup()
    end
end

local function DistanceXZ(a, b)
    -- C++ VECTOR_2D is X/Z: altitude must not change course/jump progression.
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function CourseDistance(path, point, player_pos)
    -- Stock path point indices are zero-based, matching AiPath::points.
    return DistanceXZ(GetPosition(path, point), player_pos)
end

local function AdvanceCourse(path, player_pos, warning, check_targets)
    -- Keep the original shared on_point, one-point advancement per block, and
    -- independent Update conditions (a transition can execute the next block
    -- in the SAME frame). In particular path_5 is not gated on hint1.
    local count = GetPathPointCount(path)
    -- Validate the cursor before querying either point.
    if s.on_point < 0 or s.on_point + 1 >= count then
        return false
    end
    local current = CourseDistance(path, s.on_point, player_pos)
    if current > s.forgiveness and GetTime() > s.repeat_time then
        AudioMessage(warning)
        if check_targets and not IsAlive(s.target)
            and not IsAlive(s.target2) and not s.lost then
            s.lost = true
            FailMission(GetTime() + 5.0, "misn01l1.des")
        end
        s.repeat_time = GetTime() + 15.0
        s.num_reps = s.num_reps + 1
    end
    -- Use the actual stock path count, never an out-of-range GetPosition probe.
    -- BUG FIX: avoid C++'s unchecked points[on_point+1] access if a path is
    -- malformed or the shared cursor is out of bounds. Valid source paths
    -- always have a next point here, so normal progression is unchanged.
    local next_distance = CourseDistance(path, s.on_point + 1, player_pos)
    if next_distance < current then
        s.on_point = s.on_point + 1
        return s.on_point == count - 1
    end
    return false
end

function Update()
    local player_handle = GetPlayerHandle()
    if not s.start_done then
        -- Original disabled statement: start_done=TRUE;
        s.get_in_me = GetHandle("avfigh0_wingman")
        s.aud = AudioMessage("misn0101.wav")
        s.target = GetHandle("svturr0_turrettank")
        s.target2 = GetHandle("svturr1_turrettank")
        s.start_done = true
        s.repeat_time = GetTime() + 30.0
        ClearObjectives()
        AddObjective("misn0101.otf", "white")
        AddObjective("misn0103.otf", "white")
        s.num_reps = 0
    end

    -- BUG FIX: source leaves player2d uninitialized when the player is dead,
    -- and later dereferences GameObject::GetUser(). Skip positional course
    -- logic without a live player; keep target/result logic running below.
    -- No live-player branch, threshold or timer is changed.
    local player_pos = nil
    if IsAlive(player_handle) then
        player_pos = GetPosition(player_handle)
    end

    if not s.start_path1 and GetTime() > s.repeat_time then
        s.repeat_time = GetTime() + 20.0
        ClearObjectives()
        AddObjective("misn0101.otf", "green")
        -- aud=AudioMessage("misn0101.wav"); -- Disabled in C++.
        s.num_reps = s.num_reps + 1
    end

    if player_pos then
        if not s.start_path1 then
            -- how far are we from the start..
            if CourseDistance(s.p1, 0, player_pos) < s.forgiveness then
                -- we've started
                if player_handle ~= s.get_in_me and not s.hop_in then
                    s.hop_in = true
                    if s.aud ~= nil then StopAudioMessage(s.aud) end
                    AudioMessage("misn0122.wav")
                else
                    ClearObjectives()
                    AddObjective("misn0101.otf", "green")
                    AddObjective("misn0103.otf", "white")
                end
                StartCockpitTimerUp(0, 300, 240)
                s.repeat_time = 0.0
                s.num_reps = 0
                s.start_path1 = true
                s.on_point = 0
            end
        end

        if s.start_path1 and not s.start_path2
            and player_handle == s.get_in_me then
            if AdvanceCourse(s.p1, player_pos, "misn0103.wav", true) then
                s.start_path2 = true
                s.on_point = 0
            end
        end

        if s.start_path2 and not s.start_path3 then
            if AdvanceCourse(s.p2, player_pos, "misn0103.wav", true) then
                s.start_path3 = true
                AudioMessage("misn0104.wav")
                s.on_point = 0
            end
        end

        if s.start_path3 and not s.jump_start then
            if AdvanceCourse(s.p3, player_pos, "misn0103.wav", true) then
                s.jump_start = true
                s.jump_done = GetTime() + 8.0
                -- Source deliberately does not reset on_point here.
            end
        end
    end

    if s.jump_start and not s.hint1 and GetTime() > s.jump_done then
        s.repeat_time = GetTime() + 45.0 -- grace period to continue
        AudioMessage("misn0105.wav")
        s.forgiveness = s.forgiveness * 1.5 -- for the jumps you'll need it
        AudioMessage("misn0107.wav")
        s.hint1 = true
    end

    if player_pos then
        if not s.start_path4 then
            -- Source checks this independently even before jump_start/hint1.
            if CourseDistance(s.p4, 0, player_pos) < s.forgiveness then
                s.repeat_time = 0.0
                s.num_reps = 0
                s.start_path4 = true
                s.on_point = 0
                -- Original editorial comment retained verbatim in the appendix.
                if player_handle ~= s.get_in_me then
                    AudioMessage("misn0122.wav")
                end
            end
        end

        if s.start_path4 and not s.combat_start then
            if AdvanceCourse(s.p4, player_pos, "misn0108.wav", false) then
                StopCockpitTimer()
                s.combat_start = true
                -- BUG FIX: C++ dereferences target even if destroyed earlier.
                -- Guard just the marker/name; keep the transition and narration
                -- at the same time, including early target-destruction cases.
                if IsValid(s.target) then
                    SetObjectiveOn(s.target)
                    SetObjectiveName(s.target, "Combat Training")
                end
                AudioMessage("misn0109.wav")
            end
        end

        if s.combat_start and not s.hint2 and IsAlive(s.target) then
            -- This combat check is 3D, unlike the driving course.
            local target_pos = GetPosition(s.target)
            local dx = target_pos.x - player_pos.x
            local dy = target_pos.y - player_pos.y
            local dz = target_pos.z - player_pos.z
            if dx * dx + dy * dy + dz * dz < 100.0 * 100.0 then
                HideCockpitTimer()
                AudioMessage("misn0111.wav")
                s.hint2 = true
            end
        end
    end

    if not s.combat_start2 and not IsAlive(s.target) and IsAlive(s.target2) then
        SetObjectiveOn(s.target2)
        SetObjectiveName(s.target2, "Combat Training 2")
        AudioMessage("misn0113.wav")
        s.combat_start2 = true
    end

    if not s.done_message and not IsAlive(s.target) and not IsAlive(s.target2) then
        AudioMessage("misn0121.wav")
        s.done_message = true
        SucceedMission(GetTime() + 10, "misn01w1.des")
    end

    if s.num_reps > 4 and not s.lost then
        s.repeat_time = 99999.0
        ClearObjectives()
        AddObjective("misn0102.otf", "red")
        AudioMessage("misn0123.wav")
        FailMission(GetTime() + 10, "misn01l1.des")
        s.num_reps = 0
        -- Preserve source: this branch does not set lost. Do not merge result
        -- branches or add a terminal-state gate; source can schedule success
        -- after failure when both targets die during the ending delay.
    end
end

-- Complete inactive source archive for cut-content reconstruction.
--[====[
// Tran01Mission.cpp
#include "GameCommon.h"

// the first training mission uses Misn01Mission.cpp

// Misn01Mission.cpp
#include "GameCommon.h"

#include "..\fun3d\PowerUp.h"
#include "..\fun3d\ScriptUtils.h"

/*
	Misn01Mission
*/

// used by (misn01.bzn) as first training mission

#include "..\fun3d\AiMission.h"

class Misn01Mission : public AiMission {
	DECLARE_RTIME(Misn01Mission)
public:
	Misn01Mission(void);
	~Misn01Mission();

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
				b_last;
		};
		bool b_array[16];
	};

	// floats
	union {
		struct {
			float
				repeat_time,
				forgiveness,
				jump_done,
				f_last;
		};
		float f_array[3];
	};

	// object handles
	union {
		struct {
			Handle
				get_in_me,
				target,
				target2,
				h_last;
		};
		Handle h_array[3];
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
				aud,
				num_reps,
				on_point,
				i_last;
		};
		int i_array[3];
	};
};

IMPLEMENT_RTIME(Misn01Mission)

Misn01Mission::Misn01Mission(void)
{
}

Misn01Mission::~Misn01Mission()
{	
}

bool Misn01Mission::Load(file fp)
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

bool Misn01Mission::PostLoad(void)
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

bool Misn01Mission::Save(file fp)
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

void Misn01Mission::Update(void)
{
	AiMission::Update();
	Execute();
}

void Misn01Mission::Setup(void)
{
	start_done=false;
	lost=false;
	first_objective=false;
	second_objective=false;
	third_objecitve=false;
	start_path1=false;
	start_path2=false;
	start_path3=false;
	start_path4=false;
	jump_start=false;
	hop_in=false;
	combat_start=false;
	combat_start2=false;
	hint1=false;
	hint2=false;
	done_message=false;
	repeat_time=0.0f;
	num_reps=0;
	forgiveness=40.0f;
}

void Misn01Mission::Execute(void)
{
	GameObject *player = GameObject::GetUser();
	Handle player_handle=GetPlayerHandle();
	VECTOR_2D player2d;
	if (IsAlive(player_handle)) player2d = Vec2D_From3D(player->GetPosition());
	if (!start_done)
	{
//		start_done=TRUE;
		get_in_me=GetHandle("avfigh0_wingman");
		aud=AudioMessage("misn0101.wav");
		p1=AiPath::Find("path_1");
		p2=AiPath::Find("path_2");
		p3=AiPath::Find("path_3");
		p4=AiPath::Find("path_5");
		target=GetHandle("svturr0_turrettank");
		target2=GetHandle("svturr1_turrettank");
		start_done=TRUE;
		repeat_time=Get_Time()+30.0f;
		ClearObjectives();
		AddObjective("misn0101.otf",WHITE);
		AddObjective("misn0103.otf",WHITE);
		num_reps=0;
	}

	GameObject *first = GameObjectHandle::GetObj(target);
	if ((!start_path1) && (Get_Time()>repeat_time))
	{
		repeat_time=Get_Time()+20.0f;
		ClearObjectives();
		AddObjective("misn0101.otf",GREEN);

		//		aud=AudioMessage("misn0101.wav");
		num_reps++;
	}
	if (!start_path1)		
	{
		// how far are we from the start..
		VECTOR_2D diff= Vec2D_Subtract(p1->points[0],player2d);
		if (Vec2D_Len(diff)<forgiveness)
		{
			// we've started
			if ((player_handle!=get_in_me)
				&& (!hop_in))
			{
				hop_in=true;
				StopAudioMessage(aud);
				AudioMessage("misn0122.wav");
			}
			else
			{
				ClearObjectives();
				AddObjective("misn0101.otf",GREEN);
				AddObjective("misn0103.otf",WHITE);

			}
			StartCockpitTimerUp(0,300,240);
			repeat_time=0.0f;
			num_reps=0;
			start_path1=TRUE;
			on_point=0;
		}
	}
	if ((start_path1) && (!start_path2) && (player_handle==get_in_me))
	{
		// are we out of range of current point?
		VECTOR_2D diff=Vec2D_Subtract(p1->points[on_point],player2d);
		float x=Vec2D_Len(diff);
		if ((Vec2D_Len(diff)>forgiveness) && (Get_Time()>repeat_time))
		{
			// tell player to get back where he was before
			AudioMessage("misn0103.wav");
			if ((!IsAlive(target)) &&
				(!IsAlive(target2)) && (!lost))
			{
				lost=true;
				FailMission(GetTime()+5.0f,"misn01l1.des");
			}
			repeat_time=Get_Time()+15.0f;
			num_reps++;
		}
		VECTOR_2D diff2=Vec2D_Subtract(p1->points[on_point+1],player2d);
		if (Vec2D_Len(diff2)<Vec2D_Len(diff))
		{
			// time to switch where we are on the path
			on_point++;
			if (on_point==p1->pointCount-1)
			{
				start_path2=TRUE;
				on_point=0;
			}
		}
	}
	if ((start_path2) && (!start_path3))
	{
		// are we out of range of current point?
		VECTOR_2D diff=Vec2D_Subtract(p2->points[on_point],player2d);
		float x=Vec2D_Len(diff);
		if ((Vec2D_Len(diff)>forgiveness) && (Get_Time()>repeat_time))
		{
			// tell player to get back where he was before
			AudioMessage("misn0103.wav");
			if ((!IsAlive(target)) &&
				(!IsAlive(target2)) && (!lost))
			{
				lost=true;
				FailMission(GetTime()+5.0f,"misn01l1.des");
			}
			repeat_time=Get_Time()+15.0f;
			num_reps++;
		}
		VECTOR_2D diff2=Vec2D_Subtract(p2->points[on_point+1],player2d);
		if (Vec2D_Len(diff2)<Vec2D_Len(diff))
		{
			// time to switch where we are on the path
			on_point++;
			if (on_point==p2->pointCount-1)
			{
				start_path3=TRUE;
				AudioMessage("misn0104.wav");
				on_point=0;
			}
		}
		
	}
	if ((start_path3) && (!jump_start))
	{
		// are we out of range of current point?
		VECTOR_2D diff=Vec2D_Subtract(p3->points[on_point],player2d);
		float x=Vec2D_Len(diff);
		if ((Vec2D_Len(diff)>forgiveness) && (Get_Time()>repeat_time))
		{
			// tell player to get back where he was before
			AudioMessage("misn0103.wav");
			if ((!IsAlive(target)) &&
				(!IsAlive(target2)) && (!lost))
			{
				lost=true;
				FailMission(GetTime()+5.0f,"misn01l1.des");
			}
			repeat_time=Get_Time()+15.0f;
			num_reps++;
		}
		VECTOR_2D diff2=Vec2D_Subtract(p3->points[on_point+1],player2d);
		if (Vec2D_Len(diff2)<Vec2D_Len(diff))
		{
			// time to switch where we are on the path
			on_point++;
			if (on_point==p3->pointCount-1)
			{
				jump_start=TRUE;
				jump_done=Get_Time()+8.0f;
			}
		}
		
	}
	if ((jump_start) && (!hint1) && (Get_Time()>jump_done))
	{

		repeat_time=Get_Time()+45.0f;  // grace period to continue
		AudioMessage("misn0105.wav");
		forgiveness=forgiveness*1.5f;  // for the jumps you'll need it
		AudioMessage("misn0107.wav");
		hint1=TRUE;
	}
	if (!start_path4)		
	{
		// how far are we from the start..
		VECTOR_2D diff= Vec2D_Subtract(p4->points[0],player2d);
		if (Vec2D_Len(diff)<forgiveness)
		{
			// we've started
			repeat_time=0.0f;
			num_reps=0;
			start_path4=TRUE;
			on_point=0;
			/*
				In case the player is
				developmentally 
				disabled.
			*/
			if (player_handle!=get_in_me)
			{
					AudioMessage("misn0122.wav");
			}
		}

	}
	if ((start_path4) && (!combat_start))
	{
		// are we out of range of current point?
		VECTOR_2D diff=Vec2D_Subtract(p4->points[on_point],player2d);
		float x=Vec2D_Len(diff);
		if ((Vec2D_Len(diff)>forgiveness) && (Get_Time()>repeat_time))
		{
			// tell player to get back where he was before
			AudioMessage("misn0108.wav");
			repeat_time=Get_Time()+15.0f;
			num_reps++;
		}
		VECTOR_2D diff2=Vec2D_Subtract(p4->points[on_point+1],player2d);
		if (Vec2D_Len(diff2)<Vec2D_Len(diff))
		{
			// time to switch where we are on the path
			on_point++;
			if (on_point==p4->pointCount-1)
			{
				StopCockpitTimer();
				combat_start=TRUE;
				GameObject *second_obj=GameObjectHandle::GetObj(target);  
				second_obj->SetObjective(TRUE);
				second_obj->SetName("Combat Training");
				AudioMessage("misn0109.wav");
			}
		}
		
	}
	if ((combat_start) && (!hint2) && (IsAlive(target)))
	if  		
			(Dist3D_Squared(first->GetPosition(), player->GetPosition())
			< 100.0f * 100.0f)

	{
		HideCockpitTimer();
		AudioMessage("misn0111.wav");
		hint2=TRUE;
	}
		

	if ((!combat_start2) && 
		(!IsAlive(target)) && (IsAlive(target2)))
	{
		GameObject *second_obj=GameObjectHandle::GetObj(target2);  
		second_obj->SetObjective(TRUE);
		second_obj->SetName("Combat Training 2");
		AudioMessage("misn0113.wav");
		combat_start2=TRUE;
	}

	if ((!done_message) &&
		(!IsAlive(target))
		&& (!IsAlive(target2)))
	{
		AudioMessage("misn0121.wav");
		done_message=true;
		SucceedMission(GetTime()+10,"misn01w1.des");
	}
	if ((num_reps>4) && (!lost))
	{
		repeat_time=99999.0f;
		ClearObjectives();
		AddObjective("misn0102.otf",RED);
		AudioMessage("misn0123.wav");
		FailMission(GetTime()+10,"misn01l1.des");
		num_reps=0;
	}
}

]====]
