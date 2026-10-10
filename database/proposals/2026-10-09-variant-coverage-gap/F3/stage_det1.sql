-- F3 — staging da coleção det1 a partir do snapshot pokemontcg-snapshot-2026-10-09 (ADR-034).
-- Pré-requisito: F3-01 aplicado. Rodar primeiro como está (DRY_RUN, não grava nada).
-- Para gravar: trocar false por true na última linha e rodar de novo.
-- O texto entre $snap$ é o arquivo sets/det1.json exato (SHA-256 f7927b13d5500f57cc93759c6f4c3b025dbd372ba63b6cf183ea52ca091db82f).
SELECT internal.stage_pokemontcg_snapshot_set($snap${
  "set_id": "det1",
  "total_count": 18,
  "cards": [
    {"id": "det1-1", "number": "1", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-2", "number": "2", "rarity": "Rare", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-3", "number": "3", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-4", "number": "4", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-5", "number": "5", "rarity": "Rare Ultra", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-6", "number": "6", "rarity": "Rare", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-7", "number": "7", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-8", "number": "8", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-9", "number": "9", "rarity": "Rare Ultra", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-10", "number": "10", "rarity": "Rare", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-11", "number": "11", "rarity": "Rare", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-12", "number": "12", "rarity": "Rare Ultra", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-13", "number": "13", "rarity": "Rare", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-14", "number": "14", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-15", "number": "15", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-16", "number": "16", "rarity": "Common", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-17", "number": "17", "rarity": "Rare Ultra", "tcgplayer_price_keys": ["holofoil"]},
    {"id": "det1-18", "number": "18", "rarity": "Rare", "tcgplayer_price_keys": ["holofoil"]}
  ]
}
$snap$, false);
