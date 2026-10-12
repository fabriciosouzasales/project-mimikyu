import { createLucideIcon } from "lucide-react";

/**
 * Pokébola minimalista (D6, Opção A aprovada por Fabrício — Pokédex P1,
 * 2026-10-12). Criada com `createLucideIcon` em vez de um SVG solto: o
 * resultado tem exatamente o tipo `LucideIcon`, então entra em `nav-config.ts`,
 * `Header` e `EmptyState` sem nenhuma adaptação, e herda o mesmo traço
 * (`stroke="currentColor"`, 2px, cantos arredondados) dos demais ícones do
 * menu — monocromático, segue a cor do item (ativo/inativo) e do tema
 * claro/escuro automaticamente, sem cor própria.
 *
 * Geometria no grid 24×24 da lucide: aro externo, faixa central interrompida
 * pelo botão e botão central.
 */
export const Pokeball = createLucideIcon("Pokeball", [
  ["circle", { cx: "12", cy: "12", r: "9", key: "pokeball-ring" }],
  ["path", { d: "M3 12h6", key: "pokeball-band-left" }],
  ["path", { d: "M15 12h6", key: "pokeball-band-right" }],
  ["circle", { cx: "12", cy: "12", r: "3", key: "pokeball-button" }],
]);
