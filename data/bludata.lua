--[[
* BluForge - Blue Mage Spell Set & Trait Data
*
* This file contains the static data the addon needs that cannot be obtained
* from the game's own resources:
*
*   costs  - The "set point" cost of each Blue Magic spell. (Extracted from the
*            in-game spell-set menu values.)
*   traits - The Blue Mage job trait table. Each trait lists its tiers and the
*            spells (with the trait points each contributes). (Sourced from
*            BG-Wiki: Blue_Mage_Job_Traits.)
*
* Tiers: every job trait tier requires 8 trait points (tier N = 8*N points),
* and each Blue Mage Job Point trait-bonus gift adds +8 trait points (only when
* the trait already has at least one point). The first value stored in each
* tier entry is BG-Wiki's *minimum set-point cost* reference for that tier - it
* is informational only and not used for the calculation; the calculation uses
* the 8-points-per-tier rule and the number of tiers as the maximum tier.
*
* All spells are keyed by their full resource spell id (513+). When talking to
* the equip packet code, ids are reduced by 512 (handled elsewhere).
*
* gift_exempt traits do NOT benefit from Blue Mage Job Point trait bonus gifts.
--]]

local data = T{};

-- Trait points required for each tier. Every tier needs 8 trait points, so
-- tier N requires 8*N points.
local POINTS_PER_TIER = 8;
local ROMAN = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII' };

--[[
* Set point cost per Blue Magic spell. (full resource id -> cost)
--]]
data.costs = T{
    [513]=3,  [515]=5,  [517]=1,  [519]=3,  [521]=4,  [522]=2,  [524]=2,  [527]=3,
    [529]=2,  [530]=4,  [531]=3,  [532]=4,  [533]=3,  [534]=4,  [535]=1,  [536]=1,
    [537]=2,  [538]=4,  [539]=3,  [540]=4,  [541]=2,  [542]=2,  [543]=2,  [544]=2,
    [545]=4,  [547]=1,  [548]=3,  [549]=1,  [551]=1,  [554]=5,  [555]=3,  [557]=4,
    [560]=3,  [561]=3,  [563]=3,  [564]=4,  [565]=4,  [567]=2,  [569]=4,  [570]=2,
    [572]=1,  [573]=3,  [574]=2,  [575]=4,  [576]=3,  [577]=2,  [578]=3,  [579]=4,
    [581]=4,  [582]=2,  [584]=2,  [585]=4,  [587]=2,  [588]=2,  [589]=5,  [591]=4,
    [592]=2,  [593]=3,  [594]=3,  [595]=5,  [596]=2,  [597]=2,  [598]=4,  [599]=2,
    [603]=3,  [604]=5,  [605]=3,  [606]=2,  [608]=3,  [610]=4,  [611]=5,  [612]=4,
    [613]=5,  [614]=3,  [615]=5,  [616]=5,  [617]=3,  [618]=2,  [620]=3,  [621]=2,
    [622]=2,  [623]=3,  [626]=3,  [628]=3,  [629]=3,  [631]=3,  [632]=4,  [633]=5,
    [634]=5,  [636]=4,  [637]=5,  [638]=3,  [640]=4,  [641]=5,  [642]=3,  [643]=3,
    [644]=4,  [645]=4,  [646]=4,  [647]=2,  [648]=1,  [650]=4,  [651]=4,  [652]=3,
    [653]=2,  [654]=4,  [655]=3,  [656]=3,  [657]=3,  [658]=4,  [659]=4,  [660]=3,
    [661]=5,  [662]=3,  [663]=4,  [664]=2,  [665]=1,  [666]=3,  [667]=2,  [668]=3,
    [669]=2,  [670]=4,  [671]=4,  [672]=5,  [673]=4,  [674]=1,  [675]=3,  [677]=3,
    [678]=3,  [679]=3,  [680]=5,  [681]=5,  [682]=2,  [683]=4,  [684]=4,  [685]=3,
    [686]=4,  [687]=2,  [688]=2,  [689]=3,  [690]=5,  [692]=4,  [693]=5,  [694]=3,
    [695]=4,  [696]=5,  [697]=4,  [698]=2,  [699]=2,  [700]=6,  [701]=6,  [702]=6,
    [703]=6,  [704]=6,  [705]=3,  [706]=2,  [707]=5,  [708]=6,  [709]=7,  [710]=6,
    [711]=7,  [712]=6,  [713]=6,  [714]=6,  [715]=6,  [716]=6,  [717]=6,  [718]=6,
    [719]=8,  [720]=8,  [721]=8,  [722]=8,  [723]=7,  [724]=7,  [725]=8,  [726]=8,
    [727]=8,  [728]=8,
};

