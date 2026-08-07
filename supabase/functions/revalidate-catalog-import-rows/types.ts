// Project Mimikyu — Edge Function: revalidate-catalog-import-rows
// Cadastro self-service de Raridade (2026-08-07). Único tipo genuinamente
// local desta função — os tipos de linha/normalização vêm inteiramente de
// _shared/catalog-normalization/ (mesmo núcleo usado por
// import-catalog-cards), sem reexportação própria porque este arquivo não
// precisa de nenhum apelido local (diferente de import-catalog-cards/
// types.ts, que preserva PreparedRow por compatibilidade com imports já
// existentes).

export type RequestBody = {
  // Opcional: revalida só os jobs informados. Omitido/vazio = todo job em
  // STAGED é candidato (uso esperado do botão "Revalidar linhas
  // pendentes" em /catalogo/raridades — uma nova raridade mapeada pode
  // afetar linhas em várias coleções diferentes ao mesmo tempo).
  job_ids?: string[];
};
