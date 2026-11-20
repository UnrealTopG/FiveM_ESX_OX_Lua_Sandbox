local root = debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
local S = dofile(root..'../init.lua')
S.createPlayer(11,{accounts={money=0,bank=100}})
local resource = root..'../examples/basic_resource.lua'
S.loadResource(resource,'server','demo')
S.loadResource(resource,'client','demo')
S.setSide('client',11)
assert(lib.callback.await('demo:getWater',false)==0)
TriggerServerEvent('demo:buyWater')
assert(lib.callback.await('demo:getWater',false)==1)
assert(ESX.GetPlayerFromId(11).getAccount('bank').money==80)
assert(S.state.notices[#S.state.notices].title=='Purchase complete')
print('[PASS] end-to-end example resource')
