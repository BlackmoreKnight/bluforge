--[[
* BluForge - ImGui interface module.
*
* Handles the spell browser, the visual slot editor, set save/load, applying
* sets to the game (fast mode), and the trait planner.
--]]

require 'common';

local imgui    = require 'imgui';
local chat     = require 'chat';
local json     = require 'json';
local settings = require 'settings';
local ffi      = require 'ffi';
local data     = require 'data.bludata';

-- BLU's job id, used for job point/level lookups.
local BLU_JOB_ID = 16;

-- Blue Magic set limits by level, per the BG-Wiki Blue Mage chart. Indexed by
-- 10-level bracket: [1] = levels 1-10, [2] = 11-20, ... [10] = 91-99.
--   POINTS_BY_BRACKET : base set points available (main job base; sub job uses
--                       the same per-level value, without merits/job points).
--   SLOTS_BY_BRACKET  : number of Blue Magic spells that can be set.
local POINTS_BY_BRACKET = { 10, 15, 20, 25, 30, 35, 40, 45, 50, 55 };
local SLOTS_BY_BRACKET  = {  6,  8, 10, 12, 14, 16, 18, 20, 20, 20 };

-- Additional main-job-only set points beyond the level base.
local ASSIMILATION_MAX = 5;    -- Group 2 merit. (read live via GetAssimilationPoints)
local JP_BONUS_MAX     = 20;   -- "Blue Magic Point Bonus" job point gift.

--[[
* Returns the 10-level bracket index (1-10) for a given level, or 0 if invalid.
--]]
local function level_bracket(level)
    if (level == nil or level < 1) then return 0; end
    local idx = math.floor((level - 1) / 10) + 1;
    if (idx > 10) then idx = 10; end
    return idx;
end

-- Persisted configuration defaults.
local defaults = T{
    filter_known    = false,   -- "Known only" browser toggle.
    filter_settable = false,   -- "Hide non-settable" browser toggle.
    safe_mode       = true,    -- Apply using safe packet mode (vs. fast injection).
};

-- The number of Blue Magic set slots. (Matches the in-game maximum.)
local MAX_SLOTS = 20;

-- Packet delay floors (seconds). The entry box accepts any value, but anything
-- below the fast minimum is raised to it; safe mode is rate limited to 1.0s.
local FAST_MIN_DELAY = 0.10;
local SAFE_MIN_DELAY = 1.00;

--==========================================================================
-- Blue Mage memory / packet helpers
--
-- Folded in from the BluSets 'blu' helper (atom0s, GPL-3.0) so the addon has
-- no dependency on the blusets addon being installed. Both packet modes are
-- supported: 'safe' (the game's own queued functions, rate limited) and 'fast'
-- (custom packet injection); the active mode is chosen by the UI toggle.
--==========================================================================

-- FFI prototypes for the BLU equip function / packet. (0x0102 client to server)
ffi.cdef[[
    typedef uint8_t (__cdecl *equipex_t)(uint8_t isSubJob, uint16_t jobType, uint16_t index, uint8_t id);

    typedef struct packet_equipex_c2s_t {
        uint16_t    IdSize;
        uint16_t    Sync;
        uint8_t     SpellId;
        uint8_t     Unknown0000;
        uint16_t    Unknown0001;
        uint8_t     JobId;
        uint8_t     IsSubJob;
        uint16_t    Unknown0002;
        uint8_t     Spells[20];
        uint8_t     Unknown0003[132];
    } packet_equipex_c2s_t;
]];

local blu = T{
    -- Memory signatures, resolved once at load.
    offset  = ffi.cast('uint32_t*', ashita.memory.find(0, 0, 'C1E1032BC8B0018D????????????B9????????F3A55F5E5B', 10, 0)),
    points  = ffi.cast('uint8_t***', ashita.memory.find(0, 0, 'A1????????33C98A4E5E33D28A565D5F5E8950148948185B83C414C20400', 1, 0)),
    equipex = ffi.cast('equipex_t', ashita.memory.find(0, 0, '8B0D????????81EC9C00000085C95356570F??????????8B', 0, 0)),

    -- Packet sender mode: 'safe' uses the game's own queued functions (rate
    -- limited); 'fast' uses custom packet injection. Set from the UI toggle.
    mode = 'safe',
};

-- Returns true if the player's main job is BLU.
function blu.is_blu_main()
    return AshitaCore:GetMemoryManager():GetPlayer():GetMainJob() == 16;
end

-- Returns true if the player's sub job is BLU.
function blu.is_blu_sub()
    return AshitaCore:GetMemoryManager():GetPlayer():GetSubJob() == 16;
end

-- Returns the maximum BLU set points reported by the game.
function blu.get_max_points()
    local max = blu.points[0][0][0x18];
    return max or 0;
end

-- Returns the table of currently set BLU spells (reduced ids, 0 for empty).
function blu.get_spells()
    local ptr = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('inventory'));
    if (ptr == 0) then return T{}; end
    ptr = ashita.memory.read_uint32(ptr);
    if (ptr == 0) then return T{}; end
    return T(ashita.memory.read_array((ptr + blu.offset[0]) + (blu.is_blu_main() and 0x04 or 0xA0), 0x14));
end

-- Returns the raw BLU buffer pointer. (used by the safe-mode reset packet)
function blu.get_blu_buffer_ptr()
    local ptr = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('inventory'));
    if (ptr == 0) then return 0; end
    ptr = ashita.memory.read_uint32(ptr);
    if (ptr == 0) then return 0; end
    return ptr + blu.offset[0] + (blu.is_blu_main() and 0x00 or 0x9C);
end

-- Builds a base extended-equip packet for the current job. (fast mode)
local function blu_new_packet()
    return ffi.new('packet_equipex_c2s_t', {
        0x5302, 0x0000,
        0,
        0, 0,
        0x10, blu.is_blu_sub() == true and 1 or 0,
        0
    });
end

-- fast: reset all spells via custom packet injection.
local function fast_reset_all_spells()
    local eqex = blu_new_packet();
    local spells = blu.get_spells();
    for x = 1, #spells do
        eqex.Spells[x - 1] = spells[x];
    end
    local packet = ffi.string(eqex, ffi.sizeof('packet_equipex_c2s_t')):totable();
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x102, packet);
end

-- fast: set/unset a single spell via custom packet injection.
local function fast_set_spell(index, id)
    local eqex = blu_new_packet();
    if (id == 0) then
        eqex.SpellId = 0;
        eqex.Spells[index - 1] = blu.get_spells()[index];
    else
        eqex.SpellId = id;
        eqex.Spells[index - 1] = id;
    end
    local packet = ffi.string(eqex, ffi.sizeof('packet_equipex_c2s_t')):totable();
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x102, packet);
end

