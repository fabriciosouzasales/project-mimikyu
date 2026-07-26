"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSiteUrl } from "@/lib/site-url";
import { traduzirErroAuth } from "@/lib/supabase/auth-errors";
import {
  isDisplayNameValid,
  isUsernameFormatValid,
  normalizeDisplayName,
  normalizeUsername,
} from "@/lib/username";

export type AuthActionState = { error: string | null; success?: boolean };

export async function login(_prevState: AuthActionState, formData: FormData): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) {
    return { error: "Informe e-mail e senha." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    return { error: traduzirErroAuth(error.message) };
  }

  redirect("/");
}

export async function signup(_prevState: AuthActionState, formData: FormData): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const username = normalizeUsername(String(formData.get("username") ?? ""));
  const displayName = normalizeDisplayName(String(formData.get("display_name") ?? ""));

  if (!email || !password) {
    return { error: "Informe e-mail e senha." };
  }
  if (password.length < 6) {
    return { error: "A senha precisa ter pelo menos 6 caracteres." };
  }
  // Mesmas regras aplicadas por handle_new_user() no banco (ver
  // database/schema/1020_create_handle_new_user_function.sql) — validação
  // aqui é só antecipação de UX, a autoridade final é o banco.
  if (!isUsernameFormatValid(username)) {
    return { error: "Nome de usuário inválido: use de 3 a 20 caracteres (letras minúsculas, números e _)." };
  }
  if (!isDisplayNameValid(displayName)) {
    return { error: "Informe um nome de exibição de até 60 caracteres." };
  }

  const supabase = await createClient();
  const siteUrl = await getSiteUrl();

  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${siteUrl}/auth/callback`,
      // Nomes exatos esperados por handle_new_user(): raw_user_meta_data
      // ->>'username' e ->>'display_name' (ver Query 1020).
      data: { username, display_name: displayName },
    },
  });

  if (error) {
    return { error: traduzirErroAuth(error.message) };
  }

  return { error: null, success: true };
}

export async function requestPasswordReset(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "").trim();
  if (!email) {
    return { error: "Informe seu e-mail." };
  }

  const supabase = await createClient();
  const siteUrl = await getSiteUrl();

  // Nunca revela se o e-mail existe ou não (evita enumeração de contas) — sempre
  // reporta sucesso ao usuário, independente do resultado real da chamada.
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl}/auth/callback?next=/atualizar-senha`,
  });

  return { error: null, success: true };
}

export async function updatePassword(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const password = String(formData.get("password") ?? "");
  if (password.length < 6) {
    return { error: "A senha precisa ter pelo menos 6 caracteres." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password });

  if (error) {
    return { error: traduzirErroAuth(error.message) };
  }

  redirect("/");
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
