-- Nonblocking, scene-local clock for the Operation Livewire prototype.
-- Lua 5.1; no engine or EXU dependency. The mission owns callbacks/resources.
local SXDirector = {}
SXDirector.__index = SXDirector

function SXDirector.New(scenes, hooks)
    return setmetatable({ scenes = scenes, hooks = hooks or {}, mode = "idle",
        index = 0, elapsed = 0, nextCue = 1 }, SXDirector)
end

function SXDirector:_Call(name, ...)
    local fn = self.hooks[name]
    if type(fn) ~= "function" then return true end
    local ok, result = pcall(fn, ...)
    if not ok then
        self.error = tostring(result)
        return false
    end
    return result ~= false
end

function SXDirector:Finish(reason)
    if self.mode ~= "tour" then return end
    local scene = self.scenes[self.index]
    self.mode = "freeplay" -- Reentrant callbacks cannot fire more cues.
    self:_Call("leave", scene, reason)
    self:_Call("finish", reason)
end

function SXDirector:Start(id)
    local index = 1
    if id then
        index = nil
        for i, scene in ipairs(self.scenes) do
            if scene.id == id then index = i; break end
        end
        if not index then return false end
    end
    self:Finish("replay")
    self.mode, self.index, self.elapsed, self.nextCue = "tour", index, 0, 1
    self.error = nil
    if not self:_Call("enter", self.scenes[index]) then
        self:Finish("setup-error")
        return false
    end
    return true
end

function SXDirector:Update(dt)
    if self.mode ~= "tour" then return end
    if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then return end
    -- Bound the loop by the authored scene count, even after a frame hitch.
    local remaining = dt
    for _ = 1, #self.scenes do
        local scene = self.scenes[self.index]
        local step = math.min(remaining, scene.duration - self.elapsed)
        self.elapsed = self.elapsed + step
        remaining = remaining - step
        while self.mode == "tour" and scene.cues[self.nextCue]
            and scene.cues[self.nextCue].at <= self.elapsed do
            local cue = scene.cues[self.nextCue]
            self.nextCue = self.nextCue + 1 -- Once, including reentrant callbacks.
            if not self:_Call("cue", scene, cue) then self:Finish("cue-error") end
        end
        if self.mode ~= "tour" then return end
        if not self:_Call("tick", scene, self.elapsed, step) then
            self:Finish("camera-error")
            return
        end
        if self.elapsed < scene.duration then return end
        if self.index == #self.scenes then self:Finish("complete"); return end
        if not self:_Call("leave", scene, "complete") then
            self:Finish("cleanup-error")
            return
        end
        self.index, self.elapsed, self.nextCue = self.index + 1, 0, 1
        if not self:_Call("enter", self.scenes[self.index]) then
            self:Finish("setup-error")
            return
        end
        if remaining <= 0 then return end
    end
end

function SXDirector:Snapshot()
    return { mode = self.mode, scene = self.scenes[self.index] and
        self.scenes[self.index].id or "", elapsed = self.elapsed,
        nextCue = self.nextCue, error = self.error }
end

return SXDirector
