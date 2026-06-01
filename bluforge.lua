--[[
* BluForge - Copyright (c) 2026
*
* A Blue Mage focused addon that combines the spell-set management of BluSets
* with an in-game ImGui interface inspired by BluCheck.
*
* Features:
*   - Define and manage Blue Magic spell sets through an ImGui interface.
*   - Browse known/unknown spells (color coded) with a "known only" filter.
*   - Visual slots that map to the in-game Blue Magic set slots (1-20).
*   - Save, load and delete spell sets.
*   - Apply a set to the game using BluSets' fast packet mode.
*   - Set point usage that respects BLU main/sub job availability.
*   - A traits panel identifying the job traits a set will grant.
*
* This addon is free software released under the GNU GPL v3, matching the
* BluSets / BluCheck addons it is derived from.
--]]

addon.name      = 'bluforge';
addon.author    = 'derived from atom0s BluSets/BluCheck';
addon.version   = '1.2';
addon.desc      = 'Blue Mage spell set manager with an ImGui UI and trait planner.';
addon.link      = 'https://ashitaxi.com/';

require 'common';

local chat = require 'chat';
local ui   = require 'ui';

--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
    -- Ensure the configuration folder for saved sets exists..
    local path = ('%s\\config\\addons\\%s\\'):fmt(AshitaCore:GetInstallPath(), addon.name);
    if (not ashita.fs.exists(path)) then
        ashita.fs.create_dir(path);
    end

    ui.load();
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    ui.save_settings();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/bluforge', '/bforge', '/bf')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    -- Handle: /bluforge help
    if (#args >= 2 and args[2]:any('help')) then
        print(chat.header(addon.name):append(chat.message('Commands:')));
        print(chat.header(addon.name):append(chat.color1(6, '/bluforge          - Toggles the BluForge window.')));
        print(chat.header(addon.name):append(chat.color1(6, '/bluforge load <n> - Loads the named spell set into the editor.')));
        print(chat.header(addon.name):append(chat.color1(6, '/bluforge apply    - Applies the current editor set to the game (fast).')));
        return;
    end

    -- Handle: /bluforge load <name>
    if (#args >= 3 and args[2]:any('load')) then
        ui.load_set(args:concat(' ', 3):trim());
        return;
    end

    -- Handle: /bluforge apply
    if (#args >= 2 and args[2]:any('apply')) then
        ui.apply_set();
        return;
    end

    -- Handle: /bluforge - Toggle the window.
    ui.is_open[1] = not ui.is_open[1];
end);

--[[
* event: packet_in
* desc : Event called when the addon is processing incoming packets.
--]]
ashita.events.register('packet_in', 'packet_in_cb', ui.packet_in);

--[[
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', ui.render);
