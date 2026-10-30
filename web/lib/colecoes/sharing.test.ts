// Compartilhamento de coleções (V1-12) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/sharing.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  parseSharedPositions,
  sharedPositionsHref,
  sharedPageToBinderPage,
  attachSharedBinderImages,
  parseSharedBinderImages,
  parseSharedCover,
  activeOrPending,
  classifySharingFailure,
  inviteOutcomeMessage,
  invitedAgoLabel,
  normalizeUsername,
  parseInvite,
  parseInvites,
  parsePublicBinder,
  parseSharedBinder,
  publicBinderHref,
  parseSharedBinderPages,
  parseSharedCards,
  parseSharedCollection,
  sharedBatchStart,
  sharedBinderHref,
  sharedPocketLabel,
  spreadFirstPage,
  parseSharedWithMe,
  parseSharing,
  sharedCollectionHref,
  sharingFailureMessage,
  statusLabel,
} from "./sharing.ts";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";

test("normalizeUsername: @ opcional, minúsculas, mesmo formato do perfil", () => {
  assert.equal(normalizeUsername("  @Fulano_1 "), "fulano_1");
  assert.equal(normalizeUsername("ab"), null);
  assert.equal(normalizeUsername("a b c"), null);
  assert.equal(normalizeUsername("x".repeat(21)), null);
  assert.equal(normalizeUsername("@@dup"), null);
});

test("parseSharing: só participações bem formadas; nunca expõe id de usuário", () => {
  const s = parseSharing({
    visibility: "PUBLIC",
    lifecycle_status: "ACTIVE",
    members: [
      { membership_id: A, username: "ana", display_name: "Ana", status: "ACTIVE", role: "VIEWER", user_id: B },
      { membership_id: B, username: "bia", display_name: "", status: "PENDING" },
      { membership_id: "x", username: "zz", status: "ACTIVE" },
      { membership_id: A, username: "yy", status: "EDITOR" },
    ],
  });
  assert.ok(s);
  assert.equal(s.visibility, "PUBLIC");
  assert.equal(s.members.length, 2);
  assert.equal(s.members[1]?.displayName, "bia");
  assert.equal("userId" in (s.members[0] ?? {}), false);
  assert.equal(activeOrPending(s.members), 2);
  assert.equal(parseSharing(null), null);
  assert.equal(parseSharing({ visibility: "FRIENDS", members: [] }), null);
});

test("parseInvite e mensagens de resultado", () => {
  const r = parseInvite({ outcome: "INVITED", membership_id: A, username: "ana", display_name: "Ana", status: "PENDING" });
  assert.ok(r);
  assert.equal(r.member.status, "PENDING");
  assert.match(inviteOutcomeMessage("INVITED", r.member), /Ana \(@ana\)/);
  assert.match(inviteOutcomeMessage("ALREADY_PENDING", r.member), /esperando/);
  assert.equal(parseInvite({ outcome: "CHANGED", membership_id: A, username: "x" }), null);
});

test("parseInvites: caixa só com o necessário para decidir", () => {
  const list = parseInvites([
    { membership_id: A, collection_id: B, collection_name: "Escarlate", owner_display_name: "Ana", owner_username: "ana", invited_at: "2026-10-30" },
    { membership_id: "bad", collection_id: B, collection_name: "X" },
  ]);
  assert.equal(list.length, 1);
  assert.equal(list[0]?.ownerUsername, "ana");
  assert.deepEqual(parseInvites({}), []);
});

