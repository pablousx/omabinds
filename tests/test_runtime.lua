-- Real Lua with a small Hyprland API double. No input synthesis.
local bound, calls, removed = {}, 0, {}
hl = {dsp={exec_cmd=function(cmd) return function() calls=calls+1 end end}}
function hl.bind(keys, action, opts)
  opts=opts or {}
  local b={key=keys:match('[^+ ]+$'),keycode=0,modmask=keys:find('SUPER') and 64 or 0,
    submap='',description=opts.description or '',enabled=true,release=opts.release or false,
    repeating=opts.repeating or false,locked=opts.locked or false}
  function b:is_enabled() assert(not removed[self], 'dead handle'); return self.enabled end
  function b:set_enabled(v) self.enabled=v end
  function b:remove() self.enabled=false end
  b.action=action; bound[#bound+1]=b;return b
end
function hl.unbind(keys) for _,b in ipairs(bound) do if b.key==keys:match('[^+ ]+$') then removed[b]=true;b.enabled=false end end end
local runtime=dofile('lua/runtime.lua')
local action=function() calls=calls+1 end
hl.bind('SUPER + V',function() error('removed action') end,{description='Old'})
hl.unbind('SUPER + V')
local source=hl.bind('SUPER + V',action,{description='Clipboard'})
local state=os.tmpname(); local catalog=os.tmpname()
local f=assert(io.open(state,'w'));f:write('return {mappings={}}');f:close()
runtime.finish(state,catalog,true)
assert(#runtime.catalog==1 and runtime.catalog[1].name=='Clipboard')
local sig=runtime.catalog[1].signature
f=assert(io.open(state,'w'));f:write(string.format('return {mappings={{id="alias",name="Alias",enabled=true,trigger="F22",action={kind="alias",source="|SUPER + V",signature=%q}}}}',sig));f:close()
-- Fresh runtime mirrors a configuration reload.
bound={};removed={};runtime=dofile('lua/runtime.lua')
source=hl.bind('SUPER + V',action,{description='Clipboard'})
runtime.finish(state,catalog,true)
assert(source.enabled and #bound==2)
assert(bound[2].action==source.action,'Alias must share exact callable')
source.action();bound[2].action();assert(calls==2)
-- An unapproved replacement is rejected before any original is disabled.
bound={};removed={};runtime=dofile('lua/runtime.lua')
source=hl.bind('SUPER + V',action,{description='Clipboard'})
f=assert(io.open(state,'w'));f:write('return {mappings={{id="replace",name="Replacement",enabled=true,trigger="SUPER + V",action={kind="command",command="true"}}}}');f:close()
local ok=pcall(function()runtime.finish(state,catalog,true)end)
assert(not ok and source.enabled and #bound==1)
-- Explicit consent disables only the original handle for this generation.
bound={};removed={};runtime=dofile('lua/runtime.lua')
source=hl.bind('SUPER + V',action,{description='Clipboard'})
f=assert(io.open(state,'w'));f:write(string.format('return {mappings={{id="replace",name="Replacement",enabled=true,trigger="SUPER + V",replaces={["|SUPER + V"]=%q},action={kind="command",command="true"}}}}',sig));f:close()
runtime.finish(state,catalog,true)
assert(not source.enabled and #bound==2 and bound[2].enabled)
-- A disabled replacement reloads the original untouched.
bound={};removed={};runtime=dofile('lua/runtime.lua')
source=hl.bind('SUPER + V',action,{description='Clipboard'})
f=assert(io.open(state,'w'));f:write('return {mappings={{id="replace",name="Replacement",enabled=false,trigger="SUPER + V",action={kind="command",command="true"}}}}');f:close()
runtime.finish(state,catalog,true)
assert(source.enabled and #bound==1)
os.remove(state);os.remove(catalog)
print('Lua: dead-handle safety, exact alias identity, original preserved, conflict rejection, explicit replacement and restoration: OK')
