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
- v2.1.0 (Sprint B3.13, CONFIRMADO CONCLUÍDO no Sprint B3.15 — execução real
  de ponta a ponta validada: `imported: 188`, `ignored: 0`, `total: 188` para
  a `ME1`, reconfirmado por `COUNT(*)` em `card_external_reference`):
  incremento real de persistência (Incremento 1). `card`/`card_variant` já
  estão populadas para as 5 coleções (ver docs/05-modelo-de-dados.md) — esta
  função NUNCA insere em `card`, apenas consulta. Carrega todas as cartas da
  coleção via `listCardsMap` (um único SELECT, `Map<collector_number,
  card_id>`) e faz `UPSERT` em `card_external_reference`
  (`upsertCardExternalReference`, idempotente via
  `ON CONFLICT (card_id, asset_source_id)`). Bloqueio real encontrado e
  corrigido no caminho: GRANT ausente em `card_external_reference` para
  `service_role` (Query 253).
- v2.2.0 (Sprint B3.18/B3.19): Incremento 2 (Download de Imagens), primeira
  versão do teste controlado com uma única carta (`set.cards[0]`). Deploy
  confirmado no Sprint B3.18; execução bloqueada, em sequência, por quatro
  novos casos reais do mesmo gap de GRANT (`language`, `card_asset_type`,
  `card_asset`, `expansion` — Query `254`), cada um diagnosticado pelo erro
  real do PostgreSQL nos logs, nunca adivinhado. **CONFIRMADO CONCLUÍDO no
  Sprint B3.19**: com os quatro GRANTs corrigidos, o teste controlado
  finalmente executou de ponta a ponta com sucesso — primeira imagem real do
  projeto baixada da TCGdex, enviada ao Supabase Storage (bucket
  `card-front`) e registrada em `card_asset` (`ME1-001`/Bulbasaur).
- v2.3.0 (Sprint B3.20, 🎉 CONFIRMADO CONCLUÍDO — MARCO REAL: Incremento 2
  100% completo para a `ME1`, `188/188` imagens importadas, `0` falhas):
  refatoração aprovada por Fabrício antes de escalar — lógica de
  download/checksum/caminho/upload extraída para `services/storage.ts`
  (`buildTcgdexHighImageUrl`, `buildCardStoragePath`, `downloadImage`,
  `uploadImage`); `index.ts` volta a ser apenas orquestrador. Processamento
  ampliado de uma única carta (`set.cards[0]`) para todas as cartas da
  coleção, com concorrência controlada em lotes de 5 (`processInBatches`,
  `IMAGE_BATCH_SIZE = 5`) — evita excesso de requisições simultâneas contra a
  TCGdex/Storage. Caminho de Storage passou a incluir o idioma
  (`me1/en/001.webp`), preparando o terreno para uma futura importação em
  `pt-BR` sem colisão. **Bug real de regra de negócio encontrado e
  corrigido** na primeira tentativa em escala: o código gravava a URL de
  origem da TCGdex em `external_url` mesmo para ativos já baixados e
  armazenados internamente (`storage_path` preenchido) — violando uma regra
  já aplicada pelo banco (esse campo é reservado para ativos não baixados,
  apenas referenciados externamente); corrigido para `external_url: null`
  sempre que o ativo é armazenado internamente. **Pergunta real de
  idempotência respondida, sem código novo**: reexecutar a função não
  duplica nem arquivos no Storage (`upsert: true` no upload) nem registros em
  `card_asset` (busca por chave natural antes de `INSERT`/`UPDATE`) — uma
  melhoria de performance (pular cartas já importadas, evitando novo
  download/upload) foi proposta e **deliberadamente adiada por decisão
  explícita de Fabrício**, para não interromper o fluxo a um passo da
  conclusão da `ME1`. Resposta final ampliada:
  `configuration`/`external_references`/`images`/`failures`.
