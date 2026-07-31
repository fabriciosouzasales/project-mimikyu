"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { DeleteEntitiesActionState, EntityActionState } from "@/lib/catalogo/admin-action-types";

/**
 * Server Actions de escrita da tela Coleções (/catalogo/card-sets),
 * adicionadas em 2026-07-31 (pedido de Fabrício: "inclusão dos botões de
 * edição e exclusão em cada Card Set" — "faça todos os ajustes necessários
 * para manter o mesmo padrão da página Expansões"). Mesma estrutura de
 * `expansoes/actions.ts`: aliases sobre os tipos compartilhados
 * (`lib/catalogo/admin-action-types.ts`).
 *
 * `createCardSet` adicionada na mesma data, rodada seguinte (pedido
 * explícito de Fabrício: "ainda não consigo incluir novos itens pela própria
 * tela") — resolve a decisão futura que ficava em aberto (`admin_create_card_set()`
 * não existia). Chama `admin_create_card_set()` (Query 2051, ADR-023, emenda
 * "Card Set: cadastro real via UI"). Até Fabrício confirmar a execução da
 * Query 2051 no Supabase (ritual de pareamento de SQL do projeto), esta
 * action retorna o erro genuíno do Postgres (função inexistente) — o
 * frontend já está com a fiação completa, só falta o banco. Mesma situação
 * já vivida por `updateCardSet`/`deleteCardSets` (Queries 2048/2050) até
 * serem confirmadas.
 */
export type CardSetActionState = EntityActionState;
export type DeleteCardSetsActionState = DeleteEntitiesActionState;

/**
 * Cadastra um novo Card Set via admin_create_card_set() (Query 2051,
 * ADR-023). Diferente de updateCardSet, precisa validar todos os campos
 * estruturais obrigatórios — não há linha existente de onde herdar
 * set_type/base_set_size/total_set_size. release_date é opcional (data de
 * lançamento ainda não confirmada, mesma regra de negócio de card_set).
 */