-- safe: reset all spells using the game's own packet queue.
local function safe_reset_all_spells()
    AshitaCore:GetPacketManager():QueuePacket(0x102, 0xA4, 0x00, 0x00, 0x00, function (ptr)
        local p = ffi.cast('uint8_t*', ptr);
        ffi.fill(p + 0x04, 0xA0);
        ffi.copy(p + 0x08, ffi.cast('uint8_t*', blu.get_blu_buffer_ptr()), 0x9C);
    end);
end

-- safe: set/unset a single spell using the in-game equip function.
local function safe_set_spell(index, id)
    blu.equipex(blu.is_blu_main() == true and 0 or 1, 0x1000, index - 1, id);
end

-- Queues a reset of all BLU spells using the current mode.
function blu.reset_all_spells()
    if (blu.mode == 'fast') then
        fast_reset_all_spells();
        return;
    end
    safe_reset_all_spells();
end

-- Queues a single BLU spell set (or unset, id == 0) using the current mode.
function blu.set_spell(index, id)
    if (index <= 0 or index > 20) then
        print(chat.header(addon.name):append(chat.error('Failed to set spell; invalid index. (Index: %d, Id: %d)')):fmt(index, id));
        return;
    end

    -- Reject setting a spell that is already assigned elsewhere..
    local spells = blu.get_spells();
    if (id ~= 0 and spells:hasval(id)) then
        print(chat.header(addon.name):append(chat.error('Failed to set spell; already assigned. (Index: %d, Id: %d)')):fmt(index, id));
        return;
    end

    -- Nothing to do when unsetting an already-empty slot..
    local current = spells[index];
    if (id == 0 and (current == nil or current == 0)) then
        return;
    end

    if (blu.mode == 'fast') then
        fast_set_spell(index, id);
        return;
    end
    safe_set_spell(index, id);
end

local ui = {
    -- Main window state.
    is_open = { false, },

    -- Spell data.
    spells  = T{},     -- All BLU spells: { index, name, level, element, known, cost, zones }
    byid    = T{},     -- Quick lookup: full id -> spell entry.
    learned = T{},     -- Raw "learned from" data loaded from /data/spells.json.
    counts  = T{ known = 0, missing = 0, total = 0, },

    -- The working set being edited. (slot index 1..MAX_SLOTS -> full spell id or 0)
    set = T{},

    -- Spell browser state.
    selected_id = -1,                 -- The full id of the spell selected in the browser.
    filter_known    = { false, },     -- "Known only" filter toggle.
    filter_settable = { false, },     -- "Hide non-settable" filter toggle. (cost 0 / n/a)
    filter_text     = { '', },        -- Name search filter.

    -- Save/load state.
    set_name     = { '', },           -- Name buffer for saving a set.
    saved_sets   = T{},               -- List of saved set file names (no extension).
    selected_set = { -1, },           -- Index into saved_sets for the load/delete combo.

    -- Apply state.
    fast_delay = { 0.30, },           -- Delay between packets when applying. (numeric source of truth)
    delay_text = { '0.30', },         -- Text-entry buffer for the delay.
    safe_mode  = { true, },           -- true = safe packet mode, false = fast injection.

    -- Transient status line shown at the bottom of the window.
    status        = '',
    status_expire = 0,

    -- Persisted settings table. (Populated in ui.load.)
    settings = nil,
};

--[[
* Writes the persisted browser toggles back to the settings table and saves
* them to disk so they are remembered across reloads and sessions.
--]]
function ui.save_settings()
    if (ui.settings == nil) then return; end
    ui.settings.filter_known    = ui.filter_known[1];
    ui.settings.filter_settable = ui.filter_settable[1];
    ui.settings.safe_mode       = ui.safe_mode[1];
    settings.save();
end

--[[
* Returns the BLU Job Point trait-bonus gift level, read directly from memory.
*
* Spending 100 and 1200 total Blue Mage job points each grants a gift that
* raises equipped Blue Magic job traits by one tier, so the level is 0, 1 or 2.
*
* Job points only apply while BLU is the main job; as a sub job there is no
* trait bonus regardless of job points spent, so this returns 0.
*
* @return {number} The detected gift level (0-2).
--]]
function ui.get_trait_gifts()
    if (not blu.is_blu_main()) then return 0; end
    local spent = AshitaCore:GetMemoryManager():GetPlayer():GetJobPointsSpent(BLU_JOB_ID);
    local gifts = 0;
    if (spent >= 100) then gifts = gifts + 1; end
    if (spent >= 1200) then gifts = gifts + 1; end
    return gifts;
end

--[[
* Sets the transient status line. Messages auto-clear after a few seconds.
*
* @param {string} msg - The message to display. ('' clears it.)
* @param {number} secs - Optional seconds before the message clears. (default 6)
--]]
function ui.set_status(msg, secs)
    ui.status = msg or '';
    ui.status_expire = os.time() + (secs or 6);
end

-- Initialize an empty set..
for i = 1, MAX_SLOTS do ui.set[i] = 0; end

--==========================================================================
-- Data loading / spell information
--==========================================================================

--[[
* Returns the string representation of the given spell element id.
--]]
function ui.get_spell_element(t)
    return switch(t, {
        [0] = function () return 'Fire'; end,
        [1] = function () return 'Ice'; end,
        [2] = function () return 'Wind'; end,
        [3] = function () return 'Earth'; end,
        [4] = function () return 'Lightning'; end,
        [5] = function () return 'Water'; end,
        [6] = function () return 'Light'; end,
        [7] = function () return 'Dark'; end,
        [15] = function () return '(None)'; end,
        [switch.default] = function () return tostring(t); end
    });
end

--[[
* Returns the "learned from" data block for the given spell id.
--]]
function ui.get_spell_data(id)
    local _, v = ui.learned:findkey(tostring(id));
    return v or T{};
end

--[[
* Builds the list of Blue Magic spells from the game resources.
--]]
function ui.get_spells()
    ui.spells = T{};
    ui.byid   = T{};

    for x = 0, 2048 do
        local spell = AshitaCore:GetResourceManager():GetSpellById(x);
        if (spell ~= nil and spell.Skill == 43 and spell.LevelRequired[16 + 1] > 0) then
            local entry = T{
                index   = x,
                name    = spell.Name[1],
                level   = spell.LevelRequired[16 + 1],
                element = spell.Element,
                known   = AshitaCore:GetMemoryManager():GetPlayer():HasSpell(x),
                cost    = data.get_cost(x),
                zones   = ui.get_spell_data(x),
            };
            ui.spells:append(entry);
            ui.byid[x] = entry;
        end
    end

    -- Default sort by level then name..
    ui.spells:sort(function (a, b)
        return (a.level < b.level) or (a.level == b.level and a.name < b.name);
    end);
