-- Tran02Mission: stock Battlezone 98 Redux / Lua 5.1 port.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Tran02Mission.cpp
-- Source blob: 9b91ae48a9e2648658c1ecc37601795e8c84d16f
-- Standalone LuaMission entry point; uses the original map labels and assets.
-- Assign this script to the tran02 map's LuaMission externally.
-- The complete original C++ is archived below, including every disabled line.

local s = {}
local fields = {
    "lost", "go_reminder", "start_done", "first_objective",
    "second_objective", "third_objecitve", "combat_start", "combat_start2",
    "start_path1", "start_path2", "start_path3", "start_path4", "hint1", "hint2",
    "first_selection", "second_selection", "third_selection", "thirda_selection",
    "fourth_selection", "fifth_selection", "end_message", "jump_start",
    "hint_delay", "repeat_time", "turret", "pointer", "haul1", "haul2",
    "num_reps", "message", "on_point", "defense_menu_pressed",
}

local reminders = {
    "tran0202.wav", "tran0203.wav", "tran0204.wav", "tran0211.wav",
    "tran0206.wav", "misn0109.wav", "tran0207.wav", "tran0208.wav",
}

local function Setup()
    s = {}
    for i = 1, 22 do s[fields[i]] = false end
    s.turret = GetHandle("avturr-1_turrettank")
    s.pointer = GetHandle("nparr-1_i76building")
    s.haul1 = GetHandle("avhaul-1_tug")
    s.haul2 = GetHandle("avhaul19_tug")
    s.hint_delay = 99999.0
    s.repeat_time = 99999.0 -- source first writes 0.0, then overwrites it
    s.num_reps = 0
    s.message = 0
    -- BUGFIX: C++ leaves on_point and p1..p4 uninitialized but serializes them.
    -- on_point is unused; initialize it deterministically. AiPath pointers are
    -- unused too and have no Lua counterpart, so omit them. No branch uses these
    -- values and neither correction changes the tutorial's gameplay flow.
    s.on_point = 0
    s.defense_menu_pressed = false
end

function Start()
    Setup()
end

function AddObject(h)
    -- this is the handle thing brad made for me
    -- Source AddObject(Handle) is empty; LuaMission handles engine bookkeeping.
end

function GameKey(key)
    -- PORT LIMITATION: ControlPanel::GetCurrentItem()==2 has no documented
    -- stock Lua equivalent. Use a fresh default defensive-menu "2" key event
    -- for the two optional instructional cues only. Do not latch the last key:
    -- an early press must not trigger a later target-range hint.
    -- Selection and command progress still use actual engine state below.
    -- Remapped controls and menu context require in-game validation; this pulse
    -- cannot prove that the native menu really opened. It is not exact parity.
    if key == "2" then s.defense_menu_pressed = true end
end

local function PlayReminder(time, message)
    local new_time = time
    if GetTime() > time then
        new_time = GetTime() + 15.0
        if reminders[message] then AudioMessage(reminders[message]) end
        if message == 8 then new_time = 99999.0 end -- we're done
    end
    return new_time
end

