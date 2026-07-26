import { CheckCircle2 } from "lucide-react";

/** Aviso discreto de operação bem-sucedida — mesma paleta de StateBadge tone="success". */
export function SuccessBanner({ message }: { message: string }) {
  return (
    <div className="flex items-center gap-2 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-sm text-success">
      <CheckCircle2 className="h-4 w-4 shrink-0" />
      {message}
    </div>
  );
}
