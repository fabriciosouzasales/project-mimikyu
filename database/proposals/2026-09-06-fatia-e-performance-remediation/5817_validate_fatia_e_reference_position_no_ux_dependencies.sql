/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5817 - Validação incremental: ausência de dependências de
               UX no SQL EXECUTÁVEL de collection_pokedex_scope_positions
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-
               POSTCHECK-2C-CORRECTION-STAGING-01)

================================================================
MOTIVO — substituição da evidência do 5814 id 8 (POSTCHECK-2c)
================================================================
Em COLLECTIONS-POKEDEX-FATIA-E-PERFORMANCE-REMEDIATION-IMPLEMENTATION-01,
após 5102 e 5103 irem LIVE, o `5814` v1.3 foi reexecutado INALTERADO e
retornou 87 casos / 86 PASS / 1 FAIL. O único caso reprovado foi:

  id 8 — POSTCHECK-2c - NAO contem Primary Representative/
         assignment_count/Physical Card/UX

A asserção original do 5814 é TEXTUAL sobre `pg_get_functiondef()`:

  v_src NOT ILIKE '%primary_representative%'
  AND v_src NOT ILIKE '%assignment_count%'
  AND v_src NOT ILIKE '%physical_card%'

Duas causas, ambas confirmadas por diagnóstico read-only:

1. `_` É WILDCARD em LIKE/ILIKE. O padrão `%primary_representative%`
   significa `primary` + QUALQUER caractere + `representative`. O
   comentário do 5103 contém a frase "Primary Representative" (com
   ESPAÇO) numa única linha — e o espaço casa com o `_`. No 5101
   (versão anterior) a mesma frase estava quebrada em duas linhas
   ("Nunca consulta Primary" / "-- Representative nem ..."), com quatro
   caracteres entre as palavras, e por isso NÃO casava — foi por isso
   que o caso passava antes.

2. TOKEN LITERAL EM COMENTÁRIO. O comentário do 5103 contém
   literalmente `physical_card` na frase
   "card_primary_species, physical_card ou card_variant." — parte da
   explicação de que a função NUNCA consulta essas relações.

Ambas as ocorrências vivem EXCLUSIVAMENTE em linhas de comentário
(`-- ...`), nunca no SQL executável. A falha é um FALSO-POSITIVO
TEXTUAL causado pelo texto de comentário redigido em 5103, não uma
regressão semântica.

================================================================
GOVERNANÇA DESTA CORREÇÃO
================================================================
Decisão de COLLECTIONS-POKEDEX-FATIA-E-POSTCHECK-2C-CORRECTION-
STAGING-01:

- `5814` v1.3 NÃO é alterado. É evidência histórica já executada e
  permanece intocado, com seu resultado 86/87 registrado como está.
- `5102` e `5103` NÃO são alterados e NÃO sofrem rollback. Permanecem
  LIVE (migrations 20260906183951 e 20260906184108).
- Esta Query (`5817`) substitui EXCLUSIVAMENTE a evidência do id 8.
  NÃO repete nenhum dos outros 86 casos.

`pg_depend` NÃO É USADO COMO PROVA. Funções `LANGUAGE sql` com corpo
textual não registram, nesse catálogo, todas as relações efetivamente
referenciadas pelo corpo — em particular quando o corpo é analisado
sob `search_path = ''` e resolvido em tempo de execução. Usar
`pg_depend` para afirmar AUSÊNCIA de referência seria uma prova
inválida por construção (ausência no catálogo não implica ausência no
SQL). A prova adotada aqui é sobre o PRÓPRIO TEXTO DO SQL EXECUTÁVEL.

