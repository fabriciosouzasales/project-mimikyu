-- STATUS: PROPOSTA -- ainda NAO aplicada em producao. Testada em BEGIN/ROLLBACK nesta
-- rodada (P16.5.1, item 2 do escopo autorizado por Fabricio em 2026-08-26). Aguarda
-- autorizacao explicita para aplicacao real.
--
-- Contexto: staging durável do payload externo adquirido durante a fase ACQUIRING do
-- bootstrap, chaveado por (pricing_set_mapping_id, external_card_id) -- decisao final
-- da Fase 4 desta sessao: tabela dedicada em vez de JSONB-in-row em
-- pricing_set_bootstrap_state, pela preferencia ja registrada de Fabricio (separar
-- "estado/checkpoint" de "payload temporario") e pelo custo de reescrita O(n^2) que um
-- JSONB unico reescrito a cada pagina teria em Sets grandes (WAL/bloat).
--
-- Correcao obrigatoria 1 desta rodada (auditoria de campos): buildExternalNumberIndex()
-- e classifyCardMatch() (supabase/functions/_shared/pricing-justtcg-matching/
-- card-matching.ts) foram relidos e re-grepados nesta rodada -- os UNICOS campos do
-- candidato externo (JustTcgCard) referenciados em qualquer ponto da classificacao sao:
--   - id            -> external_card_id (chave)
--   - number        -> usado tanto para a chave normalizada quanto para o desempate por
--                      denominador (parseCollectorNumberParts() decompoe o proprio
--                      `number`, ex. "015/203", em numerador+denominador -- NUNCA existe
--                      um campo separado de "total" do lado externo; o denominador é
--                      sempre re-derivado do mesmo `number` já staged, nunca precisa de
--                      coluna própria)
--   - name          -> usado só por isNameCompatible() para a evidencia de
--                      divergencia_de_nome (nunca decide classificacao sozinho)
-- `rarity`, `variants` e `uuid` (presentes em JustTcgCard) NAO sao referenciados em
-- nenhum ponto de card-matching.ts -- confirmado via grep dedicado nesta rodada, alem da
-- leitura integral já feita em rodada anterior. `collector_total` (o desempate que
-- Fabricio apontou) é um atributo LOCAL (LocalCard.collector_total, lido da tabela
-- `card`), nunca precisa ser staged do lado externo. Logo, o payload de 3 campos
-- (external_card_id, number, name) é suficiente e completo para reproduzir exatamente o
-- matching atual -- nenhuma simplificacao indevida.
--
-- external_number preserva o valor bruto (inclusive NULL/"N/A") sem normalizar --
-- normalizeNumber()/isUsableExternalNumber()/parseCollectorNumberParts() operam sobre
-- o valor cru no momento da classificacao (mesma fronteira de hoje); staging nunca
-- pre-normaliza, para nao divergir do comportamento do nucleo P16.2 caso a normalizacao
-- mude no futuro.

CREATE TABLE public.pricing_set_bootstrap_card_staging (
  pricing_set_mapping_id uuid NOT NULL
    REFERENCES public.pricing_set_mapping(id) ON DELETE CASCADE,
  external_card_id text NOT NULL,
  external_number text NULL,
  external_name text NOT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (pricing_set_mapping_id, external_card_id),
  CONSTRAINT ck_psbcs_external_card_id_not_blank CHECK (length(btrim(external_card_id)) > 0),
  CONSTRAINT ck_psbcs_external_name_not_blank CHECK (length(btrim(external_name)) > 0)
);

CREATE TRIGGER trg_pricing_set_bootstrap_card_staging_set_updated_at
  BEFORE UPDATE ON public.pricing_set_bootstrap_card_staging
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE public.pricing_set_bootstrap_card_staging ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
  ON public.pricing_set_bootstrap_card_staging
  FOR SELECT
  TO public
  USING (is_admin());

REVOKE ALL ON public.pricing_set_bootstrap_card_staging FROM PUBLIC;
GRANT SELECT ON public.pricing_set_bootstrap_card_staging TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.pricing_set_bootstrap_card_staging TO service_role;
