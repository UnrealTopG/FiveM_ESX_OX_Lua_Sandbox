-- FiveM ESX/OX Lua Sandbox. Runs trusted FiveM Lua logic without a FiveM server.
local path = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') or './'
local Sandbox = { version = '0.1.0', path = path }
_G.Sandbox = Sandbox

dofile(path .. 'core.lua')(Sandbox)
dofile(path .. 'ox_inventory.lua')(Sandbox)
dofile(path .. 'esx.lua')(Sandbox)
dofile(path .. 'ox_lib.lua')(Sandbox)
Sandbox.reset()
return Sandbox
