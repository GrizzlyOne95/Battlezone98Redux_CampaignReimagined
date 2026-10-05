-- Behavioral model of the GOG Redux BZRNet peer envelope. Source/capture:
-- OpenShim reverse_engineering/bzrnet_protocol_capture_20260321.md;
-- GOG FUN_0075beb0 / FUN_0075d800, executable SHA-256
-- 8d71f56c1314e69a8ad38f4eeaf20a8ff825965a84cf196e5f77ea4cc3377413.
-- This is NOT the Lua Send serializer, object protocol, or real UDP. Callers
-- select reliability: the current Redux Lua Send binding is not yet traced.
-- Retry timing and initial sequence are scenario inputs, not engine claims.
local Sim = {}
local function be(value, bytes)
    local out = {}
    for i = bytes, 1, -1 do
        out[i] = string.char(value % 256)
        value = math.floor(value / 256)
    end
    return table.concat(out)
end
function Sim.New(receive, options)
    options = options or {}
    local self = { links = {}, queue = {}, now = 0, delivered = 0, rejected = 0,
        retries = 0, retry = options.retry or 0.25, latency = options.latency or 0 }
    local function link(from, to)
        local key = from .. ":" .. to
        if not self.links[key] then
            self.links[key] = { next = options.sequence or 1,
                expected = options.sequence or 1, pending = {} }
        end
        return self.links[key]
    end
    local function enqueue(packet)
        local datagram = {}
        for k, v in pairs(packet) do datagram[k] = v end
        datagram.due = self.now + self.latency
        self.queue[#self.queue + 1] = datagram
    end
    function self:Send(from, to, kind, args, reliable)
        local direction, reverse = link(from, to), link(to, from)
        local values = {}
        for i, value in ipairs(args) do
            assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean",
                "fixture must serialize primitives, never share peer Lua tables")
            values[i] = value
        end
        local packet = { from = from, to = to, kind = kind, args = values,
            reliable = reliable, seq = direction.next, ack = reverse.expected }
        if reliable then
            direction.next = direction.next + 1
            direction.pending[packet.seq] = { packet = packet, retryAt = self.now + self.retry }
        end
        enqueue(packet)
    end
    function self:Header(packet)
        local flags = packet.ackOnly and 0x40 or (packet.reliable and 0xC0 or 0x40)
        return string.char(flags, packet.ackOnly and 6 or 0) ..
            be(math.floor(self.now * 1000), 8) .. be(packet.seq, 4) .. be(packet.ack, 4)
    end
    function self:Step(time, reverseOrder, drop)
        self.now = time
        for _, direction in pairs(self.links) do
            local sequences = {}
            for seq in pairs(direction.pending) do sequences[#sequences + 1] = seq end
            table.sort(sequences)
            for _, seq in ipairs(sequences) do
                local pending = direction.pending[seq]
                if pending.retryAt <= time then
                    pending.retryAt = time + self.retry
                    self.retries = self.retries + 1
                    enqueue(pending.packet)
                end
            end
        end
        local batch = self.queue
        self.queue = {}
        if reverseOrder then
            local reversed = {}
            for i = #batch, 1, -1 do reversed[#reversed + 1] = batch[i] end
            batch = reversed
        end
        for _, packet in ipairs(batch) do
            if packet.due > time then
                self.queue[#self.queue + 1] = packet
            elseif not (drop and drop(packet)) then
                assert(#self:Header(packet) == 18)
                local incoming, outgoing = link(packet.from, packet.to), link(packet.to, packet.from)
                for seq in pairs(outgoing.pending) do
                    if seq < packet.ack then outgoing.pending[seq] = nil end
                end
                if not packet.ackOnly then
                    local accepted = packet.seq == incoming.expected
                    if packet.reliable or not accepted then
                        if accepted then incoming.expected = incoming.expected + 1 end
                        enqueue({ from = packet.to, to = packet.from, ackOnly = true,
                            seq = outgoing.next, ack = incoming.expected })
                    end
                    if accepted then
                        self.delivered = self.delivered + 1
                        receive(packet)
                    else
                        self.rejected = self.rejected + 1
                    end
                end
            end
        end
    end
    return self
end
return Sim
