import { MmkyuWordmark } from "./wordmark";

/**
 * Contracapa interna do BINDER-NAV-01 — conteúdo do slot esquerdo na
 * primeira abertura (posição 0), ao lado da primeira página de bolsos.
 *
 * Rodada 5 (2026-08-28) — direção nova, substituindo por completo as
 * Rodadas 3/4 (rejeitadas por Fabrício: "a contracapa NÃO deve parecer uma
 * grande capa acolchoada/painel independente"). Decisão: a contracapa segue
 * a MESMA lógica visual e proporção de uma página do Binder, só que sem
 * slots — o fundo/sombra/folhas-fantasma agora vêm do container
 * compartilhado em `binder-pages-nav.tsx` (idêntico ao de uma página real).
 * Este componente deixou de ter fundo/moldura/zíper/costura PRÓPRIOS — é
 * puramente o CONTEÚDO: nada de textura de couro/veludo, nada de borda
 * acolchoada, nada de zíper aqui (o zíper discreto que contorna o Binder
 * mora na moldura externa, em `binder-pages-nav.tsx`).
 *
 * Conteúdo (pedido, 5 pontos):
 *  1. Centro: logomarca "MMKYU Collector" — mesmo glifo SVG debossado já
 *     usado em `BinderCover`/Rodadas anteriores (identidade única, não um
 *     wordmark novo), acabamento de baixo contraste (opacidade ~45%) para
 *     não competir visualmente com as cartas da página ao lado.
 *  2. Rodapé, duas linhas centralizadas com respiro inferior generoso:
 *     linha 1 = nome da coleção, ligeiramente mais destacada; linha 2 =
 *     identificador curto (ex. "MMKYU · ME2.5 · 2026"), menor e mais
 *     discreta. Ambos os textos são mock/placeholder — não correspondem a
 *     nenhum dado real de domínio (mesma natureza mock dos cards
 *     fictícios já usados no spike).
 *
 * Rodada 8 (2026-08-28) — removido o glifo de escudo (usava `LEATHER_HUE`
 * marrom, inconsistente com a nova referência preta da capa fechada), pedido
 * explícito de Fabrício: "sem inventar um brasão genérico". Substituído por
 * `MmkyuWordmark` (ver `wordmark.tsx`) — mesma solução tipográfica agora
 * usada também na capa fechada (`binder-cover-closed.tsx`), aqui centralizada
 * em vez de no canto, com "Collector" como subtítulo.
 *
 * 100% decorativo: `aria-hidden` no container raiz, sem interação.
 */
export function InsideCoverFace() {
  return (
    <div aria-hidden className="flex h-full w-full flex-col items-center justify-between">
      {/* Centro — logomarca, baixo contraste/deboss. */}
      <div className="flex flex-1 flex-col items-center justify-center gap-1.5 opacity-60">
        <MmkyuWordmark size="md" tone="hsl(38 20% 55% / 0.55)" />
        <span
          className="text-[9px] font-medium uppercase tracking-[0.3em] sm:text-[10px]"
          style={{ color: "hsl(38 18% 50% / 0.4)" }}
        >
          Collector
        </span>
      </div>

      {/* Rodapé — nome da coleção (mais destacado) + identificador (mais discreto). */}
      <div className="flex flex-col items-center gap-1 pb-2 text-center sm:pb-3">
        <span className="text-xs font-medium tracking-wide" style={{ color: "hsl(38 22% 70% / 0.55)" }}>
          Coleção Mimikyu
        </span>
        <span className="text-[9px] uppercase tracking-[0.2em]" style={{ color: "hsl(38 18% 60% / 0.35)" }}>
          MMKYU · ME2.5 · 2026
        </span>
      </div>
    </div>
  );
}
