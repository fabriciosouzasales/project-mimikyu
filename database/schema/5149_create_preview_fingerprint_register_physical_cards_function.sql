/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5149 - preview_fingerprint_register_physical_cards():
               fingerprint do ESTADO DO MUNDO de B1
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-08 (COLLECTIONS-BULK-02-GATE-A-REVISION-02)

Descrição...:
FONTE ÚNICA do `preview_fingerprint` de `B1`. **HELPER INTERNO.**

É usada nos DOIS lados da comparação, e é justamente por ser a mesma
função nos dois lados que a comparação tem sentido:

  1. no PREVIEW, por quem construir a tela de preview — que, neste
     incremento, ainda não existe como RPC pública. **`BULK-03` será a
     interface pública de Preview** e chamará esta função de dentro da
     sua própria RPC `SECURITY DEFINER`;
  2. na CONFIRMAÇÃO, DENTRO da transação de
     `register_physical_cards_bulk()`, DEPOIS dos locks, para
     recalcular o mesmo fingerprint sobre o estado já pinado.

================================================================
POR QUE NÃO É ENDPOINT PÚBLICO (REVISION-02)
================================================================
Na v1.0 esta função tinha `GRANT EXECUTE TO authenticated` e era
`SECURITY DEFINER`. Duas razões derrubaram isso:

  1. **BULK-03 é a interface pública de Preview.** Expor aqui um
     segundo caminho público para a mesma coisa criaria duas portas
     para um contrato só — e a segunda nasceria obsoleta.
  2. **Trabalho não limitado escolhido pelo chamador.** Esta função
     tem apenas guard MÍNIMO de forma; ela NÃO impõe o teto de 1000
     nem os guards de contrato — esses são de `5150`, deliberadamente.
     Pública e `SECURITY DEFINER`, um chamador poderia mandar um array
     arbitrariamente grande e fazer o banco varrer catálogo sem teto,
     com privilégio elevado.

A saída NÃO é duplicar em `5149` os guards de `5150`. Duplicar
recriaria a divergência de implementação que `5147` existe para
eliminar. A saída é mantê-la INTERNA: `EXECUTE` revogado dos quatro
papéis, alcançável só de dentro de RPC `SECURITY DEFINER` que já
validou o payload.

================================================================
POR QUE `VOLATILE`, E NÃO `STABLE` (REVISION-02 — BLOCKER)
================================================================
Uma função `STABLE` enxerga o snapshot tomado no início da query que a
chamou. Isso é fatal aqui.

O caminho de `5150` é: `5148` adquire `FOR UPDATE` na Collection →
`5149` recalcula. Quando a sessão B **espera** nesse lock porque a
sessão A está alterando a mesma Collection, B só prossegue depois do
COMMIT de A. Nesse instante B PRECISA ler o estado novo — é
exatamente a mudança que o fingerprint existe para detectar.

Com `STABLE`, o snapshot poderia ser anterior ao COMMIT de A, o
fingerprint recalculado bateria com o antigo, `PREVIEW_STALE` não
dispararia e B escreveria sobre um mundo que já mudou. O bug seria
silencioso e só apareceria sob concorrência real.

`VOLATILE` obriga um snapshot novo a cada chamada. É requisito de
correção, não preferência de estilo. Provado estaticamente por `E08`
do `5822` e em concorrência real pelo runbook
`CONCURRENCY-PROOF-PREVIEW-STALE.sql`.

`SECURITY INVOKER` acompanha: a função é chamada por `5150`
(`SECURITY DEFINER`, owner `postgres`) e, no futuro, pela RPC
`SECURITY DEFINER` de `BULK-03`. Ela herda o privilégio de quem a
chama e não precisa de nenhum próprio.

================================================================
POR QUE A CONFERÊNCIA NÃO PODE FICAR NA APLICAÇÃO
================================================================
TOCTOU. Se a aplicação lesse o estado, comparasse o fingerprint e só
então chamasse a RPC, existiria uma janela entre a leitura e a
transação em que o mundo pode mudar. A operação escreveria sobre um
estado diferente do que foi conferido, e o `PREVIEW_STALE` nunca
dispararia.

Fechando dentro da transação e DEPOIS dos locks de `5148`, a janela
tem largura zero: o estado conferido é literalmente o estado travado
sobre o qual se escreve.

================================================================
O QUE ENTRA NO FINGERPRINT
================================================================
Exatamente o estado do mundo que muda o RESULTADO de B1 — nem mais,
nem menos:

    {
      "operation":    "REGISTER_PHYSICAL_CARDS",
      "inventory_id": "<uuid>",
      "collection":   null | {
                        "id", "updated_at", "lifecycle_status",
                        "mode", "game_id",
                        "reference_kind", "reference_card_set_id"
                      },
      "storage":      null | { "id", "updated_at" },
      "catalog":      [ { "card_variant_id", "language_id",
                          "card_set_id", "game_id" } , ... ]
    }

