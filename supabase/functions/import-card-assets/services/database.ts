// Project Mimikyu — Edge Function: import-card-assets
// Database Service — CONFIRMADO DEPLOYADO no Sprint B3.3, junto com index.ts v1.3.0
// e o novo services/tcgdex.ts (ver docs/06-pipeline-importacao.md, "Sprint B3.3").
//
// Reescrito por completo no Sprint B3.1 (ganhou `findCardSetExternalReference`)
// e corrigido no Sprint B3.2: o import de `SupabaseClient` de
// "@supabase/supabase-js" foi removido porque esse pacote não está mapeado no
// `deno.json` da função (só há entradas para "@supabase/functions-js" e
// "@supabase/server") — o deploy real chegou a falhar por causa desse import
// (erro de bundling: "Relative import path ... not in import map"). Como este
// arquivo nunca cria um cliente Supabase (recebe sempre um já pronto via
// `ctx.supabaseAdmin`), não precisa do tipo concreto — `supabase: any` é uma
// escolha deliberada e temporária, até a arquitetura estabilizar (plano futuro
// registrado: gerar `database.types.ts` via `supabase gen types typescript` e
// trocar `any` por `SupabaseClient<Database>`).
//
// v2.5.0 (2026-07-24, retomada da implementação): bug real de tipagem
// corrigido em `upsertCardExternalReference` — `image_source_url` estava
// `string` obrigatório, divergindo da coluna real (nula, com CHECK). Ver o
// comentário da própria função, abaixo, para o detalhe completo.
//
// v2.7.0 (2026-08-02, CONFIRMADO DEPLOYADO): duas funções novas —
// `listCardIdsWithPrimaryAsset` (quais Cards já têm imagem, para pular no
// reprocessamento) e `updateImportRunProgress` (grava
// requested/processed/success/failed_count a cada lote, não só no final) —
// ver o comentário de cada uma e o histórico completo em index.ts.
//
// v2.8.0 (2026-08-02, mesmo dia, PROPOSTA — AGUARDANDO deploy, ver
// index.ts): nenhuma mudança neste arquivo — a otimização (restringir a
// sincronização de card_external_reference a `cardsToImport`) é só
// reordenação de chamadas já existentes em index.ts.
//
// v2.9.0 (2026-08-02, PROPOSTA — AGUARDANDO deploy, suporte EN + PT-BR, ver
// index.ts e Query 210 v2.0/Migration 277): três mudanças —
// `findImportRun` passa a selecionar `language_id` (idioma da run, definido
// por `admin_start_asset_import_run()` v1.3, Query 2092); nova
// `findLanguageById` (a função passa a resolver o idioma pela run, não mais
// por uma constante fixa — `findLanguageByCode` continua existindo, sem uso
// nesta função a partir de agora); `upsertCardExternalReference` ganha
// `language_id` no payload e no `onConflict` (era
// `card_id,asset_source_id`, agora `card_id,asset_source_id,language_id`) —
// sem isso, sincronizar a referência em um segundo idioma sobrescreveria a
// linha já usada pelo primeiro (mesma colisão sinalizada, não resolvida, no
// Sprint B3.23/B3.24).
//
// v2.6.0 (2026-07-25): bug real encontrado por Fabrício em produção —
// `asset_import_run` tem uma máquina de estados completa (`PENDING` →
// `RUNNING` → `COMPLETED`/`COMPLETED_WITH_ERRORS`/`FAILED`/`CANCELLED`,
// governada pelo trigger `govern_asset_import_run()`, ver
// `database/schema/221_asset_import_run_triggers.sql`), mas nenhuma versão
// anterior deste arquivo jamais escrevia nessa tabela — só o `SELECT` de
// `findImportRun`. Toda execução, inclusive as bem-sucedidas, ficava presa em
// `PENDING` para sempre. Corrigido com duas novas funções:
// `transitionImportRunToRunning` (chamada assim que a run é localizada) e
// `finishImportRun` (chamada ao final, sucesso ou falha, com as contagens
// reais). As 11 runs já executadas antes desta correção foram corrigidas via
// backfill manual (ver docs/05-modelo-de-dados.md, seção Asset Import Run,
// para o detalhe e a query real executada). CONFIRMADO DEPLOYADO E TESTADO
// EM PRODUÇÃO: o primeiro UPDATE real (`transitionImportRunToRunning`)
// expôs mais um caso do mesmo gap de GRANT já visto nas Queries 250/253/254
// — `service_role` só tinha SELECT/TRUNCATE/REFERENCES/TRIGGER em
// `asset_import_run`, confirmado por consulta direta a
// `information_schema.role_table_grants` antes de corrigir. Corrigido por
// `database/migrations/272_grant_asset_import_run_write_permissions.sql`.
// Reinvocação confirmou o fluxo completo: `PENDING` → `RUNNING` →
// `COMPLETED_WITH_ERRORS`, contagens e timestamps corretos.

