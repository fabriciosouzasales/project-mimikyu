/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5260 - remove_layout_page: referências de espécie exigem
              confirmação explícita (ajuste B)
              remove_layout_page(uuid, integer) — NOVA: confirmação com a contagem
              remove_layout_page(uuid)          — CREATE OR REPLACE: delega com 0
Versão......: 1.0 (2026-10-24, POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-24
              (LIVE-EXECUTION-01, autorização expressa de Fabrício; ledger
              20261024163750 `5260_update_remove_layout_page_species_references`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-24-pokedex-
              binder-species-reference/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo (md5). Harness 5857
              não executado. Ver LIVE-EXECUTION-2026-10-24.md da proposta.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Ajuste B aprovado: "Não apagar referências silenciosamente por uma ação cuja
consequência não esteja clara para o usuário."

  - Corpo da 5235 preservado passo a passo (resolve owner-scoped → trava
    5122 → trava da página → revalidação → recusas por carta, reserva,
    mesclagem e imagem → exclusão + renumeração). Único acréscimo: passo
    5b, depois das quatro recusas existentes.
  - 5b: a página tem N referências de espécie (da proprietária atual).
      p_confirm_species_references = N → apaga as N referências e segue;
      qualquer outro valor (inclusive 0 e NULL) → recusa com
        'page has N species reference(s) — confirm their removal before deleting the page'
        HINT 'SPECIES_REFERENCES_ON_PAGE:N'
      sem tocar em nada. A interface mostra o aviso com N e repete a
      chamada com N quando o usuário confirmar.
  - Página sem referências: comportamento IDÊNTICO ao da 5235 (o valor de
    confirmação é ignorado).
  - A assinatura de 1 argumento (5126/5235) continua existindo e passa a
    delegar com confirmação 0: para página sem referências nada muda; para
    página com referências passa a recusar (antes da 5260 elas seriam
    apagadas por CASCADE sem aviso).
  - Referências de proprietária antiga (fichário transferido, ocultas)
    também são apagadas junto com a página — são invisíveis e não têm
    leitura; entram na contagem só as da proprietária atual, as demais
    seguem a exclusão do bolso (CASCADE da 5257).
  - Desmontagem do fichário inteiro (5242) NÃO muda: apaga páginas/bolsos e,
    por CASCADE, as referências — consequência explícita da própria ação.
  - Grants: as duas assinaturas EXECUTE só para authenticated.

Hoje a interface não oferece remover página (nenhum chamador no web/);
a recusa vale para qualquer chamada direta à RPC.
Dependências: 5257, 5235, 5122.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_slot_species_reference') is null then
    raise exception 'PRECHECK 5260: aplique a 5257 antes';
  end if;
  if to_regprocedure('public.remove_layout_page(uuid)') is null
     or to_regclass('public.collection_layout_slot_image') is null then
    raise exception 'PRECHECK 5260: 5235 ausente';
  end if;
  if to_regprocedure('public.remove_layout_page(uuid, integer)') is not null then
    raise exception 'PRECHECK 5260: remove_layout_page(uuid, integer) já existe';
  end if;
end;
$pre$;

CREATE FUNCTION public.remove_layout_page(
    p_page_id                    UUID,
    p_confirm_species_references INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_layout_id   UUID;
    v_page_number INTEGER;
    v_count       INTEGER;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED (5235).
    SELECT p.layout_id
      INTO v_layout_id
      FROM public.collection_layout_page p
      JOIN public.collection_layout l ON l.id = p.layout_id
      JOIN public.collection c        ON c.id = l.collection_id
     WHERE p.id = p_page_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout page not found or not owned by caller';
    END IF;

    -- 2) COLLECTION LOCK -> LAYOUT LOCK (helper 5122) + ACTIVE.
    BEGIN
        PERFORM public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout page not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 3) PAGE LOCK.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.id = p_page_id
        AND p.layout_id = v_layout_id
      FOR UPDATE;

    -- 4) REVALIDAÇÃO PÓS-LOCK.
    SELECT p.page_number
      INTO v_page_number
      FROM public.collection_layout_page p
     WHERE p.id = p_page_id
       AND p.layout_id = v_layout_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout page not found or not owned by caller';
    END IF;

    -- 5) Estado dos filhos (5235), lido pós-lock.
    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_assignment a
      JOIN public.collection_layout_slot s ON s.id = a.slot_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % slot assignment(s) — remove them before deleting the page', v_count;
    END IF;

    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_expected_content e
      JOIN public.collection_layout_slot s ON s.id = e.slot_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % expected content entr(y/ies) — clear them before deleting the page', v_count;
    END IF;

    SELECT count(*) INTO v_count
      FROM public.collection_layout_region r
     WHERE r.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % layout region(s) — unmerge them before deleting the page', v_count;
    END IF;

    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_image i
      JOIN public.collection_layout_slot s ON s.id = i.slot_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'page has % custom image(s) — remove them before deleting the page', v_count;
    END IF;

    -- 5b) 5260 (ajuste B): referências de espécie da proprietária atual exigem
    -- confirmação com a contagem exata; nunca são apagadas em silêncio.
    SELECT count(*) INTO v_count
      FROM public.collection_layout_slot_species_reference sr
      JOIN public.collection_layout_slot s ON s.id = sr.slot_id
      JOIN public.collection_layout l      ON l.id = sr.layout_id AND l.collection_id = sr.collection_id
     WHERE s.page_id = p_page_id;

    IF v_count > 0 THEN
        IF p_confirm_species_references IS DISTINCT FROM v_count THEN
            RAISE EXCEPTION
                'page has % species reference(s) — confirm their removal before deleting the page', v_count
                USING HINT = 'SPECIES_REFERENCES_ON_PAGE:' || v_count;
        END IF;
    END IF;

    DELETE FROM public.collection_layout_slot_species_reference sr
     USING public.collection_layout_slot s
     WHERE s.id = sr.slot_id
       AND s.page_id = p_page_id;

    -- 6) MUTAÇÃO, com o page_number pós-lock (5235).
    DELETE FROM public.collection_layout_page
     WHERE id = p_page_id;

    UPDATE public.collection_layout_page
       SET page_number = page_number - 1
     WHERE layout_id   = v_layout_id
       AND page_number > v_page_number;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.remove_layout_page(uuid, integer)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_layout_page(uuid, integer)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_layout_page(
    p_page_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- 5260: mesma operação, sem confirmação de referências (0).
    PERFORM public.remove_layout_page(p_page_id, 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.remove_layout_page(uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_layout_page(uuid)
    TO authenticated;

COMMIT;

/*
Como reverter: reaplicar o bloco BEGIN..COMMIT da 5235 (1 argumento) e
  DROP FUNCTION public.remove_layout_page(uuid, integer);
Atenção: depois da reversão, remover uma página com referências volta a
apagá-las por CASCADE sem aviso.
*/