function Update(timestep)
    -- Part of the failure/success race fix: once failure is scheduled, do not
    -- retry the failed stage or later schedule success during its delay.
    if s.lost then return end
    local defense_menu_pressed = s.defense_menu_pressed
    s.defense_menu_pressed = false
    if IsAlive(s.turret) then
        s.repeat_time = PlayReminder(s.repeat_time, s.message)
        if not s.start_done then
            SetObjectiveOn(s.turret)
            SetObjectiveName(s.turret, "Turret")
            AudioMessage("tran0201.wav")
            s.hint_delay = GetTime() + 1.0
            ClearObjectives()
            AddObjective("tran0201.otf", "green")
            s.start_done = true
        end
        if GetTime() > s.hint_delay then
            -- was
            -- AudioMessage("tran0202.wav");
            AudioMessage("tran0204.wav")
            s.hint_delay = 99999.0
            s.repeat_time = GetTime() + 30.0
            s.message = 3 -- was 1
            -- new
            s.second_selection = true
        end
        if not s.thirda_selection and s.second_selection and defense_menu_pressed then
            AudioMessage("tran0205.wav")
            -- AudioMessage("tran0211.wav");
            s.thirda_selection = true
            s.repeat_time = GetTime() + 30.0
            s.message = 4
        end
        if not s.third_selection and s.second_selection and IsSelected(s.turret) then
            AudioMessage("tran0206.wav")
            SetObjectiveOff(s.turret)
            -- BUGFIX: the C++ dereferences pointer without checking it. Only
            -- mark/name an existing range marker; selection progression is
            -- unchanged on a valid map, and a missing marker cannot crash Lua.
            if IsValid(s.pointer) then
                SetObjectiveOn(s.pointer)
                SetObjectiveName(s.pointer, "Target Range")
            end
            s.third_selection = true
            s.repeat_time = GetTime() + 30.0
            s.message = 5
        end
        if s.third_selection and not s.go_reminder and not IsSelected(s.turret) then
            AudioMessage("misn0109.wav") -- good job now head for the target range
            s.go_reminder = true
            s.repeat_time = GetTime() + 30.0
            s.message = 6
        end
        -- Preserve the source's strict 3D <100m test, not a horizontal distance.
        -- The same missing-marker guard avoids a source null dereference; do
        -- not invent a replacement range location or advance the stage early.
        if s.third_selection and not s.hint1 and IsValid(s.pointer)
            and Distance3DSquared(GetPosition(s.pointer), GetPosition(s.turret)) < 100.0 * 100.0 then
            AudioMessage("tran0207.wav")
            AudioMessage("tran0212.wav") -- press 2
            s.hint1 = true
            s.repeat_time = GetTime() + 30.0
            s.message = 7
        end
        if s.hint1 and not s.hint2 and defense_menu_pressed then
            s.hint2 = true
            AudioMessage("tran0211.wav") -- press 1
            s.repeat_time = GetTime() + 20.0
            s.message = 4
        end
        if s.hint1 and not s.fourth_selection and IsSelected(s.turret) then
            AudioMessage("tran0208.wav")
            s.fourth_selection = true
            s.repeat_time = GetTime() + 30.0
            s.message = 8
        end
        if s.fourth_selection and not s.fifth_selection
            and GetCurrentCommand(s.turret) == AiCommand.GO then
            s.repeat_time = 99999.0 -- we're done repeating
            AudioMessage("tran0209.wav")
            if IsAlive(s.haul1) then
                -- The C++ two-point AiPath ends at the turret's position at
                -- issuance. Snapshot the vector: this is GO, not FOLLOW.
                Goto(s.haul1, GetPosition(s.turret), 1) -- so the computer doesn't interupt
                if IsValid(s.pointer) then SetObjectiveOff(s.pointer) end
                SetObjectiveOn(s.haul1)
                SetObjectiveName(s.haul1, "Target Drone")
            else
                -- BUGFIX: C++ schedules failure but sets fifth_selection, so
                -- a null haul1 can also schedule success later in this frame.
                -- End this failed run explicitly; a live drone follows the
                -- original sequence and retains the original success timing.
                s.lost = true
                FailMission(GetTime() + 2.0, "tran02l1.des")
                return
            end
            s.fifth_selection = true
        end
        -- SOURCE NO-OP (not restored as active gameplay): when haul1 is alive
        -- and CMD_NONE, C++ constructs AiCmdInfo/AiPath but never SetCommand.
        -- Issuing Goto here would introduce perpetual pursuit and could move
        -- the drone before fifth_selection. Preserve that original behavior;
        -- the full unfinished block remains in the source archive below.
        if s.fifth_selection and not s.end_message and not IsValid(s.haul1) then
            -- Match GetObj(haul1)==NULL: death alone is not object removal.
            AudioMessage("tran0210.wav")
            s.end_message = true
            SucceedMission(GetTime() + 10.0, "tran02w1.des")
        end
    elseif not s.lost then
        s.lost = true
        FailMission(GetTime() + 5.0, "tran02l1.des")
    end
end

