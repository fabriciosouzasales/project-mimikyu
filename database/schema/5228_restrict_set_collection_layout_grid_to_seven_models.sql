/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5228 - Fichário Digital (P2-A1): set_collection_layout_grid
              aceita só os sete modelos aprovados (D2)
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-A1-LIVE-APPLY-01, autorização expressa de Fabrício; ledger
              20261023120522 `5228_restrict_set_collection_layout_grid_to_seven_models`). Do `begin;` ao `commit;`
              byte a byte idêntica ao texto aplicado e ao arquivo da pasta
              database/proposals/2026-10-22-p2-a1-digital-binder/ (só este
              bloco Status difere). Pós-checagens estruturais 10/10 PASS;
              comportamento SEM prova comportamental; tetos provisórios.
Autor.......: Fabrício Sales / Claude
Ordem do pacote: 5225 → 5223 → 5224 → 5226 → 5227 → 5228 (independente das
              anteriores no banco; fica por último porque fecha D2 depois
              que o único caminho de criação — 5224 — já valida D2).

──────────────────────────────────────────────────────────────────────
CONTRATO VIGENTE (investigado)
  Há UMA função: public.set_collection_layout_grid(uuid, integer, integer)
  → TABLE(id uuid, collection_id uuid, grid_rows integer, grid_columns
  integer), plpgsql, SECURITY DEFINER, search_path ''. A 5137 a criou e a
  5141 (CREATE OR REPLACE, mesma assinatura) só qualificou o UPDATE; a
  definição canônica efetiva é database/schema/5137 v1.1 (5141 foldada).
  5137 e 5141 NÃO são dois pontos de entrada. Grants: REVOKE PUBLIC/anon,
  GRANT authenticated. Nenhum chamador em web/, supabase/ ou em outra
  função SQL (só harness 5818 e READMEs).

  Regras atuais, todas preservadas, na mesma ordem:
    1. auth.uid() obrigatório;
    2. assert_collection_layout_mutable (5122): trava coleção → layout,
       dono (não enumera: 'collection layout not found or not owned by
       caller') e coleção ACTIVE ('collection is ARCHIVED …');
    3. rows/columns não nulos e entre 1 e 10;
    4. ZERO páginas, contadas depois da trava (mensagem existente);
    5. UPDATE do grid (trigger 5107 continua como defesa estrutural);
    6. devolve a linha do layout.

POR QUE (D2)
  Um fichário montado pode ter todas as páginas removidas (5126 aceita a
  última página vazia) e, com zero páginas, a grade podia ir para qualquer
  formato 1..10 × 1..10 — fora dos sete modelos aprovados.

O QUE MUDA (mínimo)
  CREATE OR REPLACE com a MESMA assinatura, o MESMO retorno, a mesma
  linguagem, SECURITY DEFINER e search_path. Entre a regra 3 e a 4 entra:
    (p_grid_columns, p_grid_rows) ∈ {(2,2),(3,3),(3,4),(4,3),(4,4),(4,5),(5,4)}
    — convenção colunas × linhas ("3×4" = 3 colunas, 4 linhas) —, senão
    22023 'INVALID_GRID: …'. Nada é gravado na recusa.
  CREATE OR REPLACE preserva a ACL; os REVOKE/GRANT ao final apenas
  reafirmam a matriz (idempotentes).

O QUE NÃO MUDA
  - Nenhum dado é tocado por esta query: layouts preexistentes fora dos
    sete modelos continuam como estão, legíveis (5223) e editáveis em
    conteúdo. Só não podem RECEBER, por esta RPC, uma grade fora da lista
    (inclusive reafirmar a própria grade antiga). Trocar para um dos sete
    continua possível nas condições de sempre (zero páginas).
  - Não cria fluxo de troca de modelo, migração de posições nem
    reorganização automática.
  - Coleção arquivada e coleção de outro usuário: mesmas recusas de hoje
    (vêm da 5122, antes da validação de modelo).
================================================================
*/

begin;

do $pre$
declare
  v_oid oid := to_regprocedure('public.set_collection_layout_grid(uuid, integer, integer)');
begin
  if v_oid is null then
    raise exception 'PRECHECK 5228: set_collection_layout_grid(uuid, integer, integer) ausente';
  end if;
  if pg_get_function_result(v_oid) <> 'TABLE(id uuid, collection_id uuid, grid_rows integer, grid_columns integer)' then
    raise exception 'PRECHECK 5228: retorno diferente do canônico 5137 v1.1: %', pg_get_function_result(v_oid);
  end if;
  -- O corpo vivo precisa ser o da 5141 (UPDATE qualificado) e ainda sem a
  -- regra dos sete modelos.
  if (select position('WHERE l.id = p_layout_id' in p.prosrc) = 0 from pg_proc p where p.oid = v_oid) then
    raise exception 'PRECHECK 5228: corpo vivo difere da 5137 v1.1 / 5141';
  end if;
  if (select position('INVALID_GRID' in p.prosrc) > 0 from pg_proc p where p.oid = v_oid) then
    raise exception 'PRECHECK 5228: regra dos sete modelos já presente';
  end if;
  if to_regprocedure('public.assert_collection_layout_mutable(uuid)') is null then
    raise exception 'PRECHECK 5228: assert_collection_layout_mutable (5122) ausente';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.set_collection_layout_grid(
    p_layout_id    UUID,
    p_grid_rows    INTEGER,
    p_grid_columns INTEGER
)
RETURNS TABLE (
    id            UUID,
    collection_id UUID,
    grid_rows     INTEGER,
    grid_columns  INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id UUID;
    v_page_count    INTEGER;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) COLLECTION LOCK -> LAYOUT LOCK + ACTIVE + ownership (5122).
    v_collection_id := public.assert_collection_layout_mutable(p_layout_id);

    -- 2) Domínio do grid (5137).
    IF p_grid_rows IS NULL OR p_grid_columns IS NULL THEN
        RAISE EXCEPTION 'p_grid_rows e p_grid_columns são obrigatórios';
    END IF;

    IF p_grid_rows < 1 OR p_grid_rows > 10
       OR p_grid_columns < 1 OR p_grid_columns > 10 THEN
        RAISE EXCEPTION
            'grid inválido: rows e columns devem estar entre 1 e 10 (recebido % x %)',
            p_grid_rows, p_grid_columns;
    END IF;

    -- 2b) 5228 (D2): só os sete modelos Normais, colunas × linhas.
    IF (p_grid_columns, p_grid_rows) NOT IN ((2,2), (3,3), (3,4), (4,3), (4,4), (4,5), (5,4)) THEN
        RAISE EXCEPTION
            'INVALID_GRID: modelo % colunas × % linhas fora dos sete aprovados (2×2, 3×3, 3×4, 4×3, 4×4, 4×5, 5×4)',
            p_grid_columns, p_grid_rows
            USING ERRCODE = '22023';
    END IF;

    -- 3) REVALIDAÇÃO PÓS-LOCK: Pages contadas depois da trava (5137).
    SELECT count(*) INTO v_page_count
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    IF v_page_count > 0 THEN
        RAISE EXCEPTION
            'grid do Layout não pode ser alterado enquanto existirem Pages — remova as % Page(s) primeiro (Grid Change com Pages existentes é DEFERRED)',
            v_page_count;
    END IF;

    -- 4) MUTAÇÃO (5141: tabela aliasada, coluna qualificada). 5107 revalida.
    UPDATE public.collection_layout AS l
       SET grid_rows    = p_grid_rows,
           grid_columns = p_grid_columns
     WHERE l.id = p_layout_id;

    RETURN QUERY
    SELECT l.id, l.collection_id, l.grid_rows, l.grid_columns
      FROM public.collection_layout l
     WHERE l.id = p_layout_id;