test("parseSharedCollection: acesso, membership só para VIEWER, progresso opcional", () => {
  const base = { collection_id: A, name: "CO", visibility: "PRIVATE", lifecycle_status: "ACTIVE", owner_display_name: "Ana", copies_count: 3 };
  const viewer = parseSharedCollection({ ...base, access: "VIEWER", membership_id: B, total_positions: 10, satisfied_positions: "4", is_complete: false });
  assert.equal(viewer?.membershipId, B);
  assert.deepEqual(viewer?.progress, { total: 10, satisfied: 4, complete: false });
  const pub = parseSharedCollection({ ...base, visibility: "PUBLIC", access: "PUBLIC", membership_id: B });
  assert.equal(pub?.membershipId, null);
  assert.equal(pub?.progress, null);
  assert.equal(parseSharedCollection(null), null);
  assert.equal(parseSharedCollection({ ...base, access: "ADMIN" }), null);
});

test("parseSharedWithMe e parseSharedCards", () => {
  const list = parseSharedWithMe([{ collection_id: A, name: "CO", owner_display_name: "Ana", copies_count: 2, lifecycle_status: "ARCHIVED" }]);
  assert.equal(list[0]?.archived, true);
  assert.equal(list[0]?.progress, null);
  const cards = parseSharedCards([
    { card_variant_id: A, language_code: "pt-BR", card_name: "Pikachu", collector_number: "25", copies_count: 2, total_count: 7 },
    { card_variant_id: "x", language_code: "en", card_name: "?" },
  ]);
  assert.equal(cards.items.length, 1);
  assert.equal(cards.total, 7);
  assert.equal(cards.items[0]?.copies, 2);
});

test("classifySharingFailure cobre 5303–5307 e a ausência da proposta", () => {
  assert.equal(classifySharingFailure("P0002", "USER_NOT_FOUND"), "user_not_found");
  assert.equal(classifySharingFailure("22023", "CANNOT_INVITE_SELF"), "self");
  assert.equal(classifySharingFailure("23505", "ALREADY_MEMBER"), "already_member");
  assert.equal(classifySharingFailure("54000", "MEMBER_LIMIT"), "member_limit");
  assert.equal(classifySharingFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifySharingFailure("P0002", "MEMBERSHIP_NOT_FOUND"), "not_found");
  assert.equal(classifySharingFailure("P0002", "INVITE_NOT_FOUND"), "invite_not_found");
  assert.equal(classifySharingFailure("PGRST202", "Could not find the function"), "unavailable");
  assert.equal(classifySharingFailure("XX000", "boom"), "unknown");
  assert.match(sharingFailureMessage("unknown"), /Nada foi alterado/);
  assert.equal(statusLabel("DECLINED"), "Recusou");
  assert.equal(sharedCollectionHref(A, 2), `/colecoes/compartilhada/${A}?pagina=2`);
});

test("parseSharedBinder: sem fichário, com fichário e formato inválido", () => {
  assert.deepEqual(parseSharedBinder({ has_binder: false }), { hasBinder: false });
  assert.deepEqual(parseSharedBinder({ has_binder: true, grid_columns: 3, grid_rows: 3, page_count: 10, own_filled_count: 7 }), {
    hasBinder: true,
    columns: 3,
    rows: 3,
    pageCount: 10,
    ownFilled: 7,
    identity: null,
  });
  // 5320 (proposta): identidade do fichário — nome próprio aparado/limitado, vazio = sem nome próprio
  const named = parseSharedBinder({ has_binder: true, grid_columns: 3, grid_rows: 3, page_count: 1, own_filled_count: 0, binder_name: "  Meu fichário  ", show_brand_mark: false });
  assert.deepEqual(named && named.hasBinder ? named.identity : undefined, { name: "Meu fichário", showBrandMark: false });
  const unnamed = parseSharedBinder({ has_binder: true, grid_columns: 3, grid_rows: 3, page_count: 1, binder_name: null, show_brand_mark: true });
  assert.deepEqual(unnamed && unnamed.hasBinder ? unnamed.identity : undefined, { name: null, showBrandMark: true });
  assert.equal(parseSharedBinder(null), null);
  assert.equal(parseSharedBinder({ has_binder: true, grid_columns: 0, grid_rows: 3, page_count: 1 }), null);
  // nenhum campo privado atravessa o parser, mesmo se o banco mandasse
  const parsed = parseSharedBinder({ has_binder: true, grid_columns: 2, grid_rows: 2, page_count: 1, binder_storage_name: "Caixa" });
  assert.ok(parsed && !("binder_storage_name" in parsed));
});