--[[
* Blue Mage job trait table.
*
* tiers : ordered list of { min_set_point_cost (BG-Wiki reference), label }. The
*         number of entries is the trait's maximum tier; the stored numbers are
*         reference only (see the file header - tiers use 8 trait points each).
* spells: full spell id -> trait points contributed.
--]]
data.traits = T{
    T{ name='Accuracy Bonus', gift_exempt=false,
       tiers=T{ {5,'I'},{11,'II'},{19,'III'},{29,'IV'},{39,'V*'},{48,'VI**'} },
       spells=T{ [589]=4,[560]=4,[611]=4,[667]=4,[700]=8,[721]=8 } },

    T{ name='Attack Bonus', gift_exempt=false,
       tiers=T{ {6,'I'},{13,'II'},{19,'III'},{27,'IV'},{39,'V*'},{51,'VI**'} },
       spells=T{ [620]=4,[594]=4,[554]=4,[540]=4,[616]=4,[675]=4,[703]=8,[719]=8 } },

    T{ name='Auto Refresh', gift_exempt=true,
       tiers=T{ {9,'I'} },
       spells=T{ [537]=1,[561]=2,[533]=2,[535]=1,[634]=2,[579]=3,[612]=4,[615]=4,[681]=4 } },

    T{ name='Auto Regen', gift_exempt=false,
       tiers=T{ {6,'I'},{6,'II*'},{6,'III**'} },
       spells=T{ [581]=4,[584]=4,[690]=4 } },

    T{ name='Clear Mind', gift_exempt=false,
       tiers=T{ {3,'I'},{7,'II'},{13,'III'},{20,'IV'},{28,'V*'},{36,'VI**'} },
       spells=T{ [536]=4,[598]=4,[513]=4,[606]=4,[548]=4,[515]=4,[573]=4,[651]=4,[621]=4,[636]=4,[588]=4,[644]=4 } },

    T{ name='Conserve MP', gift_exempt=false,
       tiers=T{ {4,'I'},{9,'II'},{14,'III'},{20,'IV*'},{28,'V**'} },
       spells=T{ [582]=4,[647]=4,[608]=4,[637]=4,[687]=4,[707]=8 } },

    T{ name='Counter', gift_exempt=false,
       tiers=T{ {5,'I'},{15,'II*'},{24,'III**'} },
       spells=T{ [633]=4,[653]=4,[689]=4,[696]=4 } },

    T{ name='Critical Attack Bonus', gift_exempt=false,
       tiers=T{ {6,'I'},{6,'II*'},{6,'III**'} },
       spells=T{ [714]=8 } },

    T{ name='Defense Bonus', gift_exempt=false,
       tiers=T{ {5,'I'},{11,'II'},{17,'III'},{25,'IV'},{37,'V*'},{49,'VI**'} },
       spells=T{ [622]=4,[539]=4,[614]=4,[617]=4,[718]=8,[722]=8 } },

    T{ name='Double Attack', gift_exempt=true,
       tiers=T{ {5,'I'} },
       spells=T{ [656]=4,[659]=4,[677]=4,[688]=4,[709]=8 } },

    T{ name='Dual Wield', gift_exempt=false,
       tiers=T{ {4,'I'},{10,'II'},{17,'III'},{26,'IV'},{35,'V*'},{41,'VI**'} },
       spells=T{ [661]=4,[657]=4,[673]=4,[682]=4,[686]=4,[699]=4,[715]=8 } },

    T{ name='Evasion Bonus', gift_exempt=false,
       tiers=T{ {6,'I'},{12,'II'},{20,'III'},{32,'IV*'},{44,'V**'} },
       spells=T{ [519]=4,[641]=4,[679]=4,[701]=8,[727]=8 } },

    T{ name='Fast Cast', gift_exempt=false,
       tiers=T{ {6,'I'},{12,'II'},{21,'III*'},{33,'IV**'} },
       spells=T{ [604]=4,[654]=4,[671]=4,[698]=4,[710]=8 } },

    T{ name='Gilfinder', gift_exempt=true,
       tiers=T{ {8,'I'} },
       spells=T{ [680]=6,[683]=6,[697]=6 } },

    T{ name='Inquartata', gift_exempt=false,
       tiers=T{ {7,'I'},{7,'II*'},{7,'III**'} },
       spells=T{ [723]=8 } },

    T{ name='Beast Killer', gift_exempt=true,
       tiers=T{ {5,'I'} },
       spells=T{ [603]=4,[597]=4,[650]=4,[595]=4,[716]=8 } },

    T{ name='Lizard Killer', gift_exempt=true,
       tiers=T{ {4,'I'} },
       spells=T{ [577]=4,[587]=4,[585]=4,[717]=8 } },

    T{ name='Plantoid Killer', gift_exempt=true,
       tiers=T{ {3,'I'} },
       spells=T{ [551]=4,[543]=4,[652]=4 } },

    T{ name='Undead Killer', gift_exempt=true,
       tiers=T{ {5,'I'} },
       spells=T{ [529]=4,[527]=4 } },

    T{ name='Magic Accuracy Bonus', gift_exempt=false,
       tiers=T{ {8,'I'},{8,'II*'},{8,'III**'} },
       spells=T{ [728]=8 } },

    T{ name='Magic Attack Bonus', gift_exempt=false,
       tiers=T{ {3,'I'},{9,'II'},{16,'III'},{24,'IV'},{36,'V*'},{48,'VI**'} },
       spells=T{ [544]=4,[572]=4,[557]=4,[538]=4,[591]=4,[613]=4,[646]=4,[678]=4,[708]=8,[720]=8 } },

    T{ name='Magic Burst Bonus', gift_exempt=false,
       tiers=T{ {6,'I'},{13,'II'},{17,'III'},{23,'IV*'},{31,'V**'} },
       spells=T{ [663]=6,[660]=6,[684]=6,[712]=8 } },

    T{ name='Magic Defense Bonus', gift_exempt=false,
       tiers=T{ {6,'I'},{12,'II'},{20,'III'},{28,'IV*'},{36,'V**'} },
       spells=T{ [555]=4,[531]=4,[672]=4,[702]=8,[726]=8 } },

    T{ name='Magic Evasion Bonus', gift_exempt=false,
       tiers=T{ {8,'I'},{8,'II*'},{8,'III**'} },
       spells=T{ [725]=8 } },

    T{ name='Max HP Boost', gift_exempt=false,
       tiers=T{ {5,'I'},{11,'II'},{18,'III'},{26,'IV'},{36,'V*'},{48,'VI**'} },
       spells=T{ [629]=4,[564]=4,[628]=4,[685]=4,[695]=4,[706]=4,[711]=8 } },

    T{ name='Max MP Boost', gift_exempt=false,
       tiers=T{ {4,'I'},{10,'II'},{16,'III*'},{28,'IV**'} },
       spells=T{ [517]=4,[534]=4,[563]=4,[668]=4,[694]=4 } },

    T{ name='Rapid Shot', gift_exempt=true,
       tiers=T{ {6,'I'} },
       spells=T{ [638]=4,[569]=4,[631]=4 } },

    T{ name='Resist Gravity', gift_exempt=true,
       tiers=T{ {3,'I'} },
       spells=T{ [574]=4,[648]=4 } },

    T{ name='Resist Silence', gift_exempt=true,
       tiers=T{ {4,'I'} },
       spells=T{ [705]=8 } },

    T{ name='Resist Sleep', gift_exempt=true,
       tiers=T{ {4,'I'} },
       spells=T{ [549]=4,[578]=4,[593]=4,[576]=4,[645]=4 } },

    T{ name='Skillchain Bonus', gift_exempt=false,
       tiers=T{ {6,'I'},{13,'II'},{18,'III'},{24,'IV*'},{30,'V**'} },
       spells=T{ [666]=6,[670]=6,[693]=6,[704]=8 } },

    T{ name='Store TP', gift_exempt=false,
       tiers=T{ {5,'I'},{11,'II'},{19,'III'},{27,'IV*'},{39,'V**'} },
       spells=T{ [545]=4,[640]=4,[674]=4,[692]=4,[713]=8 } },

    T{ name='Tenacity', gift_exempt=false,
       tiers=T{ {7,'I'},{7,'II*'},{7,'III**'} },
       spells=T{ [724]=8 } },

    T{ name='Treasure Hunter', gift_exempt=true,
       tiers=T{ {12,'I'} },
       spells=T{ [680]=6,[683]=6,[697]=6 } },

    T{ name='Triple Attack', gift_exempt=true,
       tiers=T{ {12,'I'} },
       spells=T{ [656]=4,[659]=4,[677]=4,[688]=4,[709]=8 } },

    T{ name='Zanshin', gift_exempt=true,
       tiers=T{ {3,'I'} },
       spells=T{ [665]=4,[669]=4 } },
};