END;
$$;

COMMENT ON FUNCTION public.set_collection_layout_grid(uuid, integer, integer) IS
  'Binder Foundation (5137/5141) restrita pela 5228 (P2-A1, D2): altera a grade de um layout do próprio usuário, com coleção ACTIVE e ZERO páginas, apenas para um dos sete modelos (colunas × linhas: 2×2, 3×3, 3×4, 4×3, 4×4, 4×5, 5×4); outro par → 22023 INVALID_GRID sem gravar. Assinatura, retorno e demais regras inalterados.';

REVOKE EXECUTE ON FUNCTION public.set_collection_layout_grid(uuid, integer, integer)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_layout_grid(uuid, integer, integer)
    TO authenticated;

-- Pós-checagem (falha alto e desfaz tudo se a matriz efetiva divergir).
do $post$
declare
  v_oid oid := to_regprocedure('public.set_collection_layout_grid(uuid, integer, integer)');
begin
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or has_function_privilege('anon', v_oid, 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_oid and a.grantee = 0) then
    raise exception 'POSTCHECK 5228: matriz de EXECUTE divergente do esperado (authenticated sim; anon/PUBLIC não)';
  end if;
  if (select not (p.prosecdef and p.proconfig @> array['search_path=""']) from pg_proc p where p.oid = v_oid) then
    raise exception 'POSTCHECK 5228: SECURITY DEFINER/search_path divergentes';
  end if;
end;
$post$;

notify pgrst, 'reload schema';

commit;

/*
Reversão: reaplicar o corpo canônico de database/schema/5137 v1.1 (sem o
bloco 2b). Não há dado a desfazer.

Como validar: harness 5850, 0.9 (estrutura/privilégios) e 14.1–14.6.
*/