test("parseSharedBinderPages: grade completa, três estados e falha estrita", () => {
  const rows = [
    { page_number: 2, row_index: 1, column_index: 1, pocket_state: "CARD", card_name: "Pikachu", collector_number: "25", collector_total: 102, card_set_code: "base1", variant_label: "Holo", language_code: "pt-BR", image_path: "a.webp" },
    { page_number: 2, row_index: 1, column_index: 2, pocket_state: "RESERVED", card_name: "Raichu", collector_number: "14", language_code: "en", image_path: "b.webp" },
    { page_number: 2, row_index: 2, column_index: 1, pocket_state: "EMPTY", card_name: "Vazamento" },
  ];
  const pages = parseSharedBinderPages(rows, 2, 2);
  assert.ok(pages);
  assert.equal(pages.length, 1);
  const page = pages[0]!;
  assert.equal(page.pageNumber, 2);
  assert.equal(page.pockets.length, 4);
  assert.equal(page.pockets[0]!.kind, "card");
  assert.equal(page.pockets[1]!.kind, "reserve");
  assert.equal(page.pockets[1]!.languageCode, null);
  assert.equal(page.pockets[2]!.kind, "empty");
  assert.equal(page.pockets[2]!.cardName, null); // vazio nunca carrega texto
  assert.equal(page.pockets[3]!.kind, "empty"); // célula ausente = vazio
  assert.equal(parseSharedBinderPages([{ page_number: 1, row_index: 3, column_index: 1, pocket_state: "EMPTY" }], 2, 2), null);
  assert.equal(parseSharedBinderPages([{ page_number: 1, row_index: 1, column_index: 1, pocket_state: "OCCUPIED_MATCH" }], 2, 2), null);
  assert.equal(parseSharedBinderPages(null, 2, 2), null);
});

test("spreadFirstPage, rótulos e rota do fichário compartilhado", () => {
  assert.equal(spreadFirstPage(1, 2), 1);
  assert.equal(spreadFirstPage(2, 2), 1);
  assert.equal(spreadFirstPage(5, 2), 5);
  assert.equal(spreadFirstPage(6, 1), 6);
  assert.equal(spreadFirstPage(0, 2), 1);
  assert.equal(sharedBatchStart(1), 1);
  assert.equal(sharedBatchStart(4), 1);
  assert.equal(sharedBatchStart(5), 5);
  assert.equal(sharedBatchStart(10), 9);
  assert.equal(sharedBinderHref(A), `/colecoes/compartilhada/${A}/fichario`);
  const empty = { row: 1, column: 2, kind: "empty" as const, cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null };
  assert.equal(sharedPocketLabel(empty), "Linha 1, coluna 2: bolso vazio");
  assert.equal(sharedPocketLabel({ ...empty, kind: "reserve", cardName: "Raichu" }), "Linha 1, coluna 2: falta Raichu");
});

