/**
 * Traduz mensagens de erro do Supabase Auth para uma linguagem útil ao usuário final.
 * Mensagens não mapeadas caem num fallback genérico — nunca expomos detalhes técnicos crus.
 */
export function traduzirErroAuth(message: string): string {
  const mapa: Record<string, string> = {
    "Invalid login credentials": "E-mail ou senha incorretos.",
    "Email not confirmed": "Confirme seu e-mail antes de entrar — verifique sua caixa de entrada.",
    "User already registered": "Já existe uma conta com este e-mail.",
    "Password should be at least 6 characters": "A senha precisa ter pelo menos 6 caracteres.",
  };

  return mapa[message] ?? "Não foi possível concluir a operação. Tente novamente em instantes.";
}
