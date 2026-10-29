/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5293 - P3-B S6 · Histórico do Fichário — instrumentação E19b (Fichário vazio removido)
              delete_collection_layout(uuid)
Versão......: 1.0 (2026-10-28, P3-B S6 — instrumentação E01, E16–E20)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (P3-B S6, autorização
              operacional do proprietário; harness dispensado sob H-A; ledger 20261028215642 `5293_instrument_delete_collection_layout`).
              Do `begin;` ao `commit;` idêntica ao arquivo de database/proposals/2026-10-25-
              p3b-binder-activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — texto do ledger = corpo (md5).
              LIVE_S6_90 bloco A 6/6; E19b NÃO exercitado dinamicamente (sem caminho no frontend).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5124 (md5(prosrc) LIVE 1b4bf89732af4ef36c834a30b08fec44, conferido em 2026-10-28;
              canônico: database/schema/5124_create_delete_collection_layout_function.sql).
Autoridade..: README da proposta §4.1, §4.2, §14.7, §20 (W3), §33 (S6).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S6". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s6.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento BINDER_DELETED_EMPTY (atômico): 1 item BINDER/CLOSED {reason: EMPTY}, gravado antes do
DELETE. Sem caminho na interface atual (executável por authenticated).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null then
    raise exception 'PRECHECK 5293: dependências ausentes (5268/5271/5275/5279)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.delete_collection_layout(uuid)')) is distinct from '1b4bf89732af4ef36c834a30b08fec44' then
    raise exception 'PRECHECK 5293: função no LIVE diverge da base 5124 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.delete_collection_layout(
    p_layout_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
    v_page_count INTEGER;
BEGIN
    PERFORM public.assert_collection_layout_mutable(p_layout_id);

    SELECT count(*) INTO v_page_count
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    IF v_page_count > 0 THEN
        RAISE EXCEPTION
            'layout has % page(s) — remove all pages before deleting the layout', v_page_count;
    END IF;

    -- E19b: registro ANTES de apagar (o cabeçalho lê o fichário); o histórico sobrevive (A1).  -- P3B-S6
    PERFORM public.binder_activity_begin(p_layout_id, 'BINDER_DELETED_EMPTY', 'FICHARIO');  -- P3B-S6
    PERFORM public.binder_activity_add_item('BINDER', 'CLOSED', NULL, NULL, NULL, NULL, NULL, NULL,  -- P3B-S6
                                            jsonb_build_object('reason', 'EMPTY'));  -- P3B-S6
    DELETE FROM public.collection_layout
     WHERE id = p_layout_id;
    PERFORM public.binder_activity_end();  -- P3B-S6
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.delete_collection_layout(uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_collection_layout(uuid)
    TO authenticated;

commit;

/*
Resultado esperado: delete_collection_layout(uuid) recriada com o mesmo contrato; nenhum evento gravado pela instalação.
Como validar (só leitura): LIVE_S6_90_postcheck_readonly.sql, bloco A.
*/
