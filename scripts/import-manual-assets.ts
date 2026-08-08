/*
Project Mimikyu
Script administrativo standalone: import-manual-assets

Objetivo: importar manualmente os card_asset (CARD_FRONT) de coleções cuja
fonte externa (TCGdex) ainda não publica o campo `image` — hoje, `MEE` e
`MEP`, confirmado por consulta real em 2026-07-24 (ver
docs/05-modelo-de-dados.md, revisão 0.66, e docs/operations/import-card-assets.md,
"Estado Atual"). `card_external_reference` das duas coleções já está 100%
importada via `import-card-assets` (RUN-20260724-00000041/MEE,
RUN-20260724-00000061/MEP) — este script cuida apenas da camada `card_asset`,
que não depende de `card_external_reference` (ver docs/05-modelo-de-dados.md,
seção Card Asset: "card_asset NÃO tem uma coluna card_external_reference_id").

CONFIRMADO EXECUTADO em 2026-07-24: `MEE`/`en`, 8/8 cartas, 0 falhas
(dry-run limpo seguido de execução real, ver docs/05-modelo-de-dados.md,
revisão 0.67, para o detalhe completo). Imagem validada visualmente via URL
pública do Storage.

Este é um script administrativo, não uma Edge Function — segue o mesmo
precedente de `scripts/discover-tcgdex-sets.ts` (ver
docs/06-pipeline-importacao.md, "Sprint B2.5A"): roda localmente, sob demanda,
com a Service Role Key do projeto, nunca é implantado no Supabase.
Deliberadamente NÃO fica em `supabase/functions/import-card-assets/` —
essa pasta é implantada por inteiro a cada `supabase functions deploy`, e
este script lê arquivos locais do disco (`Deno.readDirSync`/`readFile`), o
que nem existe no runtime de uma Edge Function.

Convenção de pastas esperada (confirmada com Fabrício em 2026-07-24):

  assets/manual-imports/{card_set_code_lowercase}/{language_code}/{collector_number}.{ext}

Exemplos:
  assets/manual-imports/mee/en/001.png
  assets/manual-imports/mee/pt-BR/001.png
  assets/manual-imports/mep/en/046.png

IMPORTANTE: o nome do arquivo (sem extensão) deve ser EXATAMENTE igual ao
`card.collector_number` já cadastrado (não `collector_order`) — para `MEP`,
`collector_number` preserva lacunas reais da numeração promocional (ver
docs/05-modelo-de-dados.md, seção Card Set, "Migration 265-268"), então o
nome do arquivo não é necessariamente sequencial.

Rastreabilidade (confirmado com Fabrício): todo `card_asset` criado por este
script é marcado com `source_code = "MANUAL"`, diferente de `"TCGDEX"` usado
pelo pipeline automático — preserva a possibilidade de auditar/substituir
depois, caso a TCGdex publique os assets reais.

Uso:

  # PowerShell — defina as variáveis de ambiente ANTES de rodar.
  # NUNCA cole a Service Role Key em chat/log — pegue direto em
  # Supabase Dashboard > Project Settings > API > service_role secret.
  $env:SUPABASE_URL = "https://qjfutqujxrbzgrtkpgkg.supabase.co"
  $env:SUPABASE_SERVICE_ROLE_KEY = "<service_role_key>"

  deno run --allow-net --allow-read --allow-env scripts/import-manual-assets.ts

  # Para processar só uma coleção/idioma específico (opcional):
  deno run --allow-net --allow-read --allow-env scripts/import-manual-assets.ts --set=mee --language=en

Convenção #7 do projeto (validação antes de qualquer execução real) também
se aplica aqui: rode primeiro com --dry-run para conferir o que seria feito
sem gravar nada.

Refatorado em 2026-08-08 (ADR-026, emenda "Segundo ponto de entrada via UI"):
a lógica de validação/resolução (extensão/MIME, Card Set/Card/idioma) foi
extraída para web/lib/catalogo/manual-asset-import/core.ts — núcleo
compartilhado, runtime-neutro, também usado pela Server Action da tela
/catalogo/importar-imagens (modo Manual). Este script continua sendo o único
lugar que lê arquivos do disco local e grava direto em card_asset via Service
Role Key (bypassa RLS) — a Server Action grava por admin_persist_manual_
card_asset() (Query 2120, exige sessão real de administrador, nunca aceitaria
uma chamada por Service Role Key). Comportamento deste script não mudou; só
a lógica compartilhada deixou de estar duplicada aqui.
*/

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  buildScriptManualAssetStoragePath,
  findCardAssetTypeByCode,
  findStorageBucketByCode,
  MANUAL_ASSET_MIME_TYPES,
  ManualAssetImportError,
  extensionOf,
  resolveManualAssetCard,
  sha256Hex,
  stripExtension,
  uploadManualAssetFile,
} from "../web/lib/catalogo/manual-asset-import/core.ts";

