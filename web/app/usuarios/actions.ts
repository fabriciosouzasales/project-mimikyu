"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroAdmin } from "@/lib/supabase/admin-errors";

export type AdminActionState = { error: string | null; success?: boolean };

export async function grantAdmin(_prevState: AdminActionState, formData: FormData): Promise<AdminActionState> {
  const userId = String(formData.get("user_id") ?? "");
  if (!userId) {
    return { error: "Usuário inválido." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_grant_admin", { p_user_id: userId });

  if (error) {
    return { error: traduzirErroAdmin(error.message) };
  }

  revalidatePath("/usuarios");
  return { error: null, success: true };
}

export async function revokeAdmin(_prevState: AdminActionState, formData: FormData): Promise<AdminActionState> {
  const userId = String(formData.get("user_id") ?? "");
  if (!userId) {
    return { error: "Usuário inválido." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_revoke_admin", { p_user_id: userId });

  if (error) {
    return { error: traduzirErroAdmin(error.message) };
  }

  revalidatePath("/usuarios");
  return { error: null, success: true };
}
