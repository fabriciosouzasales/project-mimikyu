// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/supabase-adapter.ts
// Única implementação de PriceRefreshRunPort sobre o SupabaseClient real — Incremento de
// Atualização Diária JustTCG (2026-08-21), item B/C.
//
// Mesmo padrão de supabase/functions/_shared/pricing-ptax/supabase-adapter.ts: este é o
// ÚNICO arquivo do núcleo de refresh que importa/usa SupabaseClient — core.ts, wave-
// plan.ts, extract.ts, observation-decision.ts e run-lifecycle.ts nunca o veem. Construído
// uma única vez pela Edge Function (index.ts), reaproveitado para todas as operações.
//
// AVISO IMPORTANTE (paralelo ao incidente real documentado no Incremento P14.4.1 do CLI,
// "Fix P14.4.1 — Truncamento de 1.000 linhas do Data API"): pricing_source_card_identity
// já tem ~8.143 linhas para a fonte JUSTTCG (7.335 PRIMARY + 808 ALTERNATE, 2026-08-20) —
// acima do limite padrão de 1.000 linhas por requisição do PostgREST quando nenhum
// `.range()` é informado. TODA leitura deste adapter que pode crescer além de 1.000 linhas
// é paginada explicitamente via fetchAllRows() abaixo (mesmo padrão de fetchAllPages() no
// CLI) — nunca um `.select()` solto sem `.range()`.
//
// Este arquivo NUNCA foi executado neste ciclo (sem SupabaseClient real disponível no
// ambiente de validação offline) — mesma limitação já documentada para
// pricing-ptax/supabase-adapter.ts em P13.3. A primeira execução real acontece no dry-run
// que Fabrício roda localmente/no Supabase, não nesta rodada.

import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  ExistingProductRow,
  FinalRefreshRunStatus,
  InsertedProductRow,
  InsertObservationInput,
  InsertObservationsResult,
  InsertPriceRefreshRunResult,
  InsertProductInput,
  InsertProductsResult,
  LatestObservationKey,
  LatestObservationRow,
  PriceRefreshCallLogEntry,
  RefreshIdentityRow,
  RefreshSetCandidate,
  UpdateSyncRunPatch,
} from "./port.ts";
import type { PriceRefreshRunPort } from "./run-lifecycle.ts";

// Logger sanitizado e injetável — mesmo contrato de
// justtcg-price-refresh/handler.ts (SanitizedLogger/defaultSanitizedLogger), duplicado
// aqui deliberadamente em vez de importado: este arquivo vive em _shared/ e nunca deve
// depender de um tipo definido dentro de uma Edge Function específica (camada invertida —
// o núcleo compartilhado não conhece seus consumidores). Só usado por updateSyncRun
// abaixo; as demais operações deste adapter nunca logam (lançam ou retornam um código
// fixo — ver bloco de comentário logo abaixo desta declaração).
export type SanitizedLogger = (
  code: string,
  context?: Readonly<Record<string, unknown>>,
) => void;

function defaultSanitizedLogger(
  code: string,
  context?: Readonly<Record<string, unknown>>,
): void {
  if (context && Object.keys(context).length > 0) {
    console.error(code, context);
  } else {
    console.error(code);
  }
}

// Correção de segurança (2026-08-21, 3ª rodada — "gate local"): as 13 ocorrências abaixo
// (9 `throw new Error(...)` de leitura + 4 `return {..., message: ...}` de escrita) antes
// interpolavam `error.message` bruto do PostgREST na própria mensagem/campo retornado.
// Como run-lifecycle.ts e core.ts só REPASSAM essas strings adiante — sem nunca as
// inspecionar ou alterar — elas acabavam, sem qualquer sanitização real, em
// `pricing_sync_run.error_summary` (telemetria persistida) e, em alguns casos, em
// `errorParts`/`WaveExecutionResult.errorParts` (potencialmente visível a quem lê a
// telemetria). `sanitize()` (_shared/pricing-justtcg/mod.ts) só redige padrões
// CONHECIDOS (chave `tcg_...`, `bearer ...`) — nunca uma garantia geral contra texto cru
// arbitrário do Postgres (nome de coluna/constraint, fragmento de query, etc.).
//
// Corrigido na origem (aqui, não em run-lifecycle.ts/core.ts — eles não precisam mudar):
// cada operação agora usa exclusivamente um código fixo, sanitizado e distinto por
// operação — nunca `error.message`, `error.details`, `error.hint`, `error.stack`, o
// objeto `error` em si, nem qualquer payload/query enviados ao Postgres. `error.code`
// (ex.: "23505") continua sendo LIDO para decidir um branch (nunca persistido/logado) —
// não é o tipo de conteúdo problemático aqui (é um código de erro SQL padronizado de 5
// caracteres, não um texto livre que possa carregar dado sensível).