export async function findImportRun(
  supabase: any,
  runCode: string,
) {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select(`
      id,
      run_code,
      asset_source_id,
      card_set_id,
      language_id,
      status,
      created_at
    `)
    .eq("run_code", runCode)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("IMPORT_RUN_QUERY_FAILED");
  }

  return data;
}

/**
 * Transiciona a run de `PENDING` para `RUNNING`, assim que ela é localizada
 * e antes de qualquer processamento real começar. O trigger
 * `govern_asset_import_run()` preenche `started_at` automaticamente.
 */
export async function transitionImportRunToRunning(
  supabase: any,
  runId: string,
) {
  const { error } = await supabase
    .from("asset_import_run")
    .update({ status: "RUNNING" })
    .eq("id", runId);

  if (error) {
    console.error(
      "IMPORT RUN TRANSITION TO RUNNING ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `IMPORT_RUN_TRANSITION_TO_RUNNING_FAILED: ${error.message}`,
    );
  }
}

/**
 * Encerra a run em um status terminal (`COMPLETED`, `COMPLETED_WITH_ERRORS`
 * ou `FAILED`), com as contagens reais do processamento. O trigger
 * `govern_asset_import_run()` preenche `finished_at` automaticamente e
 * valida a coerência entre `status` e `failed_count`
 * (`COMPLETED` exige `failed_count = 0`;
 * `COMPLETED_WITH_ERRORS` exige `failed_count > 0`).
 *
 * Deliberadamente tolerante a falha: um erro aqui é logado, mas nunca deve
 * mascarar o resultado real da importação já processado — por isso não
 * relança a exceção, apenas retorna `false` em caso de erro.
 */
export async function finishImportRun(
  supabase: any,
  runId: string,
  payload: {
    status: "COMPLETED" | "COMPLETED_WITH_ERRORS" | "FAILED";
    requested_count: number;
    processed_count: number;
    success_count: number;
    failed_count: number;
    error_summary?: string | null;
  },
): Promise<boolean> {
  const { error } = await supabase
    .from("asset_import_run")
    .update({
      status: payload.status,
      requested_count: payload.requested_count,
      processed_count: payload.processed_count,
      success_count: payload.success_count,
      failed_count: payload.failed_count,
      error_summary: payload.error_summary ?? null,
    })
    .eq("id", runId);

  if (error) {
    console.error(
      "IMPORT RUN FINISH ERROR:",
      JSON.stringify(error, null, 2),
    );
    return false;
  }

  return true;
}

/**
 * Grava o progresso parcial da run (2026-08-02, pedido explícito de
 * Fabrício: "quero enxergar o progresso real" enquanto a importação de
 * imagens está rodando) — chamada a cada lote processado (`IMAGE_BATCH_SIZE`
 * cartas), não só ao final como `finishImportRun`. Não altera `status`
 * (continua `RUNNING`, já definido por `transitionImportRunToRunning`) nem
 * `error_summary` — só os quatro contadores, para o frontend poder consultar
 * `asset_import_run` por `run_code` e mostrar "X de Y" em tempo real via
 * polling, sem esperar a função inteira terminar. Mesmo espírito tolerante a
 * falha de `finishImportRun`: um erro aqui é só logado, nunca interrompe o
 * processamento real das imagens.
 */
