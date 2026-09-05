/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6112 - Create Card Primary Species Table
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em
               COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-AUDIT-01;
               revisado em COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-
               MODELING-REVISION-01)

Correção v1.1 (REVISION-01): a v1.0 só exigia source_evidence NOT NULL
para AUTOMATIC_DEXID, sem contrato de forma — JSON opaco. Fabrício
pediu explicitamente um schema lógico mínimo. chk_card_primary_
species_basis_requires_evidence é substituída por chk_card_primary_
species_automatic_evidence_shape (abaixo), que exige três chaves:
"source" = 'TCGDEX' (identifica a origem — único valor aceito hoje,
mas o campo já existe para uma futura segunda fonte, ex. PokéAPI, sem
migration estrutural), "tcgdex_dex_ids" (array JSON não vazio — a
evidência BRUTA como observada, preservando eventuais duplicatas
literais, ex. [25] ou [25,25]) e "resolved_dex_id" (number — o valor
único efetivamente usado na decisão, sempre presente quando
resolution_basis = AUTOMATIC_DEXID, mesmo que tcgdex_dex_ids tenha
mais de um elemento IDÊNTICO). Nenhuma FK/CHECK cross-tabela verifica
resolved_dex_id contra pokemon_species.national_dex_number aqui —
essa correção é garantida por CONSTRUÇÃO: as duas únicas funções
capazes de escrever nesta tabela (Queries 6114/6115, REVISION-01)
nunca aceitam DML direto de nenhum chamador (nenhum GRANT de INSERT/
UPDATE/DELETE existe nesta tabela, nem para authenticated nem para
service_role — SECURITY DEFINER executa com os privilégios do dono),
e a única delas que pode gravar AUTOMATIC_DEXID (6115) monta
resolved_dex_id deterministicamente a partir do mesmo valor que usou
para resolver pokemon_species_id. O CHECK aqui é defesa em
profundidade, não o mecanismo primário de correção.

