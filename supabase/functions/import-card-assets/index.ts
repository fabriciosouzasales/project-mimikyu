/*
Project Mimikyu
Edge Function: import-card-assets
Sprint: B3.6 — Marco real: o HTTP 401 que bloqueava toda invocação desde o
Sprint B3.3 foi definitivamente eliminado, confirmado por teste real de
terminal. CONFIRMADO DEPLOYADO: `npx supabase functions deploy
import-card-assets` bem-sucedido, seguido de uma chamada real SEM nenhum
header de autenticação (agora desnecessário — ver abaixo) retornando HTTP 500
em vez do 401 histórico, prova de que a função finalmente executa. Ver
docs/06-pipeline-importacao.md, "Sprint B3.6", para o contexto completo.

Este arquivo é uma cópia versionada do código confirmado como publicado no
projeto Supabase, seguindo o mesmo princípio já usado em `database/` para SQL:
copiado para o repositório apenas depois de confirmado (ver `database/README.md`).

MUDANÇA ARQUITETURAL REAL, decidida e confirmada nesta revisão: a biblioteca
`@supabase/server` (`withSupabase`) foi abandonada para esta função — e,
esperado, para as futuras Edge Functions do projeto — depois de três revisões
consecutivas (Sprints B3.3/B3.4/B3.5) sem conseguir fazer `auth: ["secret"]`
autenticar com sucesso uma Secret Key real, mesmo após múltiplas hipóteses
reais testadas e descartadas (tipo/nome da chave, `verify_jwt`, header
`apikey`, remoção do próprio `auth: ["secret"]`). Substituída por
`Deno.serve()` puro + `@supabase/supabase-js`, com um cliente Supabase criado
uma única vez, no escopo do módulo, a partir de `SUPABASE_URL`/
`SUPABASE_SERVICE_ROLE_KEY` (variáveis de ambiente padrão de toda Edge
Function Supabase, não secrets customizados). Decisão explicitamente
concordada por Fabrício ("Concordo completamente... eu também abandonaria o
@supabase/server. A arquitetura ficará mais simples e muito mais previsível.").
A Convenção #4 (execução restrita via `auth: ["secret"]`), declarada na
revisão `0.9` de docs/06-pipeline-importacao.md, está SUPERSEDIDA por esta
mudança — ver nova Convenção #8 abaixo.

Consequência prática: validações que antes eram implícitas via `withSupabase`
(método HTTP, parsing de JSON, corpo obrigatório) agora são feitas manualmente
neste arquivo — sem alteração de comportamento observável para quem chama a
função.

Histórico:
- v1.0.0 (Sprint B2.1/B2.2, CONFIRMADO publicado e invocado com sucesso):
  respondia apenas `{ success: true, function: "import-card-assets", version: "1.0.0", status: "ready" }`.
- v1.1.0 (Sprint B2.3, CONFIRMADO publicado e testado): recebe `run_code` via
  payload JSON e consulta `asset_import_run`.
- v1.2.0 (Sprint B2.4, CONFIRMADO publicado e testado com execução real —
  `card_set` `ME0`/"Black Star Promos", `card_count: 0`): fluxo ampliado para
  `run_code` → `asset_import_run` → `card_set` → listagem de `card` (ordenada
  por `collector_order`). Toda a lógica vivia em um único arquivo.
- v1.2.1 (Sprint B2.4.1, CONFIRMADO publicado e testado — mesmo resultado do
  teste anterior, apenas com `version: "1.2.1"`): refatoração estrutural, sem
  mudança de comportamento observável. Lógica de acesso a dados extraída para
  `services/database.ts`.
- v1.3.0 (Sprint B3.3, CONFIRMADO DEPLOYADO — primeira vez que a função chama
  uma fonte externa real): fluxo passa a incluir `findCardSetExternalReference`
  e uma chamada real a `TcgdexClient.getSet()` (`services/tcgdex.ts`, também
  confirmado deployado nessa revisão pela primeira vez). Deploy confirmado,
  mas nenhuma invocação bem-sucedida — bloqueada por HTTP 401.
- v1.3.1 (Sprint B3.4/B3.5, aplicada e testada por Fabrício): removia
  `{ auth: ["secret"] }` de `withSupabase(...)`, mantendo a biblioteca. Testada
  de ponta a ponta no Sprint B3.5 — o 401 PERSISTIU, invalidando essa hipótese
  como correção suficiente. Nunca copiada a este arquivo no repositório.
- v2.0.0 (Sprint B3.6, CONFIRMADO DEPLOYADO, COM O 401 ELIMINADO POR TESTE
  REAL): remove completamente `@supabase/server`/`withSupabase`; cliente
  Supabase criado manualmente via `createClient(SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY)` no escopo do módulo; mesmo fluxo funcional das
  versões anteriores (`findImportRun`→`findCardSet`→
  `findCardSetExternalReference`→`TcgdexClient.getSet()`), agora com
  validação manual de método HTTP/corpo JSON/`run_code` (antes implícita via
  `withSupabase`). Teste real sem nenhum header de autenticação (correto
  agora — a autenticação é interna à função, via variável de ambiente)
  retornou HTTP 500 em vez de 401, confirmando que a função finalmente
  executa. Causa do 500 diagnosticada como GRANT ausente em
  `card_set_external_reference` para `service_role` (a tabela nunca recebeu
  `GRANT SELECT/INSERT/UPDATE/DELETE` explícito) — corrigida por uma nova
  migration real (ver `database/migrations/250_grant_card_set_external_reference_permissions.sql`)
  e reconfirmada por consulta real a `information_schema.role_table_grants`.
  **Nota importante**: uma resposta final `success: true` com `tcgdex_set`
  populado por uma chamada real de ponta a ponta ainda não foi explicitamente
  confirmada nesta revisão — todos os bloqueios conhecidos (401 e GRANT)
  foram eliminados, mas o próximo teste real ainda precisa confirmar o
  resultado final.
- v2.1.0 (Sprint B3.13, CONFIRMADO CONCLUÍDO no Sprint B3.15 — execução real
  de ponta a ponta validada: `imported: 188`, `ignored: 0`, `total: 188` para
  a `ME1`, reconfirmado por `COUNT(*)` em `card_external_reference`):
  incremento real de persistência. `card`/`card_variant` já estão populadas
  para as 5 coleções (ver docs/05-modelo-de-dados.md) — esta função NUNCA
  insere em `card`, apenas consulta. Depois de obter `tcgdex_set` da TCGdex,
  carrega todas as cartas da coleção via `listCardsMap` (um único SELECT,
  `Map<collector_number, card_id>`), localiza cada `card_id` pelo `localId`
  da TCGdex e faz `UPSERT` em `card_external_reference`
  (`upsertCardExternalReference`, idempotente via
  `ON CONFLICT (card_id, asset_source_id)`). Cartas sem correspondência local
  são contadas em `ignored`, não interrompem a execução. Resposta passa a
  incluir `imported`/`ignored`/`total`. Bloqueio real encontrado e corrigido
  no caminho: GRANT ausente em `card_external_reference` para `service_role`
  (Query 253) — ver docs/06-pipeline-importacao.md, "Sprint B3.15".
- v2.2.0 (Sprint B3.18, CONFIRMADO DEPLOYADO — execução ainda NÃO confirmada,
  bloqueada por um terceiro caso real do mesmo gap de GRANT, desta vez em
  `language`): Incremento 2 (Download de Imagens), teste controlado com uma
  única carta. Mantém a sincronização completa de `card_external_reference`
  (herdada da v2.1.0) e, além disso, processa a primeira carta retornada pela
  TCGdex (`set.cards[0]`): baixa a imagem de alta resolução
  (`${tcgCard.image}/high.webp`), calcula o checksum `SHA-256`, envia ao
  bucket físico do Storage (resolvido via `storage_bucket.code`, catálogo
  interno confirmado no Sprint B3.17/B3.18 — não é o bucket físico em si) e
  cria/atualiza o registro correspondente em `card_asset`
  (`upsertCardAsset`, chave natural `card_id`+`asset_type_id`+`language_id`+
  `storage_bucket_id`). Resposta amplia para `card_set`/`external_references`/
  `controlled_test`. Deploy confirmado por saída real de terminal; a
  invocação real retornou HTTP 500 com `LANGUAGE_QUERY_FAILED` — mesmo padrão
  de GRANT ausente para `service_role` já visto nas Queries 250/253, agora em
  `language`; correção proposta, ainda NÃO confirmada executada nesta
  revisão. Ver docs/06-pipeline-importacao.md, "Sprint B3.18".

Ver docs/06-pipeline-importacao.md, seções "Sprint B3.6", "Sprint B3.15" e
"Sprint B3.18", para o contexto completo, o roteiro de sprints e o status real
de cada etapa (o que foi de fato confirmado vs. o que ainda está planejado).

Convenções permanentes de Edge Functions do Project Mimikyu (ver docs/06):
1. Nunca criar arquivos de Edge Function "na mão" — sempre via
   `npx supabase functions new <nome-da-função>`.
2. Nunca alterar o template oficial da CLI sem necessidade — evoluir sobre ele.
3. Responsabilidade única por função.
4. [SUPERSEDIDA no Sprint B3.6] Execução restrita por padrão via
   `auth: ["secret"]` (`@supabase/server`) — substituída pela Convenção #8
   abaixo, depois de três revisões reais sem sucesso em autenticar com essa
   biblioteca.
5. Nunca avançar sem validar — cada sprint fecha só com critério de aceite
   confirmado.
6. `index.ts` apenas orquestra — não conhece SQL/PostgreSQL/fontes externas
   diretamente, apenas coordena chamadas aos serviços especializados.
7. Fluxo padrão de validação antes de cada deploy: `deno cache index.ts` +
   `deno check index.ts`, executados de dentro da pasta da função (onde está
   o `deno.json`), depois `npx supabase functions deploy <nome-da-função>`
   executado na raiz do projeto (onde está o `config.toml`).
8. [NOVA, Sprint B3.6] Toda Edge Function cria seu próprio cliente Supabase
   manualmente, via `createClient(Deno.env.get("SUPABASE_URL")!,
   Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)`, uma única vez, no escopo do
   módulo — não usa `withSupabase`/`@supabase/server`. Validações de método
   HTTP, corpo e payload passam a ser responsabilidade explícita do próprio
   `index.ts`.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  findImportRun,
  findCardSet,
  findCardSetExternalReference,
  listCardsMap,
  upsertCardExternalReference,
  findLanguageByCode,
  findCardAssetTypeByCode,
  findStorageBucketByCode,
  upsertCardAsset,
} from "./services/database.ts";
import { TcgdexClient } from "./services/tcgdex.ts";

type RequestBody = {
  run_code?: string;
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/**
 * Calcula o checksum SHA-256 do arquivo baixado.
 */