export async function createCardSet(
  _prevState: CardSetActionState,
  formData: FormData,
): Promise<CardSetActionState> {
  const expansionId = String(formData.get("expansion_id") ?? "");
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const setType = String(formData.get("set_type") ?? "").trim();
  const releaseOrderRaw = String(formData.get("release_order") ?? "").trim();
  const releaseOrder = Number(releaseOrderRaw);
  const baseSetSizeRaw = String(formData.get("base_set_size") ?? "").trim();
  const baseSetSize = Number(baseSetSizeRaw);
  const totalSetSizeRaw = String(formData.get("total_set_size") ?? "").trim();
  const totalSetSize = Number(totalSetSizeRaw);
  const releaseDateRaw = String(formData.get("release_date") ?? "").trim();

  if (!expansionId) {
    return { error: "Selecione a Expansão." };
  }
  if (!code) {
    return { error: "Informe o código do Card Set." };
  }
  if (!name) {
    return { error: "Informe o nome do Card Set." };
  }
  if (!setType) {
    return { error: "Selecione o tipo do Card Set." };
  }
  if (!releaseOrderRaw || !Number.isInteger(releaseOrder) || releaseOrder <= 0) {
    return { error: "Informe uma ordem de lançamento válida (número inteiro positivo)." };
  }
  if (!baseSetSizeRaw || !Number.isInteger(baseSetSize) || baseSetSize <= 0) {
    return { error: "Informe uma quantidade base válida (número inteiro positivo)." };
  }
  if (!totalSetSizeRaw || !Number.isInteger(totalSetSize) || totalSetSize < baseSetSize) {
    return { error: "Informe uma quantidade total válida (maior ou igual à quantidade base)." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_create_card_set", {
    p_expansion_id: expansionId,
    p_code: code,
    p_name: name,
    p_set_type: setType,
    p_release_order: releaseOrder,
    p_base_set_size: baseSetSize,
    p_total_set_size: totalSetSize,
    p_release_date: releaseDateRaw || null,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/card-sets");
  return { error: null, success: true, id: data as string };
}

/**
 * Atualiza nome, tipo, ordem de lançamento e data de lançamento de um Card
 * Set via admin_update_card_set() (Query 2048, ADR-023). expansion_id e
 * code nunca são aceitos aqui — imutáveis por construção (a função nem tem
 * parâmetro para isso), mesmo princípio já aplicado a Game/Expansion.
 * base_set_size/total_set_size também ficam de fora — não pedidos, e mudar
 * set_type sozinho já precisa lidar com as regras de PROMO usando o tamanho
 * já cadastrado (a função antecipa isso com mensagem clara).
 *
 * Ampliado em 2026-07-31, rodada seguinte (pedido explícito de Fabrício:
 * "na tela de edição do set card deve ser permitido editar o tipo e a data
 * de lançamento") — antes só aceitava nome/ordem (Query 2048 v1.0). Depende
 * da Migration 2052 (assinatura mudou de 3 para 5 parâmetros) ser executada
 * por Fabrício; até lá, retorna o erro genuíno do Postgres (função com essa
 * assinatura não existe).
 */
export async function updateCardSet(
  _prevState: CardSetActionState,
  formData: FormData,
): Promise<CardSetActionState> {
  const id = String(formData.get("id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const setType = String(formData.get("set_type") ?? "").trim();
  const releaseOrderRaw = String(formData.get("release_order") ?? "").trim();
  const releaseOrder = Number(releaseOrderRaw);
  const releaseDateRaw = String(formData.get("release_date") ?? "").trim();

  if (!id) {
    return { error: "Card Set inválido." };
  }
  if (!name) {
    return { error: "Informe o nome do Card Set." };
  }
  if (!setType) {
    return { error: "Selecione o tipo do Card Set." };
  }
  if (!releaseOrderRaw || !Number.isInteger(releaseOrder) || releaseOrder <= 0) {
    return { error: "Informe uma ordem de lançamento válida (número inteiro positivo)." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_card_set", {
    p_id: id,
    p_name: name,
    p_set_type: setType,
    p_release_order: releaseOrder,
    p_release_date: releaseDateRaw || null,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/card-sets");
  return { error: null, success: true, id };
}

/**
 * Exclui um ou mais Card Sets via admin_delete_card_set() (Query 2050,
 * ADR-023 — emenda 2026-07-31 "Card Set: atualização e exclusão real via
 * UI", mesmo padrão de deleteExpansions/deleteGames). Chama a função uma vez
 * por id — cada exclusão é bloqueada individualmente pela FK
 * fk_card_card_set se o Card Set tiver Cards associadas, e o resultado por
 * item é reportado de volta.
 */
export async function deleteCardSets(
  _prevState: DeleteCardSetsActionState,
  formData: FormData,
): Promise<DeleteCardSetsActionState> {
  const ids = formData.getAll("ids").map(String).filter(Boolean);

  if (ids.length === 0) {
    return { error: "Nenhum Card Set selecionado." };
  }

  const supabase = await createClient();
  const deletedIds: string[] = [];
  const failures: { id: string; error: string }[] = [];

  for (const id of ids) {
    const { error } = await supabase.rpc("admin_delete_card_set", { p_id: id });
    if (error) {
      failures.push({ id, error: traduzirErroCatalogo(error.message) });
    } else {
      deletedIds.push(id);
    }
  }

  revalidatePath("/catalogo/card-sets");

  return {
    error: null,
    success: true,
    deletedIds,
    failures: failures.length > 0 ? failures : undefined,
  };
}

/**
 * Define (ou remove, com `logoStoragePath: null`) a logo de um Card Set via
 * admin_set_card_set_logo() — infraestrutura de banco já existente desde
 * 2026-07-26 (Queries 275/276, ADR-022), CONFIRMADA EXECUTADA na época;
 * esta action é a primeira vez que ela é chamada a partir do frontend (ver
 * `CardSetLogoUploader`, novo em 2026-07-31, pedido de Fabrício: "use o
 * mesmo padrão da tela de edição de Expansão"). Mesmo padrão de
 * `setExpansionLogo()` (`expansoes/actions.ts`): chamada diretamente pelo
 * componente de upload depois que o arquivo já foi enviado ao bucket
 * `card-set-logo` pelo cliente — esta action só grava o ponteiro
 * (`logo_storage_path`), nunca lida com o arquivo em si.
 */
export async function setCardSetLogo(
  cardSetId: string,
  logoStoragePath: string | null,
): Promise<{ error: string | null }> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_card_set_logo", {
    p_card_set_id: cardSetId,
    p_logo_storage_path: logoStoragePath,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/card-sets");
  return { error: null };
}
