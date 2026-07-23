/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 820 - Seed Card Set
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Insere os Card Sets regulares/especiais da Expansion Mega Evolution (ME),
com dados validados contra as folhas oficiais de verificação arquivadas em
assets/reference-sources/.
Card Sets inseridos:
- ME1   - Megaevolução        (REGULAR)
- ME2   - Fogo Fantasmagórico (REGULAR)
- ME2.5 - Heróis Excelsos     (SPECIAL)
- ME3   - Equilíbrio Perfeito (REGULAR)
- ME4   - Caos Ascendente     (REGULAR)
Regras de Negócio:
- Os Card Sets devem ser vinculados ao Game POKEMON e à Expansion ME.
- Os UUIDs das entidades relacionadas não devem ser informados diretamente.
- A execução deve ser idempotente.
- Uma nova execução não pode gerar registros duplicados.
- Os nomes usam o idioma atualmente adotado pelo catálogo (português), com
  base nas folhas oficiais disponíveis — nunca uma tradução não-oficial.
- A quantidade de cartas secretas não é armazenada diretamente.
PENDÊNCIA (ver docs/05-modelo-de-dados.md, seção Set, "Pendência — Reescrita
da Query 820"): esta versão ainda NÃO inclui o Card Set promocional (ME0,
inserido separadamente por 821_seed_promo_card_set.sql). Decisão já tomada
de consolidar tudo aqui, usando ON CONFLICT ... DO UPDATE em vez de
DO NOTHING — SQL reescrito ainda não apresentado/executado.
===============================================================================
*/

INSERT INTO public.card_set (
    expansion_id, code, name, set_type, release_order,
    release_date, base_set_size, total_set_size
)
SELECT
    expansion.id, seed.code, seed.name, seed.set_type, seed.release_order,
    seed.release_date, seed.base_set_size, seed.total_set_size
FROM public.expansion
INNER JOIN public.game ON game.id = expansion.game_id
CROSS JOIN (
    VALUES
        ('ME1',   'Megaevolução',         'REGULAR', 1, DATE '2025-09-26', 132, 188),
        ('ME2',   'Fogo Fantasmagórico',  'REGULAR', 2, DATE '2025-11-14',  94, 130),
        ('ME2.5', 'Heróis Excelsos',      'SPECIAL', 3, DATE '2026-01-30', 217, 295),
        ('ME3',   'Equilíbrio Perfeito',  'REGULAR', 4, DATE '2026-03-27',  88, 124),
        ('ME4',   'Caos Ascendente',      'REGULAR', 5, DATE '2026-05-22',  86, 122)
) AS seed (code, name, set_type, release_order, release_date, base_set_size, total_set_size)
WHERE game.code = 'POKEMON'
  AND expansion.code = 'ME'
ON CONFLICT (expansion_id, code) DO NOTHING;
