-- Example FiveM resource logic. Run through tests/example_resource_test.lua.
if Sandbox.side == 'server' then
    lib.callback.register('demo:getWater', function(source)
        return exports.ox_inventory:Search(source, 'count', 'water')
    end)
    RegisterNetEvent('demo:buyWater', function()
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer or not xPlayer.removeAccountMoney('bank', 20) then return end
        local success = exports.ox_inventory:AddItem(source, 'water', 1)
        if not success then
            xPlayer.addAccountMoney('bank', 20) -- compensate a failed purchase
            return
        end
        TriggerClientEvent('demo:purchased', source, 'water')
    end)
else
    RegisterNetEvent('demo:purchased', function(item)
        lib.notify({title='Purchase complete', description='Received '..item, type='success'})
    end)
end