end

--[[
* Updates the known/missing/total spell counts.
--]]
function ui.get_spell_counts()
    local counts = T{ known = 0, missing = 0, total = 0, };
    ui.spells:each(function (v)
        counts.total = counts.total + 1;
        if (v.known) then counts.known = counts.known + 1;
        else counts.missing = counts.missing + 1; end
    end);
    ui.counts = counts;
end

--[[
* Refreshes the list of saved set files from disk.
--]]
function ui.refresh_saved_sets()
    ui.saved_sets = T{};
    local path = ('%s\\config\\addons\\%s\\'):fmt(AshitaCore:GetInstallPath(), addon.name);
    local files = ashita.fs.get_dir(path, '.*.txt', true);
    if (files ~= nil) then
        T(files):each(function (v)
            ui.saved_sets:append(v:gsub('%.txt$', ''));
        end);
        ui.saved_sets:sort(function (a, b) return a:lower() < b:lower(); end);
    end
end

--[[
* Loads the ui, preparing it for usage.
--]]
function ui.load()
    -- Load persisted settings and apply the browser toggles..
    ui.settings = settings.load(defaults);
    ui.filter_known[1]    = ui.settings.filter_known;
    ui.filter_settable[1] = ui.settings.filter_settable;
    ui.safe_mode[1]       = ui.settings.safe_mode;

    -- Keep the toggles in sync if the settings block changes (character
    -- switch, manual reload, etc.)..
    settings.register('settings', 'bluforge_settings', function (s)
        ui.filter_known[1]    = s.filter_known;
        ui.filter_settable[1] = s.filter_settable;
        ui.safe_mode[1]       = s.safe_mode;
    end);

    -- Load the BLU "learned from" data..
    local f = io.open(addon.path .. '/data/spells.json', 'rb');
    if (f ~= nil) then
        local c = f:read('*all');
        f:close();
        ui.learned = T(json.decode(c) or {});
    end

    ui.get_spells();
    ui.get_spell_counts();
    ui.refresh_saved_sets();
    ui.load_from_game();
end

--==========================================================================
-- Set helpers
--==========================================================================

--[[
* Returns the total set point cost currently used by the working set.
--]]
function ui.used_points()
    local total = 0;
    for i = 1, MAX_SLOTS do
        local id = ui.set[i];
        if (id ~= nil and id > 0) then
            total = total + data.get_cost(id);
        end
    end
    return total;
end

--[[
* Returns the effective Blue Mage level (main job level if BLU main, sub job
* level if BLU sub), or 0 if the player is neither.
--]]
function ui.blu_level()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (blu.is_blu_main()) then
        return player:GetMainJobLevel();
    elseif (blu.is_blu_sub()) then
        return player:GetSubJobLevel();
    end
    return 0;
end

--[[
* Returns the maximum number of Blue Magic spells that can be set, based on the
* current Blue Mage level. Falls back to MAX_SLOTS for planning when the player
* is not BLU (no level to key from).
--]]
function ui.max_slots()
    local b = level_bracket(ui.blu_level());
    if (b == 0) then return MAX_SLOTS; end
    return SLOTS_BY_BRACKET[b];
end

--[[
* Returns the maximum set points available, or -1 when it cannot be determined
* (player is not BLU main or sub).
*
* The base value comes from the level chart. On main job the Assimilation merit
* (read live) is added, and the "Blue Magic Point Bonus" job point gift is added
* using the game's reported maximum (which is not otherwise readable per
* category), bounded to the known maximum so a bad memory read cannot inflate it.
--]]
function ui.max_points()
    local b = level_bracket(ui.blu_level());
    if (b == 0) then return -1; end

    local base = POINTS_BY_BRACKET[b];

    -- Merits and job points only apply while BLU is the main job.
    if (blu.is_blu_main()) then
        base = base + math.min(AshitaCore:GetMemoryManager():GetPlayer():GetAssimilationPoints(), ASSIMILATION_MAX);

        -- The job-point bonus is not readable per-category, so trust the game's
        -- reported maximum to supply it, but only to raise the total (never below
        -- the chart value) and never beyond the maximum possible bonus.
        local mem = blu.get_max_points();
        if (mem > base and mem <= base + JP_BONUS_MAX) then
            return mem;
        end
    end

    return base;
end

--[[
* Returns the number of filled slots in the working set.
--]]
function ui.filled_slots()
    local n = 0;
    for i = 1, MAX_SLOTS do
        if (ui.set[i] ~= nil and ui.set[i] > 0) then n = n + 1; end
    end
    return n;
end

--[[
* Returns the first empty slot index within the current slot limit, or nil if
* the set is full.
--]]
function ui.first_free_slot()
    local limit = ui.max_slots();
    for i = 1, limit do
        if (ui.set[i] == nil or ui.set[i] == 0) then return i; end
    end
    return nil;
end

--[[
* Returns true if the given spell id is already in the working set.
--]]
function ui.is_in_set(id)
    for i = 1, MAX_SLOTS do
        if (ui.set[i] == id) then return true; end
    end
    return false;
end

--[[
* Returns true if the given spell entry can be used at the current Blue Mage
* level. When the player is not BLU (planning mode, level 0) all spells are
* allowed since there is no level to gate against.
*
* @param {table} entry - A spell entry from ui.spells / ui.byid.
--]]
function ui.level_ok(entry)
    if (entry == nil) then return false; end
    local lvl = ui.blu_level();
    if (lvl <= 0) then return true; end
    return entry.level <= lvl;
end