-- Save flat primitives/engine handles, with an explicit count to retain nil
-- handles. LuaMission serializes/remaps handles; no native PostLoad is needed.
function Save()
    local values = {}
    for i, field in ipairs(fields) do values[i] = s[field] end
    return unpack(values, 1, #fields)
end

function Load(...)
    local values = {...}
    s = {}
    for i, field in ipairs(fields) do s[field] = values[i] end
end

-- Verbatim C++ source archive (line endings normalized). This preserves the
-- class layout, unused flags/paths, save/load plumbing, source comments, cut
-- audio lines, and incomplete idle-drone command for later reconstruction.
--[==[
#include "GameCommon.h"

#include "..\fun3d\AiMission.h"
#include "..\fun3d\GameObjectHandle.h"
#include "..\fun3d\AiUtil.h"
#include "..\fun3d\PowerUp.h"
#include "..\fun3d\ScriptUtils.h"
#include "..\fun3d\ControlPanel.h"

/*
	Tran02Mission
*/

class Tran02Mission : public AiMission {
	DECLARE_RTIME(Tran02Mission)
public:
	Tran02Mission(void);
	~Tran02Mission();

	virtual bool Load(file fp);
	virtual bool PostLoad(void);
	virtual bool Save(file fp);

	virtual void Update(void);

	virtual void AddObject(GameObject *gameObj);

private:
	void Setup(void);
	void AddObject(Handle h);
	void Execute(void);

	// bools
	union {
		struct {
			bool
				lost,
				go_reminder,
				start_done,
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
				first_selection,
				second_selection,
				third_selection,
				thirda_selection,
				fourth_selection,
				fifth_selection,
				end_message,
				jump_start,
				b_last;
		};
		bool b_array[22];
	};

	// floats
	union {
		struct {
			float
				hint_delay,
				repeat_time,
				f_last;
		};
		float f_array[2];
	};

	// handles
	union {
		struct {
			Handle
				turret,
				pointer,
				haul1,
				haul2,
				h_last;
		};
		Handle h_array[4];
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
				num_reps,
				message,
				on_point,
				i_last;
		};
		int i_array[3];
	};
};


void Tran02Mission::Setup(void)
{
	lost=false;
	start_done=false;
	first_selection=false;
	second_selection=false;
	third_selection=false;
	fourth_selection=false;
	fifth_selection=false;
	first_objective=false;
	second_objective=false;
	third_objecitve=false;
	thirda_selection=false;
	start_path1=false;
	start_path2=false;
	start_path3=false;
	start_path4=false;
	jump_start=false;
	combat_start=false;
	combat_start2=false;
	end_message=false;
	go_reminder=false;
	hint1=false;
	hint2=false;
	turret=GetHandle("avturr-1_turrettank");
	pointer=GetHandle("nparr-1_i76building");
	haul1=GetHandle("avhaul-1_tug");
	haul2=GetHandle("avhaul19_tug");
	repeat_time=0.0f;
	num_reps=0;
	hint_delay=99999.0f;
	repeat_time=99999.0f;
	message=0;
}

// this is the handle thing brad made for me
void Tran02Mission::AddObject(Handle h)
{
}

float PlayReminder(float time,int message)
{
	float new_time=time;
	if (Get_Time()>time)
	{		
		new_time=Get_Time()+15.0f;
		switch (message)
		{
			case 1: AudioMessage("tran0202.wav");
				break;
			case 2: AudioMessage("tran0203.wav");
				break;
			case 3: AudioMessage("tran0204.wav");
				break;
			case 4: AudioMessage("tran0211.wav");
				break;
			case 5: AudioMessage("tran0206.wav");
				break;
			case 6: AudioMessage("misn0109.wav");
				break;
			case 7: AudioMessage("tran0207.wav");
				break;
			case 8: AudioMessage("tran0208.wav");
					new_time=99999.0f;  // we're done
				break;
		}
	}
	return new_time;
}

void Tran02Mission::Execute(void)
{
	if (IsAlive(turret))
	{
		repeat_time=PlayReminder(repeat_time,message);
		if (!start_done)
		{
			GameObject *second_obj=GameObjectHandle::GetObj(turret);  
			second_obj->SetObjective(TRUE);
			second_obj->SetName("Turret");
			AudioMessage("tran0201.wav");
			hint_delay=Get_Time()+1.0f;
			ClearObjectives();
			AddObjective("tran0201.otf",GREEN);
			start_done=true;
		}
		if (Get_Time()>hint_delay)
		{
			// was
			// AudioMessage("tran0202.wav");
			AudioMessage("tran0204.wav"); 
			hint_delay=99999.0f;
			repeat_time=Get_Time()+30.0f;
			message=3;  // was 1
			// new 
			second_selection=true;
		}
		if ((!thirda_selection) &&
			(second_selection) &&
			(ControlPanel::GetCurrentItem()==2))
		{
			AudioMessage("tran0205.wav");
		//	AudioMessage("tran0211.wav");
			thirda_selection=true;
			repeat_time=Get_Time()+30.0f;
			message=4;
		}
	
		if ((!third_selection) &&
			(second_selection) &&
			(GameObjectHandle::GetObj(turret)->IsSelected()))
		{
			AudioMessage("tran0206.wav");
			GameObject *second_obj=GameObjectHandle::GetObj(turret);  
			second_obj->SetObjective(false);
			second_obj=GameObjectHandle::GetObj(pointer);  
			second_obj->SetObjective(true);
			second_obj->SetName("Target Range");
			third_selection=true;
			repeat_time=Get_Time()+30.0f;
			message=5;	
		}
		if ((third_selection) && (!go_reminder) &&
			(!GameObjectHandle::GetObj(turret)->IsSelected()))
		{
			AudioMessage("misn0109.wav"); // good job now head for the target range
			go_reminder=true;
			repeat_time=GetTime()+30.0f;
			message=6;
		}
		if ((third_selection) && 
			(!hint1) &&
			(Dist3D_Squared(GameObjectHandle::GetObj(pointer)->GetPosition(),
				GameObjectHandle::GetObj(turret)->GetPosition())
				< 100.0f * 100.0f))
		{
			AudioMessage("tran0207.wav");
			AudioMessage("tran0212.wav"); // press 2
			hint1=true;
			repeat_time=Get_Time()+30.0f;
			message=7;
		}
		if ((hint1) && (!hint2) &&
			(ControlPanel::GetCurrentItem()==2))
		{
			hint2=true;
			AudioMessage("tran0211.wav");  // press 1
			repeat_time=Get_Time()+20.0f;
			message=4;
		}
		if ((hint1) &&
			(!fourth_selection) &&
			(GameObjectHandle::GetObj(turret)->IsSelected()))
		{
			AudioMessage("tran0208.wav");
			fourth_selection=true;
			repeat_time=Get_Time()+30.0f;
			message=8;
		}
		if ((fourth_selection) &&
			(!fifth_selection) &&
			(GetCurrentCommand(turret)==CMD_GO))
		{
			repeat_time=99999.0f; // we're done repeating
			AudioMessage("tran0209.wav");	
			if (IsAlive(haul1))
			{
				AiCmdInfo info;
				info.what=CMD_GO;
				info.priority=1;  // so the computer doesn't interupt
				info.where=new AiPath(GameObjectHandle::GetObj(haul1)->GetPosition(),GameObjectHandle::GetObj(turret)->GetPosition());
			
				GameObjectHandle::GetObj(haul1)->SetCommand(info);
				GameObject *second_obj=GameObjectHandle::GetObj(pointer);  
				second_obj->SetObjective(false);
				second_obj=GameObjectHandle::GetObj(haul1);  
				second_obj->SetObjective(TRUE);
				second_obj->SetName("Target Drone");
			}
			else FailMission(GetTime()+2.0f,"tran02l1.des");
			fifth_selection=true;
		}
		if ((IsAlive(haul1)) && (GetCurrentCommand(haul1)==CMD_NONE))
		{
			AiCmdInfo info;
			info.what=CMD_GO;
			info.priority=1;  // so the computer doesn't interupt
			info.where=new AiPath(GameObjectHandle::GetObj(haul1)->GetPosition(),GameObjectHandle::GetObj(turret)->GetPosition());	
		}
		if ((fifth_selection) &&
			(!end_message) &&
			(GameObjectHandle::GetObj(haul1)==NULL))
		{
			AudioMessage("tran0210.wav");
			end_message=true;
			SucceedMission(GetTime()+10.0f,"tran02w1.des");
		}
	}
	else
	{
		if (!lost)
		{
			lost=true;
			FailMission(GetTime()+5.0f,"tran02l1.des");
		}
	}
}

IMPLEMENT_RTIME(Tran02Mission)

Tran02Mission::Tran02Mission(void)
{
}

Tran02Mission::~Tran02Mission()
{
}

void Tran02Mission::AddObject(GameObject *gameObj)
{
	AddObject(gameObj->GetHandle());
	AiMission::AddObject(gameObj);
}

bool Tran02Mission::Load(file fp)
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

bool Tran02Mission::PostLoad(void)
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

bool Tran02Mission::Save(file fp)
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

void Tran02Mission::Update(void)
{
	AiMission::Update();
	Execute();
}

]==]
