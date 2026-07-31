import type { LucideIcon } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

/**
 * Placeholder para rotas já presentes na navegação mas ainda não implementadas.
 * Existe pra que clicar num item do menu sempre mantenha o usuário dentro do
 * shell (trilha + submenu + header) em vez de cair no 404 genérico do Next —
 * o 404 cru foi exatamente o bug que Fabrício reportou (2026-07-25).
 *
 * `icon` opcional (2026-07-31, padronização "mesmo ícone do menu antes do
 * título" iniciada em Expansões) — repassado direto ao `AppShell`, mesmo
 * ícone do item de menu correspondente (`nav-config.ts`).
 */
export function ComingSoonPage({
  title,
  description,
  icon,
}: {
  title: string;
  description: string;
  icon?: LucideIcon;
}) {
  return (
    <AppShell title={title} icon={icon}>
      <Card className="max-w-lg">
        <CardHeader>
          <CardTitle>Em construção</CardTitle>
          <CardDescription>{description}</CardDescription>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          Esta tela ainda não foi implementada.
        </CardContent>
      </Card>
    </AppShell>
  );
}
