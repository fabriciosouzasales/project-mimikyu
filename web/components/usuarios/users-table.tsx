"use client";

import { useActionState, useEffect, useState } from "react";
import { grantAdmin, revokeAdmin, type AdminActionState } from "@/app/usuarios/actions";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

export type AdminUserRow = {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  email: string | null;
  created_at: string;
  is_admin: boolean;
  total_count: number;
};

const initialActionState: AdminActionState = { error: null };

export function UsersTable({
  initialUsers,
  initialTotalCount,
  pageSize,
  currentUserId,
}: {
  initialUsers: AdminUserRow[];
  initialTotalCount: number;
  pageSize: number;
  currentUserId: string;
}) {
  const [users, setUsers] = useState(initialUsers);
  const [totalCount, setTotalCount] = useState(initialTotalCount);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));

  async function loadPage(nextPage: number) {
    setLoading(true);
    setLoadError(null);

    const supabase = createClient();
    const { data, error } = await supabase.rpc("admin_list_users", {
      p_limit: pageSize,
      p_offset: nextPage * pageSize,
    });

    setLoading(false);

    if (error) {
      setLoadError("Não foi possível carregar esta página. Tente novamente.");
      return;
    }

    const rows = (data ?? []) as AdminUserRow[];
    setUsers(rows);
    setTotalCount(rows[0]?.total_count ?? 0);
    setPage(nextPage);
  }

  if (users.length === 0) {
    return <Alert>Nenhum usuário encontrado.</Alert>;
  }

  return (
    <div className="space-y-4">
      {loadError && <Alert variant="destructive">{loadError}</Alert>}

      <div className="overflow-x-auto rounded-md border border-border">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border bg-surface-muted text-left text-xs font-medium text-muted-foreground">
              <th className="px-4 py-2.5">Usuário</th>
              <th className="px-4 py-2.5">E-mail</th>
              <th className="px-4 py-2.5">Criado em</th>
              <th className="px-4 py-2.5">Papel</th>
              <th className="px-4 py-2.5" />
            </tr>
          </thead>
          <tbody>
            {users.map((user) => (
              <UserRow
                key={user.id}
                user={user}
                isSelf={user.id === currentUserId}
                onChanged={() => loadPage(page)}
              />
            ))}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between text-sm text-muted-foreground">
        <span>
          {page * pageSize + 1}–{Math.min((page + 1) * pageSize, totalCount)} de {totalCount}
        </span>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" disabled={loading || page === 0} onClick={() => loadPage(page - 1)}>
            Anterior
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={loading || page >= totalPages - 1}
            onClick={() => loadPage(page + 1)}
          >
            Próxima
          </Button>
        </div>
      </div>
    </div>
  );
}

function UserRow({
  user,
  isSelf,
  onChanged,
}: {
  user: AdminUserRow;
  isSelf: boolean;
  onChanged: () => void;
}) {
  const action = user.is_admin ? revokeAdmin : grantAdmin;
  const [state, formAction, pending] = useActionState(action, initialActionState);

  useEffect(() => {
    if (state.success) {
      onChanged();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <tr className="border-b border-border last:border-b-0">
      <td className="px-4 py-3">
        <div className="flex items-center gap-1.5">
          <span className="font-medium text-foreground">{user.display_name}</span>
          <span className="text-muted-foreground">@{user.username}</span>
          {isSelf && <span className="text-xs text-muted-foreground">(você)</span>}
        </div>
        {state.error && <p className="mt-1 text-xs text-destructive">{state.error}</p>}
      </td>
      <td className="px-4 py-3 text-muted-foreground">{user.email ?? "—"}</td>
      <td className="px-4 py-3 text-muted-foreground">
        {new Date(user.created_at).toLocaleDateString("pt-BR")}
      </td>
      <td className="px-4 py-3">
        {user.is_admin ? (
          <Badge variant="primary">Administrador</Badge>
        ) : (
          <Badge variant="outline">Usuário</Badge>
        )}
      </td>
      <td className="px-4 py-3 text-right">
        <form action={formAction}>
          <input type="hidden" name="user_id" value={user.id} />
          <Button type="submit" variant="outline" size="sm" disabled={pending}>
            {pending ? "Salvando…" : user.is_admin ? "Revogar admin" : "Tornar admin"}
          </Button>
        </form>
      </td>
    </tr>
  );
}