================================================================
FORMA DA PROVA
================================================================
1. Obter o corpo via `pg_get_functiondef()`.
2. Construir uma representação SOMENTE PARA ANÁLISE, removendo os
   comentários SQL do source:
   a. primeiro os block comments `/* ... */`
      — `regexp_replace(src, '/\*.*?\*/', ' ', 'gs')`
      — não-guloso (`*?`) e com flag `s` para que `.` cruze newline;
      — removidos ANTES dos line comments porque um block comment pode
        legitimamente conter a sequência `--` no seu interior, e
        removê-lo primeiro evita que o stripper de linha corrompa o
        fechamento `*/`;
   b. depois os line comments `-- ... <fim da linha>`
      — `regexp_replace(src, '--.*$', ' ', 'gn')`
      — flag `n`: `.` não cruza newline e `$` casa em cada fim de linha.
3. Verificar por comparação LITERAL, com `position()` sobre
   `lower(source_sem_comentarios)`. NUNCA `LIKE`/`ILIKE`, para que `_`
   e `%` não sejam interpretados como wildcards.

Critério (as três verificações mínimas do mandato):

  position('primary_representative' in exec_lower) = 0
  position('assignment_count'       in exec_lower) = 0
  position('physical_card'          in exec_lower) = 0

LIMITAÇÃO CONHECIDA E DECLARADA: a remoção de comentários é
puramente lexical e não interpreta literais de string. Se o corpo
contivesse a sequência `--` DENTRO de um literal (ex.: `'a--b'`), o
stripper truncaria a partir dali. As duas funções da Fatia E não
possuem literais com `--` (seus literais são identificadores de
domínio: 'FULL_REFERENCE', 'GENERATION_FILTERED', 'POKEDEX',
'REFERENCE_BASED', 'REFERENCE_POSITION'). Este stripper é adequado a
este alvo específico e NÃO deve ser reaproveitado cegamente para
funções com literais arbitrários. A direção do erro, caso ocorresse,
seria conservadora para a asserção de ausência (removeria texto a
mais), mas isso é registrado aqui como limitação, não como garantia.

================================================================
DIAGNÓSTICO REGISTRADO SEPARADAMENTE
================================================================
A Query devolve, além do veredito, colunas de diagnóstico que NÃO
compõem o critério de PASS, com o propósito de tornar o falso-positivo
do 5814 auditável em números:

- `diag_raw_literal_*`  — `position()` LITERAL sobre o source BRUTO
  (com comentários). Espera-se `physical_card` PRESENTE aqui, e
  `primary_representative` AUSENTE (porque no texto há um ESPAÇO, não
  um underscore).
- `diag_raw_ilike_*`    — reprodução EXATA do padrão do 5814
  (`ILIKE '%token%'`) sobre o source bruto. Espera-se TRUE para
  `primary_representative` e para `physical_card` — é isto que
  reproduz e explica a falha do id 8.
- `diag_exec_*`         — os mesmos tokens após a remoção de
  comentários. Espera-se AUSENTES nos três.
- `diag_exec_card_variant` / `diag_exec_card_primary_species` —
  verificações adicionais, meramente informativas, FORA do critério.

O contraste esperado, que é a própria tese desta Query:

  raw + ILIKE (padrão do 5814) ......... primary_representative TRUE
                                         physical_card          TRUE
  executable-source + position() ....... primary_representative  0
                                         assignment_count        0
                                         physical_card           0

================================================================
OUTRAS VERIFICAÇÕES (mesma Query, mesmo caso)
================================================================
- função existe exatamente na assinatura `(uuid, boolean)`;
- LANGUAGE sql;
- STABLE;
- SECURITY DEFINER;
- `search_path` vazio no `proconfig`;
- owner = postgres;
- `authenticated` com EXECUTE;
- `anon` SEM EXECUTE;
- nenhum GRANT de EXECUTE a PUBLIC (via `aclexplode`, grantee = 0).

================================================================
NATUREZA DA EXECUÇÃO
================================================================
100% READ-ONLY. Uma única instrução `SELECT`.
NENHUMA escrita. NENHUMA fixture. NENHUM índice. NENHUMA função
criada. NENHUMA TEMP TABLE. NENHUM `BEGIN`/`ROLLBACK` — não há
mutação a reverter, portanto não há transação explícita nem resíduo
possível. Pode ser executada com segurança em uma única chamada, e a
instrução final é a própria (e única) leitura consolidada.

