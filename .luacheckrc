std = "lua51"
global = false
unused_args = false
unused_secondaries = false
max_line_length = false

-- These are narrow, reviewed legacy idioms rather than a repository-wide warning
-- disable. New warnings elsewhere remain blocking. MarkerMacro uses empty accepted
-- branches as a strict macro-line whitelist; MarkerExecutor intentionally returns
-- the first blocking reason from an unordered blocker set. The remaining entries
-- are inert locals/callback shadowing retained to avoid behavior changes in the
-- same hardening PR.
files["Core/MarkerMacro.lua"] = {
  ignore = { "542" },
}

files["Core/MarkerPlanner.lua"] = {
  ignore = { "311/overflow" },
}

files["Runtime/SmartMacroManager.lua"] = {
  ignore = { "231/currentBody", "231/currentIcon" },
}

files["Runtime/MarkerExecutor.lua"] = {
  ignore = { "512" },
}

files["UI/ConfigurationUI.lua"] = {
  ignore = { "432/self" },
}

files["Core/Commands.lua"] = {
  ignore = { "211/L", "221/openError", "221/applyError", "431/L" },
}