--[[
* Returns the set point cost for a spell. (full resource id)
*
* @param {number} id - The full spell resource id.
* @return {number} The set point cost, or 0 if unknown.
--]]
function data.get_cost(id)
    return data.costs[id] or 0;
end

--[[
* Computes the job traits granted by a set of equipped spells.
*
* @param {table} ids - List of full spell resource ids currently equipped.
* @param {number} gifts - Number of Job Point trait-bonus gifts (0, 1, or 2).
* @return {table} List of { name, label, points, effective, next, contributors }
*                 for every trait with at least one contributing spell, sorted
*                 by trait name. label is nil when no tier is reached.
--]]
function data.compute_traits(ids, gifts)
    gifts = gifts or 0;

    -- Build a quick lookup of equipped ids..
    local equipped = T{};
    T(ids):each(function (v)
        if (v ~= nil and v > 0) then
            equipped[v] = true;
        end
    end);

    local results = T{};
    data.traits:each(function (trait)
        -- Sum the base points contributed by equipped spells..
        local base = 0;
        local contributors = T{};
        trait.spells:each(function (pts, id)
            if (equipped[id]) then
                base = base + pts;
                contributors:append(T{ id = id, points = pts });
            end
        end);

        -- Skip traits with nothing equipped toward them..
        if (base <= 0) then
            return;
        end

        -- Apply the job point gift bonus: each gift adds 8 trait points. This
        -- only applies when the trait already has points (guaranteed here, since
        -- base > 0) and not to gift-exempt traits.
        local effective = base;
        if (not trait.gift_exempt) then
            effective = effective + (POINTS_PER_TIER * gifts);
        end

        -- Each tier needs 8 trait points (tier N = 8*N). The number of tiers the
        -- trait defines is its maximum attainable tier.
        local maxtier  = #trait.tiers;
        local tier_num = math.floor(effective / POINTS_PER_TIER);
        if (tier_num > maxtier) then tier_num = maxtier; end

        local label = (tier_num >= 1) and ROMAN[tier_num] or nil;
        local nextpts = nil;
        if (tier_num < maxtier) then
            nextpts = (tier_num + 1) * POINTS_PER_TIER;
        end

        results:append(T{
            name         = trait.name,
            label        = label,
            points       = base,
            effective    = effective,
            next         = nextpts,
            gift_exempt  = trait.gift_exempt,
            contributors = contributors,
        });
    end);

    -- Sort active traits first, then alphabetically..
    results:sort(function (a, b)
        local aa = a.label ~= nil;
        local bb = b.label ~= nil;
        if (aa ~= bb) then return aa; end
        return a.name < b.name;
    end);

    return results;
end

return data;