`updated_at` entra porque `collection` e `storage_container` têm
trigger `BEFORE UPDATE` de `updated_at` (`5031` e `5021`): qualquer
mutação daquelas linhas move o fingerprint. `reference_kind` e
`reference_card_set_id` entram explicitamente porque mudar o Reference
NÃO necessariamente toca a linha de `collection`.

`catalog` contém apenas as tuplas que RESOLVEM hoje. Se uma Card
Variant do payload deixar de existir entre o preview e a confirmação,
o array encolhe e o fingerprint muda — que é o comportamento correto.

O `quantity` NÃO entra: quantidade é INTENÇÃO, e intenção mora no
`request_hash` (`5147`), não no fingerprint. Manter os dois conceitos
separados é `D9`.

Hash: `bulk_request_hash()` de `5147` — a mesma canonicalização
independente de ordem usada pelo `request_hash`. Uma primitiva, dois
usos, zero divergência possível.

Timestamps são serializados por
`to_char(ts AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS')`: forma
explícita, sem depender de `DateStyle` nem de `TimeZone` da sessão.

================================================================
SEGURANÇA
================================================================
`SECURITY INVOKER`, `VOLATILE`, `search_path = ''`, owner `postgres`.
`EXECUTE` revogado de `PUBLIC`, `anon`, `authenticated` e
`service_role` — helper INTERNO, como `5147` e `5148`.

Somente LEITURA. Nenhum lock, nenhuma escrita. Os locks são
responsabilidade de quem chama na confirmação (`5148`).

Não-enumeração idêntica à de `5148` e `5150`: Collection/Storage
inexistente e de terceiro produzem a MESMA mensagem. Isso é **defesa
em profundidade**, não a linha de frente: no caminho de `5150` os
recursos já foram resolvidos e travados por `5148` antes de esta
função ser chamada, então estes `RAISE` são inalcançáveis ali. Eles
existem para o dia em que `BULK-03` a chamar sem lock prévio.

