import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell/app-shell";
import { UsersTable, type AdminUserRow } from "@/components/usuarios/users-table";
import { Alert } from "@/components/ui/alert";
import { createClient } from "@/lib/supabase/server";

const PAGE_SIZE = 20;

export default async function UsuariosPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: isAdmin } = await supabase.rpc("is_admin");

  let listError = false;
  let initialUsers: AdminUserRow[] = [];
  let initialTotalCount = 0;

  if (isAdmin) {
    const { data, error } = await supabase.rpc("admin_list_users", { p_limit: PAGE_SIZE, p_offset: 0 });
    if (error) {
      listError = true;
    } else {
      initialUsers = (data ?? []) as AdminUserRow[];
      initialTotalCount = initialUsers[0]?.total_count ?? 0;
    }
  }

  return (
    <AppShell title="Usuários">
      <div className="mx-auto max-w-4xl">
        <div className="mb-6">
          <h1 className="text-xl font-medium text-foreground">Usuários</h1>
          <p className="mt-1 text-sm text-muted-foreground">Lista administrativa de usuários cadastrados.</p>
        </div>

        {!isAdmin ? (
          <Alert variant="destructive">Acesso restrito a administradores.</Alert>
        ) : listError ? (
          <Alert variant="destructive">
            Não foi possível carregar a lista de usuários. Tente recarregar a página.
          </Alert>
        ) : (
          <UsersTable
            initialUsers={initialUsers}
            initialTotalCount={initialTotalCount}
            pageSize={PAGE_SIZE}
            currentUserId={user.id}
          />
        )}
      </div>
    </AppShell>
  );
}
