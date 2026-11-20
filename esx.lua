-- ESX Legacy mock with ox_inventory-backed player inventory and cash accounts.
return function(S)
    ESX = { Players = {}, Jobs = {}, Items = {}, PlayerData = {}, ServerCallbacks = {}, UsableItems = {}, Math = {} }
    local function db() return S.state end
    local function validAmount(amount)
        return type(amount)=='number' and amount>=0 and amount==math.floor(amount) and amount<math.huge
    end
    local function getPlayer(id) return db().players[tonumber(id)] end
    local function makeJob(name, grade)
        local definition = db().jobs[name]
        local level = definition and definition.grades[tostring(grade or 0)]
        if not level then return nil end
        local rank = tonumber(grade) or 0
        return {name=name,label=definition.label,grade=rank,grade_name=level.name,
            grade_label=level.label or level.name,grade_salary=level.salary or 0,
            skin_male={},skin_female={}}
    end
    function S.defineJob(name, data) db().jobs[name] = S.copy(data); ESX.Jobs = db().jobs end
    function S.resetESX()
        db().jobs = {
            unemployed = {label='Unemployed', grades={['0']={name='unemployed',label='Unemployed',salary=0}}},
            police = {label='Police', grades={['0']={name='recruit',label='Recruit',salary=50},
                ['1']={name='officer',label='Officer',salary=75},['2']={name='sergeant',label='Sergeant',salary=100},
                ['3']={name='boss',label='Chief',salary=150}}},
            ambulance = {label='EMS', grades={['0']={name='trainee',label='Trainee',salary=50},
                ['1']={name='doctor',label='Doctor',salary=100}}},
        }
        ESX.Players, ESX.Jobs, ESX.Items, ESX.ServerCallbacks, ESX.UsableItems =
            db().players, db().jobs, db().items, {}, db().usableItems
        S.updateClientData()
        S.setSide('server')
        AddEventHandler('esx:getSharedObject', function(cb) if cb then cb(ESX) end end)
        S.setSide('client')
        AddEventHandler('esx:getSharedObject', function(cb) if cb then cb(ESX) end end)
        S.setSide('server')
    end
    function S.updateClientData()
        local p = getPlayer(S.clientSource)
        ESX.PlayerData = p and S.copy({identifier=p.identifier,job=p.job,accounts=p.accounts,
            inventory=S.inventory.GetInventoryItems(p.source), name=p.name,
            metadata=p.metadata,coords=p.coords,group=p.group}) or {}
        ESX.PlayerLoaded = p ~= nil
        if lib and lib.cache then
            lib.cache.serverId, lib.cache.playerId = S.clientSource, S.clientSource
            lib.cache.ped = GetPlayerPed(S.clientSource)
        end
    end
    function S.syncInventoryAccount(id, itemName)
        if itemName ~= 'money' and itemName ~= 'black_money' then return end
        local p = getPlayer(id)
        if p and p.accounts[itemName] then
            p.accounts[itemName].money = S.inventory.GetItemCount(id, itemName)
        end
        if id==S.clientSource then S.updateClientData() end
    end
    local function makePlayer(id, options)
        options = options or {}
        assert(type(id)=='number' and id>=1 and id==math.floor(id),'player id must be positive integer')
        assert(not getPlayer(id),'player already exists')
        local accounts = options.accounts or {}
        local player = {
            source=id, identifier=options.identifier or ('license:mock%06d'):format(id),
            name=options.name or ('Mock Player '..id), group=options.group or 'user',
            job=makeJob('unemployed',0), metadata=S.copy(options.metadata or {}),
            coords=S.copy(options.coords or vector3(0,0,0)),
            variables={}, accounts={
                money={name='money',label='Cash',money=0},
                bank={name='bank',label='Bank',money=accounts.bank or 5000},
                black_money={name='black_money',label='Dirty Money',money=0},
            }
        }
        db().players[id] = player
        S.createInventory(id, {slots=options.slots or 50, maxWeight=options.maxWeight or 30000})
        for _, itemName in ipairs({'money','black_money'}) do
            local initial = accounts[itemName]
            if initial == nil then initial = itemName=='money' and 500 or 0 end
            assert(validAmount(initial),'invalid initial money amount')
            if initial>0 then
                local ok,err = S.inventory.AddItem(id,itemName,initial)
                assert(ok,err)
            end
        end
        if options.job then
            local jobName = type(options.job)=='table' and options.job.name or options.job
            local grade = type(options.job)=='table' and options.job.grade or options.grade or 0
            player.job = assert(makeJob(jobName,grade),'invalid initial job')
        end
        if options.inventory then
            for _, item in ipairs(options.inventory) do
                local ok,err = S.inventory.AddItem(id,item.name,item.count or 1,item.metadata,item.slot)
                assert(ok,err)
            end
        end
        function player.getIdentifier() return player.identifier end
        function player.getName() return player.name end
        function player.setName(name) player.name=name; S.updateClientData() end
        function player.getGroup() return player.group end
        function player.setGroup(group) player.group=group; S.updateClientData() end
        function player.getJob() return S.copy(player.job) end
        function player.setJob(name, grade)
            local job = makeJob(name,grade)
            if not job then return false end
            player.job=job
            S.updateClientData()
            return true
        end
        function player.getAccount(name) return S.copy(player.accounts[name]) end
        function player.getAccounts() return S.copy(player.accounts) end
        function player.setAccountMoney(name, amount, reason)
            if not player.accounts[name] or not validAmount(amount) then return false end
            if name=='money' or name=='black_money' then
                local current=S.inventory.GetItemCount(id,name)
                if amount>current then
                    return S.inventory.AddItem(id,name,amount-current)
                elseif amount<current then
                    return S.inventory.RemoveItem(id,name,current-amount)
                end
            else player.accounts[name].money=amount end
            S.updateClientData()
            return true
        end
        function player.addAccountMoney(name, amount, reason)
            if not player.accounts[name] or not validAmount(amount) then return false end
            return player.setAccountMoney(name, player.accounts[name].money+amount, reason)
        end
        function player.removeAccountMoney(name, amount, reason)
            if not player.accounts[name] or not validAmount(amount) or player.accounts[name].money<amount then return false end
            return player.setAccountMoney(name, player.accounts[name].money-amount, reason)
        end
        function player.getMoney() return player.accounts.money.money end
        function player.addMoney(amount, reason) return player.addAccountMoney('money', amount, reason) end
        function player.removeMoney(amount, reason) return player.removeAccountMoney('money', amount, reason) end
        function player.setMoney(amount, reason) return player.setAccountMoney('money', amount, reason) end
        function player.getInventory() return S.inventory.GetInventoryItems(id) end
        function player.getInventoryItem(name)
            local def = db().items[name]
            if not def then return nil end
            return {name=name,label=def.label or name,count=S.inventory.GetItemCount(id,name),
                weight=def.weight or 0,usable=def.close~=false,rare=false,canRemove=true}
        end
        function player.addInventoryItem(name, count, metadata, slot)
            return S.inventory.AddItem(id,name,count or 1,metadata,slot)
        end
        function player.removeInventoryItem(name, count, metadata, slot)
            return S.inventory.RemoveItem(id,name,count or 1,metadata,slot)
        end
        function player.setInventoryItem(name, count)
            if not validAmount(count) then return false end
            local current=S.inventory.GetItemCount(id,name)
            if count>current then return S.inventory.AddItem(id,name,count-current)
            elseif count<current then return S.inventory.RemoveItem(id,name,current-count) end
            return true
        end
        function player.canCarryItem(name, count) return S.inventory.CanCarryItem(id,name,count) end
        function player.hasItem(name, metadata)
            return S.inventory.GetItemCount(id,name,metadata)>0
        end
        function player.getMeta(key) return key and S.copy(player.metadata[key]) or S.copy(player.metadata) end
        function player.setMeta(key, value) player.metadata[key] = S.copy(value); S.updateClientData() end
        function player.clearMeta(key) player.metadata[key] = nil; S.updateClientData() end
        function player.getCoords(asVector) return S.copy(player.coords) end
        function player.setCoords(coords) player.coords = S.copy(coords); S.updateClientData() end
        function player.get(key) return S.copy(player.variables[key]) end
        function player.set(key, value) player.variables[key]=S.copy(value) end
        function player.triggerEvent(name, ...) TriggerClientEvent(name,id,...) end
        function player.showNotification(message, notifyType)
            TriggerClientEvent('esx:showNotification',id,message,notifyType)
            db().notices[#db().notices+1]={target=id,description=message,type=notifyType or 'inform'}
        end
        function player.kick(reason) db().players[id]=nil; db().inventories[tostring(id)] = nil end
        if id==S.clientSource then S.updateClientData() end
        return player
    end
    S.createPlayer = makePlayer
    function ESX.GetPlayerFromId(id) return getPlayer(id) end
    function ESX.GetPlayerFromIdentifier(identifier)
        for _,p in pairs(db().players) do if p.identifier==identifier then return p end end
    end
    function ESX.GetPlayers()
        local result={}
        for id in pairs(db().players) do result[#result+1]=id end
        table.sort(result)
        return result
    end
    function ESX.GetExtendedPlayers(key,value)
        local result={}
        for _,id in ipairs(ESX.GetPlayers()) do
            local p=getPlayer(id)
            if not key or (key=='job' and p.job.name==value) or (key=='group' and p.group==value) then
                result[#result+1]=p
            end
        end
        return result
    end
    function ESX.GetPlayerData() S.updateClientData(); return S.copy(ESX.PlayerData) end
    function ESX.GetJobs() return S.copy(db().jobs) end
    function ESX.GetItems() return S.copy(db().items) end
    function ESX.GetItemLabel(name) return db().items[name] and db().items[name].label or name end
    function ESX.RegisterServerCallback(name, fn) ESX.ServerCallbacks[name]=fn end
    local function runCallback(name, ...)
        local fn=ESX.ServerCallbacks[name]
        assert(fn,'Unknown ESX server callback: '..tostring(name))
        local called, values = false, nil
        fn(S.clientSource,function(...) called=true; values=table.pack(...) end,...)
        assert(called,'ESX callback did not invoke cb() synchronously: '..name)
        return table.unpack(values,1,values.n)
    end
    function ESX.TriggerServerCallback(name, cb, ...) cb(runCallback(name,...)) end
    function ESX.AwaitServerCallback(name, ...) return runCallback(name,...) end
    function ESX.RegisterUsableItem(name, fn) db().usableItems[name]=fn end
    function ESX.GetUsableItems() return db().usableItems end
    function S.useItem(id, name, ...)
        if S.inventory.GetItemCount(id,name)<1 then return false,'item_missing' end
        local handler=db().usableItems[name]
        if not handler then return false,'not_usable' end
        handler(id,name,...)
        return true
    end
    function ESX.ShowNotification(message, notifyType)
        db().notices[#db().notices+1] = {target=S.clientSource,description=message,type=notifyType or 'inform'}
    end
    function ESX.ShowHelpNotification(message) ESX.ShowNotification(message,'inform') end
    function ESX.Math.Round(value,places)
        local scale=10^(places or 0)
        return math.floor(value*scale+0.5)/scale
    end
    function ESX.Math.Trim(text) return (text:gsub('^%s*(.-)%s*$','%1')) end
    S.registerExport('es_extended','getSharedObject',function() return ESX end)
end