async function calculateSha256(
  arrayBuffer: ArrayBuffer,
): Promise<string> {
  const hashBuffer = await crypto.subtle.digest(
    "SHA-256",
    arrayBuffer,
  );

  return Array.from(new Uint8Array(hashBuffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json(
      {
        success: false,
        error: "METHOD_NOT_ALLOWED",
      },
      {
        status: 405,
        headers: {
          Allow: "POST",
        },
      },
    );
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json(
      {
        success: false,
        error: "INVALID_JSON",
      },
      { status: 400 },
    );
  }

  const runCode = body.run_code?.trim();

  if (!runCode) {
    return Response.json(
      {
        success: false,
        error: "RUN_CODE_REQUIRED",
      },
      { status: 400 },
    );
  }

  try {
    const run = await findImportRun(
      supabase,
      runCode,
    );

    if (!run) {
      return Response.json(
        {
          success: false,
          error: "IMPORT_RUN_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    const cardSet = await findCardSet(
      supabase,
      run.card_set_id,
    );

    if (!cardSet) {
      return Response.json(
        {
          success: false,
          error: "CARD_SET_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    const externalReference =
      await findCardSetExternalReference(
        supabase,
        run.card_set_id,
        run.asset_source_id,
      );

    if (!externalReference) {
      return Response.json(
        {
          success: false,
          error: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    const tcgdex = new TcgdexClient("en");
    const set = await tcgdex.getSet(
      externalReference.external_set_id,
    );

    const cards = await listCardsMap(
      supabase,
      run.card_set_id,
    );

    let importedReferences = 0;
    let ignoredReferences = 0;

    // Sincronização completa de card_external_reference (Incremento 1,
    // CONFIRMADO CONCLUÍDO no Sprint B3.15 — mantida idêntica nesta versão).
    for (const tcgCard of set.cards) {
      const cardId = cards.get(
        tcgCard.localId,
      );

      if (!cardId) {
        console.warn(
          `Carta ${tcgCard.localId} não encontrada no catálogo.`,
        );
        ignoredReferences++;
        continue;
      }

      await upsertCardExternalReference(
        supabase,
        {
          card_id: cardId,
          asset_source_id: run.asset_source_id,
          external_card_id: tcgCard.id,
          external_set_id: externalReference.external_set_id,
          source_number: tcgCard.localId,
          source_url:
            `https://api.tcgdex.net/v2/en/cards/${tcgCard.id}`,
          image_source_url: tcgCard.image,
          metadata: tcgCard,
          is_active: true,
        },
      );
      importedReferences++;
    }

    // Sprint B3.18 — TESTE CONTROLADO do Incremento 2 (Download de Imagens):
    // processa somente a primeira carta retornada pela coleção, não as 188.
    const tcgCard = set.cards[0];

    if (!tcgCard) {
      throw new Error("TCGDEX_SET_HAS_NO_CARDS");
    }

    const cardId = cards.get(tcgCard.localId);

    if (!cardId) {
      throw new Error(
        `CARD_NOT_FOUND_FOR_IMAGE_IMPORT: ${tcgCard.localId}`,
      );
    }

    if (!tcgCard.image) {
      throw new Error(
        `TCGDEX_IMAGE_NOT_AVAILABLE: ${tcgCard.id}`,
      );
    }

    const language = await findLanguageByCode(
      supabase,
      "en",
    );

    if (!language) {
      throw new Error("LANGUAGE_NOT_FOUND: en");
    }

    const assetType = await findCardAssetTypeByCode(
      supabase,
      "CARD_FRONT",
    );

    if (!assetType) {
      throw new Error(
        "CARD_ASSET_TYPE_NOT_FOUND: CARD_FRONT",
      );
    }

    const storageBucket = await findStorageBucketByCode(
      supabase,
      "card-front",
    );

    if (!storageBucket) {
      throw new Error(
        "STORAGE_BUCKET_NOT_FOUND: card-front",
      );
    }

    // A URL retornada pela TCGdex é uma URL-base; o sufixo /high.webp
    // seleciona a imagem em alta resolução no formato WebP.
    const imageSourceUrl = `${tcgCard.image}/high.webp`;
    const imageResponse = await fetch(imageSourceUrl);

    if (!imageResponse.ok) {
      throw new Error(
        `IMAGE_DOWNLOAD_FAILED: ${imageResponse.status} ${imageResponse.statusText}`,
      );
    }

    const imageBuffer = await imageResponse.arrayBuffer();

    if (imageBuffer.byteLength === 0) {
      throw new Error("IMAGE_DOWNLOAD_EMPTY");
    }

    const mimeType =
      imageResponse.headers.get("content-type")
        ?.split(";")[0]
        ?.trim() || "image/webp";
    const fileExtension = "webp";
    const storagePath =
      `${cardSet.code.toLowerCase()}/${tcgCard.localId}.${fileExtension}`;
    const checksumSha256 = await calculateSha256(imageBuffer);

    const { error: uploadError } = await supabase.storage
      .from(storageBucket.code)
      .upload(
        storagePath,
        imageBuffer,
        {
          contentType: mimeType,
          upsert: true,
          cacheControl: "3600",
        },
      );

    if (uploadError) {
      console.error(
        "STORAGE UPLOAD ERROR:",
        JSON.stringify(uploadError, null, 2),
      );
      throw new Error(
        `STORAGE_UPLOAD_FAILED: ${uploadError.message}`,
      );
    }

    const cardAsset = await upsertCardAsset(
      supabase,
      {
        card_id: cardId,
        asset_type_id: assetType.id,
        source_code: "TCGDEX",
        source_reference: tcgCard.id,
        storage_path: storagePath,
        external_url: null,
        mime_type: mimeType,
        file_extension: fileExtension,
        file_size_bytes: imageBuffer.byteLength,
        width_pixels: null,
        height_pixels: null,
        checksum_sha256: checksumSha256,
        is_primary: true,
        asset_order: 1,
        is_active: true,
        language_id: language.id,
        storage_bucket_id: storageBucket.id,
      },
    );

    const { data: publicUrlData } = supabase.storage
      .from(storageBucket.code)
      .getPublicUrl(storagePath);

    return Response.json({
      success: true,
      version: "2.2.0",
      run: {
        id: run.id,
        run_code: run.run_code,
      },
      card_set: {
        id: cardSet.id,
        code: cardSet.code,
        name: cardSet.name,
      },
      external_references: {
        imported: importedReferences,
        ignored: ignoredReferences,
        total: set.cards.length,
      },
      controlled_test: {
        card_id: cardId,
        external_card_id: tcgCard.id,
        collector_number: tcgCard.localId,
        name: tcgCard.name,
        language: language.code,
        asset_type: assetType.code,
        bucket: storageBucket.code,
        source_url: imageSourceUrl,
        storage_path: storagePath,
        public_url: publicUrlData.publicUrl,
        mime_type: mimeType,
        file_extension: fileExtension,
        file_size_bytes: imageBuffer.byteLength,
        checksum_sha256: checksumSha256,
        card_asset_id: cardAsset.id,
      },
    });
  } catch (error) {
    console.error(error);
    return Response.json(
      {
        success: false,
        error:
          error instanceof Error
            ? error.message
            : "UNEXPECTED_ERROR",
      },
      { status: 500 },
    );
  }
});
