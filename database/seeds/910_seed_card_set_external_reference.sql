-- Project Mimikyu
-- Query 910 - Seed Card Set External Reference
-- Status: CONFIRMADA EXECUTADA (PARCIAL — ME1/ME2/ME2.5/ME3/ME4)
-- Ver docs/05-modelo-de-dados.md, seção "Card Set External Reference",
-- "Query 910", para o contexto completo.
--
-- external_set_id descobertos via chamada real à TCGdex
-- (scripts/discover-tcgdex-sets.ts, execução confirmada, ver
-- docs/06-pipeline-importacao.md, Sprint B2.5A/B3).
--
-- ME0 deliberadamente NÃO incluído: existe um Set oficial `mee`
-- ("Mega Evolution Energy") na TCGdex, mas ainda não está confirmado
-- se ele corresponde exatamente à coleção interna ME0 (decisão de
-- negócio em aberto, cross-referenciada com a pendência "escopo
-- ENERGY" — ver docs/06-pipeline-importacao.md, "Em Aberto").
--
-- ME5 não inserido: card_set.code = 'ME5' ainda não existe no banco
-- físico (confirmado por consulta real) — o JOIN (não LEFT JOIN)
-- abaixo simplesmente não encontra correspondência para ME5, sem
-- gerar erro. Reexecutar esta Query depois que ME5 for cadastrado
-- populará o mapeamento automaticamente (idempotente).

begin;

insert into public.card_set_external_reference (
    card_set_id,
    asset_source_id,
    external_set_id,
    source_url
)
select
    cs.id,
    src.id,
    m.external_set_id,
    'https://api.tcgdex.net/v2/en/sets/' || m.external_set_id
from (
    values
        ('ME1', 'me01'),
        ('ME2', 'me02'),
        ('ME2.5', 'me02.5'),
        ('ME3', 'me03'),
        ('ME4', 'me04'),
        ('ME5', 'me05')
) as m(card_set_code, external_set_id)
join public.card_set cs
    on cs.code = m.card_set_code
join public.asset_source src
    on src.code = 'TCGDEX'
on conflict (card_set_id, asset_source_id)
do update set
    external_set_id = excluded.external_set_id,
    source_url = excluded.source_url,
    updated_at = now();

commit;
