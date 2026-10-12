/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2268 - Estado ativo/inativo de Card Variant + trava de novos vínculos — P2b
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-12, apply_migration no LIVE, versão 20261012031352, autorizado por
              Fabrício após ensaio PASS 11/11). Validação: 0 inativas, CHECK 1, 4 triggers.
              Pós-P2b: 37.881 variantes (todas ativas), 156.706 produtos de preço, 715 sem variante,
              log 2.017, Collections 0 vínculos — iguais ao pré; demais funções inalteradas (hash).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — P2b aprovada (Queries 2268–2270): desativar/reativar variante
              individualmente, preservando todo vínculo histórico e impedindo vínculos novos com
              variante inativa.
Ordem.......: 2268 → 2269 → 2270 (as três num mesmo envio no ensaio).

O que faz
  1. card_variant.is_active boolean NOT NULL DEFAULT true. Default constante: o PostgreSQL grava só
     no catálogo, sem reescrever as ~37,9 mil linhas.
  2. CHECK ck_card_variant_default_active (is_active OR NOT is_default): a variante padrão nunca
     fica inativa. Barreira final; a RPC 2270 dá a mensagem legível antes.
  3. internal.guard_card_variant_reference_active(): BEFORE INSERT OR UPDATE OF card_variant_id em
     pricing_product, physical_card, collection_master_set_scope e
     collection_layout_slot_expected_content. Recusa (SQLSTATE MV001, CARD_VARIANT_INACTIVE) apontar
     uma linha NOVA, ou TROCAR o card_variant_id de uma linha, para variante inativa. Linhas
     existentes e UPDATEs que não mudam card_variant_id passam intactos (histórico preservado).
     Lê a variante com FOR SHARE: se uma desativação estiver em curso na mesma variante, espera o
     COMMIT dela e decide sobre o estado final (sem janela de corrida). SECURITY DEFINER porque
     card_variant tem RLS admin-only e physical_card é gravado por usuários comuns.

Lock
  ALTER TABLE pega ACCESS EXCLUSIVE em card_variant por instantes (coluna com default constante +
  CHECK validado em ~37,9 mil linhas). lock_timeout 5 s: se a tabela estiver ocupada, a migration
  falha inteira sem efeito e basta reenviar.

Como validar
  select (select count(*) from public.card_variant where not is_active) as inativas_must_be_0,
         (select count(*) from pg_constraint where conname = 'ck_card_variant_default_active') as check_must_be_1,
         (select count(*) from pg_trigger where tgname = 'trg_guard_card_variant_active' and not tgisinternal) as triggers_must_be_4;
===============================================================================
*/

SET LOCAL lock_timeout = '5s';

-- 1–2. Coluna e regra "padrão sempre ativa"
ALTER TABLE public.card_variant
  ADD COLUMN is_active boolean NOT NULL DEFAULT true,
  ADD CONSTRAINT ck_card_variant_default_active CHECK (is_active OR NOT is_default);

COMMENT ON COLUMN public.card_variant.is_active IS
  'P2b (2268). false = variante desativada pelo admin: preserva histórico (preços, inventário, Collections), mas não aceita vínculos novos. Só public.admin_set_card_variant_active (2270) altera.';

-- 3. Trava de vínculos novos
CREATE OR REPLACE FUNCTION internal.guard_card_variant_reference_active()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_active boolean;
BEGIN
  IF NEW.card_variant_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.card_variant_id IS NOT DISTINCT FROM OLD.card_variant_id THEN
    RETURN NEW;
  END IF;

  SELECT v.is_active INTO v_active
    FROM public.card_variant v
   WHERE v.id = NEW.card_variant_id
     FOR SHARE;

  IF v_active IS FALSE THEN
    RAISE EXCEPTION 'CARD_VARIANT_INACTIVE: a variação % está inativa e não aceita novos vínculos.', NEW.card_variant_id
      USING ERRCODE = 'MV001';
  END IF;
  -- Variante inexistente: a FK de cada tabela continua sendo a autoridade.
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.guard_card_variant_reference_active() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_guard_card_variant_active
  BEFORE INSERT OR UPDATE OF card_variant_id ON public.pricing_product
  FOR EACH ROW EXECUTE FUNCTION internal.guard_card_variant_reference_active();

CREATE TRIGGER trg_guard_card_variant_active
  BEFORE INSERT OR UPDATE OF card_variant_id ON public.physical_card
  FOR EACH ROW EXECUTE FUNCTION internal.guard_card_variant_reference_active();

CREATE TRIGGER trg_guard_card_variant_active
  BEFORE INSERT OR UPDATE OF card_variant_id ON public.collection_master_set_scope
  FOR EACH ROW EXECUTE FUNCTION internal.guard_card_variant_reference_active();

CREATE TRIGGER trg_guard_card_variant_active
  BEFORE INSERT OR UPDATE OF card_variant_id ON public.collection_layout_slot_expected_content
  FOR EACH ROW EXECUTE FUNCTION internal.guard_card_variant_reference_active();