const MANUAL_IMPORT_ROOT = "assets/manual-imports";
const ASSET_TYPE_CODE = "CARD_FRONT";
const STORAGE_BUCKET_CODE = "card-front";
const SOURCE_CODE = "MANUAL";

type CliArgs = {
  set?: string;
  language?: string;
  dryRun: boolean;
};

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = { dryRun: false };

  for (const arg of argv) {
    if (arg === "--dry-run") {
      args.dryRun = true;
    } else if (arg.startsWith("--set=")) {
      args.set = arg.slice("--set=".length).toLowerCase();
    } else if (arg.startsWith("--language=")) {
      args.language = arg.slice("--language=".length);
    }
  }

  return args;
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);

  if (!value) {
    console.error(`Variável de ambiente obrigatória ausente: ${name}`);
    Deno.exit(1);
  }

  return value;
}

// Mesma estratégia de idempotência de services/database.ts::upsertCardAsset —
// localizar pela chave natural (card_id + asset_type_id + language_id +
// storage_bucket_id) em vez de depender de um nome de constraint UNIQUE.
// Gravação direta na tabela (Service Role Key, bypassa RLS) — deliberadamente
// NÃO compartilhada com a web, que grava por admin_persist_manual_card_asset()
// (Query 2120, exige sessão real de administrador). Ver nota no cabeçalho.
async function upsertCardAsset(
  supabase: any,
  payload: {
    card_id: string;
    asset_type_id: string;
    language_id: string;
    storage_bucket_id: string;
    storage_path: string;
    mime_type: string;
    file_extension: string;
    file_size_bytes: number;
    checksum_sha256: string;
  },
) {
  const { data: existing, error: findError } = await supabase
    .from("card_asset")
    .select("id")
    .eq("card_id", payload.card_id)
    .eq("asset_type_id", payload.asset_type_id)
    .eq("language_id", payload.language_id)
    .eq("storage_bucket_id", payload.storage_bucket_id)
    .eq("is_active", true)
    .maybeSingle();

  if (findError) {
    throw new ManualAssetImportError("CARD_ASSET_QUERY_FAILED", findError.message);
  }

  const record = {
    card_id: payload.card_id,
    asset_type_id: payload.asset_type_id,
    source_code: SOURCE_CODE,
    source_reference: null,
    storage_path: payload.storage_path,
    external_url: null,
    mime_type: payload.mime_type,
    file_extension: payload.file_extension,
    file_size_bytes: payload.file_size_bytes,
    width_pixels: null,
    height_pixels: null,
    checksum_sha256: payload.checksum_sha256,
    is_primary: true,
    asset_order: 1,
    is_active: true,
    language_id: payload.language_id,
    storage_bucket_id: payload.storage_bucket_id,
    updated_at: new Date().toISOString(),
  };

  if (existing) {
    const { data, error } = await supabase
      .from("card_asset")
      .update(record)
      .eq("id", existing.id)
      .select()
      .single();

    if (error) {
      throw new ManualAssetImportError("CARD_ASSET_UPDATE_FAILED", error.message);
    }

    return { data, wasUpdate: true };
  }

  const { data, error } = await supabase
    .from("card_asset")
    .insert(record)
    .select()
    .single();

  if (error) {
    throw new ManualAssetImportError("CARD_ASSET_INSERT_FAILED", error.message);
  }

  return { data, wasUpdate: false };
}

type ProcessResult = {
  set: string;
  language: string;
  collector_number: string;
  file: string;
  success: boolean;
  storage_path?: string;
  action?: "created" | "updated" | "dry-run";
  error?: string;
};

