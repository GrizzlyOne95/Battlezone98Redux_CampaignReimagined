-- Faithful Tran04Mission port for stock Battlezone 98 Redux / Lua 5.1.
-- Source: BZ1/from_bz2_dll_src/Tran04Mission.cpp, blob
-- 184a7a4631a6e0bd4f17b510719a01123e57dd21 in GrizzlyOne95/Battlezone_Source.
-- Original native source, including every comment and cut block, is archived
-- below. No EXU/OpenShim or community mission framework is required.

local function NewState()
    local state = {
        found1 = false, found2 = false, start_done = false, press7 = false,
        attacked = false, jump_start = false,
        repeat_time = 0, camera_delay = 0, num_reps = 0, on_point = 0,
        player = nil, target1 = nil, target2 = nil, recycler = nil,
        muf = nil, camera = nil, wing = nil, recy = nil,
    }
    for i = 1, 16 do state["message" .. i] = false end
    -- PORT FIX: initialize fields omitted by native Setup. camera_delay is
    -- overwritten before use; jump_start/on_point and the path pointers are
    -- unused. Deterministic defaults do not change any active mission branch.
    return state
end

-- Map-loading AddObject callbacks may precede Start. Keep their discoveries.
local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

function Start()
    -- Setup is performed at script creation, before map AddObject callbacks.
end

-- this is the handle thing brad made for me
function AddObject(h)
    if not Valid(h) or GetTeamNum(h) ~= 1 then return end
    if IsOdf(h, "avmuf") then
        M.found1 = true
        M.muf = h
    end
    if IsOdf(h, "avfigh") then
        M.found2 = true
        M.wing = h
    end
end