// Mesmo rótulo de mercado já usado por scripts/sync-justtcg-pricing.ts (persistBatchedResults,
// Fase 3) — precisa continuar idêntico entre os dois escritores para que a comparação
// "última observação conhecida" (observation-decision.ts) encontre o grupo correto
// (pricing_product_id + condition_id + price_type + currency_code + market_label).
const MARKET_LABEL = "JUSTTCG_AGGREGATE";
const PAGE_SIZE = 500;
const CHUNK_SIZE = 200; // tamanho de lote para cláusulas .in() — evita URLs excessivamente longas

function chunk<T>(arr: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    out.push(arr.slice(i, i + size) as T[]);
  }
  return out;
}

// Paginação determinística (.order("id").range(...)) — nunca deduz término por total
// presumido, sempre até uma página vir vazia/mais curta que PAGE_SIZE. Mesmo padrão de
// fetchAllPages() em scripts/sync-justtcg-pricing.ts (P14.4.1 fix).
//
// Tipo de retorno de `build` como `any` (deliberado, não um descuido): o SupabaseClient
// deste adapter é usado sem generics de Database (mesmo padrão de todo o arquivo), então
// cada `.select(colunas as any)` nos 3 call sites abaixo produz um `PostgrestFilterBuilder`
// especializado em um formato de linha DIFERENTE por chamada (`GenericStringError[]` —
// sentinela do supabase-js para select-string não estaticamente parseável). Declarar aqui
// um tipo de retorno fixo e específico (ex.: `ReturnType<QueryBuilder["select"]>`) nunca
// bate com o formato real de nenhuma chamada individual — daí os 3 erros TS2739
// ("missing properties from PostgrestQueryBuilder") reportados por `deno check`. A forma
// segura já usada em cada call site abaixo continua sendo `.select(<colunas> as any)` — o
// resultado desta função já é sempre estreitado para `T[]` logo abaixo, então o formato de
// linha do builder nunca escapa para o chamador.
async function fetchAllRows<T>(
  supabase: SupabaseClient,
  table: string,
  // deno-lint-ignore no-explicit-any
  build: (q: ReturnType<SupabaseClient["from"]>) => any,
): Promise<T[]> {
  const out: T[] = [];
  let offset = 0;
  for (;;) {
    const query = build(supabase.from(table));
    const { data, error } = await query
      .order("id", { ascending: true })
      .range(offset, offset + PAGE_SIZE - 1);
    if (error) {
      throw new Error(`${table.toUpperCase()}_PAGINATED_QUERY_FAILED`);
    }
    const rows = (data ?? []) as T[];
    out.push(...rows);
    if (rows.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }
  return out;
}

export function buildPricingJustTcgRefreshSupabaseAdapter(
  supabase: SupabaseClient,
  // Opcional — default seguro (defaultSanitizedLogger acima) quando o chamador não injeta
  // nada; index.ts não precisa saber deste detalhe para funcionar corretamente (mesma
  // disciplina de handler.ts/pricing-source-lookup.ts). Só updateSyncRun usa; testes
  // injetam um espião para provar, por asserção, que nenhum detalhe sensível chega aqui.
  logError: SanitizedLogger = defaultSanitizedLogger,
): PriceRefreshRunPort {
  return {
    async listRefreshCandidateSets(
      pricingSourceId: string,
    ): Promise<RefreshSetCandidate[]> {
      // Passo 1 — Sets CONFIRMED em pricing_set_mapping (nunca escreve; leitura pura).
      type SetMappingRow = {
        card_set_id: string;
        external_set_id: string | null;
      };
      const setMappingRows = await fetchAllRows<SetMappingRow>(
        supabase,
        "pricing_set_mapping",
        (q) =>
          q
            // deno-lint-ignore no-explicit-any
            .select("card_set_id, external_set_id" as any)
            .eq("pricing_source_id", pricingSourceId)
            .eq("match_status", "CONFIRMED"),
      );
      const externalSetIdByCardSetId = new Map<string, string>();
      for (const row of setMappingRows) {
        if (row.external_set_id) {
          externalSetIdByCardSetId.set(row.card_set_id, row.external_set_id);
        }
      }

      // Passo 2 — identidades PRIMARY/ALTERNATE CONFIRMED da fonte (regra 17: PENDING/
      // REJECTED/ALIAS nunca entram aqui).
      type IdentityRow = {
        id: string;
        external_card_id: string;
        pricing_card_mapping_id: string;
      };
      const identityRows = await fetchAllRows<IdentityRow>(
        supabase,
        "pricing_source_card_identity",
        (q) =>
          q
            // deno-lint-ignore no-explicit-any
            .select("id, external_card_id, pricing_card_mapping_id" as any)
            .eq("pricing_source_id", pricingSourceId)
            .eq("match_status", "CONFIRMED")
            .in("identity_role", ["PRIMARY", "ALTERNATE"]),
      );

      if (identityRows.length === 0) {
        return [];
      }

      // Passo 3 — pricing_card_mapping -> card_id, em lotes .in().
      const mappingIds = [
        ...new Set(identityRows.map((r) => r.pricing_card_mapping_id)),
      ];
      const cardIdByMappingId = new Map<string, string>();
      for (const ids of chunk(mappingIds, CHUNK_SIZE)) {
        const { data, error } = await supabase
          .from("pricing_card_mapping")
          .select("id, card_id")
          .in("id", ids);
        if (error) {
          throw new Error("PRICING_CARD_MAPPING_BATCH_SELECT_FAILED");
        }
        for (
          const row of (data ?? []) as Array<{ id: string; card_id: string }>
        ) {
          cardIdByMappingId.set(row.id, row.card_id);
        }
      }

      // Passo 4 — card -> card_set_id, em lotes .in().
      const cardIds = [...new Set([...cardIdByMappingId.values()])];
      const cardSetIdByCardId = new Map<string, string>();
      for (const ids of chunk(cardIds, CHUNK_SIZE)) {
        const { data, error } = await supabase
          .from("card")
          .select("id, card_set_id")
          .in("id", ids);
        if (error) {
          throw new Error("CARD_BATCH_SELECT_FAILED");
        }
        for (
          const row of (data ?? []) as Array<
            { id: string; card_set_id: string }
          >
        ) {
          cardSetIdByCardId.set(row.id, row.card_set_id);
        }
      }

      // Passo 5 — card_set -> code, para os Sets efetivamente envolvidos.
      const cardSetIds = [...new Set([...cardSetIdByCardId.values()])];
      const codeByCardSetId = new Map<string, string>();
      for (const ids of chunk(cardSetIds, CHUNK_SIZE)) {
        const { data, error } = await supabase
          .from("card_set")
          .select("id, code")
          .in("id", ids);
        if (error) {
          throw new Error("CARD_SET_BATCH_SELECT_FAILED");
        }
        for (
          const row of (data ?? []) as Array<{ id: string; code: string }>
        ) {
          codeByCardSetId.set(row.id, row.code);
        }
      }

      // Passo 6 — agrega: para cada Set com external_set_id CONFIRMED, conta
      // external_card_id DISTINTOS entre as identidades PRIMARY/ALTERNATE CONFIRMED cujo
      // card pertence a este Set.
      const distinctExternalCardIdsByCardSetId = new Map<string, Set<string>>();
      for (const identity of identityRows) {
        const cardId = cardIdByMappingId.get(identity.pricing_card_mapping_id);
        if (!cardId) continue; // defensivo — mapping sem card correspondente (nunca deveria ocorrer, FK garante integridade)
        const cardSetId = cardSetIdByCardId.get(cardId);
        if (!cardSetId) continue;
        if (!externalSetIdByCardSetId.has(cardSetId)) continue; // Set sem pricing_set_mapping CONFIRMED — fora de escopo
        if (!distinctExternalCardIdsByCardSetId.has(cardSetId)) {
          distinctExternalCardIdsByCardSetId.set(cardSetId, new Set());
        }
        distinctExternalCardIdsByCardSetId.get(cardSetId)!.add(
          identity.external_card_id,
        );
      }

      const candidates: RefreshSetCandidate[] = [];
      for (
        const [cardSetId, externalIds] of distinctExternalCardIdsByCardSetId
      ) {
        const externalSetId = externalSetIdByCardSetId.get(cardSetId);
        const setCode = codeByCardSetId.get(cardSetId);
        if (!externalSetId || !setCode) continue; // defensivo
        candidates.push({
          cardSetId,
          setCode,
          externalSetId,
          confirmedCardCount: externalIds.size,
        });
      }
      return candidates;
    },

    async listConfirmedIdentitiesForSet(
      pricingSourceId: string,
      cardSetId: string,
    ): Promise<RefreshIdentityRow[]> {
      // Mesma cadeia do Passo 2-4 acima, restrita a um único Set — reconstruída aqui em
      // vez de reaproveitar listRefreshCandidateSets() porque o chamador (core.ts) só
      // precisa das identidades de UM Set por vez (o da onda em processamento), nunca do
      // catálogo inteiro de novo.
      type IdentityRow = {
        id: string;
        external_card_id: string;
        identity_role: "PRIMARY" | "ALTERNATE";
        pricing_card_mapping_id: string;
      };
      const identityRows = await fetchAllRows<IdentityRow>(
        supabase,
        "pricing_source_card_identity",
        (q) =>
          q
            .select(
              // deno-lint-ignore no-explicit-any
              "id, external_card_id, identity_role, pricing_card_mapping_id" as any,
            )
            .eq("pricing_source_id", pricingSourceId)
            .eq("match_status", "CONFIRMED")
            .in("identity_role", ["PRIMARY", "ALTERNATE"]),
      );
      if (identityRows.length === 0) return [];

      const mappingIds = [
        ...new Set(identityRows.map((r) => r.pricing_card_mapping_id)),
      ];
      const cardIdByMappingId = new Map<string, string>();
      for (const ids of chunk(mappingIds, CHUNK_SIZE)) {
        const { data, error } = await supabase
          .from("pricing_card_mapping")
          .select("id, card_id")
          .in("id", ids);
        if (error) {
          // Código distinto do homônimo em listRefreshCandidateSets acima — mesma
          // operação (SELECT em pricing_card_mapping), mas trajeto de chamada diferente
          // (restrito a um Set em vez do catálogo inteiro); manter distinguível para
          // diagnóstico (item 4 do pedido de Fabrício).
          throw new Error("PRICING_CARD_MAPPING_BATCH_SELECT_BY_SET_FAILED");
        }
        for (
          const row of (data ?? []) as Array<{ id: string; card_id: string }>
        ) {
          cardIdByMappingId.set(row.id, row.card_id);
        }
      }

      const cardIds = [...new Set([...cardIdByMappingId.values()])];
      const cardIdsInSet = new Set<string>();
      for (const ids of chunk(cardIds, CHUNK_SIZE)) {
        const { data, error } = await supabase
          .from("card")
          .select("id, card_set_id")
          .eq("card_set_id", cardSetId)
          .in("id", ids);
        if (error) {
          // Código distinto do homônimo em listRefreshCandidateSets — mesma disciplina de
          // PRICING_CARD_MAPPING_BATCH_SELECT_BY_SET_FAILED acima.
          throw new Error("CARD_BATCH_SELECT_BY_SET_FAILED");
        }
        for (const row of (data ?? []) as Array<{ id: string }>) {
          cardIdsInSet.add(row.id);
        }
      }

      const result: RefreshIdentityRow[] = [];
      for (const identity of identityRows) {
        const cardId = cardIdByMappingId.get(identity.pricing_card_mapping_id);
        if (!cardId || !cardIdsInSet.has(cardId)) continue;
        result.push({
          identityId: identity.id,
          externalCardId: identity.external_card_id,
          identityRole: identity.identity_role,
          pricingCardMappingId: identity.pricing_card_mapping_id,
        });
      }
      return result;
    },

    async getConditionMap(
      pricingSourceId: string,
    ): Promise<Map<string, string>> {
      const { data, error } = await supabase
        .from("pricing_condition_mapping")
        .select("external_condition_code, condition_id")
        .eq("pricing_source_id", pricingSourceId);
      if (error) {
        throw new Error("CONDITION_MAPPING_QUERY_FAILED");
      }
      return new Map(
        (
          data ?? []
        ).map((
          r: { external_condition_code: string; condition_id: string },
        ) => [r.external_condition_code, r.condition_id]),
      );
    },

    async findExistingProducts(
      identityIds: readonly string[],
    ): Promise<ExistingProductRow[]> {
      if (identityIds.length === 0) return [];
      const out: ExistingProductRow[] = [];
      for (const ids of chunk(identityIds, CHUNK_SIZE)) {
        const { data, error } = await supabase
          .from("pricing_product")
          .select("id, pricing_source_card_identity_id, external_product_id")
          .in("pricing_source_card_identity_id", ids);
        if (error) {
          throw new Error("PRODUCT_BATCH_SELECT_FAILED");
        }
        for (
          const row of (data ?? []) as Array<{
            id: string;
            pricing_source_card_identity_id: string;
            external_product_id: string;
          }>
        ) {
          out.push({
            productId: row.id,
            pricingSourceCardIdentityId: row.pricing_source_card_identity_id,
            externalProductId: row.external_product_id,
          });
        }
      }
      return out;
    },

    async findLatestObservations(
      keys: readonly LatestObservationKey[],
    ): Promise<LatestObservationRow[]> {
      if (keys.length === 0) return [];
      const out: LatestObservationRow[] = [];
      for (const keysChunk of chunk(keys, CHUNK_SIZE)) {
        const payload = keysChunk.map((k) => ({
          pricing_product_id: k.productId,
          condition_id: k.conditionId,
          price_type: "MARKET",
          currency_code: "USD",
          market_label: MARKET_LABEL,
        }));
        const { data, error } = await supabase.rpc(
          "batch_select_latest_pricing_observation_by_identity",
          { p_keys: payload },
        );
        if (error) {
          throw new Error("OBSERVATION_LATEST_BATCH_SELECT_FAILED");
        }
        for (
          const row of (data ?? []) as Array<{
            pricing_product_id: string;
            condition_id: string;
            observed_at: string;
            price: number;
          }>
        ) {
          out.push({
            productId: row.pricing_product_id,
            conditionId: row.condition_id,
            price: Number(row.price),
            observedAt: row.observed_at,
          });
        }
      }
      return out;
    },

    async insertProducts(
      rows: readonly InsertProductInput[],
    ): Promise<InsertProductsResult> {
      if (rows.length === 0) return { ok: true, inserted: [] };
      const inserted: InsertedProductRow[] = [];
      for (const batch of chunk(rows, CHUNK_SIZE)) {
        const { data, error } = await supabase
          .from("pricing_product")
          .insert(
            batch.map((r) => ({
              // pricing_card_mapping_id: obrigatório (NOT NULL) na tabela física —
              // resolvido pelo chamador (core.ts) a partir da própria leitura da
              // identidade em pricing_source_card_identity.pricing_card_mapping_id
              // (RefreshIdentityRow.pricingCardMappingId), nunca por uma segunda
              // consulta aqui. Vale tanto para identidades PRIMARY quanto ALTERNATE —
              // ambas compartilham o mesmo pricing_card_mapping_id da carta local.
              pricing_card_mapping_id: r.pricingCardMappingId,
              pricing_source_card_identity_id: r.pricingSourceCardIdentityId,
              external_product_id: r.externalProductId,
              source_printing_label: r.sourcePrintingLabel,
              language_status: "UNDETERMINED",
              language_id: null,
            })),
          )
          .select("id, pricing_source_card_identity_id, external_product_id");
        if (error) {
          return { ok: false, message: "PRODUCT_INSERT_FAILED" };
        }
        for (
          const row of (data ?? []) as Array<{
            id: string;
            pricing_source_card_identity_id: string;
            external_product_id: string;
          }>
        ) {
          inserted.push({
            productId: row.id,
            pricingSourceCardIdentityId: row.pricing_source_card_identity_id,
            externalProductId: row.external_product_id,
          });
        }
      }
      return { ok: true, inserted };
    },

    async insertObservations(
      rows: readonly InsertObservationInput[],
    ): Promise<InsertObservationsResult> {
      if (rows.length === 0) return { ok: true };
      for (const batch of chunk(rows, CHUNK_SIZE)) {
        const { error } = await supabase.from("pricing_observation").insert(
          batch.map((r) => ({
            pricing_product_id: r.productId,
            condition_id: r.conditionId,
            sync_run_id: r.syncRunId,
            price_type: "MARKET",
            price: r.price,
            currency_code: "USD",
            market_label: MARKET_LABEL,
            market_scope: "UNDETERMINED",
            market_evidence: {},
            market_evidence_confirmed: false,
            observed_at: r.observedAt,
            raw_payload: r.rawPayload,
          })),
        );
        if (error) {
          return { ok: false, message: "OBSERVATION_INSERT_FAILED" };
        }
      }
      return { ok: true };
    },

    async insertPriceRefreshRun(
      pricingSourceId: string,
    ): Promise<InsertPriceRefreshRunResult> {
      const { data, error } = await supabase
        .from("pricing_sync_run")
        .insert({
          pricing_source_id: pricingSourceId,
          run_type: "PRICE_REFRESH",
          status: "PROCESSING",
          triggered_by: "SCHEDULED",
          confirmed_by: null,
        })
        .select("id")
        .single();
      if (error) {
        // 23505 (unique_violation) só pode vir de um dos dois índices únicos parciais que
        // guardam concorrência para esta fonte: o pré-existente
        // (ux_pricing_sync_run_active_price_per_source_type, por pricing_source_id+
        // run_type) ou o novo desta rodada (item D — mútua exclusão CARD_SYNC×
        // PRICE_REFRESH, por pricing_source_id apenas). Nunca precisamos distinguir qual
        // dos dois disparou — ambos significam a mesma coisa para este chamador: já existe
        // uma sincronização ativa desta fonte, aborta antes de tocar a JustTCG.
        if ((error as { code?: string }).code === "23505") {
          return { outcome: "CONCURRENT_CONFLICT" };
        }
        return { outcome: "OTHER_ERROR", message: "SYNC_RUN_START_FAILED" };
      }
      return { outcome: "STARTED", syncRunId: (data as { id: string }).id };
    },

    async insertSyncRunCalls(
      syncRunId: string,
      callLog: readonly PriceRefreshCallLogEntry[],
    ): Promise<InsertObservationsResult> {
      if (callLog.length === 0) return { ok: true };
      const { error } = await supabase.from("pricing_sync_run_call").insert(
        callLog.map((c) => ({ ...c, sync_run_id: syncRunId })),
      );
      if (error) return { ok: false, message: "SYNC_RUN_CALL_INSERT_FAILED" };
      return { ok: true };
    },

    async updateSyncRun(
      syncRunId: string,
      patch: UpdateSyncRunPatch,
    ): Promise<void> {
      const { error } = await supabase
        .from("pricing_sync_run")
        .update({
          status: patch.status satisfies FinalRefreshRunStatus,
          requests_made: patch.requestsMade,
          rate_limit_hits: patch.rateLimitHits,
          error_summary: patch.errorSummary,
        })
        .eq("id", syncRunId);
      if (error) {
        // Correção de segurança (2026-08-21, 2ª rodada; injeção adicionada na 3ª rodada
        // para tornar testável) — `error.message` aqui é a resposta bruta do PostgREST e
        // nunca deve chegar a Function Logs, nem mesmo neste caminho de "best effort" (a
        // função não lança — só resta logar). Código fixo + contexto operacional já
        // seguro (syncRunId e o status pretendido, ambos auditáveis por consulta direta à
        // tabela) — nunca error/message/stack/objeto PostgREST.
        logError("JUSTTCG_PRICE_REFRESH_SYNC_RUN_FINALIZE_FAILED", {
          syncRunId,
          intendedStatus: patch.status,
        });
      }
    },
  };
}
