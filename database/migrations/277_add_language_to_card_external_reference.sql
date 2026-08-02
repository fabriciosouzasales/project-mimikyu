/*
================================================================
Projeto.....: Project Mimikyu
Migration...: 277 - Add language_id to card_external_reference
Status......: MIGRATION — reconcilia um banco onde 210/211 (v1.0, sem
               language_id) já foram executadas. Instalação nova executa
               210 v2.0 / 211 v2.0 diretamente, sem esta Migration.
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-02

Descrição...:
`card_external_reference` (Query 210) tratava "referência externa de
uma Card" como independente de idioma — `UNIQUE (card_id,
asset_source_id)`, sem coluna própria de idioma. Isso fazia sentido
enquanto só o pipeline de imagens em inglês existia de verdade, mas
Fabrício pediu suporte real e simultâneo a EN + PT-BR ("os dois
idiomas") depois de notar que a importação automática nunca trazia as
imagens em português. A TCGdex devolve `image`/`name`/outros campos
DIFERENTES por idioma para a MESMA carta (mesmo `external_card_id`,
confirmado no teste real do Sprint B3.24 — `ME1-001` em `en` e
`pt-BR` são o mesmo identificador externo, com `image_source_url`
diferente); sem `language_id`, sincronizar a referência num segundo
idioma fazia `UPSERT` sobre a MESMA linha já usada pelo primeiro
(`ON CONFLICT (card_id, asset_source_id)`), sobrescrevendo o
`image_source_url`/`metadata` anterior — risco já sinalizado, e nunca
resolvido, desde o próprio teste do Sprint B3.23/B3.24.

Regras de Negócio (idênticas à Query 210 v2.0 — ver lá para o
raciocínio completo):
- `language_id` NOT NULL, FK para `language`.
- Backfill: toda linha já existente foi sincronizada em `en` (única
  importação em lote real até aqui — os testes controlados de
  `pt-BR` do Sprint B3.23/B3.24 tocaram só uma carta, `ME1-001`, e
  foram sobrescritos pela reversão para `en` do Sprint B3.24 antes de
  qualquer importação em lote) — todas as linhas recebem
  `language_id` de `en`.
- `uq_card_external_reference_card_source` (card_id, asset_source_id)
  vira `uq_card_external_reference_card_source_language` (+
  language_id) — cada (carta, fonte, idioma) agora tem sua própria
  linha.
- `uq_card_external_reference_source_external` (asset_source_id,
  external_card_id) vira `uq_card_external_reference_source_external_language`
  (+ language_id) — o `external_card_id` da TCGdex é o mesmo entre
  idiomas da mesma carta, então a unicidade por fonte+identificador
  externo também precisa do idioma para não colidir entre as duas
  línguas.
- `protect_card_external_reference_identity()` (Query 211) passa a
  proteger `language_id` também, mesmo tratamento já dado a
  id/card_id/asset_source_id.

Pré-requisitos: Query 210 v1.0 e Query 211 v1.0 já executadas
(banco pré-existente); Query 190 (language) com `en` cadastrado.
================================================================
*/

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.card_external_reference') IS NULL THEN
        RAISE EXCEPTION 'Migration 277 interrompida: public.card_external_reference não existe.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_external_reference'
          AND column_name = 'language_id'
    ) THEN
        RAISE EXCEPTION 'Migration 277 interrompida: language_id já existe em card_external_reference.';
    END IF;
END;
$$;

ALTER TABLE public.card_external_reference
    ADD COLUMN language_id UUID;

UPDATE public.card_external_reference
    SET language_id = (SELECT id FROM public.language WHERE code = 'en')
    WHERE language_id IS NULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.card_external_reference WHERE language_id IS NULL) THEN
        RAISE EXCEPTION 'Migration 277 interrompida: linhas sem language_id restantes após backfill (idioma en não cadastrado?).';
    END IF;
END;
$$;

ALTER TABLE public.card_external_reference
    ALTER COLUMN language_id SET NOT NULL;

ALTER TABLE public.card_external_reference
    ADD CONSTRAINT fk_card_external_reference_language
        FOREIGN KEY (language_id)
        REFERENCES public.language (id)
        ON DELETE RESTRICT;

ALTER TABLE public.card_external_reference
    DROP CONSTRAINT uq_card_external_reference_card_source;
ALTER TABLE public.card_external_reference
    ADD CONSTRAINT uq_card_external_reference_card_source_language
        UNIQUE (card_id, asset_source_id, language_id);

ALTER TABLE public.card_external_reference
    DROP CONSTRAINT uq_card_external_reference_source_external;
ALTER TABLE public.card_external_reference
    ADD CONSTRAINT uq_card_external_reference_source_external_language
        UNIQUE (asset_source_id, external_card_id, language_id);

CREATE INDEX IF NOT EXISTS ix_card_external_reference_language
    ON public.card_external_reference (language_id);

COMMENT ON COLUMN public.card_external_reference.language_id IS
    'Idioma desta referência externa — a mesma Card pode ter uma linha por idioma suportado (v2.0).';
COMMENT ON COLUMN public.card_external_reference.image_source_url IS
    'URL utilizada para aquisição automática da imagem original, específica do idioma desta linha.';
COMMENT ON COLUMN public.card_external_reference.metadata IS
    'Metadados adicionais da fonte externa em formato JSON, específicos do idioma desta linha.';

CREATE OR REPLACE FUNCTION public.protect_card_external_reference_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION
            'card_external_reference.id não pode ser alterado.';
    END IF;

    IF NEW.card_id IS DISTINCT FROM OLD.card_id THEN
        RAISE EXCEPTION
            'card_external_reference.card_id não pode ser alterado.';
    END IF;

    IF NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id THEN
        RAISE EXCEPTION
            'card_external_reference.asset_source_id não pode ser alterado.';
    END IF;

    IF NEW.language_id IS DISTINCT FROM OLD.language_id THEN
        RAISE EXCEPTION
            'card_external_reference.language_id não pode ser alterado.';
    END IF;

    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'card_external_reference'
          AND column_name = 'language_id'
          AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'Migration 277 falhou: language_id ausente ou nullable.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'fk_card_external_reference_language'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION 'Migration 277 falhou: FK para language ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'uq_card_external_reference_card_source_language'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION 'Migration 277 falhou: unicidade card/source/language ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'uq_card_external_reference_source_external_language'
          AND contype = 'u'
    ) THEN
        RAISE EXCEPTION 'Migration 277 falhou: unicidade source/external/language ausente.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.card_external_reference'::regclass
          AND conname = 'uq_card_external_reference_card_source'
    ) THEN
        RAISE EXCEPTION 'Migration 277 falhou: constraint antiga uq_card_external_reference_card_source ainda existe.';
    END IF;

    RAISE NOTICE 'MIGRATION 277 CONCLUÍDA: language_id ADICIONADO A CARD_EXTERNAL_REFERENCE';
END;
$$;

COMMIT;