function Update(dt)
    -- Independent blocks intentionally preserve native Execute order and
    -- same-update progression. Get_Time() maps to stock GetTime().
    if not M.start_done then
        M.target1 = GetHandle("avturr12_turrettank")
        M.target2 = GetHandle("avturr-1_turrettank")
        M.recycler = GetHandle("avrecy-1_recycler")
        M.camera = GetHandle("apcamr-1_camerapod")
        M.player = GetHandle("player-1_hover")
        SetScrap(1, 30)
        AudioMessage("tran0401.wav")
        AudioMessage("tran0402.wav")
        AudioMessage("tran0424.wav")
        ClearObjectives()
        AddObjective("tran0401.otf", "white")
        M.start_done = true
    end

    if not M.message1 and Alive(M.recycler) and IsSelected(M.recycler) then
        AudioMessage("tran0425.wav")
        M.message1 = true
    end
    if M.message1 and not M.message2 and Alive(M.recycler) then
        if IsDeployed(M.recycler) then
            AudioMessage("tran0424.wav") -- select the recycler
            M.message2 = true
        end
        -- added to skip muf stage
    end

    -- press 7 to have the recyler build a factory
    if M.message2 and Alive(M.recycler) and IsSelected(M.recycler) and not M.press7 then
        -- was AudioMessage("tran0403.wav")
        AudioMessage("tran0406.wav")
        M.press7 = true
        M.message6 = true
    end

    -- Cut factory tutorial: inactive Lua reconstruction. The exact original
    -- block (including FailAll(10)) is in the native archive below.
    --[==[
    if M.message2 and not M.message3 then
        local money = GetScrap(1)
        if money < 30 and M.found1 then
            -- found1 is set but we don't test for it
            -- M.muf = GetHandle("avmuf-1_factory")
            if Valid(M.muf) then
                AudioMessage("tran0404.wav")
                AudioMessage("tran0405.wav")
                M.message3 = true
            else
                M.message2 = false -- so you don't repeat this
                -- FailAll(10): no stock Lua counterpart; single-player equivalent:
                FailMission(GetTime() + 10, "tran04l1.des") -- you built the wrong thing
            end
        end
    end
    if M.message3 and not M.message4 and IsSelected(M.muf) then
        AudioMessage("tran0423.wav")
        M.message4 = true
    end
    if M.message4 and not M.message5 and IsDeployed(M.muf) then
        AudioMessage("tran0405.wav")
        M.message5 = true
    end
    if M.message5 and not M.message6 and IsSelected(M.muf) then
        AudioMessage("tran0406.wav")
        M.message6 = true
    end
    ]==]

    if M.message6 and not M.message7 and Alive(M.recycler) and not IsSelected(M.recycler) then
        -- was muf selected
        AudioMessage("tran0407.wav")
        M.camera_delay = GetTime() + 5
        M.message7 = true
    end
    if M.message7 and not M.message8 and GetTime() > M.camera_delay then
        AudioMessage("tran0408.wav")
        M.camera_delay = 99999
    end
    if M.message7 and not M.message8 and GetUserTarget() == M.camera then
        AudioMessage("tran0409.wav")
        M.message8 = true
        M.camera_delay = GetTime() + 3
    end
    if M.message8 and not M.message9 and GetTime() > M.camera_delay and M.found2 then
        AudioMessage("tran0410.wav")
        -- M.wing = GetHandle("avtank-1_wingman")
        M.message9 = true
        M.camera_delay = 99999
    end
    -- PORT FIX: native checks !IsAlive(wing) immediately after camera targeting,
    -- even before AddObject has found a fighter. Require found2 so an unbuilt
    -- wingman is not treated as dead. Once built, the same death failure, five
    -- second delay, and message16 outcome latch apply; tutorial order is intact.
    if M.message8 and M.found2 and not Alive(M.wing) and not M.message16 then
        FailMission(GetTime() + 5, "tran04l1.des")
        M.message16 = true
    end
    if M.message9 and not M.message10 and Alive(M.wing) and IsSelected(M.wing) then
        AudioMessage("tran0411.wav")
        M.message10 = true
    end
    if M.message10 and not M.message11 and Alive(M.wing)
        and not IsSelected(M.wing) and M.camera_delay == 99999 then
        M.camera_delay = GetTime() + 10
    end
    if M.message10 and not M.message11 and M.camera_delay < GetTime() then
        AudioMessage("tran0412.wav")
        M.message11 = true
        M.camera_delay = 99999
    end
    if M.message10 and not M.attacked and Alive(M.wing) and GetLastEnemyShot(M.wing) > 0 then
        AudioMessage("tran0413.wav")
        M.attacked = true
    end

    if not Alive(M.target1) and not M.message12 then
        AudioMessage("tran0415.wav")
        if Alive(M.target2) then
            SetObjectiveOn(M.target2)
            SetObjectiveName(M.target2, "Drone 2")
        end
        M.message12 = true
    end
    if Valid(M.player) and Valid(M.target2) and M.message12
        and GetDistance(M.player, M.target2) < 300 and not M.message13 then
        AudioMessage("tran0416.wav")
        M.message13 = true
        AudioMessage("tran0418.wav")
        M.message13 = true -- duplicate assignment preserved from source
    end
    if M.message13 and GetUserTarget() == M.target2 and not M.message14 then
        AudioMessage("tran0410.wav")
        M.message14 = true
    end
    -- PORT FIX: native dereferences wing without checking that it still exists.
    -- Guard only the selection query; valid wingmen retain the same prompt and
    -- timing, and the existing failure branch still handles wingman loss.
    if M.message14 and not M.message15 and Valid(M.wing) and IsSelected(M.wing) then
        AudioMessage("tran0420.wav")
        M.message15 = true
    end
    if M.message6 and not Alive(M.target1) and not Alive(M.target2) and not M.message16 then
        AudioMessage("tran0421.wav")
        SucceedMission(GetTime() + 10, "tran04w1.des")
        M.message16 = true
    end
    if not M.message6 and (not Alive(M.target1) or not Alive(M.target2)) and not M.message16 then
        M.message16 = true
        FailMission(GetTime() + 5, "tran04l1.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- Stock LuaMission restores serialized handles/tables. Do not repeat Setup,
    -- briefings, scrap grants, or objective initialization on a saved-game load.
    M = state
end

-- Complete original native source, retained verbatim for cut-content recovery.
--[====[
#include "GameCommon.h"
#include <string.h>
#include "..\fun3d\PowerUp.h"
#include "..\fun3d\Recycler.h"
#include "..\fun3d\Factory.h"
#include "..\fun3d\Targeting.h"
#include "..\fun3d\ScriptUtils.h"

/*
	Tran04Mission
*/

#include "..\fun3d\AiMission.h"
#include "..\fun3d\AiProcess.h"

class Tran04Mission : public AiMission {
	DECLARE_RTIME(Tran04Mission)
public:
	Tran04Mission(void);
	~Tran04Mission();
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
				found1,
				found2,
				start_done,
				message1,
				message2,
				message3,
				message4,
				message5,
				message6,
				message7,
				message8,
				message9,
				message10,
				message11,
				message12,
				message13,
				message14,
				message15,
				message16,
				press7,
				attacked,
				jump_start,
				b_last;
		};
		bool b_array[22];
	};
	// floats
	union {
		struct {
				float
					repeat_time,
					camera_delay,
					f_last;
		};
		float f_array[2];
	};
	// handles
	union {
		struct {
			Handle
				player,
				target1,
				target2,
				recycler,
				muf,
				camera,
				wing,
				recy,
				h_last;
		};
		Handle h_array[8];
	};
	// path pointers
	union {
		struct {
			AiPath
				*p_I,
				*p_will,
				*p_never,
				*p_cut,
				*p_and,
				*p_paste,
				*p_variabls,
				*p_again,
				*p_last;
		};
		AiPath *p_array[8];
	};

	// integers
	union {
		struct {
			int 
				num_reps,
				on_point,
				i_last;
		};
		int i_array[2];
	};
				
};




void Tran04Mission::Setup(void)
{
	start_done=FALSE;
	found1=false;
	found2=false;
	press7=false;
	message1=false;
	message2=false;
	message3=false;
	message4=false;
	message5=false;
	message6=false;
	message7=false;
	message8=false;
	message9=false;
	message10=false;
	message11=false;
	message12=false;
	message13=false;
	message14=false;
	message15=false;
	message16=false;
	attacked=false;
	repeat_time=0.0f;
	num_reps=0;
}

// this is the handle thing brad made for me
void Tran04Mission::AddObject(Handle h)
{
	if (
		(GetTeamNum(h) == 1) &&
		(IsOdf(h, "avmuf"))
		)
	{
		found1 = true;
		muf= h;
	}
	if (
		(GetTeamNum(h) == 1) &&
		(IsOdf(h, "avfigh"))
		)
	{
		found2 = true;
		wing= h;
	}

}

void Tran04Mission::Execute(void)
{
	bool test = false;
	if (!start_done)
	{
		target1=GetHandle("avturr12_turrettank");
		target2=GetHandle("avturr-1_turrettank");
		recycler=GetHandle("avrecy-1_recycler");
		camera=GetHandle("apcamr-1_camerapod");
		player=GetHandle("player-1_hover");
		Recycler *myRecycler = (Recycler *) GameObjectHandle::GetObj(recycler);
		SetScrap(1,30);		
		AudioMessage("tran0401.wav");
		AudioMessage("tran0402.wav");
		AudioMessage("tran0424.wav");
		ClearObjectives();
		AddObjective("tran0401.otf",WHITE);
		start_done=true;
	}
	if ((!message1) && (IsAlive(recycler)) &&
		(GameObjectHandle::GetObj(recycler)->IsSelected()))
	{
		AudioMessage("tran0425.wav");
		message1=true;
	}
	if ((message1) &&
		(!message2) && (IsAlive(recycler))
		)
	{
		bool test=((Recycler *) GameObjectHandle::GetObj(recycler))->IsDeployed();
		if (test)
		{
			AudioMessage("tran0424.wav");  // select the recycler
			message2=true;
		}
		// added to skip muf stage
	}

	/* 
		press 7 to have the recyler build a factory
	*/

	if ((message2) && (IsAlive(recycler)) &&
		(GameObjectHandle::GetObj(recycler))->IsSelected()
		&& (!press7))
	{
		// was
		// AudioMessage("tran0403.wav");
		AudioMessage("tran0406.wav");
		press7=true;
		message6=true;
	}
	/*
	if ((message2) &&
		(!message3))
	{
		int money = ((Recycler *) GameObjectHandle::GetObj(recycler))->GetTeamList()->GetScrap();
		if ((money<30) && (found1))
		{
			// found1 is set but we don't test for it
			//muf=GetHandle("avmuf-1_factory");
			if (muf!=NULL)
			{
				AudioMessage("tran0404.wav");
				AudioMessage("tran0405.wav");
				message3=true;			
			}
			else
			{
				message2=false; // so you don't repeat this
				FailAll(10);  // you built the wrong thing
			}
		}
	}

	if ((message3)
		&& (!message4)
				&& (GameObjectHandle::GetObj(muf)->IsSelected()))
	{
		AudioMessage("tran0423.wav");
		message4=true;
	}

		if ((message4)
		&& (!message5))

	{ 
		test=((Factory *) GameObjectHandle::GetObj(muf))->IsDeployed();
		if (test)
		{
			AudioMessage("tran0405.wav");
			message5=true;
		}
	}
	 if ((message5) &&
		(!message6) &&
		(GameObjectHandle::GetObj(muf)->IsSelected()))
	{
		AudioMessage("tran0406.wav");
		message6=true;
	}
	*/
	if ((message6) &&
		(!message7) &&  (IsAlive(recycler)) &&
		(!GameObjectHandle::GetObj(recycler)->IsSelected())) // was muf selected
	{
		AudioMessage("tran0407.wav");
		camera_delay=Get_Time()+5.0f;
		message7=true;
	}
	if ((message7) 
		&& (!message8)
		&& (Get_Time()>camera_delay))
	{
		AudioMessage("tran0408.wav");
		camera_delay=99999.0f;
	}

	if ((message7) &&
		(!message8) &&
		(GetUserTarget() == camera))

	{
		AudioMessage("tran0409.wav");
		message8=true;
		camera_delay=Get_Time()+3.0f;		
	}
	if ((message8) &&
		(!message9) &&
		(Get_Time()>camera_delay) && (found2))
	{
		AudioMessage("tran0410.wav");
		// wing=GetHandle("avtank-1_wingman");
		message9=true;
		camera_delay=99999.0f;
	}
	if ((message8) && (!IsAlive(wing)) && (!message16))
	{
		FailMission(GetTime()+5.0f,"tran04l1.des");
		message16=true;

	}
 	if ((message9) &&
		(!message10) && (IsAlive(wing)) &&
		(GameObjectHandle::GetObj(wing)->IsSelected()))
	{
		AudioMessage("tran0411.wav");
		message10=true;
	}

	if ((message10) &&
		(!message11) &&		(IsAlive(wing)) &&
		(!GameObjectHandle::GetObj(wing)->IsSelected()) &&
		(camera_delay==99999.0f))
	{
		camera_delay=Get_Time()+10.0f;

	}
	if ((message10) &&
		(!message11) &&
		(camera_delay<Get_Time()))
	{
		AudioMessage("tran0412.wav");
		message11=true;
		camera_delay=99999.0f;
	}
	if ((message10) &&
		(!attacked) &&
		IsAlive(wing) &&
		(GameObjectHandle::GetObj(wing)->GetLastEnemyShot()>0))
	{
		AudioMessage("tran0413.wav");
		attacked=true;
	}


	if ((!IsAlive(target1))
		&& (!message12))
	{
		AudioMessage("tran0415.wav");
		if (IsAlive(target2))
		{
			GameObject *second_obj=GameObjectHandle::GetObj(target2);  
			second_obj->SetObjective(TRUE);
			second_obj->SetName("Drone 2");
		}
		message12=true;
	}
	if ((GameObjectHandle::GetObj(player)!=NULL)
		&& (GameObjectHandle::GetObj(target2)!=NULL))
	if ((message12) &&
		(GetDistance(player,target2)<300.0f) &&
		(!message13))
	{
		AudioMessage("tran0416.wav");
		message13=true;
		AudioMessage("tran0418.wav");
		message13=true;
	}
	if ((message13) &&
		(GetUserTarget() == target2)
			&& (!message14))
	{
		AudioMessage("tran0410.wav");
		message14=true;
	}
	if ((message14) &&
		(!message15) &&
		(GameObjectHandle::GetObj(wing)->IsSelected()))
	{
		AudioMessage("tran0420.wav");
		message15=true;
	}
	if ((message6) &&
		(!IsAlive(target1)) &&
		(!IsAlive(target2))
		&& (!message16))
	{
		AudioMessage("tran0421.wav");
		SucceedMission(GetTime()+10,"tran04w1.des");
		message16=true;
	}
	if	((!message6) &&
		((!IsAlive(target1)) || (!IsAlive(target2)))
			&& (!message16))		
	{
		message16=true;
		FailMission(GetTime()+5.0f,"tran04l1.des");
	}
}

IMPLEMENT_RTIME(Tran04Mission)

Tran04Mission::Tran04Mission(void)
{
}

Tran04Mission::~Tran04Mission()
{
}

void Tran04Mission::AddObject(GameObject *gameObj)
{
	AddObject(gameObj->GetHandle());
	AiMission::AddObject(gameObj);

}

bool Tran04Mission::Load(file fp)
{
	if (missionSave) {
		int h_count = &h_last - h_array;
		for (int i = 0; i < h_count; i++)
			h_array[i] = 0;
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

bool Tran04Mission::PostLoad(void)
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

bool Tran04Mission::Save(file fp)
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

void Tran04Mission::Update(void)
{
	AiMission::Update();
	Execute();
}
]====]
