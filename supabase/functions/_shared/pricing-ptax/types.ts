// Project Mimikyu — supabase/functions/_shared/pricing-ptax
// Núcleo compartilhado de ingestão PTAX (Incremento P13.2, 2026-08-18).
//
// Tipos centrais do módulo. Núcleo puro: nada aqui lê variável de ambiente, cria
// cliente Supabase real, ou chama Deno.env/process.env/fetch()/setTimeout() do
// ambiente global diretamente — toda dependência externa é injetada pelo chamador
// (adapter manual em scripts/sync-ptax-fx-rate.ts hoje; futura Edge Function
// agendada em P13.3+, reaproveitando exatamente estes mesmos tipos e funções, nunca
// duplicando a lógica).

export type CivilDate = string; // "YYYY-MM-DD" — sempre uma data civil, nunca timestamp

export interface PtaxPeriod {
  startDate: CivilDate;
  endDate: CivilDate;
}

// Forma bruta de um item da resposta do BCB (CotacaoDolarPeriodo), já validada por
// validatePtaxResponseShape() — ver validate.ts.
export interface PtaxRawItem {
  cotacaoCompra: number;
  cotacaoVenda: number;
  dataHoraCotacao: string;
}

// Uma cotação já resolvida (fechamento selecionado) e pronta para comparação/persistência.
export interface PtaxRate {
  rateDate: CivilDate;
  rate: number; // cotação de VENDA — decisão registrada em 05f-pricing.md, Incremento P9, preservada aqui
}

export type PtaxFetchOutcome = "SUCCESS" | "TECHNICAL_FAILURE";

// Mesma forma de log de chamada já usada pelo conector JustTCG (P8) —
// pricing_sync_run_call já tem exatamente estas colunas, nenhuma nova é necessária.
export interface PtaxCallLogEntry {
  sequenceNumber: number;
  endpoint: string;
  httpStatusCode: number | null;
  outcome: PtaxFetchOutcome;
  errorDetail: string | null;
  apiRequestsRemaining: number | null; // BCB não expõe orçamento de requisições — sempre null aqui
}

export interface PersistCounts {
  inserted: number;
  unchanged: number;
  divergent: number;
  invalid: number;
}

export interface DivergenceDetail {
  rateDate: CivilDate;
  existingRate: number;
  incomingRate: number;
}

export interface InvalidDetail {
  reason: string;
  raw?: unknown;
}

// Resultado estruturado de uma execução completa do núcleo — o adapter (manual ou
// futura Edge Function) decide como mapear isto para pricing_sync_run/status.
export type PtaxRunResult =
  | { kind: "TECHNICAL_FAILURE"; detail: string; callLog: PtaxCallLogEntry[] }
  | { kind: "FUNCTIONAL_FAILURE"; detail: string; callLog: PtaxCallLogEntry[] }
  | {
    kind: "COMPLETED";
    period: PtaxPeriod;
    quotesReceived: number;
    counts: PersistCounts;
    divergences: DivergenceDetail[];
    invalidDetails: InvalidDetail[];
    callLog: PtaxCallLogEntry[];
  };

// Dependências injetáveis — nunca lidas de um global fixo dentro do núcleo.
export type FetchLike = typeof fetch;
export type WaitLike = (ms: number) => Promise<void>;

// Contrato mínimo de persistência que o núcleo exige do chamador. O adapter manual
// implementa isto sobre o Supabase client real; um teste implementa isto sobre um
// Map em memória — o núcleo não sabe (nem precisa saber) qual dos dois está em uso.
export interface PtaxRateRepository {
  // Lê as taxas já persistidas para as datas informadas (mesmo par de moeda/fonte,
  // sempre USD->BRL/BCB_PTAX neste incremento). Deve devolver só as datas que
  // realmente existem — ausência de uma data no Map significa "nunca foi gravada".
  findExistingRates(dates: CivilDate[]): Promise<Map<CivilDate, number>>;
  // Insere de forma idempotente (ON CONFLICT DO NOTHING real, nunca UPDATE). Deve
  // devolver "CONFLICT_IGNORED" (não "INSERTED") se outra execução concorrente já
  // tiver gravado a mesma linha entre a leitura e esta chamada.
  insertRate(entry: PtaxRate): Promise<"INSERTED" | "CONFLICT_IGNORED">;
}