--[[
* Attempts to assign a spell to a slot, respecting point capacity, duplicates
* and (when known) BLU job limits.
*
* @param {number} slot - The slot index to assign into.
* @param {number} id - The full spell id to assign.
--]]
function ui.assign(slot, id)
    if (id == nil or id <= 0) then return; end

    -- Reject spells with no set cost; these are not real settable Blue Magic..
    if (data.get_cost(id) <= 0) then
        ui.set_status('That spell cannot be set. (not a settable Blue Magic spell)');
        return;
    end

    -- Reject spells above the current Blue Mage level..
    local entry = ui.byid[id];
    if (entry ~= nil and not ui.level_ok(entry)) then
        ui.set_status(('That spell requires BLU level %d (you are %d).'):fmt(entry.level, ui.blu_level()));
        return;
    end

    -- Reject duplicates..
    if (ui.is_in_set(id)) then
        ui.set_status('That spell is already in the set.');
        return;
    end

    -- Reject slots beyond the current level's set limit..
    if (slot > ui.max_slots()) then
        ui.set_status(('That slot is locked at your level. (slot limit: %d)'):fmt(ui.max_slots()));
        return;
    end

    -- Reject if it would exceed the available set points..
    local max = ui.max_points();
    if (max > 0) then
        local current = ui.set[slot];
        local used = ui.used_points();
        if (current ~= nil and current > 0) then
            used = used - data.get_cost(current);
        end
        if (used + data.get_cost(id) > max) then
            ui.set_status(('Not enough set points. (%d/%d used, this spell costs %d)'):fmt(used, max, data.get_cost(id)));
            return;
        end
    end

    ui.set[slot] = id;
    ui.status = '';
end

--[[
* Clears the given slot.
--]]
function ui.clear_slot(slot)
    ui.set[slot] = 0;
    ui.status = '';
end

--[[
* Clears the entire working set.
--]]
function ui.clear_all()
    for i = 1, MAX_SLOTS do ui.set[i] = 0; end
    ui.set_status('Set cleared.');
end

--[[
* Loads the player's current in-game BLU spells into the working set.
--]]
function ui.load_from_game()
    local spells = blu.get_spells();
    for i = 1, MAX_SLOTS do
        local v = spells[i];
        if (v ~= nil and v > 0) then
            ui.set[i] = v + 512;     -- Stored ids are reduced by 512.
        else
            ui.set[i] = 0;
        end
    end
end

--==========================================================================
-- Save / Load to disk
--==========================================================================

--[[
* Saves the working set to a named file. (BluSets compatible: one spell name
* per line, in slot order.)
--]]
function ui.save_set(name)
    name = (name or ''):gsub('%.txt$', ''):trim();
    if (name == '') then
        ui.set_status('Enter a name before saving.');
        return;
    end

    local path = ('%s\\config\\addons\\%s\\%s.txt'):fmt(AshitaCore:GetInstallPath(), addon.name, name);
    local f = io.open(path, 'w+');
    if (f == nil) then
        ui.set_status('Failed to open file for writing.');
        return;
    end

    local lines = T{};
    for i = 1, MAX_SLOTS do
        local id = ui.set[i];
        if (id ~= nil and id > 0) then
            local res = AshitaCore:GetResourceManager():GetSpellById(id);
            lines:append(res ~= nil and res.Name[1] or '');
        else
            lines:append('');
        end
    end

    f:write(lines:concat('\n'));
    f:close();

    ui.refresh_saved_sets();
    ui.set_status(('Saved set: %s'):fmt(name));
    print(chat.header(addon.name):append(chat.message('Saved spell set: ')):append(chat.success(name)));
end

--[[
* Validates whether a set fits the current Blue Mage allowance (level, slot
* count, and set points). Returns ok(boolean), reason(string).
*
* In planning mode (not BLU, no level to gate against) any set is allowed.
*
* @param {table} ids - Slot-indexed list of full spell ids (0/nil for empty).
--]]
function ui.validate_set(ids)
    local lvl = ui.blu_level();
    if (lvl <= 0) then return true; end   -- planning mode: nothing to enforce

    local slotmax = ui.max_slots();
    local maxpts  = ui.max_points();
    local count   = 0;
    local total   = 0;

    for i = 1, MAX_SLOTS do
        local id = ids[i];
        if (id ~= nil and id > 0) then
            count = count + 1;
            total = total + data.get_cost(id);

            local entry = ui.byid[id];
            if (entry ~= nil and entry.level > lvl) then
                return false, ('contains %s (Lv.%d), above your BLU level %d'):fmt(entry.name, entry.level, lvl);
            end
        end
    end

    if (count > slotmax) then
        return false, ('uses %d spells but only %d slot(s) are available at your level'):fmt(count, slotmax);
    end
    if (maxpts > 0 and total > maxpts) then
        return false, ('needs %d set points but only %d are available'):fmt(total, maxpts);
    end
    return true;
end

--[[
* Loads a named set file into the working set.
--]]
function ui.load_set(name)
    name = (name or ''):gsub('%.txt$', ''):trim();
    local path = ('%s\\config\\addons\\%s\\%s.txt'):fmt(AshitaCore:GetInstallPath(), addon.name, name);
    if (not ashita.fs.exists(path)) then
        ui.set_status(('Set not found: %s'):fmt(name));
        print(chat.header(addon.name):append(chat.error('Set not found: ')):append(chat.warning(name)));
        return;
    end

    local f = io.open(path, 'r');
    if (f == nil) then
        ui.set_status('Failed to open set file for reading.');
        return;
    end

    -- Read into a temporary set first, in slot order..
    local temp = T{};
    for i = 1, MAX_SLOTS do temp[i] = 0; end

    local slot = 1;
    for line in f:lines() do
        line = line:trim();
        if (line ~= '' and slot <= MAX_SLOTS) then
            local res = AshitaCore:GetResourceManager():GetSpellByName(line, 0);
            if (res ~= nil and res.Index >= 512 and res.Index < 1024) then
                temp[slot] = res.Index;
            end
        end
        slot = slot + 1;
    end
    f:close();

    -- Refuse to load a set that exceeds the current job's allowance; loading it
    -- anyway would only apply an empty/partial set in-game..
    local ok, reason = ui.validate_set(temp);
    if (not ok) then
        ui.set_status(('Cannot load "%s": %s.'):fmt(name, reason));
        print(chat.header(addon.name):append(chat.error(('Cannot load set "%s": %s.'):fmt(name, reason))));
        return;
    end

    -- Commit the validated set..
    for i = 1, MAX_SLOTS do ui.set[i] = temp[i]; end
    ui.set_name[1] = name;
    ui.set_status(('Loaded set: %s'):fmt(name));
end

--[[
* Deletes a named set file.
--]]
function ui.delete_set(name)
    name = (name or ''):gsub('%.txt$', ''):trim();
    local path = ('%s\\config\\addons\\%s\\%s.txt'):fmt(AshitaCore:GetInstallPath(), addon.name, name);
    if (not ashita.fs.exists(path)) then
        ui.set_status(('Set not found: %s'):fmt(name));
        return;
    end
    ashita.fs.remove(path);
    ui.refresh_saved_sets();
    ui.selected_set[1] = -1;
    ui.set_status(('Deleted set: %s'):fmt(name));
