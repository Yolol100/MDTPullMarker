local _, Addon = ...

local RouteSnapshot = {}
Addon.RouteSnapshot = RouteSnapshot

local DataUtils = Addon.DataUtils

local MAX_PULLS = 500
local MAX_ENEMIES_PER_PULL = 500
local MAX_CLONES_PER_ENEMY = 1000
local MAX_TOTAL_CLONES = 20000
local MAX_TOTAL_ENEMIES = 20000
local MAX_SNAPSHOT_COPY_ENTRIES = 500000

local function isSecret(value)
  return DataUtils.IsSecret(value)
end

local function safeString(value)
  return DataUtils.SafeString(value, 1024, true)
end

local function safeNumber(value)
  return DataUtils.SafeNumber(value)
end

local function positiveInteger(value)
  return DataUtils.PositiveInteger(value)
end

local function copyPrimitive(value)
  if isSecret(value) then return nil end
  local valueType = type(value)
  if valueType == "string" or valueType == "number" or valueType == "boolean" then return value end
end

local function usableTable(value)
  return type(value) == "table" and not isSecret(value)
end

local function indexedValue(source, index)
  if not usableTable(source) then return nil end
  local value = source[index]
  if value == nil then value = source[tostring(index)] end
  return value
end

local function consumeCloneBudget(snapshot)
  snapshot._totalClones = (snapshot._totalClones or 0) + 1
  return snapshot._totalClones <= MAX_TOTAL_CLONES
end

local function consumeEnemyBudget(snapshot)
  snapshot._totalEnemies = (snapshot._totalEnemies or 0) + 1
  return snapshot._totalEnemies <= MAX_TOTAL_ENEMIES
end

local function addWarning(target, code, detail)
  target._warningLookup = target._warningLookup or {}
  local key = tostring(code)..":"..tostring(detail or "")
  if target._warningLookup[key] then return end
  target._warningLookup[key] = true
  target.warnings[#target.warnings + 1] = {
    code = tostring(code),
    detail = detail and tostring(detail) or nil,
  }
end

