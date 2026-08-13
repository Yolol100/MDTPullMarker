local _, Addon = ...

local L = Addon.L

L.ADDON_NAME = "MDT Pull Marker"
L.BINDING_MARK_PULL = "MDT route marker: mark up to 3 targets"
L.ACTIVE_MDT_ROUTE = "Active MDT route"
L.OPEN_CORRECT_ROUTE = "Open the correct route in MDT"
L.WAITING_FOR_DUNGEON = "Waiting for dungeon"
L.PREPARING_MACROS = "Preparing macros..."
L.MACROS_UPDATE_AFTER_COMBAT = "Macros update after combat"
L.SAME_NAME_PARKED = "Same-name pull parked safely"
L.ROUTE_MACROS_REFRESH_AFTER_COMBAT = "Route macros refresh after combat"
L.MARKED_PULL_NEEDS_ATTENTION = "Marked pull needs attention in MDT"
L.ELECTING_OWNER = "Electing party marker owner..."
L.OPEN_MATCHING_ROUTE = "Open the matching MDT route"

L.READY_AUTOMATIC = "Ready. MDT Pull Marker activates automatically when you enter a dungeon."
L.COMPARTMENT_LEFT = "Left-click: open MDT Pull Markers"
L.COMPARTMENT_RIGHT = "Right-click: open dungeon helper"
L.CONFIG_TITLE = "MDT Pull Marker"

_G.BINDING_HEADER_MDTPULLMARKER = L.ADDON_NAME
_G["BINDING_NAME_CLICK "..Addon.Constants.SmartButtonName..":LeftButton"] = L.BINDING_MARK_PULL
