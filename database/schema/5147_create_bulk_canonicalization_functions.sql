/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5147 - Canonicalização de intenção Bulk:
               bulk_canonical_json() + bulk_request_hash()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-08 (COLLECTIONS-BULK-02-GATE-A-REVISION-01)

Descrição...:
FONTE ÚNICA E REUTILIZÁVEL de canonicalização de intenção para TODA a
família Bulk — `B1` (`register_physical_cards_bulk`), `B2`
(`register_card_set_bulk`) e `BULK-03` em diante.

Motivo de existir como Query própria, e não como código embutido em
cada RPC: o `request_hash` é o que decide REPLAY vs CONFLICT. Duas
implementações levemente divergentes produziriam hashes divergentes
para a mesma intenção, e a idempotência falharia em silêncio. Este é
exatamente o risco `B4` registrado no fechamento de BULK-01. Fechá-lo
exige UMA implementação, não duas parecidas.

================================================================
CONTRATO DE `bulk_canonical_json(JSONB) -> TEXT`
================================================================
Serialização canônica, determinística e independente de ordem:

  null      -> `null`
  boolean   -> `true` / `false`
  number    -> forma numérica normalizada por `trim_scale()`
               (1.50, 1.5 e 1.500 colapsam em `1.5`)
  string    -> string JSON escapada por `to_jsonb(text)`
  array     -> elementos canonicalizados e ORDENADOS pelo próprio
               texto canônico, em `COLLATE "C"`
  object    -> pares `"chave":valor` ordenados por chave, `COLLATE "C"`

**Arrays têm semântica de CONJUNTO.** `[1,2]` e `[2,1]` produzem o
mesmo texto canônico. Isso é DELIBERADO: a intenção de uma operação
Bulk é o conjunto de itens pedidos, não a ordem em que o cliente
serializou o JSON. Nenhuma informação se perde porque os chamadores da
família Bulk REJEITAM itens duplicados antes de chegar aqui — sem
duplicatas, ordenar é uma bijeção.

`COLLATE "C"` é obrigatório e não é detalhe: sem ele a ordenação
dependeria da collation do banco, e o mesmo payload poderia hashear
diferente em ambientes com locale diferente.

================================================================
CONTRATO DE `bulk_request_hash(TEXT, JSONB) -> TEXT`
================================================================
    sha256( operation_type || E'\n' || bulk_canonical_json(intent) )

devolvido em hexadecimal. `sha256()` é nativo desde o PostgreSQL 11 —
nenhuma extensão nova.

O `operation_type` entra no material hasheado para que duas operações
de tipos diferentes com payloads estruturalmente iguais nunca colidam.

O QUE NÃO ENTRA na intenção, por decisão de contrato:
  - `idempotency_key` — é a identidade da chamada, não a intenção;
  - `preview_fingerprint` — é estado do mundo, não intenção (D9).

Ambos são responsabilidade do chamador manter fora do objeto `intent`.

================================================================
SEGURANÇA
================================================================
`search_path = ''` e referências qualificadas. `EXECUTE` revogado de
`PUBLIC`, `anon`, `authenticated` e `service_role`: são helpers
INTERNOS, alcançados apenas de dentro das RPCs `SECURITY DEFINER` da
família Bulk. Mesmo padrão de `claim_bulk_operation()` (5144) e
`complete_bulk_operation()` (5145).

Não são `SECURITY DEFINER`: são funções PURAS, não tocam tabela alguma
e não precisam de privilégio elevado. `IMMUTABLE` pelo mesmo motivo.

