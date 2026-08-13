local files = {
  "tests/test_event_inventory.lua",
  "tests/test_pull_death_tracker.lua",
  "tests/test_marker_ownership.lua",
}

for _, path in ipairs(files) do
  local chunk, loadError = loadfile(path)
  assert(chunk, loadError)
  local ok, err = pcall(chunk)
  if not ok then
    error(path .. ": " .. tostring(err), 0)
  end
end

print(("ok - %d focused regression files"):format(#files))
