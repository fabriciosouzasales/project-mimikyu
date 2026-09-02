/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5060 - Alter Collection: Widen mode and Unlock reference_locked_at
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

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

Aplicada na MESMA transação/migration em que 5049-5059 já haviam sido
aplicadas antes desta — evita uma janela onde mode já aceita
'REFERENCE_BASED' mas nenhuma das triggers/constraints subsequentes
ainda existe. Ordem completa (5049-5059 primeiro, depois 5060)
documentada no README de `database/proposals/2026-09-02-02d-
reference/` e confirmada no postcheck estrutural da Fase 3 desta
implementação.

Nenhuma linha existente de collection foi afetada — todas já tinham
mode = 'OPEN_CURATION' e reference_locked_at = NULL (única combinação
possível sob os CHECKs anteriores).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

ALTER TABLE public.collection
    DROP CONSTRAINT chk_collection_mode;

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_mode
    CHECK (mode IN ('OPEN_CURATION', 'REFERENCE_BASED'));

ALTER TABLE public.collection
    DROP CONSTRAINT chk_collection_reference_locked_at_null;
