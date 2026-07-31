import { LayoutDashboard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

/**
 * Placeholder de dashboard — valida a fundação visual (shell, tema, tokens)
 * antes de qualquer dado real. Sem proteção de rota ainda (Etapa 3).
 *
 * `icon` (2026-07-31): mesmo ícone do item "Visão geral" em `nav-config.ts`,
 * parte da padronização "ícone do menu antes do título" iniciada em
 * Expansões.
 */
export default function HomePage() {
  return (
    <AppShell title="Visão geral" icon={LayoutDashboard}>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Fundação do frontend</CardTitle>
            <CardDescription>Etapa 0 — tokens, tema e shell</CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            Layout base, tema claro/escuro e componentes primitivos prontos para os
            próximos módulos.
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Gestão de Usuários</CardTitle>
            <CardDescription>Etapa 1 em andamento</CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            Autenticação real via Supabase Auth: login, cadastro e recuperação de senha.
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Catálogo Editorial</CardTitle>
            <CardDescription>Próxima fase</CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            Início após a validação completa da Gestão de Usuários.
          </CardContent>
        </Card>
      </div>
    </AppShell>
  );
}
