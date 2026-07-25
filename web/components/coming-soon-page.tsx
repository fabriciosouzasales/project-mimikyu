import { AppShell } from "@/components/app-shell/app-shell";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

/**
 * Placeholder para rotas já presentes na navegação mas ainda não implementadas.
 * Existe pra que clicar num item do menu sempre mantenha o usuário dentro do
 * shell (trilha + submenu + header) em vez de cair no 404 genérico do Next —
 * o 404 cru foi exatamente o bug que Fabrício reportou (2026-07-25).
 */
export function ComingSoonPage({ title, description }: { title: string; description: string }) {
  return (
    <AppShell title={title}>
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