export async function updateImportRunProgress(
  supabase: any,
  runId: string,
  payload: {
    requested_count: number;
    processed_count: number;
    success_count: number;
    failed_count: number;
  },
): Promise<boolean> {
  const { error } = await supabase
    .from("asset_import_run")
    .update({
      requested_count: payload.requested_count,
      processed_count: payload.processed_count,
      success_count: payload.success_count,
      failed_count: payload.failed_count,
    })
    .eq("id", runId);

  if (error) {
    console.error(
      "IMPORT RUN PROGRESS UPDATE ERROR:",
      JSON.stringify(error, null, 2),
    );
    return false;
  }

  return true;
}

export async function findCardSet(
  supabase: any,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card_set")
    .select(`
      id,
      expansion_id,
      code,
      name,
      set_type,
      release_order,
      release_date,
      base_set_size,
      total_set_size
    `)
    .eq("id", cardSetId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_QUERY_FAILED");
  }

  return data;
}

export async function findCardSetExternalReference(
  supabase: any,
  cardSetId: string,
  assetSourceId: string,
) {
  const { data, error } = await supabase
    .from("card_set_external_reference")
    .select(`
      id,
      external_set_id,
      source_url
    `)
    .eq("card_set_id", cardSetId)
    .eq("asset_source_id", assetSourceId)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_EXTERNAL_REFERENCE_QUERY_FAILED");
  }

  return data;
}

export async function listCards(
  supabase: any,
  cardSetId: string,
) {
  const { data, error } = await supabase
    .from("card")
    .select(`
      id,
      card_set_id,
      rarity_id,
      category_id,
      collector_number,
      collector_total,
      collector_order,
      name
    `)
    .eq("card_set_id", cardSetId)
    .order("collector_order", {
      ascending: true,
    });

  if (error) {
    console.error(error);
    throw new Error("CARDS_QUERY_FAILED");
  }

  return data ?? [];
}

// Sprint B3.13 — Incremento 1 (CONFIRMADO CONCLUÍDO no Sprint B3.15: 188/188
// registros para a ME1). `card`/`card_variant` já estão populadas (ver
// docs/05-modelo-de-dados.md) — este incremento NUNCA insere em `card`,
// apenas localiza a carta já existente e popula `card_external_reference`.
//
// Nota real (Sprint B3.15): a primeira execução falhou com
// `permission denied for table card_external_reference` — GRANT ausente
// para `service_role`, mesmo gap já visto em `card_set_external_reference`
// (Query 250). Corrigido pela Query 253. Ver docs/06-pipeline-importacao.md,
// "Sprint B3.15".

/**
 * Carrega todas as cartas de uma coleção em um único SELECT e monta um
 * Map<collector_number, card_id> — lookup em memória O(1), evita uma consulta
 * por carta durante o loop de importação.
 */
export async function listCardsMap(
  supabase: any,
  cardSetId: string,
) {
  const cards = await listCards(
    supabase,
    cardSetId,
  );

  return new Map<string, string>(
    cards.map((card: any) => [
      card.collector_number,
      card.id,
    ]),
  );
}

/**
 * Cria ou atualiza uma referência externa da carta (card_external_reference).
 * Idempotente via ON CONFLICT (card_id, asset_source_id) DO UPDATE — uma
 * reexecução nunca duplica registros. Retorna o registro persistido.
 *
 * v2.5.0 (2026-07-24) — `image_source_url` corrigido de `string` para
 * `string | null`: a coluna no banco é nula por padrão, com uma constraint
 * que exige NULL ou uma URL `https://` válida (nunca string vazia) — nem
 * toda carta da TCGdex tem imagem. Bug de tipo latente desde a criação deste
 * arquivo, exposto agora pela primeira execução real de `deno check` contra
 * este projeto (ver services/tcgdex.ts para a correção irmã, que tornou
 * `tcgCard.image` corretamente opcional).
 *
 * v2.9.0 (2026-08-02) — `language_id` adicionado ao payload e ao
 * `onConflict` (era `card_id,asset_source_id`, agora
 * `card_id,asset_source_id,language_id`) — Query 210 v2.0/Migration 277:
 * sem o idioma na chave de conflito, sincronizar a referência em um segundo
 * idioma sobrescrevia a linha já usada pelo primeiro (colisão real
 * sinalizada, não resolvida, desde o Sprint B3.23/B3.24).
 */
