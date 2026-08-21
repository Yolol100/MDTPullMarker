local _, Addon = ...

local Commands = Addon.Commands

function MDTPullMarker_Open(_, buttonName)
  if buttonName == "RightButton" then
    Addon.RuntimeFrame:Open()
  else
    Commands:OpenPrimaryInterface()
  end
end

function MDTPullMarker_CompartmentEnter(_, menuButtonFrame)
  if not GameTooltip or not menuButtonFrame then return end
  local L = Addon.L or {}
  GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
  GameTooltip:SetText(L.ADDON_NAME or "MDT Pull Marker", 1, 0.82, 0)
  GameTooltip:AddLine(L.COMPARTMENT_LEFT or "Left-click: open MDT Pull Markers", 1, 1, 1)
  GameTooltip:AddLine(L.COMPARTMENT_RIGHT or "Right-click: open dungeon helper", 0.72, 0.72, 0.72)
  GameTooltip:Show()
end

function MDTPullMarker_CompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
