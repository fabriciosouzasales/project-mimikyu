import type { ReactNode } from "react";

export type StateTone = "success" | "warning" | "danger" | "muted";

/**
 * Badge discreto para estados importantes (cobertura de imagem, resultado
 * de importação) — substitui o `StatusDot` (ponto + texto) que havia
 * entrado na primeira rodada desta linguagem visual. Ajuste pedido por
 * Fabrício: "prefiro manter badges discretos para alguns estados
 * importantes em vez de substituí-los integralmente por StatusDot". Mesma
 * receita de cor já usada nas variantes `primary`/`warning` de `ui/badge.tsx`
 * (`border-{cor}/40 bg-{cor}/10 text-{cor}`), reaproveitada aqui só para
 * manter familiaridade visual — sem importar o componente global.
 *
 * 2026-07-26 — altura reduzida após Fabrício inspecionar via DevTools um
 * badge real do Supabase (49.75×17.48px, fonte 9px, padding 3px/5.5px). A
 * causa da nossa altura excessiva não era só o padding: sem `leading-none`,
 * o texto de 10px herdava a `line-height` do corpo (1.5), inflando a caixa
 * do badge bem além do tamanho da fonte.
 *
 * `uppercase` — regra confirmada por Fabrício para todo o sistema (mesma
 * convenção já usada no `Badge` global, `ui/badge.tsx`).
 *
 * `danger` adicionado para o histórico de importações (`asset_import_run`,
 * status `FAILED`) — até então só usávamos success/warning/muted.
 *
 * Fix (2026-08-23) — `danger` ganhou `dark:text-destructive-foreground`,
 * mesmo padrão já usado em `ui/badge.tsx` (variante `destructive`, linha 29):
 * sem o override, o texto usava `text-destructive` puro, que no tema escuro
 * é `--destructive` (`6 64% 20%`, quase preto) — baixo contraste mesmo sobre
 * o fundo tintado sutil (`bg-destructive/10`). `--destructive-foreground`
 * escuro (`0 0% 92%`, quase branco) resolve, réplica exata de uma correção
 * já aprovada em outro componente do mesmo sistema, não uma técnica nova.
 */
const TONE_CLASSES: Record<StateTone, string> = {
  success: "border-success/30 bg-success/10 text-success",
  warning: "border-warning/40 bg-warning/10 text-warning",
  danger: "border-destructive/40 bg-destructive/10 text-destructive dark:text-destructive-foreground",
  muted: "border-border bg-transparent text-muted-foreground",
};

export function StateBadge({ tone, children }: { tone: StateTone; children: ReactNode }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-[7px] py-[3px] text-[9px] font-medium uppercase leading-none ${TONE_CLASSES[tone]}`}
    >
      {children}
    </span>
  );
}