local function sortedPositiveKeys(source)
  local result, seen = {}, {}
  if not usableTable(source) then return result end
  for key in pairs(source) do
    local index = positiveInteger(key)
    if index and not seen[index] then
      seen[index] = true
      result[#result + 1] = index
    end
  end
  table.sort(result)
  return result
end

local function sortedCloneIndexes(source, snapshot, path)
  local result, seen = {}, {}
  if not usableTable(source) then
    addWarning(snapshot, "invalid-clone-list", path)
    return result
  end

  for _, value in pairs(source) do
    local cloneIndex = positiveInteger(value)
    if cloneIndex and not seen[cloneIndex] then
      if #result >= MAX_CLONES_PER_ENEMY or not consumeCloneBudget(snapshot) then
        addWarning(snapshot, "clone-limit-exceeded", path)
        break
      end
      seen[cloneIndex] = true
      result[#result + 1] = cloneIndex
    elseif value ~= nil and not cloneIndex then
      addWarning(snapshot, "invalid-clone-index", path)
    end
  end
  table.sort(result)
  return result
end

local function normalizeClone(cloneIndex, cloneData, snapshot, path, marker)
  local clone = { cloneIndex = cloneIndex }
  marker = positiveInteger(marker)
  if marker and marker <= 8 then clone.marker = marker end
  if not usableTable(cloneData) then
    if snapshot._expectCloneMetadata then addWarning(snapshot, "missing-clone-data", path) end
    return clone
  end

  clone.x = safeNumber(cloneData.x)
  clone.y = safeNumber(cloneData.y)
  clone.sublevel = positiveInteger(cloneData.sublevel)
  clone.scale = safeNumber(cloneData.scale)
  clone.note = safeString(cloneData.note)
  return clone
end


local function resolveEnemyName(resolver, rawName)
  local fallback = safeString(rawName)
  if type(resolver) ~= "function" or not fallback then return fallback end
  local ok, resolved = pcall(resolver, fallback)
  if not ok or isSecret(resolved) then return fallback end
  return safeString(resolved) or fallback
end

local function buildEnemyNameTotals(enemyData, resolver)
  if not usableTable(enemyData) then return nil end
  local totals = {}
  local entries = 0
  for _, enemy in pairs(enemyData) do
    if usableTable(enemy) then
      entries = entries + 1
      if entries > MAX_ENEMIES_PER_PULL * 4 then return nil end
      local exactName = resolveEnemyName(resolver, enemy.name)
      if exactName then
        local cloneCount = positiveInteger(enemy.cloneCount) or 0
        if cloneCount == 0 and usableTable(enemy.clones) then
          for cloneIndex in pairs(enemy.clones) do
            if positiveInteger(cloneIndex) then cloneCount = cloneCount + 1 end
            if cloneCount > MAX_CLONES_PER_ENEMY then break end
          end
        end
        totals[exactName] = (totals[exactName] or 0) + math.max(1, math.min(cloneCount, MAX_CLONES_PER_ENEMY))
      end
    end
  end
  return totals
end

local function normalizeEnemy(enemyIndex, cloneIndexes, enemyData, snapshot, pullIndex, enemyAssignments, enemyNameResolver)
  local enemy = {
    enemyIndex = enemyIndex,
    clones = {},
  }

  if usableTable(enemyData) then
    enemy.npcID = positiveInteger(enemyData.id or enemyData.npcID)
    enemy.name = resolveEnemyName(enemyNameResolver, enemyData.name)
    enemy.count = safeNumber(enemyData.count)
    enemy.health = safeNumber(enemyData.health)
    enemy.displayID = positiveInteger(enemyData.displayId or enemyData.displayID)
    enemy.isBoss = copyPrimitive(enemyData.isBoss) == true
  elseif snapshot._expectMetadata then
    addWarning(snapshot, "missing-enemy-data", ("pull:%d/enemy:%d"):format(pullIndex, enemyIndex))
  end

  local cloneDataList = usableTable(enemyData) and enemyData.clones or nil
  for _, cloneIndex in ipairs(cloneIndexes) do
    enemy.clones[#enemy.clones + 1] = normalizeClone(
      cloneIndex,
      indexedValue(cloneDataList, cloneIndex),
      snapshot,
      ("pull:%d/enemy:%d/clone:%d"):format(pullIndex, enemyIndex, cloneIndex),
      indexedValue(enemyAssignments, cloneIndex)
    )
  end

  return enemy
end

-- Route identity changes only when pull membership changes. Display names,
-- coordinates and addon versions are intentionally excluded so MDT metadata
-- refreshes do not reset runtime progress.
local function canonicalizeStable(snapshot)
  local parts = {
    "schema=3",
    "d="..tostring(snapshot.dungeonIndex or 0),
  }
  for _, pull in ipairs(snapshot.pulls) do
    parts[#parts + 1] = "p="..tostring(pull.index)
    for _, enemy in ipairs(pull.enemies) do
      parts[#parts + 1] = "e="..tostring(enemy.enemyIndex)
      for _, clone in ipairs(enemy.clones) do
        parts[#parts + 1] = "c="..tostring(clone.cloneIndex)
      end
    end
  end
  return table.concat(parts, "|")
end

local function finalize(snapshot)
  snapshot.canonicalRoute = canonicalizeStable(snapshot)
  snapshot.fingerprint = "route-v3-"..DataUtils.StableHash(snapshot.canonicalRoute)
  if snapshot.presetUID and snapshot.presetUID ~= "" then
    snapshot.routeKey = "uid:"..snapshot.presetUID
  else
    snapshot.routeKey = "fp:"..snapshot.fingerprint
  end
  snapshot._warningLookup = nil
  snapshot._totalClones = nil
  snapshot._totalEnemies = nil
  snapshot._expectMetadata = nil
  snapshot._expectCloneMetadata = nil
  return snapshot
end

function RouteSnapshot.NormalizePreset(preset, context)
  context = type(context) == "table" and context or {}
  local snapshot = {
    schemaVersion = 3,
    sourceMode = context.sourceMode or "unknown",
    compatibility = context.compatibility or "limited",
    mdtVersion = safeString(context.mdtVersion),
    dungeonIndex = positiveInteger(context.dungeonIndex),
    dungeonName = safeString(context.dungeonName),
    challengeMapID = positiveInteger(context.challengeMapID),
    presetIndex = positiveInteger(context.presetIndex),
    presetName = usableTable(preset) and safeString(preset.text or preset.name) or nil,
    presetUID = usableTable(preset) and safeString(preset.uid) or nil,
    currentPull = usableTable(preset) and usableTable(preset.value) and positiveInteger(preset.value.currentPull) or nil,
    nativeAssignmentsAvailable = usableTable(preset) and usableTable(preset.value) and usableTable(preset.value.enemyAssignments),
    enemyNameTotals = buildEnemyNameTotals(context.enemyData, context.enemyNameResolver),
    enemyNameScope = safeString(context.enemyDataScope) or (usableTable(context.enemyData) and "provided" or "route-only"),
    clientLocale = safeString(context.clientLocale),
    targetNameLocaleStatus = safeString(context.targetNameLocaleStatus),
    pulls = {},
    warnings = {},
    _expectMetadata = usableTable(context.enemyData),
    _expectCloneMetadata = usableTable(context.enemyData) and context.expectCloneMetadata ~= false,
  }

  if not usableTable(preset) or not usableTable(preset.value) or not usableTable(preset.value.pulls) then
    return nil, "invalid-preset"
  end

  if not snapshot.dungeonIndex then
    snapshot.dungeonIndex = positiveInteger(preset.value.currentDungeonIdx)
  end

  local pullKeys = sortedPositiveKeys(preset.value.pulls)
  local expectedPull = 1
  for _, pullIndex in ipairs(pullKeys) do
    if #snapshot.pulls >= MAX_PULLS then return nil, "too-many-pulls" end
    if pullIndex ~= expectedPull then addWarning(snapshot, "sparse-pulls", tostring(pullIndex)) end
    expectedPull = pullIndex + 1

    local rawPull = indexedValue(preset.value.pulls, pullIndex)
    if not usableTable(rawPull) then
      addWarning(snapshot, "invalid-pull", tostring(pullIndex))
    else
      local pull = {
        index = pullIndex,
        color = safeString(rawPull.color),
        enemies = {},
      }
      local enemyKeys = sortedPositiveKeys(rawPull)
      for _, enemyIndex in ipairs(enemyKeys) do
        if #pull.enemies >= MAX_ENEMIES_PER_PULL then return nil, "too-many-enemies-in-pull" end
        if not consumeEnemyBudget(snapshot) then return nil, "too-many-route-enemies" end
        local cloneIndexes = sortedCloneIndexes(indexedValue(rawPull, enemyIndex), snapshot, ("pull:%d/enemy:%d"):format(pullIndex, enemyIndex))
        local enemyData = indexedValue(context.enemyData, enemyIndex)
        local enemyAssignments = indexedValue(preset.value.enemyAssignments, enemyIndex)
        pull.enemies[#pull.enemies + 1] = normalizeEnemy(enemyIndex, cloneIndexes, enemyData, snapshot, pullIndex, enemyAssignments, context.enemyNameResolver)
      end
      snapshot.pulls[#snapshot.pulls + 1] = pull
    end
  end

  if #snapshot.pulls == 0 then addWarning(snapshot, "empty-route") end
  return finalize(snapshot)
end

local function normalizePublicClone(rawClone, fallbackIndex, snapshot, pullIndex, enemyIndex)
  if type(rawClone) == "number" then
    return normalizeClone(rawClone, nil, snapshot, ("pull:%d/enemy:%d/clone:%s"):format(pullIndex, enemyIndex, tostring(rawClone)))
  end
  if not usableTable(rawClone) then return nil end
  local cloneIndex = positiveInteger(rawClone.cloneIndex or rawClone.index or fallbackIndex)
  if not cloneIndex then return nil end
  return normalizeClone(
    cloneIndex,
    rawClone,
    snapshot,
    ("pull:%d/enemy:%d/clone:%d"):format(pullIndex, enemyIndex, cloneIndex),
    rawClone.marker or rawClone.targetMarker or rawClone.raidMarker
  )
end

function RouteSnapshot.NormalizePublic(raw, context)
  context = type(context) == "table" and context or {}
  if not usableTable(raw) then return nil, "invalid-public-snapshot" end
  if usableTable(raw.preset) then
    return RouteSnapshot.NormalizePreset(raw.preset, {
      sourceMode = "public-snapshot",
      compatibility = "full",
      mdtVersion = context.mdtVersion,
      dungeonIndex = raw.dungeonIndex,
      dungeonName = raw.dungeonName or raw.instanceName or raw.mapName,
      challengeMapID = raw.challengeMapID or raw.mapID,
      presetIndex = raw.presetIndex,
      enemyData = raw.enemyData or raw.enemies,
      enemyDataScope = raw.enemyDataScope or raw.enemyMetadataScope or "provided",
      enemyNameResolver = context.enemyNameResolver,
      clientLocale = context.clientLocale or raw.clientLocale,
      targetNameLocaleStatus = context.targetNameLocaleStatus or raw.targetNameLocaleStatus,
      expectCloneMetadata = context.expectCloneMetadata,
    })
  end

  local snapshot = {
    schemaVersion = 3,
    sourceMode = "public-snapshot",
    compatibility = "full",
    mdtVersion = safeString(context.mdtVersion),
    dungeonIndex = positiveInteger(raw.dungeonIndex),
    dungeonName = safeString(raw.dungeonName or raw.instanceName or raw.mapName),
    challengeMapID = positiveInteger(raw.challengeMapID or raw.mapID),
    presetIndex = positiveInteger(raw.presetIndex),
    presetName = safeString(raw.presetName or raw.name),
    presetUID = safeString(raw.presetUID or raw.uid),
    currentPull = positiveInteger(raw.currentPull),
    nativeAssignmentsAvailable = raw.nativeAssignmentsAvailable == true or usableTable(raw.enemyAssignments),
    enemyNameTotals = buildEnemyNameTotals(raw.enemyData or raw.enemies, context.enemyNameResolver),
    enemyNameScope = safeString(raw.enemyDataScope or raw.enemyMetadataScope) or "public-route",
    clientLocale = safeString(context.clientLocale or raw.clientLocale),
    targetNameLocaleStatus = safeString(context.targetNameLocaleStatus or raw.targetNameLocaleStatus),
    pulls = {},
    warnings = {},
    _expectMetadata = true,
    _expectCloneMetadata = context.expectCloneMetadata ~= false,
  }

  if not usableTable(raw.pulls) then return nil, "invalid-public-snapshot" end
  local pullKeys = sortedPositiveKeys(raw.pulls)
  for _, pullIndex in ipairs(pullKeys) do
    if #snapshot.pulls >= MAX_PULLS then return nil, "too-many-pulls" end
    local rawPull = indexedValue(raw.pulls, pullIndex)
    if usableTable(rawPull) then
      local pull = { index = pullIndex, color = safeString(rawPull.color), enemies = {} }
      local rawEnemies = rawPull.enemies or rawPull
      local enemyKeys = sortedPositiveKeys(rawEnemies)
      local listForm = false
      -- Do not infer the public shape from only the first numeric entry. A sparse or
      -- partially-invalid list can still contain valid enemy objects later; treating
      -- that as the membership-map form would silently lose their metadata/markers.
      for _, listIndex in ipairs(enemyKeys) do
        local candidate = indexedValue(rawEnemies, listIndex)
        if usableTable(candidate) and positiveInteger(candidate.enemyIndex or candidate.index)
          and usableTable(candidate.clones) then
          listForm = true
          break
        end
      end
      if listForm then
        local seenEnemies = {}
        for _, listIndex in ipairs(enemyKeys) do
          if #pull.enemies >= MAX_ENEMIES_PER_PULL then return nil, "too-many-enemies-in-pull" end
          local rawEnemy = indexedValue(rawEnemies, listIndex)
          local enemyIndex = usableTable(rawEnemy) and positiveInteger(rawEnemy.enemyIndex or rawEnemy.index) or nil
          if enemyIndex and seenEnemies[enemyIndex] then
            addWarning(snapshot, "duplicate-enemy-index", ("pull:%d/enemy:%d"):format(pullIndex, enemyIndex))
          elseif enemyIndex then
            if not consumeEnemyBudget(snapshot) then return nil, "too-many-route-enemies" end
            seenEnemies[enemyIndex] = true
            local enemy = {
              enemyIndex = enemyIndex,
              npcID = positiveInteger(rawEnemy.npcID or rawEnemy.id),
              name = safeString(rawEnemy.name),
              count = safeNumber(rawEnemy.count),
              health = safeNumber(rawEnemy.health),
              displayID = positiveInteger(rawEnemy.displayID or rawEnemy.displayId),
              isBoss = copyPrimitive(rawEnemy.isBoss) == true,
              clones = {},
            }
            if usableTable(rawEnemy.clones) then
              local seenClones = {}
              for cloneKey, rawClone in pairs(rawEnemy.clones) do
                if #enemy.clones >= MAX_CLONES_PER_ENEMY or not consumeCloneBudget(snapshot) then
                  addWarning(snapshot, "clone-limit-exceeded", ("pull:%d/enemy:%d"):format(pullIndex, enemyIndex))
                  break
                end
                local clone = normalizePublicClone(rawClone, cloneKey, snapshot, pullIndex, enemyIndex)
                if clone and seenClones[clone.cloneIndex] then
                  addWarning(snapshot, "duplicate-clone-index", ("pull:%d/enemy:%d/clone:%d"):format(pullIndex, enemyIndex, clone.cloneIndex))
                elseif clone then
                  seenClones[clone.cloneIndex] = true
                  if not clone.marker then
                    local enemyAssignments = indexedValue(raw.enemyAssignments, enemyIndex)
                    local marker = positiveInteger(indexedValue(enemyAssignments, clone.cloneIndex))
                    if marker and marker <= 8 then clone.marker = marker end
                  end
                  if clone.marker then snapshot.nativeAssignmentsAvailable = true end
                  enemy.clones[#enemy.clones + 1] = clone
                end
              end
              table.sort(enemy.clones, function(a, b) return a.cloneIndex < b.cloneIndex end)
            end
            pull.enemies[#pull.enemies + 1] = enemy
          end
        end
      else
        for _, enemyIndex in ipairs(enemyKeys) do
          if #pull.enemies >= MAX_ENEMIES_PER_PULL then return nil, "too-many-enemies-in-pull" end
          if not consumeEnemyBudget(snapshot) then return nil, "too-many-route-enemies" end
          local cloneIndexes = sortedCloneIndexes(indexedValue(rawEnemies, enemyIndex), snapshot, ("pull:%d/enemy:%d"):format(pullIndex, enemyIndex))
          local publicEnemyData = indexedValue(raw.enemyData or raw.enemies, enemyIndex)
          local publicEnemyAssignments = indexedValue(raw.enemyAssignments, enemyIndex)
          pull.enemies[#pull.enemies + 1] = normalizeEnemy(
            enemyIndex,
            cloneIndexes,
            publicEnemyData,
            snapshot,
            pullIndex,
            publicEnemyAssignments,
            context.enemyNameResolver
          )
        end
      end
      table.sort(pull.enemies, function(a, b) return a.enemyIndex < b.enemyIndex end)
      snapshot.pulls[#snapshot.pulls + 1] = pull
    end
  end

  if #snapshot.pulls == 0 then addWarning(snapshot, "empty-route") end
  return finalize(snapshot)
end

function RouteSnapshot.Copy(source)
  if type(source) ~= "table" then return source end
  return DataUtils.DeepCopy(source, { maxDepth = 20, maxEntries = MAX_SNAPSHOT_COPY_ENTRIES })
end