test("parsePublicBinder: vitrine só com o necessário; sem fichário; chaves extras ignoradas", () => {
  const base = {
    collection_id: A,
    name: "Base Set",
    completion_policy: "STANDARD_SET",
    cover_finish: "vinho",
    owner_display_name: "Ana",
    card_set_code: "base1",
    card_set_name: "Base Set",
    card_set_logo_path: null,
    binder_name: "Meu Base",
    show_brand_mark: true,
  };
  const withBinder = parsePublicBinder({ ...base, has_binder: true, grid_columns: 3, grid_rows: 3, page_count: 12, progress_percentage: 80 });
  assert.ok(withBinder);
  assert.deepEqual(withBinder.binder, { columns: 3, rows: 3, pageCount: 12 });
  assert.equal(withBinder.binderName, "Meu Base");
  assert.ok(!("progress" in withBinder) && !("progress_percentage" in withBinder));
  const noBinder = parsePublicBinder({ ...base, has_binder: false });
  assert.ok(noBinder);
  assert.equal(noBinder.binder, null);
  assert.equal(parsePublicBinder(null), null);
  assert.equal(parsePublicBinder({ ...base, has_binder: true, grid_columns: 0, grid_rows: 3, page_count: 1 }), null);
  assert.equal(parsePublicBinder({ ...base, collection_id: "x" }), null);
  assert.equal(publicBinderHref(A), `/fichario/${A}`);
  assert.equal(publicBinderHref(A, 3), `/fichario/${A}?pagina=3`);
});

test("invitedAgoLabel: relativo curto e data após uma semana", () => {
  const now = Date.parse("2026-10-30T12:00:00Z");
  assert.equal(invitedAgoLabel(null, now), null);
  assert.equal(invitedAgoLabel("x", now), null);
  assert.equal(invitedAgoLabel("2026-10-30T11:59:40Z", now), "agora");
  assert.equal(invitedAgoLabel("2026-10-30T11:55:00Z", now), "há 5 min");
  assert.equal(invitedAgoLabel("2026-10-30T09:00:00Z", now), "há 3 h");
  assert.equal(invitedAgoLabel("2026-10-29T10:00:00Z", now), "ontem");
  assert.equal(invitedAgoLabel("2026-10-26T12:00:00Z", now), "há 4 dias");
  assert.match(invitedAgoLabel("2026-10-12T12:00:00Z", now) ?? "", /12/);
});

test("sharedPageToBinderPage: bolso mascarado vira bolso do fichário só leitura, sem identidades internas", () => {
  const page = sharedPageToBinderPage({
    pageNumber: 3,
    pockets: [
      { row: 1, column: 1, kind: "card", cardName: "Pikachu", collectorNumber: "25", collectorTotal: 102, setCode: "base1", variantLabel: "Holo", languageCode: "pt-BR", imagePath: "a.webp" },
      { row: 1, column: 2, kind: "reserve", cardName: "Raichu", collectorNumber: "14", collectorTotal: 102, setCode: "base1", variantLabel: null, languageCode: null, imagePath: "b.webp" },
      { row: 1, column: 3, kind: "empty", cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null },
    ],
  });
  assert.equal(page.pageNumber, 3);
  const [card, reserve, empty] = page.slots;
  assert.equal(card?.state, "OCCUPIED_UNPLANNED");
  assert.equal(card?.present?.cardName, "Pikachu");
  assert.equal(card?.present?.languageCode, "pt-BR");
  assert.equal(card?.expected, null);
  assert.equal(reserve?.state, "RESERVED_EMPTY");
  assert.equal(reserve?.expected?.cardName, "Raichu");
  assert.equal(reserve?.present, null);
  assert.equal(empty?.state, "EMPTY");
  for (const slot of page.slots) {
    assert.equal(slot.locked, false);
    assert.equal(slot.assignmentId, null);
    assert.equal(slot.allocationId, null);
    assert.equal(slot.presentCollectionId, null);
    // Sem imagens decorativas no lote: nenhum bolso com imagem nem mesclagem (null = ausente).
    assert.equal(slot.image ?? null, null);
    assert.equal(slot.regionId ?? null, null);
  }
  assert.equal(new Set(page.slots.map((s) => s.slotId)).size, 3);
});

