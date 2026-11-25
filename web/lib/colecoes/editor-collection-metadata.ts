import { isBinderFinish } from "./binder-finish.ts";
import { normalizeCollectionName } from "./colecoes.ts";
import { normalizeCoverCode } from "./free-collection.ts";

/**
 * V1-13 · E3-3 — metadados da coleção pelo EDITOR (5376): nome, descrição,
 * acabamento da capa e código da placa. Regras puras, sem rede.
 *
 * O servidor é a autoridade: EDITOR ACTIVE da coleção (C-239), coleção ativa,
 * barreira da V1-13 (5389). Nada estrutural passa por aqui (Set, escopo do
 * Master Set, política, modalidade, visibilidade, arquivamento, membros).
 *
 * Concorrência: as funções da 5376 travam a linha da coleção, mas NÃO têm
 * versão — a última escrita vence. Para não sobrescrever às cegas uma mudança
 * recente do titular (ou de outro EDITOR), a ação relê o valor atual pela
 * leitura do participante logo antes de gravar e recusa se ele mudou desde que
 * o formulário foi aberto (`changed`). Isso reduz, mas não elimina, a janela
 * entre a releitura e a gravação.
 */

/** Limite de interface para a descrição (o banco não tem limite; aqui só evita textos acidentais enormes). */
export const COLLECTION_DESCRIPTION_MAX = 500;

/** Descrição digitada → valor gravado: espaços nas pontas fora; vazia = sem descrição (`null`). `undefined` = longa demais. */
export function normalizeCollectionDescription(raw: string): string | null | undefined {
  const text = raw.replace(/\r\n/g, "\n").trim();
  if (text === "") return null;
  return text.length > COLLECTION_DESCRIPTION_MAX ? undefined : text;
}

/** O código da placa só existe em coleção livre ou Pokédex (a 5376 recusa as demais com `NOT_FREE_COLLECTION`). */
export function editorCoverCodeApplies(collection: { completionPolicy: string | null; cardSetCode: string | null }): boolean {
  return (collection.completionPolicy === "NONE" && collection.cardSetCode === null) || collection.completionPolicy === "REFERENCE_POSITION";
}

export type MetadataFailure =
  | "changed"
  | "invalid"
  | "not_free"
  | "archived"
  | "capability_closed"
  | "access_lost"
  | "not_authenticated"
  | "disabled"
  | "uncertain"
  | "unknown";

/** Recusa → motivo estável. Só código e NOME da exceção; `hint`/`details` nunca são lidos. */
export function classifyMetadataFailure(code: string | null | undefined, message: string | null | undefined): MetadataFailure {
  const text = (message ?? "").trim();
  if (text === "CAPABILITY_NOT_ENABLED") return "capability_closed";
  if (code === "28000" || text.toLowerCase() === "not_authenticated") return "not_authenticated";
  if (text === "COLLECTION_NOT_FOUND") return "access_lost";
  if (text === "COLLECTION_ARCHIVED") return "archived";
  if (text === "NOT_FREE_COLLECTION") return "not_free";
  if (text === "INVALID_FINISH" || text === "INVALID_COVER_CODE" || text === "INVALID_ARGUMENT" || code === "22023") return "invalid";
  // Sem código SQLSTATE (rede, gateway, tempo esgotado): não dá para afirmar que nada foi gravado.
  if (!/^[0-9A-Z]{5}$/.test((code ?? "").trim())) return "uncertain";
  return "unknown";
}

export function metadataFailureMessage(reason: MetadataFailure): string {
  switch (reason) {
    case "changed":
      return "As informações da coleção mudaram desde que você abriu esta tela. Mostramos os valores atuais — confira e salve de novo.";
    case "invalid":
      return "Confira os campos: o nome não pode ficar vazio, a descrição tem até 500 caracteres e o código, de 2 a 6 letras ou números.";
    case "not_free":
      return "Esta coleção não usa código na capa.";
    case "archived":
      return "A coleção está arquivada. As informações ficam só para leitura.";
    case "capability_closed":
    case "disabled":
      return "Editar as informações da coleção ainda não está disponível.";
    case "access_lost":
      return "Sua permissão para editar esta coleção mudou.";
    case "not_authenticated":
      return "Sua sessão terminou. Entre de novo para continuar.";
    case "uncertain":
      return "Não conseguimos confirmar se a alteração foi salva. Mostramos os valores atuais — confira antes de tentar de novo.";
    default:
      return "Não foi possível salvar agora. Nada foi alterado — tente de novo.";
  }
}

/** Depois destas recusas a tela relê a página (o papel ou o acesso podem ter mudado) e os controles somem se for o caso. */
export function metadataFailureRechecks(reason: MetadataFailure): boolean {
  return reason === "access_lost" || reason === "archived" || reason === "capability_closed" || reason === "disabled" || reason === "changed" || reason === "uncertain";
}

/** O que a tela mostrou quando o formulário abriu (base da conferência antes de gravar). */
export type MetadataBaseline = { name: string; description: string | null };

/** O valor atual ainda é o que a tela mostrou? Descrição comparada depois da mesma normalização. */
export function sameText(current: MetadataBaseline, baseline: MetadataBaseline): boolean {
  const norm = (v: string | null) => (v === null ? null : normalizeCollectionDescription(v) ?? v);
  return current.name === baseline.name && norm(current.description) === norm(baseline.description);
}

export function validTextInput(name: string, description: string): { name: string; description: string | null } | null {
  const n = normalizeCollectionName(name);
  const d = normalizeCollectionDescription(description);
  if (n === null || d === undefined) return null;
  return { name: n, description: d };
}

export function validFinish(value: unknown): value is string {
  return typeof value === "string" && isBinderFinish(value);
}

/** Código da placa digitado → valor gravado (`null` = sem código); `"invalid"` = fora do formato. */
export function validCoverCode(raw: string): string | null | "invalid" {
  return normalizeCoverCode(raw);
}
