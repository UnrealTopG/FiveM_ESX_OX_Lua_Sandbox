-- Stateful ox_inventory mock (server and client common subset).
return function(S)
    local inventory = {}
    local function db() return S.state end
    local function validCount(count)
        return type(count) == 'number' and count > 0 and count == math.floor(count)
    end
    local function matches(actual, expected, strict)
        if expected == nil then return true end
        if type(actual) ~= 'table' or type(expected) ~= 'table' then return actual == expected end
        for k, value in pairs(expected) do
            if not matches(actual[k], value, strict) then return false end
        end
        if strict then
            for k in pairs(actual) do if expected[k] == nil then return false end end
        end
        return true
    end
    local function fullItems()
        return db().items
    end
    local function getInv(id)
        local key = tostring(id)
        local inv = db().inventories[key]
        if not inv and type(id) == 'number' and db().players[id] then
            inv = {id=id, label='Player '..id, slots=50, maxWeight=30000, items={}}
            db().inventories[key] = inv
        end
        return inv
    end
    local function weight(inv)
        local total = 0
        for _, slot in pairs(inv.items) do
            local item = fullItems()[slot.name]
            total = total + (item and item.weight or 0) * slot.count
        end
        return total
    end
    local function slotOf(inv, name, metadata, strict)
        for id = 1, inv.slots do
            local item = inv.items[id]
            if item and item.name == name and matches(item.metadata or {}, metadata, strict) then
                return id, item
            end
        end
    end
    local function emptySlot(inv)
        for i = 1, inv.slots do if not inv.items[i] then return i end end
    end
    local function countItem(inv, name, metadata)
        local count = 0
        for _, item in pairs(inv.items) do
            if item.name == name and matches(item.metadata or {}, metadata, false) then count = count + item.count end
        end
        return count
    end
    function S.resetInventory()
        db().items = {
            water={label='Water',weight=500,stack=true,close=true},
            bread={label='Bread',weight=200,stack=true,close=true},
            bandage={label='Bandage',weight=100,stack=true,close=true},
            lockpick={label='Lockpick',weight=100,stack=true,close=true},
            money={label='Cash',weight=0,stack=true,close=false},
            black_money={label='Dirty Money',weight=0,stack=true,close=false},
        }
    end
    function S.defineItem(name, def)
        assert(type(name)=='string' and type(def)=='table')
        db().items[name] = S.copy(def)
    end
    function S.createInventory(id, opts)
        opts = opts or {}
        local inv = { id=id, label=opts.label or tostring(id), slots=opts.slots or 50,
            maxWeight=opts.maxWeight or 30000, items={} }
        db().inventories[tostring(id)] = inv
        return inv
    end
    function inventory.GetInventory(id)
        local inv = getInv(id)
        if not inv then return nil end
        local snapshot = S.copy(inv)
        snapshot.weight = weight(inv)
        return snapshot
    end
    function inventory.Items(name)
        if name then return S.copy(fullItems()[name]) end
        return S.copy(fullItems())
    end
    function inventory.GetInventoryItems(id)
        local inv = getInv(id)
        return inv and S.copy(inv.items) or nil
    end
    function inventory.GetItemCount(id, name, metadata)
        local inv = getInv(id)
        return inv and countItem(inv, name, metadata) or 0
    end
    function inventory.GetItem(id, name, metadata, returnsCount)
        local inv = getInv(id)
        if not inv then return returnsCount and 0 or nil end
        if returnsCount then return countItem(inv, name, metadata) end
        local slot, item = slotOf(inv, name, metadata, false)
        if not item then return nil end
        local result = S.copy(item)
        result.count = countItem(inv, name, metadata)
        result.slot = slot
        return result
    end
    function inventory.GetSlot(id, slot)
        local inv = getInv(id)
        return inv and S.copy(inv.items[slot]) or nil
    end
    function inventory.GetSlotWithItem(id, name, metadata, strict)
        local inv = getInv(id)
        if not inv then return nil end
        local _, item = slotOf(inv, name, metadata, strict)
        return S.copy(item)
    end
    function inventory.GetSlotIdWithItem(id, name, metadata, strict)
        local inv = getInv(id)
        if not inv then return nil end
        return slotOf(inv, name, metadata, strict)
    end
    function inventory.GetSlotIdsWithItem(id, name, metadata, strict)
        local inv, ids = getInv(id), {}
        if not inv then return ids end
        for slot, item in pairs(inv.items) do
            if item.name==name and matches(item.metadata or {},metadata,strict) then ids[#ids+1]=slot end
        end
        table.sort(ids)
        return ids
    end
    function inventory.GetInventoryWeight(id)
        local inv = getInv(id)
        return inv and weight(inv) or 0
    end
    function inventory.CanCarryItem(id, name, count, metadata)
        local inv, item = getInv(id), fullItems()[name]
        if not inv or not item or not validCount(count) then return false end
        if weight(inv) + (item.weight or 0) * count > inv.maxWeight then return false end
        if item.stack ~= false and slotOf(inv,name,metadata or {},true) then return true end
        return emptySlot(inv) ~= nil
    end
    local function syncAccounts(id, name)
        if S.syncInventoryAccount and type(id) == 'number' then S.syncInventoryAccount(id, name) end
    end
    function inventory.AddItem(id, name, count, metadata, slot, cb)
        count = count or 1
        local inv, def = getInv(id), fullItems()[name]
        if not inv then if cb then cb(false,'invalid_inventory') end; return false,'invalid_inventory' end
        if not def then if cb then cb(false,'invalid_item') end; return false,'invalid_item' end
        if not validCount(count) then if cb then cb(false,'invalid_count') end; return false,'invalid_count' end
        metadata = S.copy(metadata or {})
        if weight(inv) + (def.weight or 0) * count > inv.maxWeight then
            if cb then cb(false,'inventory_full') end
            return false,'inventory_full'
        end
        if not inventory.CanCarryItem(id,name,count,metadata) and not (slot and inv.items[slot] and inv.items[slot].name==name and def.stack~=false and matches(inv.items[slot].metadata,metadata,true)) then
            if cb then cb(false,'inventory_full') end
            return false,'inventory_full'
        end
        local target
        if slot then
            if not validCount(slot) or slot > inv.slots then return false,'invalid_slot' end
            local existing = inv.items[slot]
            if existing and (existing.name ~= name or def.stack == false or not matches(existing.metadata, metadata, true)) then return false,'slot_occupied' end
            target = slot
        else
            if def.stack ~= false then target = slotOf(inv,name,metadata,true) end
            target = target or emptySlot(inv)
        end
        if not target then return false,'inventory_full' end
        if inv.items[target] then inv.items[target].count = inv.items[target].count + count
        else inv.items[target] = {name=name,label=def.label or name,count=count,weight=def.weight or 0,metadata=metadata,slot=target} end
        syncAccounts(id,name)
        if cb then cb(true, S.copy(inv.items[target])) end
        return true, S.copy(inv.items[target])
    end
    function inventory.RemoveItem(id, name, count, metadata, slot, ignoreTotal, strict)
        count = count or 1
        local inv = getInv(id)
        if not inv then return false,'invalid_inventory' end
        if not validCount(count) then return false,'invalid_count' end
        local ids = slot and {slot} or inventory.GetSlotIdsWithItem(id,name,metadata,strict)
        local available = 0
        for _, index in ipairs(ids) do
            local item = inv.items[index]
            if item and item.name == name and matches(item.metadata,metadata,strict) then
                available = available + item.count
            end
        end
        -- Never mutate a subset of slots if the complete removal cannot succeed.
        if available < count then return false,'not_enough_items' end
        local remaining = count
        for _, index in ipairs(ids) do
            local item = inv.items[index]
            if item and item.name == name and matches(item.metadata,metadata,strict) then
                local removed = math.min(item.count,remaining)
                item.count = item.count - removed
                remaining = remaining - removed
                if item.count == 0 then inv.items[index] = nil end
                if remaining == 0 then break end
            end
        end
        if remaining ~= 0 then return false,'not_enough_items' end
        syncAccounts(id,name)
        return true
    end
    function inventory.Search(id, search, names, metadata)
        -- Client signature: Search('count'|'slots', item[, metadata])
        if id == 'count' or id == 'slots' then
            local mode, item, meta = id, search, names
            id, search, names, metadata = S.clientSource, mode, item, meta
        end
        local inv = getInv(id)
        if search ~= 'count' and search ~= 'slots' then error('Search expects count or slots') end
        if not inv then return search == 'count' and 0 or {} end
        local function searchOne(name)
            if search == 'count' then return countItem(inv,name,metadata) end
            local result = {}
            for _, slot in pairs(inv.items) do
                if slot.name==name and matches(slot.metadata,metadata,false) then result[#result+1]=S.copy(slot) end
            end
            table.sort(result,function(a,b) return a.slot<b.slot end)
            return result
        end
        if type(names) == 'string' then return searchOne(names) end
        local found = {}
        for _, name in ipairs(names or {}) do found[name] = searchOne(name) end
        return found
    end
    function inventory.SetMetadata(id, slot, metadata)
        local inv = getInv(id)
        if not inv or not inv.items[slot] then return false end
        inv.items[slot].metadata = S.copy(metadata or {})
        return true
    end
    function inventory.SetDurability(id, slot, durability)
        local inv = getInv(id)
        if not inv or not inv.items[slot] then return false end
        inv.items[slot].metadata.durability = durability
        return true
    end
    function inventory.SetMaxWeight(id, maxWeight)
        local inv = getInv(id)
        if not inv or type(maxWeight)~='number' or maxWeight < 0 then return false end
        inv.maxWeight = maxWeight
        return true
    end
    function inventory.ClearInventory(id, keep)
        local inv = getInv(id)
        if not inv then return false end
        if not keep then inv.items = {}
        else
            for slot,item in pairs(inv.items) do if not keep[item.name] then inv.items[slot] = nil end end
        end
        for _, name in ipairs({'money','black_money'}) do syncAccounts(id,name) end
        return true
    end
    function inventory.RegisterStash(id, label, slots, maxWeight, owner)
        if db().stashes[id] then return false end
        db().stashes[id] = {label=label,owner=owner}
        S.createInventory(id,{label=label,slots=slots,maxWeight=maxWeight})
        return true
    end
    S.inventory = inventory
    for name,fn in pairs(inventory) do S.registerExport('ox_inventory',name,fn) end
end
