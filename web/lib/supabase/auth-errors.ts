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

  if (mapa[message]) {
    return mapa[message];
  }

  // Mensagens originadas do trigger handle_new_user() (ver
  // database/schema/1020_create_handle_new_user_function.sql). O GoTrue
  // (Supabase Auth) costuma envolver a exceção do Postgres numa mensagem
  // genérica ("Database error saving new user") em vez de repassar o texto
  // exato do RAISE EXCEPTION — por isso o match é por substring nos dois
  // lados. IMPORTANTE: o formato exato ainda não foi confirmado contra um
  // cadastro real com username inválido/indisponível; validar em produção e
  // ajustar este mapeamento se o texto observado divergir.
  const contains = (needle: string) => message.toLowerCase().includes(needle.toLowerCase());

  if (contains("username indisponível") || contains("já está em uso") || contains("user_profile_username_unique")) {
    return "Este nome de usuário já está em uso. Escolha outro.";
  }
  if (contains("username inválido") || contains("username é obrigatório")) {
    return "Nome de usuário inválido: use de 3 a 20 caracteres (letras minúsculas, números e _).";
  }
  if (contains("nome de exibição é obrigatório")) {
    return "Informe um nome de exibição.";
  }
  if (contains("database error saving new user")) {
    return "Não foi possível concluir o cadastro. Verifique se o nome de usuário escolhido é válido e ainda não está em uso.";
  }

  return "Não foi possível concluir a operação. Tente novamente em instantes.";
}