export async function upsertCardExternalReference(
  supabase: any,
  payload: {
    card_id: string;
    asset_source_id: string;
    language_id: string;
    external_card_id: string;
    external_set_id: string;
    source_number: string;
    source_url: string;
    image_source_url: string | null;
    metadata: any;
    is_active: boolean;
  },
) {
  const record = {
    ...payload,
    updated_at: new Date().toISOString(),
  };

  const { data, error } = await supabase
    .from("card_external_reference")
    .upsert(record, {
      onConflict: "card_id,asset_source_id,language_id",
    })
    .select()
    .single();

  if (error) {
    console.error(
      "UPSERT ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `CARD_EXTERNAL_REFERENCE_UPSERT_FAILED: ${error.message}`,
    );
  }

  return data;
}

// Sprint B3.18/B3.19/B3.20 — Incremento 2 (Download de Imagens). CONFIRMADO
// CONCLUÍDO no Sprint B3.20: 188/188 imagens importadas para a ME1, 0
// falhas. Execução foi bloqueada, em sequência, por quatro casos reais do
// mesmo gap de GRANT já visto nas Queries 250/253 (`language`,
// `card_asset_type`, `card_asset`, `expansion` — corrigidos pela Query
// `254`), cada um diagnosticado pelo erro real do PostgreSQL nos logs da
// Edge Function, nunca adivinhado. Ver docs/06-pipeline-importacao.md,
// "Sprint B3.19" e "Sprint B3.20", para o contexto completo.
//
// Nota arquitetural real, confirmada nesta revisão por auditoria direta de
// `information_schema.columns`: `card_asset` NÃO tem uma coluna
// `card_external_reference_id` — a relação final é
// `card_id`+`asset_type_id`+`language_id`+`storage_bucket_id`.
// `card_external_reference` é apenas a fonte de importação (de onde vêm
// `image_source_url`/`external_card_id`), não participa do relacionamento
// final do ativo.

/**
 * Localiza um idioma pelo código editorial (ex.: `en`, `pt-BR`). Mantida
 * para compatibilidade (nenhum outro caminho depende dela hoje) — a partir
 * da v2.9.0, `index.ts` resolve o idioma pela run (`findLanguageById`), não
 * mais por um código fixo.
 */
export async function findLanguageByCode(
  supabase: any,
  code: string,
) {
  const { data, error } = await supabase
    .from("language")
    .select(`
      id,
      code,
      name
    `)
    .eq("code", code)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("LANGUAGE_QUERY_FAILED");
  }

  return data;
}

/**
 * Localiza um idioma pelo id (v2.9.0) — `asset_import_run.language_id`
 * (Query 220, resolvido por `admin_start_asset_import_run()` v1.3, Query
 * 2092) passa a ser a fonte real do idioma da importação, em vez de uma
 * constante fixa em `index.ts`.
 */
export async function findLanguageById(
  supabase: any,
  languageId: string,
) {
  const { data, error } = await supabase
    .from("language")
    .select(`
      id,
      code,
      name
    `)
    .eq("id", languageId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("LANGUAGE_QUERY_FAILED");
  }

  return data;
}

/**
 * Localiza um tipo de ativo da carta pelo código (ex.: `CARD_FRONT`).
 */
export async function findCardAssetTypeByCode(
  supabase: any,
  code: string,
) {
  const { data, error } = await supabase
    .from("card_asset_type")
    .select(`
      id,
      code,
      name
    `)
    .eq("code", code)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_ASSET_TYPE_QUERY_FAILED");
  }

  return data;
}

/**
 * Localiza o bucket cadastrado no catálogo interno `storage_bucket`. O
 * `code` deve corresponder ao nome do bucket físico no Supabase Storage —
 * `storage_bucket` é um catálogo de metadados, não o bucket físico em si.
 */
export async function findStorageBucketByCode(
  supabase: any,
  code: string,
) {
  const { data, error } = await supabase
    .from("storage_bucket")
    .select(`
      id,
      code,
      name,
      description,
      storage_provider,
      bucket_order,
      is_public,
      is_active
    `)
    .eq("code", code)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("STORAGE_BUCKET_QUERY_FAILED");
  }

  return data;
}

