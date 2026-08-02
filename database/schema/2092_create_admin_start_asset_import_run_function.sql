/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2092 - Create admin_start_asset_import_run() Function
Versão......: 1.3
Status......: PROPOSTA — AGUARDANDO EXECUÇÃO (Migration 2093 reconcilia
               banco já instalado na v1.2; instalação nova executa esta
               Query diretamente).
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01 (v1.0), 2026-08-02 (v1.1/v1.2/v1.3)

Correção v1.1 (2026-08-02): a v1.0, confirmada executada, tinha um bug
real de PL/pgSQL — `RETURNS TABLE (..., run_code TEXT, ...)` cria uma
variável implícita `run_code` visível em toda a função; as duas
consultas que liam a coluna `asset_import_run.run_code` por nome
solto (`SELECT id, run_code INTO ...`) ficaram ambíguas entre a coluna
e essa variável. Descoberto ao investigar por que a primeira
importação automática real (Coleção "151"/MEW) falhou na etapa
"Importando imagens" com a mensagem genérica "Não foi possível
concluir a ação" — confirmado nos logs do Postgres: `ERROR: column
reference "run_code" is ambiguous`. A função nunca chegava a inserir
a run (nenhuma linha em `asset_import_run` para aquele Card Set).
Corrigido qualificando a coluna como `asset_import_run.run_code` nas
duas consultas (busca de run já ativa e `INSERT ... RETURNING`); toda
a lógica de negócio é idêntica à v1.0. Assinatura não muda —
`CREATE OR REPLACE` é suficiente, sem migration própria (mesmo padrão
já usado pela correção de `admin_create_card_set()`/ENERGY, Query
2051 v1.1).

Correção v1.2 (2026-08-02): descoberta ao testar a v1.1 com uma
Coleção real e grande (SV4/Fenda Paradoxal, 266 cartas) — a Edge
Function import-card-assets morreu no meio do processamento (HTTP
546, provável limite de tempo de execução da plataforma), sem nunca
chegar em finishImportRun() (só chamada uma vez, no fim). Como essa
função é a única responsável por gravar o status final de
asset_import_run, a run ficou presa em RUNNING para sempre — e como
o bloco "evita runs duplicadas" abaixo (regra de negócio já
documentada na v1.0) trata QUALQUER linha PENDING/RUNNING como
already_active, nenhuma nova tentativa de importação de imagens para
aquele Card Set conseguia sequer chamar a Edge Function de novo. Sem
esta correção, uma Coleção grande o bastante para estourar o tempo de
execução nunca mais completaria a importação de imagens pelo app.
Corrigido: a busca por run ativa passa a ignorar linhas PENDING/RUNNING
mais velhas que 15 minutos (tempo generoso acima de qualquer execução
real e plausível da Edge Function); ao encontrar uma dessas linhas
"presas", a função a fecha como FAILED (com error_summary explicando o
motivo, finished_at = NOW()) antes de abrir a nova run normalmente —
em vez de só ignorá-la e deixar duas linhas ambíguas em aberto. Nenhum
dado de imagem é perdido nessa transição: card_asset já é gravado de
forma incremental por carta dentro da Edge Function (upsertCardAsset,
fora do escopo desta função/Query), então as imagens já importadas
pela run travada continuam no Storage/tabela normalmente — só o
bookkeeping da run em si é encerrado. A nova run reprocessa a Coleção
inteira (a Edge Function não filtra por run_type — mesma limitação de
antes, fora do escopo desta correção), o que é aceitável: reimportar
uma imagem já existente é apenas redundante, não incorreto. Assinatura
não muda — `CREATE OR REPLACE` é suficiente, sem migration própria
(mesmo padrão da v1.1).

Ampliação de escopo v1.3 (2026-08-02, Migration 2093): idioma fixo
'en' vira parâmetro `p_language_code` (DEFAULT 'en', preserva
compatibilidade com todo chamador existente) — mesma motivação de
Query 210 v2.0/Migration 277 (`[[project_mimikyu_domain_decisions]]`):
Fabrício pediu suporte real a EN + PT-BR simultaneamente depois de
notar que a importação automática nunca trazia as imagens em
português. Duas mudanças de comportamento:
1. `v_language_id` passa a ser resolvido a partir de
   `p_language_code` (antes, sempre `'en'` hardcoded) — a run já
   guarda esse valor em `asset_import_run.language_id` desde a v1.0
   (Query 220), então nenhuma coluna nova é necessária aqui; só a
   fonte do valor muda de constante para parâmetro.
2. A checagem de "run já ativa" (evita runs duplicadas) passa a
   também considerar `language_id` — antes, uma run RUNNING em `en`
   bloqueava (`already_active = true`) uma tentativa de abrir uma run
   em `pt-BR` para o MESMO Card Set, o que é incorreto agora que os
   dois idiomas podem ser importados de forma independente e
   simultânea (Migration 277 permite exatamente isso em
   `card_external_reference`). Cada (card_set_id, TCGDEX, idioma) tem
   sua própria noção de "já em andamento".
A Edge Function import-card-assets (v2.9.0, pendente) passa a ler o
idioma da própria run (`activeRun.language_id`) em vez do
`LANGUAGE_CODE`/`TCGDEX_LANGUAGE` hardcoded — esta Query só abre a
run com o idioma correto; nenhuma lógica de importação em si muda
aqui.

Descrição...:
Cria admin_start_asset_import_run(), função pública SECURITY DEFINER
— primeira via administrada (não mais SQL direto/migration avulsa
por Coleção) de abrir uma linha em public.asset_import_run
(Query 220, ADR-018/pipeline de imagens, docs/06-pipeline-
importacao.md). Motivada pela emenda de ADR-024 "Continuação
automática: cartas → imagens" (2026-08-01): depois que
admin_confirm_catalog_import() (Query 2082) persiste as Cards de
um Card Set, o frontend passa a poder continuar automaticamente
para a importação de imagens — sem depender de uma migration SQL
manual nova a cada Coleção, como acontecia até aqui (ver
database/migrations/252/255/256/257/258/259/260/261/262, um
arquivo por Coleção).

Nenhuma lógica do pipeline de imagens em si é duplicada ou
reimplementada aqui — esta função só formaliza a etapa de abertura
da run (INSERT em asset_import_run), que antes era feita por SQL
avulso; o processamento real continua inteiramente dentro da Edge
Function import-card-assets (supabase/functions/import-card-
assets/index.ts), intocada por esta Query.

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- p_card_set_id é obrigatório.
- Fonte fixa: TCGDEX (public.asset_source.code = 'TCGDEX') — único
  processador automático implementado até aqui
  (import-card-assets). Fonte MANUAL/POKEMON_TCG_API não são
  abertas por esta função.
- "Suporte à importação automática de imagens" É a existência de
  public.card_set_external_reference para (card_set_id, TCGDEX,
  is_active = true) — o mesmo dado que import-card-assets já exige
  internamente (findCardSetExternalReference) e que o próprio fluxo
  de importação de Cards via TCGdex (import-catalog-cards, ADR-024)
  já grava como parte do próprio processamento
  (upsertCardSetExternalReference). Nenhuma nova regra de detecção
  foi inventada — só reaproveitada. Quando ausente (Card Sets de
  Promo/Energia ou qualquer Set fora da cobertura da TCGdex),
  `supported = false` é devolvido sem lançar exceção — o chamador
  trata como caminho normal, não erro (ver comentário do frontend).
- Idioma parametrizado (v1.3): `p_language_code` (DEFAULT 'en')
  resolve `v_language_id` via `public.language.code`. Antes da v1.3
  era sempre `'en'` fixo, refletindo o `LANGUAGE_CODE` então
  hardcoded em import-card-assets/index.ts. O `language_id` gravado
  na run já era usado pela Edge Function (v2.9.0) para decidir o
  idioma da importação em si.
- Evita runs duplicadas: se já existe uma run PENDING/RUNNING para o
  mesmo (card_set_id, TCGDEX, idioma) criada há menos de 15 minutos,
  devolve essa run existente (`already_active = true`) em vez de
  abrir uma segunda — mesmo espírito de
  uq_catalog_import_job_fingerprint_active (Query 2060, ADR-024),
  sem precisar de uma constraint nova só para isto. Escopo por
  idioma (v1.3): uma run ativa em `en` NÃO bloqueia mais abrir uma
  run em `pt-BR` para o mesmo Card Set — os dois idiomas avançam de
  forma independente.
- Runs "presas" (v1.2): uma run PENDING/RUNNING com mais de 15 minutos
  é tratada como travada (indício de a Edge Function import-card-
  assets ter morrido no meio — timeout de plataforma — sem chegar a
  gravar o status final) — a função a fecha como FAILED (error_summary
  preenchido, finished_at = NOW()) e segue para abrir uma nova run
  normalmente, em vez de bloquear novas tentativas para sempre.
- run_type validado contra o mesmo domínio de ck_asset_import_run_type
  (Query 220): aceita apenas os cinco valores já existentes.
- execution_context sempre 'SYSTEM' (já um valor válido de
  ck_asset_import_run_execution_context, Query 220) — identifica
  runs abertas automaticamente pelo fluxo de cartas, distintas de
  'MANUAL' (pipeline manual existente, preservado sem nenhuma
  alteração) e 'API'/'SCHEDULED' (não usados ainda).
- Não grava em catalog_admin_action_log — asset_import_run já é seu
  próprio mecanismo de auditoria/rastreio (status, contadores,
  started_at/finished_at, ver Query 220), mesmo padrão já aplicado
  a catalog_import_job em ADR-024.
- run_code é gerado pelo próprio DEFAULT da tabela (sequência
  asset_import_run_code_seq, Query 220) — esta função nunca monta
  esse valor manualmente.

Pré-requisitos:
- Query 220 - Create Asset Import Run.
- Query 1060 - Create is_admin() Function.
- Tabelas asset_source, card_set_external_reference, language (schema legado 200–299).
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_start_asset_import_run(
    p_card_set_id UUID,
    p_run_type TEXT DEFAULT 'FULL_CARD_SET',
    p_initiated_by TEXT DEFAULT NULL,
    p_language_code TEXT DEFAULT 'en'
)
RETURNS TABLE (
    supported BOOLEAN,
    run_id UUID,
    run_code TEXT,
    already_active BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_asset_source_id UUID;
    v_language_id UUID;
    v_external_set_id TEXT;
    v_existing_id UUID;
    v_existing_code TEXT;
    v_existing_created_at TIMESTAMPTZ;
    v_new_id UUID;
    v_new_code TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_FORBIDDEN: apenas administradores podem iniciar uma importação de imagens.';
    END IF;

    IF p_card_set_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_MISSING_CARD_SET: p_card_set_id é obrigatório.';
    END IF;

    IF p_run_type NOT IN ('MISSING_ONLY', 'REFRESH_EXISTING', 'RETRY_FAILURES', 'SINGLE_CARD', 'FULL_CARD_SET') THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_INVALID_TYPE: run_type inválido.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_set WHERE id = p_card_set_id) THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_card_set_id;
    END IF;

    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_SOURCE_NOT_FOUND: fonte TCGDEX não cadastrada em asset_source.';
    END IF;

    -- "Suporte" = já existe o mapeamento externo que a Edge Function exige
    -- (findCardSetExternalReference) — sem essa linha, nem vale a pena abrir
    -- uma run: import-card-assets falharia com
    -- CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND. Devolver `supported = false`
    -- aqui evita abrir uma run fadada a isso.
    SELECT external_set_id INTO v_external_set_id
        FROM public.card_set_external_reference
        WHERE card_set_id = p_card_set_id
          AND asset_source_id = v_asset_source_id
          AND is_active = true;

    IF v_external_set_id IS NULL THEN
        RETURN QUERY SELECT false, NULL::UUID, NULL::TEXT, false;
        RETURN;
    END IF;

    -- Idioma parametrizado (v1.3) — antes sempre 'en' fixo.
    SELECT id INTO v_language_id FROM public.language WHERE code = p_language_code;
    IF v_language_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_START_ASSET_IMPORT_RUN_LANGUAGE_NOT_FOUND: idioma % não cadastrado em language.', p_language_code;
    END IF;

    -- `asset_import_run.run_code` qualificado explicitamente (v1.1) —
    -- `RETURNS TABLE` acima declara uma variável implícita `run_code`
    -- visível aqui dentro; um `run_code` solto é ambíguo entre ela e a
    -- coluna da tabela, e falha em tempo de execução (não é um erro que
    -- `RAISE EXCEPTION`/`traduzirErroCatalogo` conseguem traduzir).
    -- Escopo por language_id (v1.3) — uma run ativa em outro idioma para
    -- o mesmo Card Set não deve ser tratada como "a mesma" importação.
    SELECT id, asset_import_run.run_code, created_at
        INTO v_existing_id, v_existing_code, v_existing_created_at
        FROM public.asset_import_run
        WHERE card_set_id = p_card_set_id
          AND asset_source_id = v_asset_source_id
          AND language_id = v_language_id
          AND status IN ('PENDING', 'RUNNING')
        ORDER BY created_at DESC
        LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        IF v_existing_created_at >= NOW() - INTERVAL '15 minutes' THEN
            -- ainda dentro da janela plausível de execução da Edge
            -- Function — trata como run de verdade em andamento.
            RETURN QUERY SELECT true, v_existing_id, v_existing_code, true;
            RETURN;
        END IF;

        -- Run "presa" (v1.2): mais velha que 15 minutos e ainda em
        -- PENDING/RUNNING — indício de a Edge Function import-card-
        -- assets ter morrido no meio do processamento (timeout de
        -- plataforma) sem chegar a chamar finishImportRun(). Fecha
        -- como FAILED em vez de deixá-la bloqueando novas tentativas
        -- para sempre; nenhuma imagem já importada é afetada
        -- (card_asset é gravado de forma incremental, fora desta
        -- função).
        UPDATE public.asset_import_run
            SET status = 'FAILED',
                error_summary = 'Run marcada como FAILED automaticamente por admin_start_asset_import_run() (v1.2): ficou parada em PENDING/RUNNING por mais de 15 minutos sem concluir — indício de timeout da Edge Function import-card-assets antes de gravar o resultado final. Uma nova run foi aberta para retomar a importação.',
                finished_at = NOW(),
                updated_at = NOW()
            WHERE id = v_existing_id;
    END IF;

    INSERT INTO public.asset_import_run (asset_source_id, card_set_id, language_id, run_type, execution_context, initiated_by)
        VALUES (v_asset_source_id, p_card_set_id, v_language_id, p_run_type, 'SYSTEM', p_initiated_by)
        RETURNING id, asset_import_run.run_code INTO v_new_id, v_new_code;

    RETURN QUERY SELECT true, v_new_id, v_new_code, false;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_start_asset_import_run(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_start_asset_import_run(UUID, TEXT, TEXT, TEXT) TO authenticated;
