/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5301 - Widen collection visibility to PUBLIC
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030142133 `5301_widen_collection_visibility_public`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-collection-sharing/
              (só este bloco Status difere); texto do ledger ≡ arquivo da proposta inteiro (md5).
              Validação: 5861 v1.3 51/51 PASS.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Alarga chk_collection_visibility para ('PRIVATE','PUBLIC'). A 5030
restringiu a 'PRIVATE' até existir uma projeção pública segura — ela
nasce neste mesmo pacote (5312/5313), então o alargamento só deve ser
aplicado junto com elas.

Regras de Negócio:
- Toda coleção continua nascendo PRIVATE (default inalterado, C-15).
- Só set_collection_visibility() (5307, titular) muda o valor.
- Nenhuma linha existente muda (todas são PRIVATE).
================================================================
*/

ALTER TABLE public.collection DROP CONSTRAINT chk_collection_visibility;

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_visibility
    CHECK (visibility IN ('PRIVATE', 'PUBLIC'));
