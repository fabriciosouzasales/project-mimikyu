-- F3 — staging da coleção dc1 a partir do snapshot pokemontcg-snapshot-2026-10-09 (ADR-034).
-- Pré-requisito: F3-01 aplicado. Rodar primeiro como está (DRY_RUN, não grava nada).
-- Para gravar: trocar false por true na última linha e rodar de novo.
-- O texto entre $snap$ é o arquivo sets/dc1.json exato (SHA-256 68059f90b8a1728955ebdfca3cb4136f3536fcaa503b626af83b65904db5e53f).
SELECT internal.stage_pokemontcg_snapshot_set($snap${
  "set_id": "dc1",
  "total_count": 34,
  "cards": [
    {"id": "dc1-1", "number": "1", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-2", "number": "2", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil", "reverseHolofoil"]},
    {"id": "dc1-3", "number": "3", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-4", "number": "4", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-5", "number": "5", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil", "reverseHolofoil"]},
    {"id": "dc1-6", "number": "6", "rarity": "Rare Ultra", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dc1-7", "number": "7", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-8", "number": "8", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil", "reverseHolofoil"]},
    {"id": "dc1-9", "number": "9", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-10", "number": "10", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-11", "number": "11", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil", "reverseHolofoil"]},
    {"id": "dc1-12", "number": "12", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-13", "number": "13", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-14", "number": "14", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil", "reverseHolofoil"]},
    {"id": "dc1-15", "number": "15", "rarity": "Rare Ultra", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dc1-16", "number": "16", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-17", "number": "17", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-18", "number": "18", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-19", "number": "19", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-20", "number": "20", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-21", "number": "21", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil", "reverseHolofoil"]},
    {"id": "dc1-22", "number": "22", "rarity": "Common", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-23", "number": "23", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-24", "number": "24", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-25", "number": "25", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-26", "number": "26", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-27", "number": "27", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-28", "number": "28", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-29", "number": "29", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-30", "number": "30", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-31", "number": "31", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-32", "number": "32", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-33", "number": "33", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]},
    {"id": "dc1-34", "number": "34", "rarity": "Uncommon", "tcgplayer_price_keys": ["normal", "reverseHolofoil"]}
  ]
}
$snap$, false);
