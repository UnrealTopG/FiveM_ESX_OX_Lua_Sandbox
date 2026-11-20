-- ox_lib mock: deterministic synchronous callbacks and recorded UI interactions.
return function(S)
    lib = {callback={}, cache={}, math={}, string={}, table={}, zones={}}
    local function db() return S.state end
    function S.resetLib()
        db().callbacks = {server={}, client={}}
        db().contexts = {}
        db().menus = {}
        db().notices = {}
        db().progress = {}
        db().textUI = nil
        db().openContext = nil
        lib.cache = {serverId=S.clientSource, ped=GetPlayerPed(S.clientSource), playerId=S.clientSource}
        db().progressActive = false
    end
    function lib.callback.register(name, fn)
        assert(type(name)=='string' and type(fn)=='function')
        db().callbacks[S.side][name] = fn
    end
    local function call(name, ...)
        local destination = S.side=='client' and 'server' or 'client'
        local fn = db().callbacks[destination][name]
        if not fn then error(('Unknown ox_lib %s callback: %s'):format(destination,tostring(name)),3) end
        if destination=='server' then return fn(S.clientSource,...) end
        return fn(...)
    end
    function lib.callback.await(name, delayOrSource, ...)
        -- delayOrSource is false/number on the client; target source on the server.
        return call(name,...)
    end
    setmetatable(lib.callback,{__call=function(_,name,delayOrSource,cb,...)
        assert(type(cb)=='function','lib.callback requires callback function')
        cb(call(name,...))
    end})
    function lib.notify(options)
        options = type(options)=='table' and S.copy(options) or {description=tostring(options)}
        options.target = options.target or S.clientSource
        db().notices[#db().notices+1] = options
        return true
    end
    local function progress(name, opts)
        db().progressActive=true
        db().progress[#db().progress+1] = {kind=name,options=S.copy(opts)}
        local result=S.getReturn('lib:'..name,true)
        db().progressActive=false
        return result
    end
    function lib.progressBar(opts) return progress('progressBar',opts) end
    function lib.progressCircle(opts) return progress('progressCircle',opts) end
    function lib.cancelProgress() db().progressActive=false end
    function lib.progressActive() return db().progressActive end
    function lib.skillCheck(difficulty,inputs)
        return S.getReturn('lib:skillCheck',true)
    end
    function lib.inputDialog(title,rows,options)
        db().lastInputDialog={title=title,rows=S.copy(rows),options=S.copy(options)}
        return S.copy(S.getReturn('lib:inputDialog'))
    end
    function lib.alertDialog(options)
        db().lastAlertDialog=S.copy(options)
        return S.getReturn('lib:alertDialog','confirm')
    end
    function lib.registerContext(context)
        if context.id then db().contexts[context.id]=S.copy(context)
        else for _,entry in ipairs(context) do db().contexts[entry.id]=S.copy(entry) end end
    end
    function lib.showContext(id)
        assert(db().contexts[id],'Unknown context: '..tostring(id))
        db().openContext=id
    end
    function lib.hideContext() db().openContext=nil end
    function lib.getOpenContextMenu() return db().openContext end
    function lib.registerMenu(options,cb) db().menus[options.id]={options=S.copy(options),onSelect=cb} end
    function lib.showMenu(id) assert(db().menus[id],'Unknown menu'); db().openMenu=id end
    function lib.hideMenu() db().openMenu=nil end
    function lib.registerRadial(menus) db().radials=db().radials or {}; db().radials[menus.id]=S.copy(menus) end
    function lib.addRadialItem(item)
        db().radialItems=db().radialItems or {}
        if item[1] then for _,entry in ipairs(item) do db().radialItems[entry.id]=S.copy(entry) end
        else db().radialItems[item.id]=S.copy(item) end
    end
    function lib.removeRadialItem(id) if db().radialItems then db().radialItems[id]=nil end end
    function lib.showTextUI(text,options) db().textUI={text=text,options=S.copy(options)} end
    function lib.hideTextUI() db().textUI=nil end
    function lib.isTextUIOpen() return db().textUI~=nil,db().textUI and db().textUI.text end
    function lib.addCommand(name,options,cb)
        RegisterCommand(name,function(source,args,raw)
            cb(source,args,raw)
        end,options and options.restricted)
    end
    function lib.math.round(num,decimals)
        local base=10^(decimals or 0)
        return math.floor(num*base+0.5)/base
    end
    function lib.string.trim(value) return (value:gsub('^%s*(.-)%s*$','%1')) end
    function lib.table.deepclone(value) return S.copy(value) end
    function lib.checkDependency(resource,minVersion)
        return GetResourceState(resource)=='started'
    end
    lib.print={}
    for _,level in ipairs({'info','warn','error','debug','verbose'}) do
        lib.print[level] = function(...) end
    end
    lib.zones.sphere=function(options)
        local zone = S.copy(options)
        zone.remove=function(self) self.removed=true end
        return zone
    end
    lib.zones.box=lib.zones.sphere
    lib.zones.poly=lib.zones.sphere
    S.registerExport('ox_lib','getLocale',function() return 'en' end)
end
