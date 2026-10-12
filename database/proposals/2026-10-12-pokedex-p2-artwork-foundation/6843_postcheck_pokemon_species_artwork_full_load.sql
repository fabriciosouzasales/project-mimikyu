/*
===============================================================================
Projeto.....: Project Mimikyu — Pokédex P2 Lote D
Query.......: 6843 — Conferência pós-carga integral das imagens (SOMENTE LEITURA)
Versão......: 1.0 (2026-10-12)
Status......: PROPOSTA — executar depois da carga integral do importador.

Objetivo: confirmar 1.025/1.025 espécies IMPORTED, 2.050 objetos coerentes no
bucket pokemon-species-artwork, associação correta espécie↔arquivo↔referência
oficial, artwork_path devolvido para as 1.025 e preservação dos demais buckets
e de card_asset (hashes capturados no LIVE em 2026-10-12, antes do Lote D).

Nenhuma escrita: Bloco 1 é um SELECT; Bloco 2 roda em transação encerrada com
ROLLBACK (troca de papel para simular usuário autenticado).

Resultado esperado: todas as linhas com resultado = 'PASS' nos dois blocos.
Como validar: qualquer 'FAIL' mostra esperado × obtido na própria linha.
===============================================================================
*/

-- ============================================================================
-- Bloco 1 — Tabela, bucket, associação e preservação
-- ============================================================================
with
src as (select id from public.asset_source where code = 'POKEAPI'),
sp as (select id, national_dex_number from public.pokemon_species where is_active),
art as (
  select s.national_dex_number as n, a.*
    from public.pokemon_species_artwork a
    join public.pokemon_species s on s.id = a.pokemon_species_id
),
obj as (
  select name, (metadata->>'size')::bigint as size, metadata->>'mimetype' as mime
    from storage.objects where bucket_id = 'pokemon-species-artwork'
),
refs as (
  select n, original_storage_path as path, original_size_bytes as size, 'image/png' as mime from art where status = 'IMPORTED'
  union all
  select n, display_storage_path, display_size_bytes, 'image/webp' from art where status = 'IMPORTED'
),
checks(ordem, verificacao, esperado, obtido) as (
  values
  (1,  'Espécies ativas',                                   '1025', (select count(*) from sp)::text),
  (2,  'Espécies IMPORTED',                                 '1025', (select count(*) from art where status = 'IMPORTED')::text),
  (3,  'Espécies FAILED',                                   '0',    (select count(*) from art where status = 'FAILED')::text),
  (4,  'Espécies sem registro (pendentes)',                 '0',    (select count(*) from sp where not exists (select 1 from art where art.pokemon_species_id = sp.id))::text),
  (5,  'Objetos PNG no bucket',                             '1025', (select count(*) from obj where name like '%/original-%.png')::text),
  (6,  'Objetos WebP no bucket',                            '1025', (select count(*) from obj where name like '%/w320-%.webp')::text),
  (7,  'Objetos no bucket (total)',                         '2050', (select count(*) from obj)::text),
  (8,  'Caminhos registrados sem objeto (faltantes)',       '0',    (select count(*) from refs r where not exists (select 1 from obj o where o.name = r.path))::text),
  (9,  'Objetos sem registro (órfãos)',                     '0',    (select count(*) from obj o where not exists (select 1 from refs r where r.path = o.name))::text),
  (10, 'Tamanho/MIME do objeto ≠ registro',                 '0',    (select count(*) from refs r join obj o on o.name = r.path where o.size is distinct from r.size or o.mime is distinct from r.mime)::text),
  (11, 'Caminho fora da pasta da própria espécie',          '0',    (select count(*) from refs where path not like 'official-artwork/' || lpad(n::text, 4, '0') || '/%')::text),
  (12, 'Caminho sem o checksum do próprio arquivo',         '0',    (select count(*) from art where status = 'IMPORTED' and (
                                                                       original_storage_path <> 'official-artwork/' || lpad(n::text, 4, '0') || '/original-' || left(original_checksum_sha256, 16) || '.png'
                                                                    or display_storage_path  <> 'official-artwork/' || lpad(n::text, 4, '0') || '/w320-'     || left(display_checksum_sha256, 16)  || '.webp'))::text),
  (13, 'Origem ≠ referência oficial POKEAPI da espécie',    '0',    (select count(*) from art a where a.status = 'IMPORTED' and not exists (
                                                                       select 1 from public.pokemon_species_external_reference r
                                                                        where r.pokemon_species_id = a.pokemon_species_id and r.asset_source_id = (select id from src)
                                                                          and r.is_active and r.external_species_id = a.source_species_id))::text),
  (14, 'Mesmo original (checksum) em espécies diferentes',  '0',    (select count(*) from (select original_checksum_sha256 from art where status = 'IMPORTED' group by 1 having count(*) > 1) d)::text),
  (15, 'Dimensões fora do contrato (orig 64..4096, webp ≤ 320)', '0', (select count(*) from art where status = 'IMPORTED' and (
                                                                       original_width not between 64 and 4096 or original_height not between 64 and 4096
                                                                    or display_width > 320 or display_height > 320
                                                                    or display_width > original_width or display_height > original_height))::text),
  (16, 'Proporção alterada na conversão (> 2%)',            '0',    (select count(*) from art where status = 'IMPORTED'
                                                                     and abs(display_width::numeric / display_height - original_width::numeric / original_height) > 0.02)::text),
  (17, 'Originais fora de 475x475 (informativo)',           '0',    (select count(*) from art where status = 'IMPORTED' and (original_width <> 475 or original_height <> 475))::text),
  (18, 'rights_status ≠ THIRD_PARTY_UNLICENSED',            '0',    (select count(*) from art where rights_status <> 'THIRD_PARTY_UNLICENSED')::text),
  (19, 'Outros buckets: quantidade de objetos',             '31702', (select count(*) from storage.objects where bucket_id <> 'pokemon-species-artwork')::text),
  (20, 'Outros buckets: hash (nome+eTag+updated_at)',       '14ec9509ca7dd37940b2a0a582365909',
                                                            (select md5(string_agg(bucket_id || '/' || name || '|' || coalesce(metadata->>'eTag', '') || '|' || updated_at::text, ',' order by bucket_id, name))
                                                               from storage.objects where bucket_id <> 'pokemon-species-artwork')),
  (21, 'card_asset: quantidade',                            '31466', (select count(*) from public.card_asset)::text),
  (22, 'card_asset: hash do conteúdo',                      'c8e71a73954d264bd857851d3fe1fde3',
                                                            (select md5(string_agg(t::text, ',' order by t::text)) from public.card_asset t))
)
select ordem, verificacao, esperado, obtido,
       case when esperado = obtido then 'PASS'
            when ordem = 17 then 'AVISO'   -- original fora de 475 é válido; só registrar
            else 'FAIL' end as resultado
  from checks
 order by ordem;

-- ============================================================================
-- Bloco 2 — artwork_path pela função do colecionador (usuário autenticado)
-- Executar separadamente, inteiro (BEGIN ... ROLLBACK).
-- ============================================================================
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000006843","role":"authenticated"}';

with f as (select * from public.get_pokedex_national_species(null, null))
select count(*)                                                        as especies,               -- esperado 1025
       count(*) filter (where artwork_path is not null)                as com_artwork_path,       -- esperado 1025
       count(*) filter (where artwork_path !~ ('^official-artwork/' || lpad(national_dex_number::text, 4, '0') || '/w320-[0-9a-f]{16}\.webp$'))
                                                                       as caminho_incoerente,     -- esperado 0
       case when count(*) = 1025
             and count(*) filter (where artwork_path is not null) = 1025
             and count(*) filter (where artwork_path !~ ('^official-artwork/' || lpad(national_dex_number::text, 4, '0') || '/w320-[0-9a-f]{16}\.webp$')) = 0
            then 'PASS' else 'FAIL' end                                as resultado
  from f;

rollback;
