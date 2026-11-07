/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5355 - get_rarity_catalog(): nomes e ordem oficiais das raridades do
              catálogo Pokémon para leitura do colecionador (V1-14 R1-H)
Versão......: 0.1
Status......: PROPOSTO — NÃO EXECUTADO (R1-H FUNCTIONAL CONTRACT APPROVAL & QUERY 5355 PROPOSAL-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-07

Objetivo
  O relatório "Distribuição por Set, raridade e idioma" agrupa o acervo pelo `rarity_code`
  que a 5159 já devolve (rarity.code da CARTA). Falta o nome oficial ("Ilustração Rara") e a
  ordem do catálogo (`display_order`): `public.rarity` só é legível por administrador
  (policy catalog_admin_select, migrations 274/2134). Esta função expõe SOMENTE esses
  metadados de catálogo — nada pessoal, nada de outro domínio — sem mexer na RLS.
  Raridades futuras aparecem sozinhas (lê a tabela vigente; nenhum mapa no front).

Esquema validado (database/schema/130_create_rarity_table.sql; conferido de novo no harness 5883)
  rarity(id uuid PK, game_id uuid NOT NULL → game, code varchar(50) NOT NULL,
         name varchar(150) NOT NULL, symbol_code varchar(50) NOT NULL,
         display_order integer NOT NULL CHECK > 0, created_at, updated_at)
  UNIQUE (game_id, code) — code é a chave estável; display_order NÃO é único (desempate
  por code). game(code varchar(50) UNIQUE) — catálogo Pokémon = game.code 'POKEMON'.

Contrato
  get_rarity_catalog()
  RETURNS TABLE(code text, name text, symbol_code text, display_order integer)
  - Todas as raridades do Game POKEMON, ordenadas por display_order, code (determinístico).
  - Uma linha por code (UNIQUE (game_id, code)). Sem parâmetros (nada para validar/injetar).
  - Compatível com a 5159: mesmo `rarity.code::text` que ela devolve em `rarity_code`.
  - Sem id, game_id, datas nem colunas futuras: o retorno é explícito.

Segurança
  SECURITY DEFINER — justificativa e alternativas avaliadas:
  (a) nova policy de SELECT para authenticated em public.rarity → proibido (não alterar a
      RLS do catálogo) e mais amplo: exporia toda linha/coluna atual e futura da tabela;
  (b) view com security_invoker = false → mesmo privilégio do dono, porém sem verificação
      de sessão e mais fácil de ampliar por engano (SELECT * em evolução da view);
  (c) SECURITY INVOKER → não funciona: o colecionador não passa na catalog_admin_select.
  Escolhida a função DEFINER: colunas fixas, filtro fixo no Game POKEMON, exige sessão
  (auth.uid(); sem sessão → 28000), STABLE, somente leitura, search_path '' com objetos
  qualificados, EXECUTE só para authenticated (revogado de PUBLIC e anon). Dono postgres
  (padrão das RPCs existentes 5159/5354).
Desempenho
  ~20 linhas, leitura pela PK de game (uq code) + filtro em rarity.game_id; esperado < 1 ms.
  Chamada única por abertura do relatório (em paralelo com a 5160), resposta de poucos KB.
================================================================
*/

create or replace function public.get_rarity_catalog()
returns table (
  code          text,
  name          text,
  symbol_code   text,
  display_order integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'RARITY_CATALOG_REQUIRES_AUTHENTICATION' using errcode = '28000';
  end if;

  return query
  select r.code::text, r.name::text, r.symbol_code::text, r.display_order
  from public.rarity r
  join public.game g on g.id = r.game_id
  where g.code = 'POKEMON'
  order by r.display_order, r.code;
end;
$$;

revoke all on function public.get_rarity_catalog() from public;
revoke all on function public.get_rarity_catalog() from anon;
grant execute on function public.get_rarity_catalog() to authenticated;

comment on function public.get_rarity_catalog() is
  'V1-14 R1-H (Query 5355): nomes e ordem oficiais das raridades do catálogo Pokémon (code, name, symbol_code, display_order), para o colecionador autenticado. Somente leitura; sem parâmetros; não altera a RLS de public.rarity.';
