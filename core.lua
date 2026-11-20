return function(S)
    local function deepcopy(value, seen)
        if type(value) ~= 'table' then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local copy = {}
        seen[value] = copy
        for k, v in pairs(value) do copy[deepcopy(k, seen)] = deepcopy(v, seen) end
        return copy
    end
    S.copy = deepcopy
    S.side = 'server'
    S.clientSource = 1
    S.resource = 'test_resource'
    S.state = {}
    S.exports = {}

    local function state() return S.state end
    function S.reset()
        S.state = {
            time = 0, tasks = {}, players = {}, events = {}, handlers = {},
            notices = {}, progress = {}, commands = {}, dbCalls = {},
            sqlReturns = {}, inventories = {}, stashes = {}, callbacks = {},
            contexts = {}, menus = {}, textUI = nil, openContext = nil,
            items = {}, jobs = {}, usableItems = {}, resourceStates = {},
            nativeReturns = {}, nextHandler = 0,
        }
        S.side, S.clientSource, S.resource = 'server', 1, 'test_resource'
        _G.source = nil
        _G.MockReturnValue = S.state.nativeReturns
        _G.MockEvents = S.state
        if S.resetInventory then S.resetInventory() end
        if S.resetESX then S.resetESX() end
        if S.resetLib then S.resetLib() end
        return S
    end
    function S.setSide(side, playerId)
        assert(side == 'server' or side == 'client', 'side must be server or client')
        S.side = side
        if playerId ~= nil then S.clientSource = playerId end
        if S.updateClientData then S.updateClientData() end
        return S
    end
    function S.setResource(name) S.resource = name; return S end
    function S.setReturn(key, value) state().nativeReturns[key] = value end
    function S.getReturn(key, default)
        local value = state().nativeReturns[key]
        return value == nil and default or value
    end
    function S.getEvents(name)
        local out = {}
        for _, event in ipairs(state().events) do
            if name == nil or event.name == name then out[#out + 1] = event end
        end
        return out
    end
    function S.advance(ms, maxSteps)
        assert(type(ms) == 'number' and ms >= 0, 'advance requires nonnegative milliseconds')
        local target, steps = state().time + ms, 0
        maxSteps = maxSteps or 10000
        while true do
            local index, due
            for i, task in ipairs(state().tasks) do
                if task.at <= target and (not due or task.at < due) then
                    index, due = i, task.at
                end
            end
            if not index then break end
            steps = steps + 1
            if steps > maxSteps then error('Scheduler step limit reached (possible infinite Wait(0) loop)') end
            state().time = due
            local task = table.remove(state().tasks, index)
            if task.co then
                local ok, delay = coroutine.resume(task.co)
                if not ok then error(debug.traceback(task.co, tostring(delay)), 2) end
                if coroutine.status(task.co) ~= 'dead' then
                    state().tasks[#state().tasks + 1] = { at = due + math.max(1, tonumber(delay) or 1), co = task.co }
                end
            else
                task.fn()
            end
        end
        state().time = target
    end
    local function scheduleThread(fn)
        local co = coroutine.create(fn)
        state().tasks[#state().tasks + 1] = { at = state().time, co = co }
    end
    Citizen = {}
    function Citizen.CreateThread(fn) scheduleThread(fn) end
    function Citizen.Wait(ms)
        if not coroutine.isyieldable() then error('Wait() requires a scheduled thread; use Sandbox.advance()') end
        return coroutine.yield(ms or 0)
    end
    function Citizen.SetTimeout(ms, fn)
        state().tasks[#state().tasks + 1] = { at = state().time + math.max(0, ms or 0), fn = fn }
    end
    function Citizen.InvokeNative(hash, ...) return S.getReturn('Native:' .. tostring(hash)) end
    function Citizen.Await(p) if p.rejected then error(p.error) end; return p.value end
    CreateThread, Wait, SetTimeout = Citizen.CreateThread, Citizen.Wait, Citizen.SetTimeout
    promise = {}
    function promise.new()
        local p = { resolved = false, rejected = false }
        function p:resolve(value) self.value, self.resolved = value, true end
        function p:reject(err) self.error, self.rejected = err, true end
        return p
    end
    function GetGameTimer() return state().time end

    local function invokeHandlers(name, side, sourceId, kind, ...)
        local arguments = table.pack(...)
        state().events[#state().events + 1] = { name = name, type = kind, source = sourceId, args = S.copy(arguments) }
        local oldSide, oldSource, oldClient = S.side, _G.source, S.clientSource
        S.side = side
        if side == 'client' and sourceId then S.clientSource = sourceId end
        _G.source = side == 'server' and sourceId or nil
        for _, entry in ipairs(state().handlers[name] or {}) do
            if entry.side == side then
                local ok, err = pcall(entry.fn, table.unpack(arguments, 1, arguments.n))
                if not ok then
                    S.side, _G.source, S.clientSource = oldSide, oldSource, oldClient
                    error(('Event %s (%s): %s'):format(name, side, err), 2)
                end
            end
        end
        S.side, _G.source, S.clientSource = oldSide, oldSource, oldClient
        if S.updateClientData then S.updateClientData() end
    end
    function AddEventHandler(name, fn)
        local handlers = state().handlers[name] or {}
        state().handlers[name] = handlers
        state().nextHandler = state().nextHandler + 1
        local entry = { id = state().nextHandler, fn = fn, side = S.side }
        handlers[#handlers + 1] = entry
        return entry
    end
    function RemoveEventHandler(entry)
        for _, handlers in pairs(state().handlers) do
            for i, registered in ipairs(handlers) do
                if registered == entry then table.remove(handlers, i); return true end
            end
        end
        return false
    end
    function RegisterNetEvent(name, fn) if fn then return AddEventHandler(name, fn) end end
    RegisterServerEvent = RegisterNetEvent
    function TriggerEvent(name, ...) invokeHandlers(name, S.side, S.side == 'client' and S.clientSource or _G.source, 'local', ...) end
    function TriggerServerEvent(name, ...) invokeHandlers(name, 'server', S.clientSource, 'server', ...) end
    function TriggerClientEvent(name, target, ...)
        if target == -1 then
            for id in pairs(state().players) do invokeHandlers(name, 'client', id, 'client', ...) end
        else invokeHandlers(name, 'client', target, 'client', ...) end
    end
    function GetTriggeredEvents() return state().events end
    function ClearTriggeredEvents() state().events = {} end
    function CancelEvent() state().cancelled = true end
    function WasEventCanceled() local value = state().cancelled or false; state().cancelled = false; return value end

    local registeredExports = {}
    function S.registerExport(resource, name, fn)
        registeredExports[resource] = registeredExports[resource] or {}
        registeredExports[resource][name] = fn
    end
    local proxies = {}
    _G.exports = setmetatable({}, {
        __index = function(_, resource)
            if proxies[resource] then return proxies[resource] end
            local proxy = {}
            setmetatable(proxy, { __index = function(_, name)
                local fn = registeredExports[resource] and registeredExports[resource][name]
                if not fn then error(('Unknown export %s:%s'):format(resource, name), 2) end
                return function(first, ...)
                    if first == proxy then return fn(...) end
                    return fn(first, ...)
                end
            end })
            proxies[resource] = proxy
            return proxy
        end,
        __call = function(_, name, fn)
            if type(fn) == 'function' then S.registerExport(S.resource, name, fn); return end
            local f = registeredExports[S.resource] and registeredExports[S.resource][name]
            return f
        end
    })
    function GetCurrentResourceName() return S.resource end
    function GetInvokingResource() return S.getReturn('InvokingResource') end
    function GetResourceState(name)
        return state().resourceStates[name] or ((name == 'es_extended' or name == 'ox_lib' or name == 'ox_inventory' or name == 'oxmysql') and 'started' or 'missing')
    end
    function GetConvar(name, fallback) return S.getReturn('Convar:' .. name, fallback) end
    function GetConvarInt(name, fallback) return tonumber(GetConvar(name, fallback)) or fallback end
    function SetConvar(name, value) S.setReturn('Convar:' .. name, value) end
    function GetPlayers()
        local players = {}
        for id in pairs(state().players) do players[#players + 1] = tostring(id) end
        table.sort(players)
        return players
    end
    function GetPlayerName(id) local p = state().players[tonumber(id)]; return p and p.name or nil end
    function GetPlayerIdentifiers(id)
        local p = state().players[tonumber(id)]
        return p and {p.identifier} or {}
    end
    function GetPlayerIdentifierByType(id, kind)
        for _, identifier in ipairs(GetPlayerIdentifiers(id)) do
            if identifier:sub(1, #kind + 1) == kind .. ':' then return identifier end
        end
    end
    function GetPlayerPing(id) return S.getReturn('GetPlayerPing:' .. id, 50) end
    function GetPlayerPed(id) return S.getReturn('GetPlayerPed:' .. id, 1000 + tonumber(id or 0)) end
    function PlayerPedId() return GetPlayerPed(S.clientSource) end
    function PlayerId() return S.clientSource end
    function GetEntityCoords(entity) return S.getReturn('GetEntityCoords:' .. tostring(entity), vector3(0, 0, 0)) end
    function DoesEntityExist(entity) return S.getReturn('DoesEntityExist:' .. tostring(entity), entity ~= nil and entity ~= 0) end
    function GetPlayerRoutingBucket(id) return S.getReturn('RoutingBucket:' .. id, 0) end
    function SetPlayerRoutingBucket(id, bucket) S.setReturn('RoutingBucket:' .. id, bucket) end
    function IsPlayerAceAllowed(id, permission) return S.getReturn(('Ace:%s:%s'):format(id, permission), false) end
    function RegisterCommand(name, fn, restricted) state().commands[name] = { fn = fn, restricted = restricted } end
    function ExecuteCommand(line)
        local name, rest = line:match('^(%S+)%s*(.*)$')
        local command = state().commands[name]
        if command then
            local args = {}
            for word in rest:gmatch('%S+') do args[#args + 1] = word end
            command.fn(0, args, line)
        end
    end
    function RegisterKeyMapping() end
    function vector2(x, y) return { x = x or 0, y = y or 0 } end
    function vector3(x, y, z)
        local v = { x = x or 0, y = y or 0, z = z or 0 }
        return setmetatable(v, {
            __add = function(a,b) return vector3(a.x+b.x,a.y+b.y,a.z+b.z) end,
            __sub = function(a,b) return vector3(a.x-b.x,a.y-b.y,a.z-b.z) end,
            __len = function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
        })
    end
    function vector4(x, y, z, w) return { x=x or 0, y=y or 0, z=z or 0, w=w or 0 } end
    vec2, vec3, vec4 = vector2, vector3, vector4
    function joaat(str)
        local hash = 0
        for i = 1, #str do
            hash = (hash + str:lower():byte(i)) & 0xffffffff
            hash = (hash + ((hash << 10) & 0xffffffff)) & 0xffffffff
            hash = hash ~ (hash >> 6)
        end
        hash = (hash + ((hash << 3) & 0xffffffff)) & 0xffffffff
        hash = hash ~ (hash >> 11)
        return (hash + ((hash << 15) & 0xffffffff)) & 0xffffffff
    end
    GetHashKey = joaat

    local function sql(method, query, params, cb)
        state().dbCalls[#state().dbCalls + 1] = { method = method, query = query, params = S.copy(params or {}) }
        local result = state().sqlReturns[query]
        if result == nil then result = S.getReturn('MySQL:' .. query) end
        if result == nil then result = ({query={}, single=nil, scalar=nil, update=0, insert=1, transaction=true})[method] end
        result = S.copy(result)
        if cb then cb(result) end
        return result
    end
    S.setSQL = function(query, result) state().sqlReturns[query] = result end
    MySQL = { Async = {}, Sync = {} }
    for _, method in ipairs({'query', 'single', 'scalar', 'update', 'insert', 'prepare', 'transaction'}) do
        local operation = {}
        operation.await = function(query, params) return sql(method, query, params) end
        setmetatable(operation, { __call = function(_, query, params, cb) return sql(method, query, params, cb) end })
        MySQL[method] = operation
    end
    MySQL.Async.fetchAll = function(query, params, cb) return sql('query', query, params, cb) end
    MySQL.Async.fetchScalar = function(query, params, cb) return sql('scalar', query, params, cb) end
    MySQL.Async.execute = function(query, params, cb) return sql('update', query, params, cb) end
    MySQL.Sync.fetchAll = function(query, params) return sql('query', query, params) end
    MySQL.Sync.fetchScalar = function(query, params) return sql('scalar', query, params) end
    MySQL.Sync.execute = function(query, params) return sql('update', query, params) end
    S.registerExport('oxmysql', 'query_async', function(query, params) return MySQL.query.await(query, params) end)
    S.registerExport('oxmysql', 'scalar_async', function(query, params) return MySQL.scalar.await(query, params) end)

    function S.loadResource(file, side, resourceName)
        local oldSide, oldResource = S.side, S.resource
        if side then S.setSide(side) end
        if resourceName then S.setResource(resourceName) end
        local ok, result = pcall(dofile, file)
        S.setSide(oldSide)
        S.setResource(oldResource)
        if not ok then error(result, 2) end
        return result
    end
end
