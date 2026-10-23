// Imagem personalizada no bolso (C-198) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-images.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { type BinderPage, type BinderSlot, classifySlotFailure, pageOccupancy, slotDescription, slotFailureMessage } from "./binder.ts";
import { canReceiveAvailable, isAddablePocket } from "./binder-share.ts";
import {
  ENCODE_LADDER,
  SLOT_IMAGE_LIMIT,
  acceptedOutputType,
  attachSlotImages,
  buildSlotImagePath,
  canFrameVertically,
  checkSourceFile,
  clampFocal,
  classifyImageFailure,
  classifyUploadError,
  fitWithin,
  focalForKey,
  focalFromDrag,
  imageFailureMessage,
  imagesLeft,
  isDefiniteRefusal,
  isSlotImagePath,
  parseClearResult,
  parseFocusResult,
  parseImageSummary,
  parseSetImageResult,
  parseSlotImages,
  parseUnlinked,
  verticalOverflow,
} from "./binder-images.ts";

const U = "11111111-1111-4111-8111-111111111111";
const L = "22222222-2222-4222-8222-222222222222";
const F = "33333333-3333-4333-8333-333333333333";
const S1 = "44444444-4444-4444-8444-444444444444";
const S2 = "55555555-5555-4555-8555-555555555555";
const PATH = `${U}/${L}/${F}.webp`;
const PATH2 = `${U}/${L}/${S1}.jpg`;

function slot(over: Partial<BinderSlot> = {}): BinderSlot {
  return {
    slotId: S1,
    row: 1,
    column: 1,
    locked: false,
    state: "EMPTY",
    expected: null,
    present: null,
    assignmentId: null,
    allocationId: null,
    expectedCardId: null,
    presentCardId: null,
    presentVariantTypeId: null,
    presentCollectionId: null,
    expectedCollectionId: null,
    ...over,
  };
}

test("arquivo de origem: JPEG/PNG/WebP aceitos; HEIC com mensagem própria; vazio e grande recusados", () => {
  assert.equal(checkSourceFile({ type: "image/jpeg", size: 1000, name: "a.jpg" }), "ok");
  assert.equal(checkSourceFile({ type: "image/png", size: 1000 }), "ok");
  assert.equal(checkSourceFile({ type: "image/webp", size: 1000 }), "ok");
  assert.equal(checkSourceFile({ type: "", size: 1000, name: "foto.JPEG" }), "ok");
  assert.equal(checkSourceFile({ type: "image/heic", size: 1000, name: "x.heic" }), "heic");
  assert.equal(checkSourceFile({ type: "", size: 1000, name: "IMG_1.HEIC" }), "heic");
  assert.equal(checkSourceFile({ type: "image/gif", size: 1000 }), "type");
  assert.equal(checkSourceFile({ type: "image/svg+xml", size: 1000 }), "type");
  assert.equal(checkSourceFile({ type: "", size: 1000, name: "doc.pdf" }), "type");
  assert.equal(checkSourceFile({ type: "image/png", size: 0 }), "empty");
  assert.equal(checkSourceFile({ type: "image/png", size: 21 * 1024 * 1024 }), "too_large");
});

test("redução: respeita 900×1800, mantém proporção e nunca amplia", () => {
  assert.deepEqual(fitWithin(4000, 3000), { width: 900, height: 675 });
  assert.deepEqual(fitWithin(1000, 4000), { width: 450, height: 1800 });
  assert.deepEqual(fitWithin(400, 550), { width: 400, height: 550 });
  assert.deepEqual(fitWithin(0, 10), { width: 0, height: 0 });
  // Escada: começa sem reduzir, só diminui, termina pequena o bastante.
  assert.equal(ENCODE_LADDER[0]?.scale, 1);
  for (let i = 1; i < ENCODE_LADDER.length; i += 1) assert.ok((ENCODE_LADDER[i]?.scale ?? 0) <= (ENCODE_LADDER[i - 1]?.scale ?? 0));
  assert.equal(acceptedOutputType("image/webp"), "image/webp");
  assert.equal(acceptedOutputType("image/jpeg"), "image/jpeg");
  // Navegador sem WebP devolve PNG: não serve para o bucket.
  assert.equal(acceptedOutputType("image/png"), null);
});

