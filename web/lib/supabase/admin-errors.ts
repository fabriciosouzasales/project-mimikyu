/**
 * Traduz as mensagens RAISE EXCEPTION de is_admin()/admin_list_users()/
 * admin_grant_admin()/admin_revoke_admin() (ver ADR-021,
 * database/schema/1060-1062) para o texto exibido ao usuário. Chamadas RPC
 * via PostgREST repassam o texto do RAISE diretamente em error.message,
 * diferente do fluxo de signup (que passa pelo GoTrue e costuma vir
 * envolvido em uma mensagem genérica) — por isso aqui basta um match exato.
 */
export function traduzirErroAdmin(message: string): string {
  const mapa: Record<string, string> = {
    "acesso restrito a administradores.": "Acesso restrito a administradores.",
    "usuário não encontrado.": "Usuário não encontrado.",
    "usuário já é administrador.": "Este usuário já é administrador.",
    "usuário não é administrador.": "Este usuário não é administrador.",
    "não é possível remover o último administrador.": "Não é possível remover o último administrador.",
  };

  return mapa[message] ?? "Não foi possível concluir a ação. Tente novamente em instantes.";
}
