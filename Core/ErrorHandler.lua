local _, Addon = ...

local ErrorHandler = {}
Addon.ErrorHandler = ErrorHandler

local MAX_ERROR_LENGTH = 800
local MAX_CONTEXT_LENGTH = 120

local function sanitize(value, maximum)
  if Addon.IsSecret and Addon.IsSecret(value) then return "<secret>" end
  value = tostring(value or "unknown")
  value = value:gsub("[%z\1-\8\11\12\14-\31]", "?")
  value = value:gsub("|", "/")
  maximum = maximum or MAX_ERROR_LENGTH
  if #value > maximum then value = value:sub(1, maximum).."..." end
  return value
end

function ErrorHandler.Capture(context, errorValue)
  context = sanitize(context, MAX_CONTEXT_LENGTH)
  local message = sanitize(errorValue, MAX_ERROR_LENGTH)
  if Addon.Log then Addon.Log("ERROR", context..": "..message, false) end
  return {
    code = "runtime-error",
    context = context,
    message = message,
  }
end

function ErrorHandler.Run(context, callback, ...)
  if type(callback) ~= "function" then
    return nil, ErrorHandler.Capture(context, "callback-not-function")
  end

  local arguments = { ... }
  local argumentCount = select("#", ...)
  local results
  local function pack(...) return { n = select("#", ...), ... } end
  local function invoke()
    results = pack(callback(unpack(arguments, 1, argumentCount)))
  end
  local ok, runtimeError
  if type(xpcall) == "function" then
    ok, runtimeError = xpcall(invoke, function(err)
      if type(debugstack) == "function" then
        local stackOk, stack = pcall(debugstack, 2, 8, 8)
        if stackOk and stack then return tostring(err).."\n"..tostring(stack) end
      end
      return err
    end)
  else
    ok, runtimeError = pcall(invoke)
  end
  if not ok then return nil, ErrorHandler.Capture(context, runtimeError) end
  if not results then return end
  return unpack(results, 1, results.n or #results)
end

ErrorHandler.Sanitize = sanitize