async function processFile(
  supabase: any,
  cardSetCode: string,
  languageCode: string,
  filePath: string,
  fileName: string,
  dryRun: boolean,
): Promise<ProcessResult> {
  const collectorNumber = stripExtension(fileName);

  const base: Omit<ProcessResult, "success"> = {
    set: cardSetCode,
    language: languageCode,
    collector_number: collectorNumber,
    file: filePath,
  };

  try {
    const { card, language } = await resolveManualAssetCard(supabase, {
      cardSetCode,
      collectorNumber,
      languageCode,
    });

    const assetType = await findCardAssetTypeByCode(supabase, ASSET_TYPE_CODE);
    if (!assetType) {
      throw new ManualAssetImportError("CARD_ASSET_TYPE_NOT_FOUND", ASSET_TYPE_CODE);
    }

    const storageBucket = await findStorageBucketByCode(supabase, STORAGE_BUCKET_CODE);
    if (!storageBucket) {
      throw new ManualAssetImportError("STORAGE_BUCKET_NOT_FOUND", STORAGE_BUCKET_CODE);
    }

    const fileBytes = await Deno.readFile(filePath);
    const extension = extensionOf(fileName);
    const mimeType = MANUAL_ASSET_MIME_TYPES[extension];

    if (!mimeType) {
      throw new ManualAssetImportError("UNSUPPORTED_EXTENSION", extension);
    }

    const checksum = await sha256Hex(fileBytes);
    const storagePath = buildScriptManualAssetStoragePath(cardSetCode, languageCode, collectorNumber, extension);

    if (dryRun) {
      return {
        ...base,
        success: true,
        storage_path: storagePath,
        action: "dry-run",
      };
    }

    await uploadManualAssetFile(supabase, storageBucket.code, storagePath, fileBytes, mimeType, { upsert: true });

    const { wasUpdate } = await upsertCardAsset(supabase, {
      card_id: card.id,
      asset_type_id: assetType.id,
      language_id: language.id,
      storage_bucket_id: storageBucket.id,
      storage_path: storagePath,
      mime_type: mimeType,
      file_extension: extension,
      file_size_bytes: fileBytes.byteLength,
      checksum_sha256: checksum,
    });

    return {
      ...base,
      success: true,
      storage_path: storagePath,
      action: wasUpdate ? "updated" : "created",
    };
  } catch (error) {
    return {
      ...base,
      success: false,
      error: error instanceof Error ? error.message : "UNEXPECTED_ERROR",
    };
  }
}

async function main() {
  const args = parseArgs(Deno.args);

  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

  const results: ProcessResult[] = [];

  let setDirs: string[];

  try {
    setDirs = Array.from(Deno.readDirSync(MANUAL_IMPORT_ROOT))
      .filter((entry) => entry.isDirectory)
      .map((entry) => entry.name)
      .filter((name) => !args.set || name.toLowerCase() === args.set);
  } catch {
    console.error(
      `Pasta não encontrada: ${MANUAL_IMPORT_ROOT} (rode a partir da raiz do repositório).`,
    );
    Deno.exit(1);
  }

  if (setDirs.length === 0) {
    console.error("Nenhuma pasta de coleção encontrada para processar.");
    Deno.exit(1);
  }

  for (const setDir of setDirs) {
    const setPath = `${MANUAL_IMPORT_ROOT}/${setDir}`;

    let languageDirs: string[];

    try {
      languageDirs = Array.from(Deno.readDirSync(setPath))
        .filter((entry) => entry.isDirectory)
        .map((entry) => entry.name)
        .filter((name) => !args.language || name === args.language);
    } catch {
      console.warn(`Pasta ignorada (sem subpastas de idioma): ${setPath}`);
      continue;
    }

    for (const languageDir of languageDirs) {
      const languagePath = `${setPath}/${languageDir}`;

      const files = Array.from(Deno.readDirSync(languagePath))
        .filter((entry) => entry.isFile);

      for (const file of files) {
        const filePath = `${languagePath}/${file.name}`;

        const result = await processFile(
          supabase,
          setDir,
          languageDir,
          filePath,
          file.name,
          args.dryRun,
        );

        results.push(result);

        const label = result.success
          ? `[OK ${result.action}]`
          : "[FALHOU]";

        console.log(
          `${label} ${result.set}/${result.language}/${result.collector_number} — ${
            result.success ? result.storage_path : result.error
          }`,
        );
      }
    }
  }

  const succeeded = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);

  console.log("");
  console.log(
    `${args.dryRun ? "[DRY-RUN] " : ""}Total: ${results.length} — Sucesso: ${succeeded.length} — Falhas: ${failed.length}`,
  );

  if (failed.length > 0) {
    console.log("Falhas:");
    for (const failure of failed) {
      console.log(
        `  ${failure.set}/${failure.language}/${failure.collector_number}: ${failure.error}`,
      );
    }
  }
}

await main();
