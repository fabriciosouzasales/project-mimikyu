/**
 * Wordmark tipográfico "MMKYU" — BINDER-NAV-01, Rodada 8 (2026-08-28).
 * Substitui o glifo de escudo (SVG) usado nas Rodadas 1-7 na capa fechada
 * (`binder-cover-closed.tsx`) e na contracapa interna (`cover-panel.tsx`) —
 * pedido explícito de Fabrício: "se a logomarca oficial não estiver
 * disponível, usar uma solução tipográfica simples e sofisticada, sem
 * inventar um brasão genérico."
 *
 * Efeito debossed via `textShadow` (highlight de 1px acima + sombra escura
 * abaixo, ambos sutis) em vez do stroke duplo usado nos glifos SVG
 * anteriores — mesma leitura de "baixo-relevo pressionado no material",
 * aplicada a texto. `tone` é resolvido pelo chamador (cada contexto tem seu
 * próprio contraste/matiz — canto discreto na capa fechada, centralizado e
 * ligeiramente mais visível na contracapa interna).
 */
export function MmkyuWordmark({ size = "sm", tone }: { size?: "sm" | "md"; tone: string }) {
  return (
    <span
      aria-hidden
      className="font-semibold uppercase leading-none"
      style={{
        fontSize: size === "md" ? "1.05rem" : "0.62rem",
        letterSpacing: "0.28em",
        color: tone,
        textShadow: "0 1px 0 hsl(0 0% 100% / 0.06), 0 -1px 1px hsl(0 0% 0% / 0.55)",
      }}
    >
      MMKYU
    </span>
  );
}
