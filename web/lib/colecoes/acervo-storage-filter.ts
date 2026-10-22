import { type AcervoStorageFilter, formatCount } from "./acervo.ts";
import type { StorageLocation } from "./storage-locations.ts";

/**
 * WHERE-04 — filtro "Localização física" do Meu acervo: regras puras.
 *
 * Sem React, sem Supabase: testável com
 * `node --experimental-strip-types --test lib/colecoes/acervo-storage-filter.test.ts`.
 *
 * Os locais vêm da 5219 (`get_my_storage_locations`), a mesma leitura de
 * "Meus locais" — nada é duplicado ou mantido no frontend. A identidade do
 * local é sempre o id (o nome é renomeável). A filtragem em si acontece no
 * banco (5220); aqui só se decide o que mostrar.
 */

/**
 * Situação do filtro diante da lista de locais:
 * - `all` / `none`: visão integral / só exemplares sem localização;
 * - `location`: local existente (com nome e contagem);
 * - `missing`: o id da URL não é (mais) um local do usuário — excluído, ou link
 *   de outra conta. A 5220 devolve vazio sem distinguir os casos, de propósito;
 * - `unknown`: a lista de locais não carregou; o filtro continua valendo no
 *   banco, só não há nome para mostrar.
 */
export type StorageFilterStatus =
  | { kind: "all" }
  | { kind: "none" }
  | { kind: "location"; location: StorageLocation }
  | { kind: "missing"; id: string }
  | { kind: "unknown"; id: string };

export function storageFilterStatus(filter: AcervoStorageFilter, locations: StorageLocation[] | null): StorageFilterStatus {
  if (filter.kind === "all") return { kind: "all" };
  if (filter.kind === "none") return { kind: "none" };
  if (locations === null) return { kind: "unknown", id: filter.id };
  const location = locations.find((l) => l.id === filter.id);
  return location ? { kind: "location", location } : { kind: "missing", id: filter.id };
}

/** Valor do `<select name="local">` (mesma forma da URL). */
export function storageFilterValue(filter: AcervoStorageFilter): string {
  return filter.kind === "none" ? "sem" : filter.kind === "location" ? filter.id : "";
}

/** Valor do `<select>` → filtro. Id sem formato de local cai na visão integral. */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function storageFilterFromValue(value: string): AcervoStorageFilter {
  if (value === "sem") return { kind: "none" };
  if (UUID.test(value)) return { kind: "location", id: value.toLowerCase() };
  return { kind: "all" };
}

export type StorageFilterOption = { value: string; label: string; disabled?: boolean };

/**
 * Opções do seletor, na ordem: visão integral, sem localização, e os locais
 * do usuário (nome · tipo, com a quantidade de exemplares guardados — a mesma
 * de "Meus locais"). Casos de borda viram opções explicativas desabilitadas,
 * e um id da URL que não é mais um local aparece como "Local indisponível"
 * para o seletor nunca mostrar um valor diferente do filtro aplicado.
 */
export function storageFilterOptions(filter: AcervoStorageFilter, locations: StorageLocation[] | null): {
  base: StorageFilterOption[];
  locations: StorageFilterOption[];
} {
  const base: StorageFilterOption[] = [
    { value: "", label: "Todos os locais" },
    { value: "sem", label: "Sem localização definida" },
  ];
  const status = storageFilterStatus(filter, locations);
  const list: StorageFilterOption[] = [];
  if (status.kind === "missing" || status.kind === "unknown") {
    list.push({ value: status.id, label: status.kind === "missing" ? "Local indisponível" : "Local selecionado" });
  }
  if (locations === null) {
    list.push({ value: "__indisponivel__", label: "Não foi possível carregar seus locais", disabled: true });
  } else if (locations.length === 0) {
    list.push({ value: "__vazio__", label: "Nenhum local criado ainda", disabled: true });
  } else {
    for (const location of locations) {
      const kind = location.kindLabel ? ` · ${location.kindLabel}` : "";
      list.push({ value: location.id, label: `${location.name}${kind} (${formatCount(location.cardCount)})` });
    }
  }
  return { base, locations: list };
}

/** Texto do chip de filtro ativo; `null` = sem filtro de local. */
export function storageFilterChipLabel(status: StorageFilterStatus): string | null {
  switch (status.kind) {
    case "all":
      return null;
    case "none":
      return "Sem localização";
    case "location":
      return `Local: ${status.location.name}`;
    case "missing":
      return "Local indisponível";
    case "unknown":
      return "Local selecionado";
  }
}

/** Nome do local filtrado para as frases da tela (`null` quando não há nome confiável). */
export function storageFilterName(status: StorageFilterStatus): string | null {
  return status.kind === "location" ? status.location.name : null;
}

/**
 * O exemplar corresponde ao filtro de local? Compara ids (C-58: o local é do
 * exemplar). `undefined` = filtro inativo ou local desconhecido — sem destaque.
 */
export function copyMatchesStorageFilter(copyStorageId: string | null | undefined, filter: AcervoStorageFilter): boolean | undefined {
  if (filter.kind === "all") return undefined;
  if (copyStorageId === undefined) return undefined;
  if (filter.kind === "none") return copyStorageId === null;
  return copyStorageId === filter.id;
}

/**
 * Por que a galeria filtrada ficou vazia — para o estado vazio falar a língua
 * do colecionador em vez de um genérico "nenhum resultado".
 * - `missing`: o local não existe mais;
 * - `empty_location`: o local existe e não guarda nenhum exemplar;
 * - `all_located`: todo o acervo tem local (só o filtro "sem localização" ativo);
 * - `combination`: o local tem exemplares, mas nenhum com os demais filtros.
 */
export type StorageEmptyReason = "missing" | "empty_location" | "all_located" | "combination";

export function storageEmptyReason(status: StorageFilterStatus, otherFiltersActive: boolean): StorageEmptyReason | null {
  if (status.kind === "missing") return "missing";
  if (status.kind === "location" && status.location.cardCount === 0) return "empty_location";
  if (status.kind === "none" && !otherFiltersActive) return "all_located";
  if (status.kind === "all") return null;
  return "combination";
}