end

--==========================================================================
-- Apply to game (safe / fast packet modes, from BluSets)
--==========================================================================

--[[
* Applies the working set to the game. Resets the current spells, then sets
* each slot with a delay between packets, using the mode selected in the UI
* (safe = the game's own queued functions; fast = custom packet injection).
--]]
function ui.apply_set()
    if (not blu.is_blu_main() and not blu.is_blu_sub()) then
        ui.set_status('You must be BLU main or sub to set spells.');
        print(chat.header(addon.name):append(chat.error('You must be BLU main or sub to set spells.')));
        return;
    end

    -- Refuse to apply a set that exceeds the current job's allowance (e.g. a
    -- main-job set while subbed); doing so would only set an empty/partial set..
    local ok, reason = ui.validate_set(ui.set);
    if (not ok) then
        ui.set_status(('Cannot apply: %s.'):fmt(reason));
        print(chat.header(addon.name):append(chat.error(('Cannot apply set: %s.'):fmt(reason))));
        return;
    end

    -- Build the slot -> reduced id list (the packet code expects id - 512).
    -- Only include slots within the current level's set limit; slots beyond it
    -- cannot be set and would be rejected by the game..
    local slotmax = ui.max_slots();
    local plan = T{};
    for i = 1, slotmax do
        local id = ui.set[i];
        if (id ~= nil and id > 0) then
            plan[i] = id - 512;
        end
    end

    -- Select the packet mode from the toggle and clamp the delay. Anything below
    -- the fast minimum is raised to it; safe mode is rate limited to 1.0s.
    blu.mode = ui.safe_mode[1] and 'safe' or 'fast';
    local delay = ui.fast_delay[1];
    if (delay < FAST_MIN_DELAY) then delay = FAST_MIN_DELAY; end
    if (blu.mode == 'safe' and delay < SAFE_MIN_DELAY) then delay = SAFE_MIN_DELAY; end

    ashita.tasks.once(1, (function (d, lst)
        -- Fully clear the current set first..
        blu.reset_all_spells();

        -- Wait until the reset is actually reflected in memory before setting
        -- the new spells. The set-spell guard reads the live spell array, so
        -- if we set too early it will still "see" the old spells and refuse.
        local waited = 0.0;
        while (waited < 4.0) do
            coroutine.sleep(0.1);
            waited = waited + 0.1;

            local cur = blu.get_spells();
            local cleared = true;
            for i = 1, #cur do
                if (cur[i] ~= nil and cur[i] ~= 0) then
                    cleared = false;
                    break;
                end
            end
            if (cleared) then
                break;
            end
        end
        coroutine.sleep(d);

        for slot = 1, MAX_SLOTS do
            local id = lst[slot];
            if (id ~= nil and id > 0) then
                blu.set_spell(slot, id);
                coroutine.sleep(d);
            end
        end
        ui.set_status('Set applied.', 4);
        print(chat.header(addon.name):append(chat.message('Finished applying blue magic spell set.')));
    end):bindn(delay, plan));

    ui.set_status(('Applying set (%s mode)...'):fmt(blu.mode));
    print(chat.header(addon.name):append(chat.message(('Applying blue magic spell set (%s); please wait..'):fmt(blu.mode))));
end

--==========================================================================
-- Packet handling (keeps known status fresh)
--==========================================================================

function ui.packet_in(e)
    -- Message Basic: spell learned.
    if (e.id == 0x0029) then
        local msg = struct.unpack('H', e.data_modified, 0x18 + 0x01);
        if (msg == 419) then
            local spellId = struct.unpack('L', e.data_modified, 0x0C + 0x01);
            local sender  = struct.unpack('H', e.data_modified, 0x14 + 0x01);
            local target  = struct.unpack('H', e.data_modified, 0x16 + 0x01);
            local player  = GetPlayerEntity();
            if (player ~= nil and sender == player.TargetIndex and target == player.TargetIndex) then
                local entry = ui.byid[spellId];
                if (entry ~= nil) then entry.known = true; end
                ui.get_spell_counts();
            end
        end
        return;
    end

    -- Spells Information: full spell list refresh.
    if (e.id == 0x00AA) then
        ashita.tasks.oncef(1, function ()
            ui.get_spells();
            ui.get_spell_counts();
        end);
        return;
    end
end

--==========================================================================
-- Rendering helpers
--==========================================================================

local COLOR_KNOWN   = { 0.40, 1.00, 0.40, 1.0 };
local COLOR_UNKNOWN = { 1.00, 0.40, 0.40, 1.0 };
local COLOR_HEADER  = { 1.00, 0.65, 0.26, 1.0 };
local COLOR_WHITE   = { 1.00, 1.00, 1.00, 1.0 };
local COLOR_DIM     = { 0.55, 0.55, 0.55, 1.0 };

-- Muted variants used for non-settable (n/a) spells so their known status is
-- still visible while signalling that they cannot be slotted.
local COLOR_KNOWN_NA   = { 0.30, 0.60, 0.30, 1.0 };
local COLOR_UNKNOWN_NA = { 0.65, 0.40, 0.40, 1.0 };
local COLOR_VALUE   = { 0.20, 0.70, 1.00, 1.0 };

--[[
* Renders the top status bar: job, point usage, slot usage, learned counts.
--]]
function ui.render_status_bar()
    -- Job status..
    imgui.TextColored(COLOR_HEADER, 'Job:');
    imgui.SameLine();
    if (blu.is_blu_main()) then
        imgui.TextColored(COLOR_KNOWN, 'BLU (Main)');
    elseif (blu.is_blu_sub()) then
        imgui.TextColored({ 1.0, 0.9, 0.3, 1.0 }, 'BLU (Sub)');
    else
        imgui.TextColored(COLOR_UNKNOWN, 'Not BLU - planning only');
    end

    imgui.SameLine();
    imgui.TextColored(COLOR_DIM, '|');
    imgui.SameLine();

    -- Point usage..
    local used = ui.used_points();
    local max  = ui.max_points();
    imgui.TextColored(COLOR_HEADER, 'Points:');
    imgui.SameLine();
    if (max < 0) then
        imgui.TextColored(COLOR_DIM, ('%d / ?'):fmt(used));
    else
        local col = (used > max) and COLOR_UNKNOWN or COLOR_KNOWN;
        imgui.TextColored(col, ('%d / %d'):fmt(used, max));
    end

    imgui.SameLine();
    imgui.TextColored(COLOR_DIM, '|');
    imgui.SameLine();

    -- Slot usage..
    local slotmax = ui.max_slots();
    imgui.TextColored(COLOR_HEADER, 'Slots:');
    imgui.SameLine();
    local slotcol = (ui.filled_slots() > slotmax) and COLOR_UNKNOWN or COLOR_VALUE;
    imgui.TextColored(slotcol, ('%d / %d'):fmt(ui.filled_slots(), slotmax));

    imgui.SameLine();
    imgui.TextColored(COLOR_DIM, '|');
    imgui.SameLine();

    -- Learned counts..
    imgui.TextColored(COLOR_HEADER, 'Known:');
    imgui.SameLine();
    imgui.TextColored(COLOR_KNOWN, ('%d'):fmt(ui.counts.known));
    imgui.SameLine();
    imgui.TextColored(COLOR_DIM, ('/ %d'):fmt(ui.counts.total));