Dependências:
- public.bulk_canonical_json/bulk_request_hash (5147);
- public.inventory (5000), public.collection, public.storage_container;
- public.collection_reference / collection_card_set_reference;
- catálogo: card_variant, card, card_set, expansion, language.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.preview_fingerprint_register_physical_cards(
    p_items                JSONB,
    p_collection_id        UUID DEFAULT NULL,
    p_storage_container_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE
SET search_path = ''
AS $$
DECLARE
    c_uuid_re CONSTANT TEXT :=
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    v_owner       UUID;
    v_inventory   UUID;
    -- Deliberadamente SQL NULL, NAO 'null'::jsonb. Se fossem
    -- inicializadas com 'null'::jsonb, um `SELECT ... INTO` sem linha
    -- deixaria a variavel intacta e o teste de "nao encontrado"
    -- passaria batido. A conversao para o JSON `null` acontece so na
    -- montagem do estado, no fim.
    v_collection  JSONB;
    v_storage     JSONB;
    v_catalog     JSONB;
    v_state       JSONB;
BEGIN
    v_owner := (select auth.uid());

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
    END IF;

    -- Guard defensivo minimo. Os guards completos de contrato sao de
    -- `5150`; aqui basta garantir que o payload e navegavel.
    IF p_items IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'items deve ser um array JSON' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_items) AS it(elem)
        WHERE jsonb_typeof(it.elem) IS DISTINCT FROM 'object'
           OR (it.elem ->> 'card_variant_id') !~* c_uuid_re
           OR (it.elem ->> 'language_id')     !~* c_uuid_re
    ) THEN
        RAISE EXCEPTION 'items contem elemento malformado ou UUID invalido'
            USING ERRCODE = '22023';
    END IF;

    SELECT inv.id INTO v_inventory
      FROM public.inventory inv
     WHERE inv.owner_user_id = v_owner;

    IF v_inventory IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user' USING ERRCODE = '22023';
    END IF;

    IF p_collection_id IS NOT NULL THEN
        SELECT jsonb_build_object(
                   'id',                     col.id::text,
                   'updated_at',             to_char(col.updated_at AT TIME ZONE 'UTC',
                                                     'YYYYMMDDHH24MISSUS'),
                   'lifecycle_status',       col.lifecycle_status,
                   'mode',                   col.mode,
                   'game_id',                col.game_id::text,
                   'reference_kind',         ref.reference_kind,
                   'reference_card_set_id',  ref.card_set_id::text
               )
          INTO v_collection
          FROM public.collection col
          LEFT JOIN LATERAL (
              SELECT cr.reference_kind, ccsr.card_set_id
                FROM public.collection_reference cr
                LEFT JOIN public.collection_card_set_reference ccsr
                       ON ccsr.collection_reference_id = cr.id
               WHERE cr.collection_id = col.id
          ) ref ON TRUE
         WHERE col.id = p_collection_id
           AND col.owner_user_id = v_owner;

        IF v_collection IS NULL THEN
            RAISE EXCEPTION 'collection not found or not owned by caller'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    IF p_storage_container_id IS NOT NULL THEN
        SELECT jsonb_build_object(
                   'id',         sc.id::text,
                   'updated_at', to_char(sc.updated_at AT TIME ZONE 'UTC',
                                         'YYYYMMDDHH24MISSUS')
               )
          INTO v_storage
          FROM public.storage_container sc
         WHERE sc.id = p_storage_container_id
           AND sc.inventory_id = v_inventory;

        IF v_storage IS NULL THEN
            RAISE EXCEPTION 'storage container not found or not owned by caller'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    -- Catalogo RESOLVIDO. Somente as tuplas que existem hoje entram.
    SELECT COALESCE(jsonb_agg(
               jsonb_build_object(
                   'card_variant_id', d.cv_id::text,
                   'language_id',     d.lang_id::text,
                   'card_set_id',     ca.card_set_id::text,
                   'game_id',         ex.game_id::text
               )
           ), '[]'::jsonb)
      INTO v_catalog
      FROM (
          SELECT DISTINCT
                 (it.elem ->> 'card_variant_id')::uuid AS cv_id,
                 (it.elem ->> 'language_id')::uuid     AS lang_id
            FROM jsonb_array_elements(p_items) AS it(elem)
      ) d
      JOIN public.card_variant cv ON cv.id = d.cv_id
      JOIN public.card ca         ON ca.id = cv.card_id
      JOIN public.card_set cs     ON cs.id = ca.card_set_id
      JOIN public.expansion ex    ON ex.id = cs.expansion_id
      JOIN public.language l      ON l.id  = d.lang_id;

    -- COALESCE explicito: aqui, e so aqui, "ausente" vira o JSON `null`.
    v_state := jsonb_build_object(
        'operation',    'REGISTER_PHYSICAL_CARDS',
        'inventory_id', v_inventory::text,
        'collection',   COALESCE(v_collection, 'null'::jsonb),
        'storage',      COALESCE(v_storage,    'null'::jsonb),
        'catalog',      v_catalog
    );

    RETURN public.bulk_request_hash('PREVIEW:REGISTER_PHYSICAL_CARDS', v_state);
END;
$$;

COMMENT ON FUNCTION public.preview_fingerprint_register_physical_cards(JSONB, UUID, UUID) IS
    'FONTE UNICA do preview_fingerprint de B1. Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role. NAO e endpoint publico — a interface publica de Preview e BULK-03. VOLATILE, e nao STABLE: uma funcao STABLE usaria o snapshot do inicio da query chamadora e o recalculo poderia enxergar o estado ANTERIOR ao commit que liberou o lock de 5148, que e exatamente o que este fingerprint existe para detectar. SECURITY INVOKER: e chamada por 5150 (SECURITY DEFINER, owner postgres) e futuramente pela RPC SECURITY DEFINER de BULK-03; nao precisa de privilegio proprio. Cobre o ESTADO DO MUNDO que muda o resultado: Inventory, Collection (updated_at, lifecycle, mode, Game, Reference), Storage (updated_at) e o catalogo RESOLVIDO. quantity NAO entra: quantidade e intencao e mora no request_hash (D9). Somente leitura, sem lock.';

REVOKE EXECUTE ON FUNCTION public.preview_fingerprint_register_physical_cards(JSONB, UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5822`, grupos `G` (fingerprint),
`E` (estrutural, incluindo `provolatile = 'v'`) e `S` (segurança).

Provas mínimas esperadas:
- `provolatile = 'v'` e `prosecdef = false`;
- `proacl` não-NULL, sem `grantee = 0`, e nenhum dos quatro papéis com
  `EXECUTE`;
- dois cálculos consecutivos, sem mudança de estado, devolvem o MESMO
  valor;
- reordenar `p_items` NÃO muda o valor;
- mudar `quantity` NÃO muda o valor (quantity não é estado do mundo);
- uma mudança REAL na Collection alvo MUDA o valor.

A prova de que o recálculo enxerga o estado pós-lock em CONCORRÊNCIA
REAL não cabe em sessão única e está no runbook
`CONCURRENCY-PROOF-PREVIEW-STALE.sql` desta mesma pasta.
*/
