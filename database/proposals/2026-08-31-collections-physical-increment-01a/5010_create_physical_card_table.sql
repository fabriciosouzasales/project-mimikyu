/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5010 - Create Physical Card Table (PROPOSTA)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01)

Descrição...:
Cria public.physical_card — identidade permanente do exemplar físico
(C-47/LDM-23/LDM-24). Referencia exatamente 1 Card Variant e 1
Language (idioma físico independente — card_variant não carrega
dimensão de idioma neste schema, confirmado por introspecção em
COLLECTIONS-PHYSICAL-MODELING-01), e 0..1 Inventory corrente.

Escopo deliberadamente mínimo: sem quantity (cada exemplar é uma
linha própria, C-47); sem Collection/Storage/Condition/Certification/
Availability/Custody/Lifecycle/Audit — incrementos futuros, fora de
escopo deste ciclo (instrução explícita de
COLLECTIONS-PHYSICAL-INCREMENT-01A).

Regras de Negócio:
- card_variant_id, language_id: NOT NULL, FK RESTRICT/RESTRICT —
  segue a convenção uniforme já usada em todo o Catálogo Editorial
  (fk_card_variant_card, fk_card_rarity, etc.) para referências
  estáveis;
- inventory_id: NULLABLE, FK RESTRICT/RESTRICT — decisão revisada em
  COLLECTIONS-PHYSICAL-MODELING-02 (item 2): NÃO usa ON DELETE
  SET NULL. Um Physical Card sair de Inventory é mudança de ownership
  corrente e deve passar por operação de domínio/Lifecycle explícita
  (futura, fora de escopo); nenhum DELETE estrutural pode alterar
  ownership silenciosamente;
- sem UNIQUE em (card_variant_id, language_id) — múltiplas cópias do
  mesmo par são esperadas e cada uma é uma linha própria, nunca
  quantidade agregada (C-47);
- RLS habilitado desde a criação; única policy é SELECT via
  resolução do Inventory do próprio usuário; nenhum INSERT/UPDATE/
  DELETE direto para authenticated — escrita exclusivamente via
  add_physical_cards() (Query 5012);
- GRANT mínimo (authenticated: SELECT; anon: nenhum); REVOKE de
  TRUNCATE/REFERENCES/TRIGGER/MAINTAIN mantido por consistência
  defensiva (ver nota em Query 5000).

Índice de idioma revisado nesta rodada (item 3 de
COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01): substituído
INDEX(language_id) por INDEX(inventory_id, language_id). Toda
consulta normal do produto é user/Inventory-scoped — inclusive a
própria RLS de SELECT resolve sempre por inventory_id primeiro — logo
um índice global em language_id sozinho não tem consumidor real: não
existe hoje nenhuma consulta legítima "todas as cartas em um idioma,
cross-user" (RLS nem permitiria ler além do próprio Inventory). Um
composto (inventory_id, language_id) serve diretamente o padrão real
"minhas cartas por idioma" (WHERE inventory_id = X AND language_id =
Y) e replica, para o filtro de idioma, a mesma lógica já aplicada ao
índice (inventory_id, card_variant_id) — que permanece inalterado
nesta revisão. Os dois compostos coexistem porque servem dimensões de
filtro distintas (identidade de Variant vs. idioma); um único índice
de 3 colunas não serviria bem as duas consultas isoladamente.

Autoridade conceitual: C-47, C-48, LDM-23, LDM-24. Aprovado em
COLLECTIONS-PHYSICAL-MODELING-02, liberado por
COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01 (READY FOR
IMPLEMENTATION).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA. Numeração 5010
provisória (mesmo milhar de 5000, bloco de dez seguinte — ver nota em
Query 5000 sobre confirmação de numeração definitiva).
================================================================
*/

CREATE TABLE public.physical_card (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_variant_id UUID NOT NULL REFERENCES public.card_variant(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    language_id     UUID NOT NULL REFERENCES public.language(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    inventory_id    UUID NULL REFERENCES public.inventory(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.physical_card IS
    'Identidade permanente de um exemplar físico (C-47). Exatamente 1 Card Variant + 1 Language; 0..1 Inventory corrente. Nunca representa quantidade agregada — cada cópia é sua própria linha. Sem Collection/Storage/Condition/Certification nesta fundação (incrementos futuros).';

CREATE INDEX ix_physical_card_inventory_variant
    ON public.physical_card (inventory_id, card_variant_id);

CREATE INDEX ix_physical_card_inventory_language
    ON public.physical_card (inventory_id, language_id);

ALTER TABLE public.physical_card ENABLE ROW LEVEL SECURITY;

CREATE POLICY physical_card_select_own
    ON public.physical_card
    FOR SELECT
    USING (
        inventory_id = (
            SELECT i.id
            FROM public.inventory i
            WHERE i.owner_user_id = (select auth.uid())
        )
    );

GRANT SELECT ON public.physical_card TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.physical_card FROM anon, authenticated;
