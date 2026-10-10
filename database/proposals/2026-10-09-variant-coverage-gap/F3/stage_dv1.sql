-- F3 — staging da coleção dv1 a partir do snapshot pokemontcg-snapshot-2026-10-09 (ADR-034).
-- Pré-requisito: F3-01 aplicado. Rodar primeiro como está (DRY_RUN, não grava nada).
-- Para gravar: trocar false por true na última linha e rodar de novo.
-- O texto entre $snap$ é o arquivo sets/dv1.json exato (SHA-256 8c0b5d7fce388c88ff42ca24f23679ee2168920967b1ba8ba2e3de0afa1d06c5).
SELECT internal.stage_pokemontcg_snapshot_set($snap${
  "set_id": "dv1",
  "total_count": 21,
  "cards": [
    {"id": "dv1-1", "number": "1", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-2", "number": "2", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-3", "number": "3", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-4", "number": "4", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-5", "number": "5", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-6", "number": "6", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-7", "number": "7", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-8", "number": "8", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-9", "number": "9", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-10", "number": "10", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-11", "number": "11", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-12", "number": "12", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-13", "number": "13", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-14", "number": "14", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-15", "number": "15", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-16", "number": "16", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-17", "number": "17", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-18", "number": "18", "rarity": null, "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-19", "number": "19", "rarity": null, "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-20", "number": "20", "rarity": "Rare Holo", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "dv1-21", "number": "21", "rarity": null, "tcgplayer_price_keys": ["holofoil"]}
  ]
}
$snap$, false);