- v2.3.1 (Sprint B3.23, CONFIRMADO DEPLOYADO — teste controlado da Fase 2):
  `LANGUAGE_CODE` alterado de `"en"` para `"pt-BR"` — **mudança temporária,
  usada apenas para o teste controlado com uma carta (reexecução do
  `run_code` original da `ME1`)**, seguindo a mesma disciplina já usada no
  Incremento 2 (validar com uma carta antes de escalar para as 5 coleções).
  Resultado real: segunda linha de `card_asset` criada para `ME1-001`
  (`language_id` = `pt-BR`, `storage_path` = `me1/pt-BR/001.webp`), ao lado
  da linha `en` já existente — confirma que `card_asset` já suporta múltiplos
  idiomas por carta corretamente. **Discrepância real sinalizada antes de
  qualquer nova execução em lote, NÃO resolvida nesta revisão**: a
  `UNIQUE (card_id, asset_source_id)` de `card_external_reference` não inclui
  idioma — como `asset_source_id` (TCGDEX) é o mesmo independente do idioma,
  uma execução em `pt-BR` pode fazer `UPSERT` sobre a mesma linha já usada
  para `en`, em vez de criar uma segunda. Fabrício optou por confirmar o
  comportamento real antes de alterar qualquer coisa — ver
  docs/06-pipeline-importacao.md, "Sprint B3.23". Espera-se que este valor
  volte a ser um parâmetro da requisição (já identificado como pré-requisito
  da Fase 2 desde o Sprint B3.21), não uma constante fixa.

Ver docs/06-pipeline-importacao.md, seções "Sprint B3.6", "Sprint B3.15",
"Sprint B3.19", "Sprint B3.20" e "Sprint B3.23", para o contexto completo, o
roteiro de sprints e o status real de cada etapa (o que foi de fato confirmado vs. o que
ainda está planejado).

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
import {
  buildTcgdexHighImageUrl,
  buildCardStoragePath,
  downloadImage,
  uploadImage,
} from "./services/storage.ts";

type RequestBody = {
  run_code?: string;
};

type ImageImportResult = {
  external_card_id: string;
  collector_number: string;
  name: string;
  success: boolean;
  storage_path?: string;
  public_url?: string;
  card_asset_id?: string;
  error?: string;
};

// Sprint B3.23 — alterado temporariamente de "en" para "pt-BR" para o teste
// controlado da Fase 2 (ver histórico de versões acima, v2.3.1). Espera-se
// que volte a ser um parâmetro da requisição antes da Fase 2 escalar para as
// 5 coleções.
const LANGUAGE_CODE = "pt-BR";
const ASSET_TYPE_CODE = "CARD_FRONT";
const STORAGE_BUCKET_CODE = "card-front";
const IMAGE_BATCH_SIZE = 5;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/**
 * Executa operações assíncronas em lotes controlados — evita excesso de
 * requisições simultâneas contra a TCGdex/Storage ao processar uma coleção
 * inteira de cartas.
 */