Dependências: nenhuma tabela. Apenas builtins de `pg_catalog`.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.bulk_canonical_json(p_value JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
    v_type  TEXT;
    v_parts TEXT[];
BEGIN
    IF p_value IS NULL THEN
        RAISE EXCEPTION 'bulk_canonical_json: valor SQL NULL nao e JSON canonicalizavel'
            USING ERRCODE = '22023';
    END IF;

    v_type := jsonb_typeof(p_value);

    IF v_type = 'null' THEN
        RETURN 'null';

    ELSIF v_type = 'boolean' THEN
        RETURN CASE WHEN (p_value #>> '{}') = 'true' THEN 'true' ELSE 'false' END;

    ELSIF v_type = 'number' THEN
        -- trim_scale normaliza 1.50 / 1.5 / 1.500 em uma unica forma.
        RETURN trim_scale((p_value #>> '{}')::numeric)::text;

    ELSIF v_type = 'string' THEN
        RETURN to_jsonb(p_value #>> '{}')::text;

    ELSIF v_type = 'array' THEN
        SELECT COALESCE(array_agg(s.c ORDER BY s.c COLLATE "C"), ARRAY[]::text[])
          INTO v_parts
          FROM (
              SELECT public.bulk_canonical_json(e.value) AS c
                FROM jsonb_array_elements(p_value) AS e(value)
          ) s;
        RETURN '[' || array_to_string(v_parts, ',') || ']';

    ELSIF v_type = 'object' THEN
        SELECT COALESCE(
                   array_agg(
                       to_jsonb(k.key)::text || ':' ||
                       public.bulk_canonical_json(p_value -> k.key)
                       ORDER BY k.key COLLATE "C"
                   ),
                   ARRAY[]::text[]
               )
          INTO v_parts
          FROM jsonb_object_keys(p_value) AS k(key);
        RETURN '{' || array_to_string(v_parts, ',') || '}';
    END IF;

    RAISE EXCEPTION 'bulk_canonical_json: tipo JSON desconhecido %', v_type
        USING ERRCODE = '22023';
END;
$$;

COMMENT ON FUNCTION public.bulk_canonical_json(JSONB) IS
    'Serializacao canonica determinista de JSONB para a familia Bulk. Chaves de objeto ordenadas e elementos de array ordenados pelo proprio texto canonico, sempre COLLATE "C". Arrays tem semantica de CONJUNTO — deliberado, porque os chamadores Bulk rejeitam duplicatas antes. Numeros normalizados por trim_scale. Helper INTERNO: EXECUTE revogado de todos os papeis.';

CREATE FUNCTION public.bulk_request_hash(
    p_operation_type TEXT,
    p_intent         JSONB
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT encode(
               sha256(
                   convert_to(
                       p_operation_type || E'\n' || public.bulk_canonical_json(p_intent),
                       'UTF8'
                   )
               ),
               'hex'
           );
$$;

COMMENT ON FUNCTION public.bulk_request_hash(TEXT, JSONB) IS
    'request_hash canonico da familia Bulk: sha256(operation_type || LF || bulk_canonical_json(intent)), hex. FONTE UNICA — B1, B2 e BULK-03 derivam o hash exclusivamente por aqui, fechando por construcao o risco B4 (duas normalizacoes divergentes). idempotency_key e preview_fingerprint NAO entram na intencao. Helper INTERNO: EXECUTE revogado de todos os papeis.';

REVOKE EXECUTE ON FUNCTION public.bulk_canonical_json(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.bulk_request_hash(TEXT, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5822`, grupo `H`.

Provas mínimas esperadas:
- `bulk_canonical_json('[{"b":1,"a":2},{"a":2,"b":1}]'::jsonb)` produz
  os dois elementos idênticos e, portanto, um array de dois iguais;
- `bulk_request_hash('X', '{"i":[1,2]}')` = `bulk_request_hash('X', '{"i":[2,1]}')`;
- `bulk_request_hash('X', '{"n":1.50}')` = `bulk_request_hash('X', '{"n":1.5}')`;
- `bulk_request_hash('X', ...)` <> `bulk_request_hash('Y', ...)`;
- `proacl` não-NULL e sem entrada `grantee = 0` nas duas funções.
*/