end

--[[
* Renders the spell browser (left pane of the editor).
--]]
function ui.render_browser()
    imgui.TextColored(COLOR_HEADER, 'Spell Browser');

    -- Filters..
    if (imgui.Checkbox('Known only', ui.filter_known)) then
        ui.save_settings();
    end
    imgui.SameLine();
    if (imgui.Checkbox('Hide non-settable', ui.filter_settable)) then
        ui.save_settings();
    end
    imgui.PushItemWidth(150);
    imgui.InputText('Search', ui.filter_text, 64);
    imgui.PopItemWidth();

    -- Sort buttons and legend live above the list so the list can fill the
    -- remaining vertical space without fragile height math..
    if (imgui.Button('Sort: Level')) then
        ui.spells:sort(function (a, b)
            return (a.level < b.level) or (a.level == b.level and a.name < b.name);
        end);
    end
    imgui.SameLine();
    if (imgui.Button('Sort: Name')) then
        ui.spells:sort(function (a, b) return a.name < b.name; end);
    end
    imgui.TextColored(COLOR_DIM, 'Green=known, Red=unknown (muted=n/a). * = in set. [Lv] = above level.');

    local search = ui.filter_text[1]:lower();

    imgui.BeginChild('browserlist', { 310, 0 }, ImGuiChildFlags_Borders);
        ui.spells:each(function (v)
            -- Apply filters..
            if (ui.filter_known[1] and not v.known) then return; end
            if (ui.filter_settable[1] and v.cost <= 0) then return; end
            if (search ~= '' and not v.name:lower():contains(search)) then return; end

            local in_set    = ui.is_in_set(v.index);
            local settable  = v.cost > 0;
            local usable    = ui.level_ok(v);
            -- Settable spells use bright green/red by known status; non-settable
            -- (n/a) spells use muted green/red so their known status still reads.
            local color;
            if (settable) then
                color = v.known and COLOR_KNOWN or COLOR_UNKNOWN;
            else
                color = v.known and COLOR_KNOWN_NA or COLOR_UNKNOWN_NA;
            end
            imgui.PushStyleColor(ImGuiCol_Text, color);
            local cost_str = settable and ('%d'):fmt(v.cost) or 'n/a';
            -- Mark spells above the current BLU level and disable their selection.
            local lvl_tag = usable and '' or ' [Lv]';
            local label = ('[%02d] %s (%s)%s%s##b%d'):fmt(v.level, v.name, cost_str, in_set and ' *' or '', lvl_tag, v.index);
            local flags = usable and ImGuiSelectableFlags_None or ImGuiSelectableFlags_Disabled;
            if (imgui.Selectable(label, ui.selected_id == v.index, flags)) then
                ui.selected_id = v.index;
            end
            imgui.PopStyleColor();

            -- Double-click assigns to the first free slot. (usable spells only)
            if (usable and imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(0)) then
                local slot = ui.first_free_slot();
                if (slot ~= nil) then ui.assign(slot, v.index); end
            end
        end);
    imgui.EndChild();
end

--[[
* Renders the visual slot editor (mirrors the in-game set slots).
--]]
function ui.render_slots()
    local slotmax = ui.max_slots();
    imgui.TextColored(COLOR_HEADER, ('Set Slots (%d available)'):fmt(slotmax));

    local sel = ui.selected_id;
    local can_place = (sel ~= -1) and not ui.is_in_set(sel);

    imgui.BeginChild('slots', { 540, 230 }, ImGuiChildFlags_Borders);
        -- Two columns of ten slots..
        imgui.Columns(2, '##slotcols', false);
        for i = 1, MAX_SLOTS do
            local id     = ui.set[i];
            local locked = i > slotmax;
            local label;
            local color;
            if (locked) then
                if (id ~= nil and id > 0) then
                    local res = AshitaCore:GetResourceManager():GetSpellById(id);
                    local name = res ~= nil and res.Name[1] or ('id %d'):fmt(id);
                    label = ('%02d: %s (locked)'):fmt(i, name);
                else
                    label = ('%02d: (locked)'):fmt(i);
                end
                color = { 0.55, 0.35, 0.35, 1.0 };
            elseif (id ~= nil and id > 0) then
                local res = AshitaCore:GetResourceManager():GetSpellById(id);
                local name = res ~= nil and res.Name[1] or ('id %d'):fmt(id);
                label = ('%02d: %s (%d)'):fmt(i, name, data.get_cost(id));
                color = COLOR_WHITE;
            else
                label = ('%02d: ---'):fmt(i);
                color = COLOR_DIM;
            end

            imgui.PushStyleColor(ImGuiCol_Text, color);
            if (imgui.Selectable(('%s##slot%d'):fmt(label, i)) and not locked) then
                if (id ~= nil and id > 0) then
                    -- Clicking a filled slot clears it..
                    ui.clear_slot(i);
                elseif (can_place) then
                    -- Clicking an empty slot assigns the selected spell..
                    ui.assign(i, sel);
                end
            end
            imgui.PopStyleColor();

            if (imgui.IsItemHovered()) then
                if (locked) then
                    imgui.SetTooltip('This slot unlocks at a higher Blue Mage level.');
                elseif (id ~= nil and id > 0) then
                    imgui.SetTooltip('Click to clear this slot.');
                elseif (can_place) then
                    imgui.SetTooltip('Click to place the selected spell here.');
                else
                    imgui.SetTooltip('Select a spell in the browser first.');
                end
            end

            imgui.NextColumn();
        end
        imgui.Columns(1);
    imgui.EndChild();

    -- Slot action buttons..
    if (imgui.Button('Load from Game')) then
        ui.load_from_game();
        ui.set_status('Loaded the current in-game set.');
    end
    imgui.SameLine();
    if (imgui.Button('Clear All')) then
        ui.clear_all();
    end
    if (ui.selected_id ~= -1) then
        imgui.SameLine();
        local entry = ui.byid[ui.selected_id];
        if (entry ~= nil and not ui.is_in_set(ui.selected_id)) then
            if (imgui.Button(('Add %s'):fmt(entry.name))) then
                local slot = ui.first_free_slot();
                if (slot ~= nil) then ui.assign(slot, ui.selected_id); end
            end
        end
    end