RESULTADO:
  case_label   = 'POSTCHECK-2C-CORRECTED'
  total_cases  = 1
  passed       = 1 se TODAS as verificações de executable-source E de
                 segurança forem verdadeiras; caso contrário 0
  failed       = 1 - passed

Pré-requisitos:
- Query 5103 (v2.0) aplicada — esta validação incide sobre o corpo LIVE
  resultante.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

WITH raw AS (
    SELECT
        to_regprocedure('public.collection_pokedex_scope_positions(uuid, boolean)') AS fn_oid,
        pg_get_functiondef(
            to_regprocedure('public.collection_pokedex_scope_positions(uuid, boolean)')
        ) AS src_raw
),
stripped AS (
    SELECT
        r.fn_oid,
        r.src_raw,
        -- (a) block comments primeiro; (b) line comments depois.
        regexp_replace(
            regexp_replace(COALESCE(r.src_raw, ''), '/\*.*?\*/', ' ', 'gs'),
            '--.*$', ' ', 'gn'
        ) AS src_exec
    FROM raw r
),
norm AS (
    SELECT
        s.fn_oid,
        s.src_raw,
        s.src_exec,
        lower(COALESCE(s.src_raw, ''))  AS raw_lower,
        lower(COALESCE(s.src_exec, '')) AS exec_lower
    FROM stripped s
),
attrs AS (
    SELECT
        n.*,
        p.provolatile,
        p.prosecdef,
        p.proconfig,
        l.lanname,
        pg_get_userbyid(p.proowner)                AS fn_owner,
        pg_get_function_identity_arguments(p.oid)  AS ident_args,
        pg_get_function_result(p.oid)              AS result_type
    FROM norm n
    LEFT JOIN pg_proc     p ON p.oid  = n.fn_oid
    LEFT JOIN pg_language l ON l.oid  = p.prolang
),
checks AS (
    SELECT
        a.*,
        -- ---------- CRITÉRIO: executable-source (literal, sem wildcard)
        (position('primary_representative' in a.exec_lower) = 0) AS chk_exec_sem_primary_representative,
        (position('assignment_count'       in a.exec_lower) = 0) AS chk_exec_sem_assignment_count,
        (position('physical_card'          in a.exec_lower) = 0) AS chk_exec_sem_physical_card,
        -- ---------- CRITÉRIO: estrutura e segurança
        (a.fn_oid IS NOT NULL)                                   AS chk_funcao_existe,
        (a.ident_args = 'p_collection_id uuid, p_only_missing boolean') AS chk_assinatura_uuid_boolean,
        (a.lanname = 'sql')                                      AS chk_language_sql,
        (a.provolatile = 's')                                    AS chk_stable,
        (a.prosecdef IS TRUE)                                    AS chk_security_definer,
        EXISTS (
            SELECT 1 FROM unnest(a.proconfig) cfg
             WHERE split_part(cfg, '=', 1) = 'search_path'
               AND split_part(cfg, '=', 2) IN ('', '""')
        )                                                        AS chk_search_path_vazio,
        (a.fn_owner = 'postgres')                                AS chk_owner_postgres,
        has_function_privilege(
            'authenticated',
            'public.collection_pokedex_scope_positions(uuid, boolean)',
            'EXECUTE')                                           AS chk_authenticated_execute,
        (NOT has_function_privilege(
            'anon',
            'public.collection_pokedex_scope_positions(uuid, boolean)',
            'EXECUTE'))                                          AS chk_anon_sem_execute,
        (NOT EXISTS (
            SELECT 1
            FROM pg_proc p2, aclexplode(p2.proacl) x
            WHERE p2.oid = a.fn_oid
              AND x.grantee = 0
              AND x.privilege_type = 'EXECUTE'
        ))                                                       AS chk_sem_grant_public
    FROM attrs a
),
verdict AS (
    SELECT
        c.*,
        (
                c.chk_exec_sem_primary_representative
            AND c.chk_exec_sem_assignment_count
            AND c.chk_exec_sem_physical_card
            AND c.chk_funcao_existe
            AND c.chk_assinatura_uuid_boolean
            AND c.chk_language_sql
            AND c.chk_stable
            AND c.chk_security_definer
            AND c.chk_search_path_vazio
            AND c.chk_owner_postgres
            AND c.chk_authenticated_execute
            AND c.chk_anon_sem_execute
            AND c.chk_sem_grant_public
        ) AS is_pass
    FROM checks c
)
SELECT
    'POSTCHECK-2C-CORRECTED'::text            AS case_label,
    v.is_pass                                 AS passed,
    1                                         AS total_cases,
    (CASE WHEN v.is_pass THEN 1 ELSE 0 END)   AS passed_count,
    (CASE WHEN v.is_pass THEN 0 ELSE 1 END)   AS failed_count,

    -- ---------- evidência do CRITÉRIO (executable-source)
    v.chk_exec_sem_primary_representative,
    v.chk_exec_sem_assignment_count,
    v.chk_exec_sem_physical_card,

    -- ---------- evidência do CRITÉRIO (estrutura/segurança)
    v.chk_funcao_existe,
    v.chk_assinatura_uuid_boolean,
    v.chk_language_sql,
    v.chk_stable,
    v.chk_security_definer,
    v.chk_search_path_vazio,
    v.chk_owner_postgres,
    v.chk_authenticated_execute,
    v.chk_anon_sem_execute,
    v.chk_sem_grant_public,

    -- ---------- atributos observados (leitura de apoio)
    v.ident_args                              AS obs_assinatura,
    v.result_type                             AS obs_returns_table,
    v.lanname                                 AS obs_language,
    v.provolatile                             AS obs_volatile,
    v.fn_owner                                AS obs_owner,
    array_to_string(v.proconfig, ',')         AS obs_proconfig,

    -- ---------- DIAGNÓSTICO (fora do critério): source BRUTO, literal
    (position('primary_representative' in v.raw_lower) > 0) AS diag_raw_literal_primary_representative,
    (position('assignment_count'       in v.raw_lower) > 0) AS diag_raw_literal_assignment_count,
    (position('physical_card'          in v.raw_lower) > 0) AS diag_raw_literal_physical_card,

    -- ---------- DIAGNÓSTICO (fora do critério): reprodução do padrão
    -- do 5814 (ILIKE, com `_` atuando como wildcard) sobre o BRUTO.
    -- É isto que explica numericamente a falha do id 8.
    (v.src_raw ILIKE '%primary_representative%')            AS diag_raw_ilike_primary_representative,
    (v.src_raw ILIKE '%assignment_count%')                  AS diag_raw_ilike_assignment_count,
    (v.src_raw ILIKE '%physical_card%')                     AS diag_raw_ilike_physical_card,

    -- ---------- DIAGNÓSTICO (fora do critério): tokens adicionais
    -- no executable-source, meramente informativos.
    (position('card_variant'          in v.exec_lower) = 0) AS diag_exec_sem_card_variant,
    (position('card_primary_species'  in v.exec_lower) = 0) AS diag_exec_sem_card_primary_species,

    -- ---------- DIAGNÓSTICO: dimensão do stripping de comentários
    length(v.src_raw)                          AS diag_len_raw,
    length(v.src_exec)                         AS diag_len_exec,
    (length(v.src_raw) - length(v.src_exec))   AS diag_bytes_removidos_em_comentarios,

    -- ---------- autoridade: o próprio texto analisado
    v.src_exec                                 AS executable_source_sem_comentarios,
    v.src_raw                                  AS raw_source
FROM verdict v;