test("parseSharedPositions: forma do titular sem acervo privado; linhas inválidas descartadas", () => {
  const id = "11111111-1111-4111-8111-111111111111";
  const page = parseSharedPositions([
    { card_id: id, collector_number: "4", collector_total: 102, card_name: "Charizard", image_path: "c.webp", is_satisfied: true, copies_in_collection: "2", copies_available: 9, total_count: "102" },
    { card_id: "x", collector_number: "5", card_name: "Inválida", total_count: 102 },
  ]);
  assert.ok(page);
  assert.equal(page.total, 102);
  assert.equal(page.items.length, 1);
  assert.deepEqual(page.items[0], { cardId: id, collectorNumber: "4", collectorTotal: 102, cardName: "Charizard", imagePath: "c.webp", isSatisfied: true, copiesInCollection: 2 });
  assert.ok(!("copiesAvailable" in page.items[0]!));
  assert.equal(parseSharedPositions(null), null);
  assert.deepEqual(parseSharedPositions([]), { items: [], total: 0 });
});

test("sharedPositionsHref: mesmo vocabulário ?ver= do titular", () => {
  const id = "11111111-1111-4111-8111-111111111111";
  assert.equal(sharedPositionsHref(id, "todas"), `/colecoes/compartilhada/${id}`);
  assert.equal(sharedPositionsHref(id, "faltam"), `/colecoes/compartilhada/${id}?ver=faltam`);
});

// ---------------------------------------------------------------------------
// V1-12 SHARED BINDER VISUAL ASSETS-01 — imagens decorativas e capa (5325–5329)
// ---------------------------------------------------------------------------

const U = "33333333-3333-4333-8333-333333333333";
const IMG = (n: number) => `${A}/${B}/${U.slice(0, -1)}${n}.webp`;

function emptyPocket(row: number, column: number) {
  return { row, column, kind: "empty" as const, cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null };
}

test("parseSharedBinderImages: bolso 1×1 e mesclagem; formato inválido descarta a leitura inteira", () => {
  const rows = [
    { page_number: 1, row_index: 3, column_index: 3, height: 1, width: 1, is_region: false, storage_path: IMG(1), focal_x: 50, focal_y: 20, updated_at: "t" },
    { page_number: 1, row_index: 3, column_index: 1, height: 1, width: 2, is_region: true, storage_path: IMG(2), focal_x: 30, focal_y: 70, updated_at: null },
  ];
  const parsed = parseSharedBinderImages(rows);
  assert.equal(parsed?.length, 2);
  assert.deepEqual(parsed?.[1], { pageNumber: 1, row: 3, column: 1, height: 1, width: 2, region: true, path: IMG(2), focalX: 30, focalY: 70, updatedAt: null, url: null });
  assert.equal(parseSharedBinderImages([{ ...rows[0], storage_path: "../x.webp" }]), null);
  assert.equal(parseSharedBinderImages([{ ...rows[0], focal_y: 101 }]), null);
  assert.equal(parseSharedBinderImages([{ ...rows[0], is_region: true }]), null, "mesclagem 1×1 não existe");
  assert.equal(parseSharedBinderImages([{ ...rows[1], is_region: false }]), null, "bolso nunca é 1×2");
  assert.equal(parseSharedBinderImages("x"), null);
  assert.deepEqual(parseSharedBinderImages([]), []);
});

test("attachSharedBinderImages: só imagens com URL, só nas páginas do lote", () => {
  const pages = [{ pageNumber: 1, pockets: [emptyPocket(1, 1)] }, { pageNumber: 2, pockets: [emptyPocket(1, 1)] }];
  const images = [
    { pageNumber: 1, row: 1, column: 1, height: 1, width: 1, region: false, path: IMG(1), focalX: 50, focalY: 50, updatedAt: null, url: "https://x/1" },
    { pageNumber: 2, row: 1, column: 1, height: 1, width: 1, region: false, path: IMG(2), focalX: 50, focalY: 50, updatedAt: null, url: null },
  ];
  const out = attachSharedBinderImages(pages, images);
  assert.equal(out[0]?.images?.length, 1);
  assert.equal(out[1]?.images, undefined, "assinatura negada → nenhuma imagem (nada revela que existe algo ali)");
  assert.equal(attachSharedBinderImages(pages, []), pages);
});

