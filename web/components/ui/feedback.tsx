import { AlertTriangle, CheckCircle2, XCircle } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

export type FeedbackTone = "success" | "error" | "warning";

const TONE_CONFIG: Record<FeedbackTone, { icon: LucideIcon; classes: string }> = {
  success: { icon: CheckCircle2, classes: "border-success/30 bg-success/10 text-success" },
  // dark: overrides (2026-07-31, pedido de Fabrício: "tarja vermelha no modo
  // escuro... não consigo ler a mensagem de erro") — mesmo diagnóstico já
  // aplicado a `StatCard tone="danger"` e `ConfirmDeleteBar`: `--destructive`
  // no tema escuro tem luminosidade muito baixa (20%), quase invisível sobre
  // fundo também escuro. `dark:text-destructive-foreground`/
  // `dark:border-destructive-foreground` (quase branco) em opacidade baixa
  // resolve sem alterar o tema claro.
  error: {
    icon: XCircle,
    classes:
      "border-destructive/30 bg-destructive/10 text-destructive dark:border-destructive-foreground/25 dark:bg-destructive/20 dark:text-destructive-foreground",
  },
  warning: { icon: AlertTriangle, classes: "border-warning/40 bg-warning/10 text-warning" },
};

/**
 * Feedback inline padrão — Fundação visual, Ciclo B (2026-07-30, ver
 * STD-004). Substitui `SuccessBanner` (fixo em sucesso, sem tom de
 * erro/aviso) e os `<p className="text-xs text-destructive">` soltos
 * repetidos em cada formulário. Decisão explícita: inline, não toast
 * flutuante — evita depender de `@radix-ui/react-toast` (dependência nova
 * sem necessidade técnica comprovada ainda) e mantém o comportamento já
 * validado em produção (mensagem aparece dentro do fluxo da página, some
 * sozinha via `useAdminListState`).
 */
export function InlineFeedback({ tone, children }: { tone: FeedbackTone; children: React.ReactNode }) {
  const { icon: Icon, classes } = TONE_CONFIG[tone];
  return (
    <div className={cn("flex items-center gap-2 rounded-md border px-3 py-2 text-sm", classes)}>
      <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
      {children}
    </div>
  );
}
