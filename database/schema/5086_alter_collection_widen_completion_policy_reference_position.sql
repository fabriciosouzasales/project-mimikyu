/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5086 - Alter Collection: Widen completion_policy for REFERENCE_POSITION
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-REVISION-01 — corrige blocker identificado na
               rodada AUDIT-01; aplicado em 2026-09-05 via
               COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
CORREÇÃO OBRIGATÓRIA (REVISION-01): a rodada AUDIT-01 havia proposto
gravar completion_policy = 'NONE' para Collection Pokédex, por
chk_collection_completion_policy (Query 5067, alargada por 5078) não
aceitar nenhuma combinação REFERENCE_BASED + <valor específico de
Pokédex>. Fabrício determinou que isso é um blocker físico real: uma
Collection Pokédex com completion_policy = 'NONE' é um estado
semanticamente falso (declara "esta Collection não tem política de
completude" quando na verdade ela TEM uma — apenas o cálculo ainda não
está implementado). A correção certa não é evitar o valor, é
materializar o valor correto desde já.

Esta Query alarga chk_collection_completion_policy para aceitar uma
quarta combinação: (mode = 'REFERENCE_BASED' AND completion_policy =
'REFERENCE_POSITION') — exatamente o mesmo mecanismo incremental já
usado duas vezes (5067: 2 combinações -> 5078: 3 combinações, para
MASTER_SET). 'REFERENCE_POSITION' passa a ser a identidade/policy
correta de qualquer Collection Pokédex, independente de a Completion
em si já ser computável.

ESCOPO EXPLICITAMENTE LIMITADO (não confundir com Fatia E): esta Query
materializa apenas o VALOR do enum físico de completion_policy — NÃO
estende collection_completion_summary()/collection_completion_positions()
(Queries 5070/5071/5083) com nenhum ramo para REFERENCE_POSITION.
Chamar essas duas funções contra uma Collection REFERENCE_POSITION
hoje retorna resultado vazio/sem linha correspondente (nenhum ramo do
UNION ALL de CTEs bate com esse valor) — não é erro, é lacuna aceita e
documentada, cuja resolução é responsabilidade integral da Fatia E
("REFERENCE_POSITION Completion"): cálculo de completion, denominator/
numerator, read models e status derivado. Diferente do precedente de
MASTER_SET (onde o alargamento do CHECK, 5078, e a extensão da função,
5083, foram aplicados na MESMA rodada, 02F), aqui o alargamento do
CHECK antecede deliberadamente a Fatia E — decisão explícita de
Fabrício nesta REVISION-01, não um descuido.

Nenhuma linha de collection existe hoje com completion_policy
diferente de NONE/STANDARD_SET/MASTER_SET (0 linhas em collection,
confirmado por auditoria read-only em 2026-09-05) — este ALTER não
requer nenhum backfill, ao contrário de 5067 (que precisou popular a
coluna pela primeira vez sobre dados já existentes).

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou chk_collection_completion_policy aceitando as quatro
combinações, incluindo (REFERENCE_BASED, REFERENCE_POSITION). Validado
funcionalmente: duas Collections Pokédex reais criadas em BEGIN/ROLLBACK
gravaram completion_policy = 'REFERENCE_POSITION' com sucesso. Zero
resíduo.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

ALTER TABLE public.collection
    DROP CONSTRAINT chk_collection_completion_policy;

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_completion_policy
    CHECK (
        (mode = 'OPEN_CURATION' AND completion_policy = 'NONE')
        OR (mode = 'REFERENCE_BASED' AND completion_policy = 'STANDARD_SET')
        OR (mode = 'REFERENCE_BASED' AND completion_policy = 'MASTER_SET')
        OR (mode = 'REFERENCE_BASED' AND completion_policy = 'REFERENCE_POSITION')
    );

COMMIT;
