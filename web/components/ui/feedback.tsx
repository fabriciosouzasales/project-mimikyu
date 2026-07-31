import { AlertTriangle, CheckCircle2, XCircle } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

export type FeedbackTone = "success" | "error" | "warning";

const TONE_CONFIG: Record<FeedbackTone, { icon: LucideIcon; classes: string }> = {
  success: { icon: CheckCircle2, classes: "border-success/30 bg-success/10 text-success" },
  error: { icon: XCircle, classes: "border-destructive/30 bg-destructive/10 text-destructive" },
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
