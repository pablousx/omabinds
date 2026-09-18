-- Loaded before user/default bindings. Never executes a captured action here.
local M = { records = {}, groups = {}, catalog = {}, warnings = {}, applied = {} }
local original = hl.bind
local originalUnbind = hl.unbind
local function copy(t)
  local out = {}; for k, v in pairs(t or {}) do out[k] = v end; return out
end
local function json(v)
  if type(v) == 'string' then
    return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
      return string.format('\\u%04x', c:byte())
    end) .. '"'
  elseif type(v) == 'boolean' or type(v) == 'number' then return tostring(v)
  elseif type(v) == 'table' then
    local out = {}
    if v[1] ~= nil or next(v) == nil then
      for _, x in ipairs(v) do out[#out+1] = json(x) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    for k, x in pairs(v) do out[#out+1] = json(k) .. ':' .. json(x) end
    table.sort(out); return '{' .. table.concat(out, ',') .. '}'
  end
  return 'null'
end
local function trigger(b)
  local mods = {}
  for _, p in ipairs({{64,'SUPER'},{4,'CTRL'},{8,'ALT'},{1,'SHIFT'},{128,'MOD5'},{32,'MOD3'}}) do
    if (b.modmask & p[1]) ~= 0 then mods[#mods+1] = p[2] end
  end
  mods[#mods+1] = b.keycode > 0 and ('code:' .. b.keycode) or b.key
  return table.concat(mods, ' + ')
end
local function normalize(keys)
  local parts, mods, key = {}, {}, ''
  for part in keys:gmatch('[^+]+') do parts[#parts+1] = part:match('^%s*(.-)%s*$'):upper() end
  local aliases = {CONTROL='CTRL', MOD4='SUPER', MOD1='ALT', WIN='SUPER', META='SUPER'}
  for i, part in ipairs(parts) do
    if i == #parts then key=part else mods[aliases[part] or part]=true end
  end
  parts={}; for _, mod in ipairs({'SUPER','CTRL','ALT','SHIFT','MOD5','MOD3'}) do if mods[mod] then parts[#parts+1]=mod end end
  parts[#parts+1]=key; return table.concat(parts,' + ')
end
hl.bind = function(keys, action, opts)
  local b = original(keys, action, opts)
  M.records[#M.records+1] = {handle=b, action=action, opts=copy(opts), keys=normalize(keys), removed=false}
  return b
end
hl.unbind = function(keys)
  for _, record in ipairs(M.records) do if record.keys == normalize(keys) then record.removed=true end end
  return originalUnbind(keys)
end
local function enabled(b)
  local ok, value = pcall(function() return b:is_enabled() end)
  return ok and value
end
function M.finish(statePath, catalogPath, strict)
  hl.bind = original
  hl.unbind = originalUnbind
  for _, record in ipairs(M.records) do
    local b = record.handle
    if not record.removed and enabled(b) then
      local key = trigger(b)
      local id = (b.submap or '') .. '|' .. key:upper()
      if not M.groups[id] then
        M.groups[id] = {}
        M.catalog[#M.catalog+1] = {id=id, trigger=key, submap=b.submap or '', name='', signature='', supported=true, ignoreMods=b.ignore_mods or false, catchAll=b.catchall or false}
      end
      M.groups[id][#M.groups[id]+1] = record
    end
  end
  for _, row in ipairs(M.catalog) do
    local names, sig, handles = {}, {}, {}
    for _, r in ipairs(M.groups[row.id]) do
      local b = r.handle
      names[#names+1] = b.description ~= '' and b.description or row.trigger
      -- Description and flags guard against an unrelated action taking over a trigger.
      sig[#sig+1] = {name=b.description or '', release=b.release, repeating=b.repeating, locked=b.locked}
      handles[#handles+1] = {dispatcher=b.handler, arg=b.arg}
      if b.mouse or b.catchall or b.ignore_mods or (r.opts.device ~= nil) then row.supported=false end
    end
    row.name = table.concat(names, ' · ')
    row.runtime = handles
    row.signature = json(sig)
  end
  -- A process killed between the disk commit and verification must not leave
  -- an unverified generation active on next login.
  local pendingPath = statePath:gsub('[^/]+$', 'pending.lua')
  local pendingFile = io.open(pendingPath, 'r')
  if not strict and pendingFile then
    pendingFile:close()
    local pending = dofile(pendingPath)
    local proc = io.open('/proc/' .. pending.pid .. '/stat', 'r')
    local stat = proc and proc:read('*a') or ''; if proc then proc:close() end
    local fields={}; for field in (stat:match('.*%) (.*)') or ''):gmatch('%S+') do fields[#fields+1]=field end
    if fields[20] ~= pending.start then statePath=pending.previous end
  end
  local state = dofile(statePath)
  local plan, targets = {}, {}
  local byId = {}; for _, row in ipairs(M.catalog) do byId[row.id] = row end
  local function fail(message)
    if strict then error(message) end
    M.warnings[#M.warnings+1] = message
  end
  for _, mapping in ipairs(state.mappings or {}) do
    if mapping.enabled then
      local actions, valid = {}, true
      if mapping.action.kind == 'alias' then
        local row = byId[mapping.action.source]
        if not row or not row.supported or row.signature ~= mapping.action.signature then
          fail('Alias unavailable or changed: ' .. mapping.name); valid=false
        else
          for _, r in ipairs(M.groups[row.id]) do actions[#actions+1] = {action=r.action, opts=copy(r.opts)} end
        end
      else
        actions[1] = {action=hl.dsp.exec_cmd(mapping.action.command), opts={}}
      end
      local target = '|' .. mapping.trigger:upper()
      if targets[target] then fail('Duplicate trigger: ' .. mapping.trigger); valid=false end
      local collisions = {}
      for _, row in ipairs(M.catalog) do
        if row.trigger:upper() == mapping.trigger:upper() or (mapping.replaces and mapping.replaces[row.id]) then collisions[#collisions+1] = row end
      end
      for _, row in ipairs(collisions) do
        local consent = mapping.replaces and mapping.replaces[row.id]
        if consent ~= row.signature or row.submap ~= '' then
          fail('Unapproved conflict: ' .. mapping.trigger .. ' — ' .. row.name); valid=false
        end
      end
      if valid then
        targets[target] = true
        plan[#plan+1] = {mapping=mapping, actions=actions, collisions=collisions}
      end
    end
  end
  -- Resolve everything before changing any original binding. Roll back handles
  -- if an API error occurs halfway through binding a group of actions.
  local added, removed = {}, {}
  local ok, err = pcall(function()
    for _, item in ipairs(plan) do
      M.applied[item.mapping.id] = item.actions
      for _, row in ipairs(item.collisions) do
        for _, r in ipairs(M.groups[row.id]) do r.handle:set_enabled(false); removed[#removed+1]=r.handle end
      end
      for _, a in ipairs(item.actions) do
        a.opts.description = '[omabinds:' .. item.mapping.id .. '] ' .. item.mapping.name
        added[#added+1] = original(item.mapping.trigger, a.action, a.opts)
      end
    end
  end)
  if not ok then
    for _, b in ipairs(added) do pcall(function() b:remove() end) end
    for _, b in ipairs(removed) do pcall(function() b:set_enabled(true) end) end
    fail(tostring(err))
  end
  if catalogPath then
    local f = assert(io.open(catalogPath .. '.tmp', 'w'))
    f:write(json({bindings=M.catalog, warnings=M.warnings})); f:close()
    assert(os.rename(catalogPath .. '.tmp', catalogPath))
  end
end
return M
