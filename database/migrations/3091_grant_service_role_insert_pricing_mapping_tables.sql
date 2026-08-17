-- Query 3091 — Conceder INSERT a service_role em pricing_set_mapping/pricing_card_mapping
-- Objetivo: habilitar a capacidade de escrita de mapeamento explicitamente deferida no
-- Incremento P2 (05f-pricing.md, seção pricing_card_mapping: "capacidade de escrita
-- adiada para incremento futuro de sincronização") — este é esse incremento (P8,
-- Conector JustTCG e Piloto Controlado). Sem esta concessão, service_role só tem SELECT
-- nas duas tabelas, tornando estruturalmente impossível persistir qualquer
-- correspondência Set/Card descoberta pelo conector.
--
-- Escopo deliberadamente mínimo: apenas INSERT, nunca UPDATE/DELETE. A idempotência de
-- resolução de mapeamento usa exclusivamente INSERT ... ON CONFLICT (..., pricing_source_id)
-- DO NOTHING (mesmo padrão já usado em pricing_observation/pricing_product) — reexecuções
-- do conector nunca precisam alterar uma linha já existente. Corrigir um mapeamento
-- (REJECTED -> nova tentativa, etc.) permanece fora de escopo deste incremento e exigiria
-- uma decisão own própria no futuro (função SECURITY DEFINER dedicada ou GRANT UPDATE
-- adicional), não decidida aqui.
--
-- REVOKE explícito dos demais privilégios "por garantia" (defesa em profundidade), mesmo
-- padrão paranoico já usado em pricing_product/pricing_observation/pricing_fx_rate — não
-- depender dos defaults de pg_default_acl.

GRANT INSERT ON public.pricing_set_mapping TO service_role;
GRANT INSERT ON public.pricing_card_mapping TO service_role;

REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_set_mapping FROM service_role;
REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_card_mapping FROM service_role;