Descrição...:
Entidade física que materializa LDM-182/183 ("Card Primary Species:
Sourcing Estrutural") — como o catálogo editorial MMKYU determina a
Primary Species canônica de uma Card Pokémon. Não confundir com
Pokédex Position Assignment (LDM-178, Species Match/Mismatch,
USER_OVERRIDE) — responsabilidade diferente, deliberadamente fora de
escopo desta Query (ver cabeçalho do README desta pasta).

Modelada como TABELA PRÓPRIA, não como coluna em public.card — decisão
direta de ADR-011 (separação Catalog Domain genérico vs. Pokémon TCG
Domain específico): o vínculo Card→Species pertence exclusivamente ao
módulo Pokémon-TCG-específico, nunca à tabela genérica multi-TCG.
Nome e milhar (6000-6999) já antecipados por
docs/standards/STD-001-database-standards.md (lista "Fora de escopo
até o momento" do módulo "Pokémon Catalog Foundation").

Cardinalidade: card_id é PK=FK (1:1 estrito com public.card). Isto
enforce estruturalmente a invariante "Card Pokémon possui exatamente
uma Primary Species canônica quando o vínculo está resolvido" sem
precisar de UNIQUE adicional — mesmo padrão de subtipo 1:1 já usado em
collection_pokedex_reference (Query 5087) e nos subtipos de Collection
Reference (5052/5087). Ausência de linha == "não resolvido" (estado
válido, não uma violação) — não existe um valor sentinela "PENDING"
dentro da tabela; a ausência da linha É o estado pendente.

pokemon_species_id NÃO é UNIQUE: múltiplas Cards (variantes de
impressão diferentes) apontam legitimamente para a mesma Species.

resolution_basis distingue como a decisão foi tomada:
- AUTOMATIC_DEXID: exatamente 1 dexId resolvível na evidência TCGdex
  (LDM-182). Resolução automática, sem intervenção humana.
- EDITORIAL_RECONCILIATION: decisão humana MMKYU — cobre múltiplos
  dexIds, dexId ausente/não resolvível, e qualquer correção posterior
  de uma resolução automática. Vocabulário deliberadamente distinto de
  SPECIES_MATCH/USER_OVERRIDE (LDM-178, nível Position Assignment) —
  ver "IMPORTANTE" do mandato desta rodada.

source_evidence (JSONB, nullable) é o snapshot da evidência que
sustentou a decisão — hoje, para AUTOMATIC_DEXID, o formato é
{"tcgdex_dex_id": <int>, "catalog_import_row_id": "<uuid>"}. Este
snapshot é o que torna a evidência DURÁVEL: auditoria read-only desta
rodada confirmou que catalog_import_row (Query 2070) é staging
EFÊMERO — Query 2111 já apagou linhas duplicadas em produção
(2026-08-07) — logo hoje a única evidência de dexId sobrevive por
acidente, não por design. Esta tabela passa a ser o local durável.
NULL permitido para EDITORIAL_RECONCILIATION sem evidência automática
correspondente (760 Cards, ~12% do universo Pokémon ativo, auditadas
nesta rodada sem nenhum dexId sobrevivente em catalog_import_row —
ver README, seção "Riscos").

resolved_at é o timestamp de DECISÃO (semântico — "quando foi
determinado"), distinto de created_at/updated_at (técnicos). Uma
correção editorial futura deve atualizar resolved_at para refletir a
data da decisão vigente, preservando created_at como identidade
técnica da linha física.

resolved_by_user_id (nullable, ON DELETE SET NULL) segue exatamente o
padrão de catalog_import_job.initiated_by (Query 2060): NULL quando
resolution_basis = AUTOMATIC_DEXID (sistema resolveu, não uma pessoa);
obrigatório quando EDITORIAL_RECONCILIATION. Anulável para sobreviver
à exclusão futura do usuário sem apagar o histórico de quem decidiu.

Rastreabilidade de correções futuras (fechada em REVISION-01): esta
Query NÃO cria uma tabela de histórico dedicada. Correções editoriais
(trocar pokemon_species_id de uma linha existente) são registradas em
public.catalog_admin_action_log (Query 2010, entity_id polimórfico,
ampliada pela Query 2159) pela própria função de escrita individual
(Query 6114) — old/new species e basis vão em metadata. Resoluções
automáticas em lote (Query 6115) NÃO geram linha em catalog_admin_
action_log — mesmo padrão já usado pelo pipeline 100% automatizado de
Pokémon Catalog Sourcing (Queries 6100-6111, nenhuma delas grava
nessa tabela): a rastreabilidade de uma decisão AUTOMATIC_DEXID já
está inteiramente contida na própria linha (source_evidence +
resolved_at), reproduzível deterministicamente a partir da mesma
evidência — nenhuma decisão humana existe ali para auditar "quem
decidiu e por quê". Mesmo raciocínio que já levou LDM-179 a evitar uma
entidade de histórico dedicada para Position Assignment.

RLS: catalog_admin_select (mesmo padrão de card/card_category/
catalog_import_job/catalog_import_row) — leitura restrita a
administradores, nenhuma policy de escrita. GRANT SELECT restrito a
authenticated. NENHUM GRANT de INSERT/UPDATE/DELETE nesta tabela, para
nenhum papel, em nenhuma rodada — decisão permanente, não uma
lacuna temporária: toda escrita passa exclusivamente pelas funções
SECURITY DEFINER das Queries 6114 (individual/editorial, is_admin())
e 6115 (bulk, service_role only), que escrevem com os privilégios do
dono da função, não do chamador — nenhum GRANT de tabela é necessário
nem desejável para elas funcionarem. Mesmo racional de ADR-023
("nunca por política de RLS ampla de INSERT/UPDATE").

Least privilege de tabela: REVOKE explícito de TRUNCATE/REFERENCES/
TRIGGER/MAINTAIN de anon/authenticated E service_role já nesta Query
de criação — incorpora a lição de Query 6111 (pg_default_acl do role
postgres concede service_role=Dxtm a toda tabela nova por herança),
mesmo padrão já corrigido em collection_pokedex_reference (Query 5087,
Fatia B) em vez do padrão mais antigo (Query 6030, sem service_role).

STATUS DESTA QUERY: PROPOSTA — aguardando revisão externa antes de
qualquer execução real.
================================================================
*/

BEGIN;

CREATE TABLE public.card_primary_species (
    card_id             UUID PRIMARY KEY
                            REFERENCES public.card(id)
                            ON UPDATE RESTRICT ON DELETE CASCADE,
    pokemon_species_id  UUID NOT NULL
                            REFERENCES public.pokemon_species(id)
                            ON UPDATE RESTRICT ON DELETE RESTRICT,
    resolution_basis    TEXT NOT NULL,
    source_evidence     JSONB,
    resolved_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_by_user_id UUID,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_primary_species_resolved_by_user_id
        FOREIGN KEY (resolved_by_user_id)
        REFERENCES auth.users (id)
        ON DELETE SET NULL,

    CONSTRAINT chk_card_primary_species_resolution_basis
        CHECK (resolution_basis IN ('AUTOMATIC_DEXID', 'EDITORIAL_RECONCILIATION')),

    CONSTRAINT chk_card_primary_species_automatic_evidence_shape
        CHECK (
            resolution_basis <> 'AUTOMATIC_DEXID'
            OR (
                source_evidence IS NOT NULL
                AND source_evidence ? 'source'
                AND source_evidence ->> 'source' = 'TCGDEX'
                AND source_evidence ? 'tcgdex_dex_ids'
                AND jsonb_typeof(source_evidence -> 'tcgdex_dex_ids') = 'array'
                AND jsonb_array_length(source_evidence -> 'tcgdex_dex_ids') >= 1
                AND source_evidence ? 'resolved_dex_id'
                AND jsonb_typeof(source_evidence -> 'resolved_dex_id') = 'number'
            )
        ),

    CONSTRAINT chk_card_primary_species_basis_resolver_coupling
        CHECK (
            (resolution_basis = 'AUTOMATIC_DEXID' AND resolved_by_user_id IS NULL)
            OR
            (resolution_basis = 'EDITORIAL_RECONCILIATION' AND resolved_by_user_id IS NOT NULL)
        )
);

COMMENT ON TABLE public.card_primary_species IS
    'Vínculo Card Pokémon -> Primary Species canônica (LDM-182/183). 1:1 estrito via PK=FK em card_id. Ausência de linha = vínculo ainda não resolvido. Não confundir com Pokédex Position Assignment / Species Match (LDM-178) — responsabilidade diferente.';

COMMENT ON COLUMN public.card_primary_species.card_id IS
    'PK=FK 1:1 para public.card. Imutável após INSERT (Query 6113). CASCADE: esta linha não tem existência própria fora da Card.';

COMMENT ON COLUMN public.card_primary_species.pokemon_species_id IS
    'Species canônica resolvida (public.pokemon_species). RESTRICT: Species é catálogo de identidade permanente, nunca perde integridade referencial por causa desta tabela. Não UNIQUE — múltiplas Cards podem apontar para a mesma Species.';

COMMENT ON COLUMN public.card_primary_species.resolution_basis IS
    'AUTOMATIC_DEXID (exatamente 1 dexId TCGdex resolvível, LDM-182) ou EDITORIAL_RECONCILIATION (decisão humana MMKYU — múltiplos/ausentes dexIds ou correção). Vocabulário distinto de SPECIES_MATCH/USER_OVERRIDE (LDM-178, nível Position Assignment).';

COMMENT ON COLUMN public.card_primary_species.source_evidence IS
    'Snapshot da evidência. Para AUTOMATIC_DEXID, schema mínimo obrigatório (chk_card_primary_species_automatic_evidence_shape): {"source": "TCGDEX", "tcgdex_dex_ids": [<int>, ...] (bruto, como observado), "resolved_dex_id": <int> (valor único usado na decisão), "catalog_import_row_id": "<uuid>"|null, "observed_at": "<timestamptz>"}. Para EDITORIAL_RECONCILIATION, forma livre (pode ser NULL). Torna a evidência durável — catalog_import_row (Query 2070) é staging efêmero.';

COMMENT ON COLUMN public.card_primary_species.resolved_at IS
    'Timestamp semântico da decisão (quando foi determinado) — distinto de created_at/updated_at (técnicos). Correção editorial futura deve atualizar este campo para refletir a decisão vigente.';

COMMENT ON COLUMN public.card_primary_species.resolved_by_user_id IS
    'Administrador que tomou a decisão editorial. NULL quando resolution_basis = AUTOMATIC_DEXID (sistema resolveu). Anulável (ON DELETE SET NULL): sobrevive à exclusão futura do usuário, mesmo padrão de catalog_import_job.initiated_by (Query 2060).';

CREATE INDEX idx_card_primary_species_pokemon_species_id
    ON public.card_primary_species (pokemon_species_id);

COMMENT ON INDEX public.idx_card_primary_species_pokemon_species_id IS
    'Suporta lookup reverso Species -> Cards (ex.: todas as variantes de impressão de uma Species). FK não é indexada automaticamente pelo Postgres.';

ALTER TABLE public.card_primary_species ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select ON public.card_primary_species
    FOR SELECT USING ((select public.is_admin()));

GRANT SELECT ON public.card_primary_species TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.card_primary_species
    FROM anon, authenticated, service_role;

COMMIT;