end

--[[
* Renders the save / load / apply controls.
--]]
function ui.render_controls()
    imgui.TextColored(COLOR_HEADER, 'Sets');

    -- Save row..
    imgui.PushItemWidth(160);
    imgui.InputText('##setname', ui.set_name, 64);
    imgui.PopItemWidth();
    imgui.SameLine();
    if (imgui.Button('Save')) then
        ui.save_set(ui.set_name[1]);
    end

    -- Load/Delete row..
    imgui.PushItemWidth(160);
    local preview = '(select a set)';
    if (ui.selected_set[1] >= 1 and ui.saved_sets[ui.selected_set[1]] ~= nil) then
        preview = ui.saved_sets[ui.selected_set[1]];
    end
    if (imgui.BeginCombo('##savedsets', preview, ImGuiComboFlags_None)) then
        ui.saved_sets:each(function (v, k)
            if (imgui.Selectable(v, ui.selected_set[1] == k)) then
                ui.selected_set[1] = k;
            end
        end);
        imgui.EndCombo();
    end
    imgui.PopItemWidth();
    imgui.SameLine();
    if (imgui.Button('Load')) then
        if (ui.selected_set[1] >= 1 and ui.saved_sets[ui.selected_set[1]] ~= nil) then
            ui.load_set(ui.saved_sets[ui.selected_set[1]]);
        end
    end
    imgui.SameLine();
    if (imgui.Button('Delete')) then
        if (ui.selected_set[1] >= 1 and ui.saved_sets[ui.selected_set[1]] ~= nil) then
            ui.delete_set(ui.saved_sets[ui.selected_set[1]]);
        end
    end

    imgui.Separator();

    -- Apply controls..
    if (imgui.Checkbox('Safe mode', ui.safe_mode)) then
        ui.save_settings();
    end
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('Safe: uses the game\'s own packet queue (rate limited, min 1.0s delay). Recommended.\nFast: custom packet injection - quicker but riskier.');
    end

    -- Packet delay as a free-form numeric entry (seconds, any value)..
    imgui.PushItemWidth(80);
    if (imgui.InputText('Packet delay (sec)', ui.delay_text, 16)) then
        local n = tonumber(ui.delay_text[1]);
        if (n ~= nil) then ui.fast_delay[1] = n; end
    end
    imgui.PopItemWidth();

    -- Signify the effective minimum that will actually be used..
    if (ui.fast_delay[1] < FAST_MIN_DELAY) then
        imgui.TextColored({ 1.0, 0.6, 0.2, 1.0 }, ('Below minimum - %.2fs will be used.'):fmt(FAST_MIN_DELAY));
    elseif (ui.safe_mode[1] and ui.fast_delay[1] < SAFE_MIN_DELAY) then
        imgui.TextColored(COLOR_DIM, ('Safe mode raises this to %.2fs.'):fmt(SAFE_MIN_DELAY));
    end

    imgui.PushStyleColor(ImGuiCol_Button, { 0.15, 0.45, 0.75, 1.0 });
    local apply_label = ('Apply to Game (%s)'):fmt(ui.safe_mode[1] and 'Safe' or 'Fast');
    if (imgui.Button(apply_label, { 200, 0 })) then
        ui.apply_set();
    end
    imgui.PopStyleColor();
end

--[[
* Renders the information panel for the currently selected browser spell.
--]]
function ui.render_spell_info()
    imgui.TextColored(COLOR_HEADER, 'Spell Information');
    imgui.BeginChild('spellinfo', { 0, 0 }, ImGuiChildFlags_Borders);
        if (ui.selected_id == -1) then
            imgui.TextColored(COLOR_WHITE, 'Select a spell to view its details.');
        else
            local entry = ui.byid[ui.selected_id];
            local res   = AshitaCore:GetResourceManager():GetSpellById(ui.selected_id);
            if (entry == nil or res == nil) then
                imgui.TextColored(COLOR_UNKNOWN, 'Failed to obtain spell information.');
            else
                local function stat(h, v)
                    imgui.TextColored(COLOR_WHITE, h);
                    imgui.SameLine();
                    imgui.TextColored(COLOR_VALUE, tostring(v));
                end

                if (imgui.Button('Show On BgWiki')) then
                    ashita.misc.open_url(('https://www.bg-wiki.com/ffxi/%s'):fmt(res.Name[1]));
                end

                imgui.PushTextWrapPos(imgui.GetFontSize() * 22.0);
                imgui.TextColored({ 1.0, 0.2, 0.5, 1.0 }, res.Name[1]);
                imgui.TextColored({ 1.0, 0.5, 0.2, 1.0 }, res.Description[1]);
                imgui.PopTextWrapPos();
                imgui.Separator();

                stat('Set Cost     :', data.get_cost(ui.selected_id));
                stat('Element      :', ui.get_spell_element(res.Element));
                stat('Mana Cost    :', res.ManaCost);
                stat('Cast Time    :', ('%.2f sec'):fmt(res.CastTime / 4.0));
                stat('Recast Delay :', ('%.2f sec'):fmt(res.RecastDelay / 4.0));
                stat('Level Needed :', res.LevelRequired[16 + 1]);

                imgui.TextColored(COLOR_WHITE, 'Known        :');
                imgui.SameLine();
                if (entry.known) then
                    imgui.TextColored(COLOR_KNOWN, 'Yes');
                else
                    imgui.TextColored(COLOR_UNKNOWN, 'No');
                end

                -- Which traits this spell contributes to..
                imgui.Separator();
                imgui.TextColored({ 1.0, 1.0, 0.4, 1.0 }, 'Contributes To Traits');
                local any = false;
                data.traits:each(function (trait)
                    local pts = trait.spells[ui.selected_id];
                    if (pts ~= nil) then
                        any = true;
                        imgui.TextColored(COLOR_WHITE, ('  %s'):fmt(trait.name));
                        imgui.SameLine();
                        imgui.TextColored(COLOR_VALUE, ('+%d'):fmt(pts));
                    end
                end);
                if (not any) then
                    imgui.TextColored(COLOR_DIM, '  (none)');
                end

                -- Where this spell can be learned (zone -> mobs)..
                imgui.Separator();
                imgui.TextColored({ 1.0, 1.0, 0.4, 1.0 }, 'Learnable From');
                if (entry.zones ~= nil and entry.zones:len() > 0) then
                    entry.zones:each(function (mobs, zoneId)
                        -- Zone keys may be a numeric zone id (resolved to a
                        -- name) or already a zone name string..
                        local znum  = tonumber(zoneId);
                        local zname = nil;
                        if (znum ~= nil) then
                            zname = AshitaCore:GetResourceManager():GetString('zones.names', znum);
                        end
                        if (zname == nil or zname == '') then
                            zname = tostring(zoneId);
                        end
                        imgui.TextColored({ 1.0, 0.4, 1.0, 1.0 }, zname);
                        imgui.Indent();
                        for _, mob in pairs(mobs) do
                            imgui.TextColored(COLOR_WHITE, tostring(mob));
                        end
                        imgui.Unindent();
                    end);
                else
                    imgui.TextColored(COLOR_DIM, '  No data available.');
                end
            end
        end
    imgui.EndChild();