test("caminho: formato do CHECK da 5232, sempre novo, só WebP/JPEG", () => {
  assert.equal(buildSlotImagePath(U, L, "image/webp", F), PATH);
  assert.equal(buildSlotImagePath(U.toUpperCase(), L, "image/jpeg", S1), PATH2);
  assert.equal(buildSlotImagePath(U, L, "image/png", F), null);
  assert.equal(buildSlotImagePath("x", L, "image/webp", F), null);
  assert.ok(isSlotImagePath(PATH));
  assert.ok(!isSlotImagePath(`${U}/${F}.webp`));
  assert.ok(!isSlotImagePath(`${U}/${L}/../${F}.webp`));
  assert.notEqual(buildSlotImagePath(U, L, "image/webp", F), buildSlotImagePath(U, L, "image/webp", S2));
});

test("enquadramento: limites, teclado e arrasto", () => {
  assert.equal(clampFocal(-4), 0);
  assert.equal(clampFocal(140), 100);
  assert.equal(clampFocal(33.6), 34);
  assert.equal(clampFocal("x"), 50);
  assert.equal(focalForKey("ArrowUp", 50), 48);
  assert.equal(focalForKey("ArrowDown", 99), 100);
  assert.equal(focalForKey("PageUp", 5), 0);
  assert.equal(focalForKey("PageDown", 50), 60);
  assert.equal(focalForKey("Home", 70), 0);
  assert.equal(focalForKey("End", 10), 100);
  assert.equal(focalForKey("Enter", 10), null);
  // Retrato alto num bolso 80×110: sobra vertical; paisagem: nada a enquadrar.
  assert.ok(verticalOverflow(800, 2000, 80, 110) > 0);
  assert.equal(verticalOverflow(2000, 800, 80, 110), 0);
  assert.ok(canFrameVertically(800, 2000));
  assert.ok(!canFrameVertically(2000, 800));
  assert.ok(!canFrameVertically(800, 1100));
  // Puxar para baixo revela o alto (valor menor).
  assert.equal(focalFromDrag(50, 50, 100), 0);
  assert.equal(focalFromDrag(50, -25, 100), 75);
  assert.equal(focalFromDrag(50, 40, 0), 50);
});

test("leitura 5234: imagens por bolso; formato inesperado não é adivinhado", () => {
  const map = parseSlotImages([{ page_number: 1, slot_id: S1, storage_path: PATH, focal_y: 30, updated_at: "2026-10-23T00:00:00Z" }]);
  assert.ok(map);
  assert.deepEqual(map.get(S1), { path: PATH, focalY: 30, updatedAt: "2026-10-23T00:00:00Z", url: null });
  assert.equal(parseSlotImages([{ slot_id: S1, storage_path: "a/b.png", focal_y: 30 }]), null);
  assert.equal(parseSlotImages([{ slot_id: S1, storage_path: PATH, focal_y: 130 }]), null);
  assert.equal(parseSlotImages(null), null);
  assert.deepEqual(parseSlotImages([])?.size, 0);
});

test("resumo e arquivos sem vínculo", () => {
  const s = parseImageSummary([{ layout_image_count: 3, user_image_count: 498, user_image_limit: SLOT_IMAGE_LIMIT }]);
  assert.deepEqual(s, { layoutCount: 3, userCount: 498, limit: 500 });
  assert.equal(imagesLeft(s ?? { userCount: 0, limit: 1 }), 2);
  assert.equal(imagesLeft({ userCount: 510, limit: 500 }), 0);
  assert.equal(parseImageSummary([{ layout_image_count: -1, user_image_count: 0, user_image_limit: 500 }]), null);
  assert.deepEqual(parseUnlinked([{ storage_path: PATH }, { storage_path: "../x" }]), [PATH]);
  assert.equal(parseUnlinked({}), null);
});

test("respostas de escrita: só REPLACED/REMOVED devolvem o arquivo a apagar", () => {
  assert.deepEqual(parseSetImageResult([{ slot_id: S1, storage_path: PATH, focal_y: 50, operation: "ADDED", previous_path: null }]), {
    slotId: S1,
    path: PATH,
    focalY: 50,
    operation: "ADDED",
    previousPath: null,
  });
  assert.equal(parseSetImageResult([{ slot_id: S1, storage_path: PATH, focal_y: 50, operation: "REPLACED", previous_path: PATH2 }])?.previousPath, PATH2);
  // UNCHANGED (repetição) nunca manda apagar nada, mesmo que algo venha no campo.
  assert.equal(parseSetImageResult([{ slot_id: S1, storage_path: PATH, focal_y: 50, operation: "UNCHANGED", previous_path: PATH2 }])?.previousPath, null);
  assert.equal(parseSetImageResult([{ slot_id: S1, storage_path: PATH, focal_y: 50, operation: "REPLACED", previous_path: null }]), null);
  assert.equal(parseSetImageResult([{ slot_id: S1, storage_path: PATH, focal_y: 50, operation: "OK" }]), null);
  assert.deepEqual(parseFocusResult([{ slot_id: S1, focal_y: 12 }]), { slotId: S1, focalY: 12 });
  assert.deepEqual(parseClearResult([{ slot_id: S1, outcome: "REMOVED", previous_path: PATH }]), { outcome: "REMOVED", previousPath: PATH });
  assert.deepEqual(parseClearResult([{ slot_id: S1, outcome: "ALREADY_ABSENT", previous_path: null }]), { outcome: "ALREADY_ABSENT", previousPath: null });
  assert.equal(parseClearResult([{ slot_id: S1, outcome: "REMOVED", previous_path: null }]), null);
});

