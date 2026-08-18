local files = {
  "tests/test_event_inventory.lua",
  "tests/test_pull_death_tracker.lua",
  "tests/test_marker_ownership.lua",
  "tests/test_migrations.lua",
  "tests/test_migration_backups.lua",
  "tests/test_mdt_focus_marker_bridge.lua",
  "tests/test_input_hardening.lua",
  "tests/test_mdt_adapter.lua",
  "tests/test_runtime_controller.lua",
  "tests/test_marker_executor.lua",
  "tests/test_smart_macro_manager.lua",
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
