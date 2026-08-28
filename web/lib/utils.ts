import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** Combina classes condicionalmente e resolve conflitos de utilitários Tailwind. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Formata um número inteiro com "." como separador de milhar (pt-BR) — ex.: 5886 → "5.886". */
export function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR").format(value);
}

/**
 * Formata data+hora no padrão gerencial pt-BR, sem segundos — ex.:
 * "22/08/2026 às 13:30" (v3.6, 2026-08-23). Fabrício apontou que
 * `toLocaleString("pt-BR")` sem opções produz "22/08/2026, 13:30:17" —
 * segundos são ruído numa camada executiva (Hero/Atenções e Ações) que só
 * precisa da hora aproximada, e a vírgula default do formato longo do
 * Node/ICU lê pior que "às". Usado só nos elementos gerenciais da Visão
 * Geral — as tabelas operacionais (`historico-execucoes-table.tsx` e
 * afins) continuam com seus próprios formatadores, fora do escopo desta
 * rodada.
 */
export function formatManagerialDateTime(value: string | number | Date): string {
  const date = value instanceof Date ? value : new Date(value);
  const datePart = date.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });
  const timePart = date.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  return `${datePart} às ${timePart}`;
}

/**
 * Formata data+hora em pt-BR já separada em duas partes (data / hora) — para
 * telas operacionais que exibem a data/hora exata como informação principal
 * em duas linhas, em vez de um único texto corrido ou de um formato relativo
 * ("há 2 dias") como substituto primário (rodada de refinamento visual de
 * `/pricing/sincronizacoes`, 2026-08-28, instrução explícita de Fabrício).
 * Retorna `null` para `value` nulo, para o chamador decidir o placeholder
 * ("—") sem repetir a checagem de null em cada tela.
 */
export function formatDateTimeParts(value: string | number | Date | null): { date: string; time: string } | null {
  if (value === null) return null;
  const date = value instanceof Date ? value : new Date(value);
  return {
    date: date.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" }),
    time: date.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }),
  };
}