async function processInBatches<T, R>(
  items: T[],
  batchSize: number,
  processor: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];

  for (
    let index = 0;
    index < items.length;
    index += batchSize
  ) {
    const batch = items.slice(index, index + batchSize);
    const batchResults = await Promise.all(
      batch.map(processor),
    );
    results.push(...batchResults);
  }

  return results;
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

    const language = await findLanguageByCode(
      supabase,
      LANGUAGE_CODE,
    );

    if (!language) {
      throw new Error(
        `LANGUAGE_NOT_FOUND: ${LANGUAGE_CODE}`,
      );
    }

    const assetType = await findCardAssetTypeByCode(
      supabase,
      ASSET_TYPE_CODE,
    );

    if (!assetType) {
      throw new Error(
        `CARD_ASSET_TYPE_NOT_FOUND: ${ASSET_TYPE_CODE}`,
      );
    }

    const storageBucket = await findStorageBucketByCode(
      supabase,
      STORAGE_BUCKET_CODE,
    );

    if (!storageBucket) {
      throw new Error(
        `STORAGE_BUCKET_NOT_FOUND: ${STORAGE_BUCKET_CODE}`,
      );
    }

    const tcgdex = new TcgdexClient(LANGUAGE_CODE);
    const set = await tcgdex.getSet(
      externalReference.external_set_id,
    );

    const cards = await listCardsMap(
      supabase,
      run.card_set_id,
    );

    // Sincronização completa de card_external_reference (Incremento 1,
    // CONFIRMADO CONCLUÍDO no Sprint B3.15 — mantida idêntica nesta versão).
    const referenceResults = await processInBatches(
      set.cards,
      20,
      async (tcgCard) => {
        const cardId = cards.get(tcgCard.localId);

        if (!cardId) {
          console.warn(
            `Carta ${tcgCard.localId} não encontrada no catálogo.`,
          );
          return false;
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
              `https://api.tcgdex.net/v2/${LANGUAGE_CODE}/cards/${tcgCard.id}`,
            image_source_url: tcgCard.image,
            metadata: tcgCard,
            is_active: true,
          },
        );
        return true;
      },
    );

    const importedReferences =
      referenceResults.filter(Boolean).length;
    const ignoredReferences =
      referenceResults.length - importedReferences;

    // Incremento 2 (Sprint B3.20) — download + upload + card_asset para
    // todas as cartas da coleção, em lotes controlados.
    const imageResults = await processInBatches(
      set.cards,
      IMAGE_BATCH_SIZE,
      async (tcgCard): Promise<ImageImportResult> => {
        try {
          const cardId = cards.get(tcgCard.localId);

          if (!cardId) {
            throw new Error(
              `CARD_NOT_FOUND: ${tcgCard.localId}`,
            );
          }

          if (!tcgCard.image) {
            throw new Error(
              `TCGDEX_IMAGE_NOT_AVAILABLE: ${tcgCard.id}`,
            );
          }

          const imageSourceUrl = buildTcgdexHighImageUrl(
            tcgCard.image,
          );
          const image = await downloadImage(imageSourceUrl);
          const storagePath = buildCardStoragePath(
            cardSet.code,
            tcgCard.localId,
            language.code,
            image.fileExtension,
          );
          const upload = await uploadImage({
            supabase,
            bucketCode: storageBucket.code,
            storagePath,
            image,
          });

          // external_url é reservado para ativos NÃO baixados (apenas
          // referenciados externamente); este ativo já foi baixado e
          // armazenado internamente (storage_path preenchido), por isso
          // permanece null — regra de negócio já aplicada pelo banco.
          const cardAsset = await upsertCardAsset(
            supabase,
            {
              card_id: cardId,
              asset_type_id: assetType.id,
              source_code: "TCGDEX",
              source_reference: tcgCard.id,
              storage_path: upload.storagePath,
              external_url: null,
              mime_type: image.mimeType,
              file_extension: image.fileExtension,
              file_size_bytes: image.fileSizeBytes,
              width_pixels: null,
              height_pixels: null,
              checksum_sha256: image.checksumSha256,
              is_primary: true,
              asset_order: 1,
              is_active: true,
              language_id: language.id,
              storage_bucket_id: storageBucket.id,
            },
          );

          return {
            external_card_id: tcgCard.id,
            collector_number: tcgCard.localId,
            name: tcgCard.name,
            success: true,
            storage_path: upload.storagePath,
            public_url: upload.publicUrl,
            card_asset_id: cardAsset.id,
          };
        } catch (error) {
          const errorMessage =
            error instanceof Error
              ? error.message
              : "UNEXPECTED_IMAGE_IMPORT_ERROR";
          console.error(
            `IMAGE IMPORT FAILED ${tcgCard.id}:`,
            errorMessage,
          );
          return {
            external_card_id: tcgCard.id,
            collector_number: tcgCard.localId,
            name: tcgCard.name,
            success: false,
            error: errorMessage,
          };
        }
      },
    );

    const importedImages = imageResults.filter(
      (result) => result.success,
    );
    const failedImages = imageResults.filter(
      (result) => !result.success,
    );

    return Response.json({
      success: failedImages.length === 0,
      version: "2.3.1",
      run: {
        id: run.id,
        run_code: run.run_code,
      },
      card_set: {
        id: cardSet.id,
        code: cardSet.code,
        name: cardSet.name,
      },
      configuration: {
        language: language.code,
        asset_type: assetType.code,
        bucket: storageBucket.code,
        image_batch_size: IMAGE_BATCH_SIZE,
      },
      external_references: {
        imported: importedReferences,
        ignored: ignoredReferences,
        total: set.cards.length,
      },
      images: {
        imported: importedImages.length,
        failed: failedImages.length,
        total: imageResults.length,
      },
      failures: failedImages,
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
