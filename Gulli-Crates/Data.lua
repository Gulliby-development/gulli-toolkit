-- The Waylaid Crates of WoW Forever and their bundles: any ONE bundle fills a crate.
-- Crate id -> { level, bundles = { { item id, count }, ... } }, in the order of the crate's tooltip.
-- Source (2026-11-14): wowforever.ninja "Waylaid Crates and Merchant's Favor", cross-checked with
-- urgametips.com "WoW: Forever Waylaid Crates Guide" (every bundle) and endgametools.com item 248691.
-- The game wins: Core.lua reads the crate's own tooltip ("- 10 Wintersbite") and uses its counts,
-- and finds a crate this table lacks when every line of its tooltip names a known item.

local _, ns = ...

ns.CRATES = {
    -- Apprentice (level 10)
    [248682] = { 10, { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },        -- Herbs
    [248683] = { 10, { { 2770, 20 }, { 2771, 20 } } },                                              -- Ore
    [248684] = { 10, { { 2589, 40 }, { 2318, 20 } } },                                              -- Textiles
    [248685] = { 10, { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },                   -- Curiosities
    [248702] = { 10, { { 4231, 2 }, { 2996, 20 } } },                                               -- Fabrics
    [248703] = { 10, { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },                                 -- Ingots
    [248704] = { 10, { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },                                 -- Parts
    -- Journeyman (level 10)
    [248686] = { 10, { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } },    -- Herbs
    [248687] = { 10, { { 2775, 10 }, { 2772, 20 } } },                                              -- Ore
    [248688] = { 10, { { 2592, 20 }, { 4306, 40 }, { 2319, 20 } } },                                 -- Textiles
    [248689] = { 10, { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },                   -- Curiosities
    [248705] = { 10, { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },                                   -- Fabrics
    [248706] = { 10, { { 2842, 10 }, { 3575, 20 } } },                                              -- Ingots
    [248707] = { 10, { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } },                     -- Parts
    -- Expert (level 20)
    [248690] = { 20, { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } },                   -- Earthly Herbs
    [248691] = { 20, { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } },                   -- Flowering Herbs
    [248692] = { 20, { { 2776, 10 }, { 3858, 20 } } },                                              -- Ore
    [248693] = { 20, { { 4338, 40 }, { 4234, 20 } } },                                              -- Textiles
    [248694] = { 20, { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },                   -- Curiosities
    [248708] = { 20, { { 4339, 8 }, { 4236, 2 } } },                                                -- Fabrics
    [248709] = { 20, { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } },                                 -- Ingots
    [248710] = { 20, { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } },                   -- Parts
    -- Artisan (level 35)
    [248695] = { 35, { { 13464, 10 }, { 8838, 20 }, { 8839, 10 }, { 8845, 10 }, { 8846, 10 } } },   -- Earthly Herbs
    [248696] = { 35, { { 13463, 20 }, { 13465, 20 }, { 13466, 20 }, { 13467, 20 } } },              -- Flowering Herbs
    [248697] = { 35, { { 7911, 10 }, { 10620, 20 }, { 11370, 20 } } },                               -- Ore
    [248698] = { 35, { { 14047, 40 }, { 4304, 20 }, { 8170, 20 } } },                                -- Textiles
    [248699] = { 35, { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } },                   -- Curiosities
    [248711] = { 35, { { 14048, 8 }, { 8172, 2 } } },                                               -- Fabrics
    [248712] = { 35, { { 11371, 2 }, { 6037, 10 }, { 12359, 20 } } },                                -- Ingots
    [248713] = { 35, { { 15994, 5 }, { 18631, 5 }, { 16000, 2 } } },                                 -- Parts
}