/**
 * Quais Cards, dentre `cardIds`, já têm uma imagem primária (`is_primary =
 * true`, `is_active = true`) do tipo/idioma pedidos — 2026-08-02, correção
 * real de bug reportado por Fabrício: sem isto, a função reprocessava a
 * Coleção inteira do zero a cada tentativa, então uma Coleção grande o
 * bastante para estourar o tempo de execução da plataforma travava sempre no
 * mesmo ponto, nunca progredindo entre retries manuais (caso real: SV4/Fenda
 * Paradoxal, 266 cartas, presa em ~115 em toda nova tentativa). Usada para
 * excluir essas Cards do lote de download/upload desta run — mantém a
 * garantia de idempotência já existente em `upsertCardAsset` (que também
 * nunca duplica), mas evita o custo de rede desnecessário de baixar/subir de
 * novo uma imagem que já está no Storage.
 */
export async function listCardIdsWithPrimaryAsset(
  supabase: any,
  cardIds: string[],
  assetTypeId: string,
  languageId: string,
): Promise<Set<string>> {
  if (cardIds.length === 0) {
    return new Set();
  }

  const { data, error } = await supabase
    .from("card_asset")
    .select("card_id")
    .in("card_id", cardIds)
    .eq("asset_type_id", assetTypeId)
    .eq("language_id", languageId)
    .eq("is_primary", true)
    .eq("is_active", true);

  if (error) {
    console.error(
      "CARD ASSET EXISTING QUERY ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `CARD_ASSET_EXISTING_QUERY_FAILED: ${error.message}`,
    );
  }

  return new Set((data ?? []).map((row: any) => row.card_id));
}

type CardAssetPayload = {
  card_id: string;
  asset_type_id: string;
  source_code: string | null;
  source_reference: string | null;
  storage_path: string | null;
  external_url: string | null;
  mime_type: string | null;
  file_extension: string | null;
  file_size_bytes: number | null;
  width_pixels: number | null;
  height_pixels: number | null;
  checksum_sha256: string | null;
  is_primary: boolean;
  asset_order: number;
  is_active: boolean;
  language_id: string;
  storage_bucket_id: string;
};

/**
 * Cria ou atualiza o ativo da carta (`card_asset`).
 *
 * A localização do registro existente usa a chave natural
 * `card_id`+`asset_type_id`+`language_id`+`storage_bucket_id`, em vez de um
 * `UPSERT` com `onConflict` — mantém o processamento idempotente sem
 * depender de um nome de constraint `UNIQUE` presumido, ainda não confirmado
 * para esta tabela.
 */
export async function upsertCardAsset(
  supabase: any,
  payload: CardAssetPayload,
) {
  const { data: existing, error: findError } = await supabase
    .from("card_asset")
    .select("id")
    .eq("card_id", payload.card_id)
    .eq("asset_type_id", payload.asset_type_id)
    .eq("language_id", payload.language_id)
    .eq("storage_bucket_id", payload.storage_bucket_id)
    .eq("is_active", true)
    .maybeSingle();

  if (findError) {
    console.error(
      "CARD ASSET FIND ERROR:",
      JSON.stringify(findError, null, 2),
    );
    throw new Error(
      `CARD_ASSET_QUERY_FAILED: ${findError.message}`,
    );
  }

  const record = {
    ...payload,
    updated_at: new Date().toISOString(),
  };

  if (existing) {
    const { data, error } = await supabase
      .from("card_asset")
      .update(record)
      .eq("id", existing.id)
      .select()
      .single();

    if (error) {
      console.error(
        "CARD ASSET UPDATE ERROR:",
        JSON.stringify(error, null, 2),
      );
      throw new Error(
        `CARD_ASSET_UPDATE_FAILED: ${error.message}`,
      );
    }

    return data;
  }

  const { data, error } = await supabase
    .from("card_asset")
    .insert(record)
    .select()
    .single();

  if (error) {
    console.error(
      "CARD ASSET INSERT ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `CARD_ASSET_INSERT_FAILED: ${error.message}`,
    );
  }

  return data;
}