end

--[[
* Renders the main editor tab.
--]]
function ui.render_tab_editor()
    imgui.BeginGroup();
        ui.render_browser();
    imgui.EndGroup();
    imgui.SameLine();

    imgui.BeginGroup();
        ui.render_slots();
        ui.render_controls();
    imgui.EndGroup();
    imgui.SameLine();

    imgui.BeginGroup();
        ui.render_spell_info();
    imgui.EndGroup();
end

--[[
* Renders the traits planner tab.
--]]
function ui.render_tab_traits()
    -- The trait-bonus gift level is detected from the character's BLU job
    -- points (read from memory), so there is nothing to configure here..
    local gifts = ui.get_trait_gifts();
    imgui.TextColored(COLOR_HEADER, 'Job Point Trait Bonus:');
    imgui.SameLine();
    imgui.TextColored(COLOR_VALUE, ('+%d tier'):fmt(gifts));
    imgui.SameLine();
    if (blu.is_blu_main()) then
        imgui.TextColored(COLOR_DIM, ('(auto-detected from %d BLU job points spent)'):fmt(
            AshitaCore:GetMemoryManager():GetPlayer():GetJobPointsSpent(BLU_JOB_ID)));
    else
        imgui.TextColored(COLOR_DIM, '(none - job point traits apply only when BLU is your main job)');
    end
    imgui.TextColored(COLOR_DIM, 'Gifts at 100 and 1200 job points each raise eligible traits by one tier (+8 points).');
    imgui.Separator();

    -- Build the set id list and compute traits..
    local ids = T{};
    for i = 1, MAX_SLOTS do
        if (ui.set[i] ~= nil and ui.set[i] > 0) then ids:append(ui.set[i]); end
    end
    local results = data.compute_traits(ids, gifts);

    imgui.BeginChild('traitlist', { 0, 0 }, ImGuiChildFlags_Borders);
        if (results:len() == 0) then
            imgui.TextColored(COLOR_WHITE, 'No traits from the current set. Add spells in the Editor tab.');
        else
            -- Active traits header..
            local shown_inactive_header = false;
            results:each(function (r)
                if (r.label ~= nil) then
                    imgui.PushStyleColor(ImGuiCol_Text, COLOR_KNOWN);
                    local header = ('%s %s'):fmt(r.name, r.label);
                    if (imgui.TreeNode(('%s##trait%s'):fmt(header, r.name))) then
                        imgui.PopStyleColor();
                        imgui.TextColored(COLOR_WHITE, ('Points: %d'):fmt(r.effective));
                        if (r.next ~= nil) then
                            imgui.SameLine();
                            imgui.TextColored(COLOR_DIM, ('(next tier at %d)'):fmt(r.next));
                        end
                        r.contributors:each(function (c)
                            local res = AshitaCore:GetResourceManager():GetSpellById(c.id);
                            imgui.TextColored(COLOR_VALUE, ('   %s'):fmt(res ~= nil and res.Name[1] or ('id %d'):fmt(c.id)));
                            imgui.SameLine();
                            imgui.TextColored(COLOR_DIM, ('+%d'):fmt(c.points));
                        end);
                        imgui.TreePop();
                    else
                        imgui.PopStyleColor();
                    end
                else
                    if (not shown_inactive_header) then
                        shown_inactive_header = true;
                        imgui.Separator();
                        imgui.TextColored(COLOR_HEADER, 'In Progress (no tier yet)');
                    end
                    imgui.PushStyleColor(ImGuiCol_Text, COLOR_DIM);
                    imgui.Text(('%s - %d pts (need %d)'):fmt(r.name, r.effective, r.next or 0));
                    imgui.PopStyleColor();
                end
            end);
        end
    imgui.EndChild();
end

--[[
* Renders the addon window.
--]]
function ui.render()
    if (not ui.is_open[1]) then
        return;
    end

    -- Expire any stale status message..
    if (ui.status ~= '' and os.time() >= ui.status_expire) then
        ui.status = '';
    end

    imgui.SetNextWindowSize({ 1080, 540 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 1020, 520 }, { FLT_MAX, FLT_MAX });
    if (imgui.Begin('BluForge', ui.is_open, ImGuiWindowFlags_None)) then
        ui.render_status_bar();
        imgui.Separator();

        -- Reserve a fixed footer for the status line so the tab content always
        -- fits inside the window regardless of how it is resized..
        local footer = imgui.GetFrameHeightWithSpacing() + 8;
        imgui.BeginChild('##content', { 0, -footer }, ImGuiChildFlags_None);
            if (imgui.BeginTabBar('##bluforge_tabs', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)) then
                if (imgui.BeginTabItem('Editor')) then
                    ui.render_tab_editor();
                    imgui.EndTabItem();
                end
                if (imgui.BeginTabItem('Traits')) then
                    ui.render_tab_traits();
                    imgui.EndTabItem();
                end
                imgui.EndTabBar();
            end
        imgui.EndChild();

        -- Footer status line. (Always present so the layout stays stable.)
        imgui.Separator();
        imgui.TextColored({ 1.0, 0.85, 0.3, 1.0 }, ui.status);
    end
    imgui.End();
end

return ui;