test("sharedPageToBinderPage: imagem de bolso e mesclagem como no titular, sem ids internos", () => {
  const page = sharedPageToBinderPage({
    pageNumber: 2,
    pockets: [emptyPocket(1, 1), emptyPocket(1, 2), emptyPocket(1, 3)],
    images: [
      { pageNumber: 2, row: 1, column: 1, height: 1, width: 2, region: true, path: IMG(2), focalX: 30, focalY: 70, updatedAt: null, url: "https://x/r" },
      { pageNumber: 2, row: 1, column: 3, height: 1, width: 1, region: false, path: IMG(1), focalX: 50, focalY: 20, updatedAt: "t", url: "https://x/s" },
    ],
  });
  const [left, right, single] = page.slots;
  assert.equal(left?.regionId, "shared-region:2:1:1");
  assert.equal(right?.regionId, "shared-region:2:1:1");
  assert.equal(left?.image, null);
  assert.deepEqual(page.regions, [
    { regionId: "shared-region:2:1:1", row: 1, leftColumn: 1, height: 1, width: 2, path: IMG(2), focalX: 30, focalY: 70, updatedAt: null, url: "https://x/r" },
  ]);
  assert.deepEqual(single?.image, { path: IMG(1), focalY: 20, updatedAt: "t", url: "https://x/s" });
  assert.equal(single?.regionId, null);
});

test("sharedPageToBinderPage: carta ou reserva desta coleção vence a imagem; mesclagem só sobre bolsos vazios", () => {
  const card = { row: 1, column: 1, kind: "card" as const, cardName: "Pikachu", collectorNumber: "25", collectorTotal: 102, setCode: "base1", variantLabel: null, languageCode: "pt-BR", imagePath: "a.webp" };
  const page = sharedPageToBinderPage({
    pageNumber: 1,
    pockets: [card, emptyPocket(1, 2), emptyPocket(1, 3)],
    images: [
      { pageNumber: 1, row: 1, column: 1, height: 1, width: 1, region: false, path: IMG(1), focalX: 50, focalY: 50, updatedAt: null, url: "https://x/1" },
      { pageNumber: 1, row: 1, column: 1, height: 1, width: 2, region: true, path: IMG(2), focalX: 50, focalY: 50, updatedAt: null, url: "https://x/2" },
      { pageNumber: 1, row: 1, column: 3, height: 1, width: 1, region: false, path: IMG(3), focalX: 50, focalY: 50, updatedAt: null, url: null },
    ],
  });
  assert.equal(page.slots[0]?.image, null);
  assert.equal(page.slots[0]?.regionId, null);
  assert.equal(page.slots[1]?.regionId, null);
  assert.equal(page.regions, undefined);
  assert.equal(page.slots[2]?.image, null, "sem URL nada aparece");
});

test("sharedPageToBinderPage: sem imagens o resultado é o de antes (sem regions, image nulo)", () => {
  const page = sharedPageToBinderPage({ pageNumber: 1, pockets: [emptyPocket(1, 1)] });
  assert.equal(page.regions, undefined);
  assert.equal(page.slots[0]?.image, null);
  assert.equal(page.slots[0]?.regionId, null);
});

test("parseSharedCover: caminho e código validados; sem linha → null", () => {
  const path = `${A}/${B}/${U}.png`;
  assert.deepEqual(parseSharedCover([{ cover_logo_path: path, cover_code: "SV1" }]), { path, code: "SV1" });
  assert.deepEqual(parseSharedCover([{ cover_logo_path: null, cover_code: null }]), { path: null, code: null });
  assert.deepEqual(parseSharedCover([{ cover_logo_path: "outro/bucket.png", cover_code: "x!" }]), { path: null, code: null });
  assert.equal(parseSharedCover([]), null);
  assert.equal(parseSharedCover(null), null);
});
