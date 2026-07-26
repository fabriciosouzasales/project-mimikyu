"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { isDisplayNameValid, normalizeDisplayName } from "@/lib/username";

export type ProfileActionState = { error: string | null; success?: boolean };

/**
 * Atualiza apenas display_name. username nunca é aceito aqui — é imutável
 * pelo próprio usuário (ver ADR-020, trigger enforce_user_profile_invariants()
 * em database/schema/1002_create_user_profile_invariants_trigger.sql).
 */
export async function updateDisplayName(
  _prevState: ProfileActionState,
  formData: FormData,
): Promise<ProfileActionState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Sua sessão expirou. Recarregue a página e faça login novamente." };
  }

  const displayName = normalizeDisplayName(String(formData.get("display_name") ?? ""));

  if (!isDisplayNameValid(displayName)) {
    return { error: "Informe um nome de exibição de 1 a 60 caracteres." };
  }

  const { error } = await supabase
    .from("user_profile")
    .update({ display_name: displayName })
    .eq("id", user.id);

  if (error) {
    return { error: "Não foi possível salvar. Tente novamente em instantes." };
  }

  revalidatePath("/perfil");
  return { error: null, success: true };
}