test("falhas: códigos estáveis da 5233; incerteza nunca autoriza apagar", () => {
  assert.equal(classifyImageFailure("55000", "IMAGE_QUOTA_REACHED"), "quota");
  assert.equal(classifyImageFailure("55000", "SLOT_OCCUPIED"), "slot_taken");
  assert.equal(classifyImageFailure("55000", "SLOT_RESERVED"), "slot_reserved");
  assert.equal(classifyImageFailure("55000", "SLOT_LOCKED"), "slot_locked");
  assert.equal(classifyImageFailure("55000", "SLOT_IN_REGION"), "slot_region");
  assert.equal(classifyImageFailure("P0002", "IMAGE_FILE_NOT_FOUND"), "file_missing");
  assert.equal(classifyImageFailure("P0002", "IMAGE_NOT_FOUND"), "image_missing");
  assert.equal(classifyImageFailure("22023", "INVALID_IMAGE_FILE"), "file_invalid");
  assert.equal(classifyImageFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyImageFailure("P0002", "SLOT_NOT_FOUND"), "not_found");
  assert.equal(classifyImageFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyImageFailure("55P03", "canceling statement due to lock timeout"), "lock_busy");
  assert.equal(classifyImageFailure(undefined, "fetch failed"), "unknown");
  assert.equal(isDefiniteRefusal("quota"), true);
  assert.equal(isDefiniteRefusal("unknown"), false);
  assert.match(imageFailureMessage("quota"), /500/);
  assert.equal(classifyUploadError({ statusCode: "413", message: "Payload too large" }), "too_large");
  assert.equal(classifyUploadError({ message: "mime type image/png is not supported" }), "type");
  assert.equal(classifyUploadError({ statusCode: 403, message: "new row violates row-level security policy" }), "denied");
  assert.equal(classifyUploadError({ statusCode: "409", message: "The resource already exists" }), "exists");
  assert.equal(classifyUploadError(null), "unknown");
});

test("sobreposição: imagem só em bolso EMPTY e solto; carta e reserva nunca são cobertas", () => {
  const page: BinderPage = {
    pageNumber: 1,
    pageId: L,
    slots: [slot(), slot({ slotId: S2, state: "RESERVED_EMPTY", expectedCardId: F })],
  };
  const img = { path: PATH, focalY: 40, updatedAt: null, url: "https://x/signed" };
  const [out] = attachSlotImages([page], new Map([[S1, img], [S2, img]]));
  assert.deepEqual(out?.slots[0]?.image, img);
  assert.equal(out?.slots[1]?.image, null);
  const locked = attachSlotImages([{ ...page, slots: [slot({ locked: true })] }], new Map([[S1, img]]));
  assert.equal(locked[0]?.slots[0]?.image, null);
});

test("bolso com imagem: não recebe carta, não abre 'Adicionar carta', não conta como vazio", () => {
  const img = { path: PATH, focalY: 50, updatedAt: null, url: null };
  const withImage = slot({ image: img });
  assert.equal(canReceiveAvailable(withImage), false);
  assert.equal(isAddablePocket(withImage), false);
  assert.equal(isAddablePocket(slot()), true);
  assert.deepEqual(pageOccupancy({ slots: [withImage, slot({ slotId: S2 })] }), { capacity: 2, occupied: 0, reservedMissing: 0, empty: 1, images: 1 });
  assert.match(slotDescription(withImage), /imagem personalizada/);
  // Operação de carta num bolso com imagem: o banco recusa (5232) e a mensagem é clara.
  assert.equal(classifySlotFailure("55000", "SLOT_HAS_IMAGE"), "has_image");
  assert.match(slotFailureMessage("has_image"), /imagem/);
});
