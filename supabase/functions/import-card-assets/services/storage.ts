// Project Mimikyu — Edge Function: import-card-assets
// Storage Service — CONFIRMADO DEPLOYADO e CONCLUÍDO no Sprint B3.20, junto
// com index.ts v2.3.0 (ver docs/06-pipeline-importacao.md, "Sprint B3.20").
//
// Extraído de dentro de index.ts nesta revisão — refatoração mínima e
// deliberada, aprovada por Fabrício antes de escalar de um teste controlado
// (1 carta) para o processamento em lote (188 cartas da ME1): download da
// imagem, cálculo de checksum SHA-256, montagem do caminho no Storage e
// upload passam a viver aqui; `index.ts` volta a ter responsabilidade única
// de orquestrar (Convenção #6).
//
// Caminho de Storage inclui o idioma (`me1/en/001.webp`) desde esta revisão,
// para não colidir com uma futura importação em `pt-BR` da mesma carta.
//
// v2.9.1 (2026-08-02, mesmo dia, rodada seguinte, CONFIRMADO DEPLOYADO —
// `npx supabase functions deploy import-card-assets` bem-sucedido, projeto
// `qjfutqujxrbzgrtkpgkg`, versão 26) — `downloadImage()` ganhou
// um timeout explícito (`IMAGE_DOWNLOAD_TIMEOUT_MS = 20000`, via
// `AbortController`). Bug real reportado por Fabrício: a importação de ME5
// (120 cartas, nenhuma imagem ainda) ficou "travada" — nenhuma imagem
// chegou ao Storage (confirmado direto no bucket) e `asset_import_run`
// mostrou `processed_count`/`success_count` zerados por minutos seguidos.
// Investigação real via MCP do Supabase (logs + banco): `card_external_
// reference` de ME5 tem `image_source_url` preenchido para as 120 cartas
// (a TCGdex respondeu normalmente ao listar o Set), mas os logs do bucket
// `card-front` não mostram NENHUMA tentativa de upload para `me5/...` — ou
// seja, a função nunca passava de `downloadImage()` para a primeira carta
// a tempo. Runs anteriores da mesma Coleção (antes desta correção)
// confirmam o padrão: `processed_count` chegava a 60–85 depois de quase 15
// minutos, mas `success_count` sempre `0` — cada tentativa de download
// aparentemente ficava pendurada por um tempo real muito longo antes de
// finalmente falhar (sem timeout, `fetch()` esperava a resposta da TCGdex
// indefinidamente), em vez de falhar rápido e liberar o lote para a
// próxima carta. Sem um timeout, um único fornecedor lento (ou uma URL de
// imagem específica que nunca responde) consome sozinho todo o orçamento
// de execução da plataforma (~150s), sem nenhum progresso registrado.
// Corrigido: cada download agora aborta depois de 20s — tempo generoso
// para uma imagem individual, mas suficiente para permitir várias
// tentativas (bem-sucedidas ou falhas reais, ex.: 404) dentro do teto de
// execução, em vez de travar tudo numa única chamada pendurada. Não
// resolve, por si só, uma eventual ausência real de imagens para ME5 na
// TCGdex (mesmo gap já visto para MEE, Sprint B3.24/`05-modelo-de-dados.md`
// revisão relevante) — só garante que esse tipo de falha aparece rápido em
// `failures[]`/`error_summary`, em vez de nunca aparecer.

type DownloadedImage = {
  sourceUrl: string;
  buffer: ArrayBuffer;
  mimeType: string;
  fileExtension: string;
  fileSizeBytes: number;
  checksumSha256: string;
};

type UploadImageParams = {
  supabase: any;
  bucketCode: string;
  storagePath: string;
  image: DownloadedImage;
};

export async function calculateSha256(
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

function resolveFileExtension(mimeType: string): string {
  switch (mimeType) {
    case "image/jpeg":
      return "jpg";
    case "image/png":
      return "png";
    case "image/webp":
      return "webp";
    default:
      return "bin";
  }
}

/**
 * A URL retornada pela TCGdex é uma URL-base; o sufixo /high.webp seleciona
 * a imagem em alta resolução no formato WebP.
 */
export function buildTcgdexHighImageUrl(
  baseImageUrl: string,
): string {
  return `${baseImageUrl}/high.webp`;
}

export function buildCardStoragePath(
  cardSetCode: string,
  collectorNumber: string,
  languageCode: string,
  fileExtension: string,
): string {
  return [
    cardSetCode.toLowerCase(),
    languageCode,
    `${collectorNumber}.${fileExtension}`,
  ].join("/");
}

// v2.9.1 — tempo máximo de espera por uma única imagem antes de desistir
// (ver comentário do cabeçalho do arquivo). Generoso o bastante para uma
// imagem individual real, mas baixo o suficiente para nunca consumir
// sozinho o orçamento de execução inteiro da Edge Function.
const IMAGE_DOWNLOAD_TIMEOUT_MS = 20_000;

export async function downloadImage(
  sourceUrl: string,
): Promise<DownloadedImage> {
  const controller = new AbortController();
  const timeoutId = setTimeout(
    () => controller.abort(),
    IMAGE_DOWNLOAD_TIMEOUT_MS,
  );

  let response: Response;
  try {
    response = await fetch(sourceUrl, {
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error(
        `IMAGE_DOWNLOAD_TIMEOUT: sem resposta em ${IMAGE_DOWNLOAD_TIMEOUT_MS}ms`,
      );
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    throw new Error(
      `IMAGE_DOWNLOAD_FAILED: ${response.status} ${response.statusText}`,
    );
  }

  const buffer = await response.arrayBuffer();

  if (buffer.byteLength === 0) {
    throw new Error("IMAGE_DOWNLOAD_EMPTY");
  }

  const mimeType =
    response.headers.get("content-type")
      ?.split(";")[0]
      ?.trim() || "application/octet-stream";
  const fileExtension = resolveFileExtension(mimeType);

  if (fileExtension === "bin") {
    throw new Error(
      `IMAGE_MIME_TYPE_NOT_SUPPORTED: ${mimeType}`,
    );
  }

  const checksumSha256 = await calculateSha256(buffer);

  return {
    sourceUrl,
    buffer,
    mimeType,
    fileExtension,
    fileSizeBytes: buffer.byteLength,
    checksumSha256,
  };
}

export async function uploadImage({
  supabase,
  bucketCode,
  storagePath,
  image,
}: UploadImageParams) {
  const { error } = await supabase.storage
    .from(bucketCode)
    .upload(
      storagePath,
      image.buffer,
      {
        contentType: image.mimeType,
        cacheControl: "3600",
        upsert: true,
      },
    );

  if (error) {
    console.error(
      "STORAGE UPLOAD ERROR:",
      JSON.stringify(error, null, 2),
    );
    throw new Error(
      `STORAGE_UPLOAD_FAILED: ${error.message}`,
    );
  }

  const { data } = supabase.storage
    .from(bucketCode)
    .getPublicUrl(storagePath);

  return {
    storagePath,
    publicUrl: data.publicUrl,
  };
}
