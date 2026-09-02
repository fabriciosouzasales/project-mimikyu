/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5060 - Alter Collection: Widen mode and Unlock reference_locked_at (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Duas correções físicas sobre constraints já existentes em
public.collection (Query 5030), ambas hardenings temporários que já
anunciavam, no próprio texto original, a condição exata sob a qual
seriam revisados — essa condição está satisfeita agora.

1. chk_collection_mode (5030): fisicamente só 'OPEN_CURATION' desde
   2B, "alargável por DROP+ADD CONSTRAINT quando Collection Reference
   existir e REFERENCE_BASED puder ser liberado" (texto original do
   comentário de 5030). Collection Reference passa a existir
   fisicamente nesta mesma rodada (Queries 5049/5052) — a condição
   está satisfeita. Ampliado para incluir 'REFERENCE_BASED'.

2. chk_collection_reference_locked_at_null (5030): "será
   conscientemente removida ou revisada no Incremento 2C, quando a
   primeira Collection Allocation passar a controlar
   reference_locked_at" (texto original). Diagnosticado em 2C que essa
   condição ainda não estava satisfeita (mode continuava só
   OPEN_CURATION, logo nenhum Reference existia para consolidar) —
   registrado explicitamente em `database/proposals/2026-09-01-02c-
   allocation/README.md`, seção "reference_locked_at — confirmado
   intocado nesta rodada". A condição real (existir Collection
   Reference) só se materializa agora, no 2D — removida.

Aplicar as duas ALTERs na MESMA transação/migration (mesmo script,
sem intervalo de COMMIT entre elas) — evita uma janela onde mode já
aceita 'REFERENCE_BASED' mas nenhuma das triggers/constraints
subsequentes (5049-5059) ainda existe. Na prática, isso significa
aplicar 5049-5059 primeiro (tabelas + todo o enforcement) e só então
5060 (widening) — a ordem completa está documentada no README desta
pasta.

Nenhuma linha existente de collection é afetada — todas já têm mode =
'OPEN_CURATION' e reference_locked_at = NULL (única combinação possível
sob os CHECKs anteriores).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

ALTER TABLE public.collection
    DROP CONSTRAINT chk_collection_mode;

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_mode
    CHECK (mode IN ('OPEN_CURATION', 'REFERENCE_BASED'));

ALTER TABLE public.collection
    DROP CONSTRAINT chk_collection_reference_locked_at_null;
