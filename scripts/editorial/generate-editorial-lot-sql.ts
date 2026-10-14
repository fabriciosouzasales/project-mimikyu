/*
Project Mimikyu
Script offline: generate-editorial-lot-sql
Pokédex P3e — geração determinística da seed editorial e da validação independente (2026-10-13).

O que faz
  A partir de um lote editorial 100% APROVADO (mesmo JSON validado por validate-editorial-lot.ts)
  e dos lotes já publicados (ex.: pilot-pt-BR.json), escreve dois arquivos SQL:
    - <seed>: publicação transacional, atômica e idempotente das linhas MMKYU_EDITORIAL pt-BR
      do lote (GENUS + FLAVOR por espécie), com pré e pós-condições que abortam tudo em
      qualquer divergência;
    - <validation>: verificação só de leitura (BEGIN/ROLLBACK) do estado após a publicação,
      incluindo a preservação dos lotes já publicados pelos md5 versionados.

Garantias da geração
  - Recusa gerar se o lote não passar no validador com --require-approved (erros = abortar).
  - Saída é função pura dos JSONs de entrada: mesma entrada → mesmos bytes (sem data/hora);
    o cabeçalho registra o sha256 de cada JSON de entrada para proveniência.
  - Os textos entram como literais $t$...$t$; a geração aborta se algum texto contiver "$t$".
  - O md5 de cada texto é conferido no próprio SQL contra o content_md5 aprovado.

Não acessa rede nem banco. Não executa SQL.

Uso (Node 22+ ou Deno)
  node --experimental-strip-types scripts/editorial/generate-editorial-lot-sql.ts \
    --lot <lote.json> --published <publicado.json>... --snapshot <snapshot.json> \
    --seed-query 6137 --validation-query 6848 --out-dir <pasta> --tag <slug>
*/

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { type Lot, type SnapshotSpecies, loadJson, md5, publishedNumbers, validateLot } from "./validate-editorial-lot.ts";

type PublishedLot = {
  batch?: string;
  entries: Array<{ national_dex_number: number; content_md5: { genus: string; description: string } }>;
  publication?: { published?: boolean };
};

type Baseline = { source_rows: number; source_md5: string };

export type GenerateInput = {
  lot: Lot;
  lotSha256: string;
  published: Array<{ path: string; sha256: string; data: PublishedLot }>;
  snapshot?: SnapshotSpecies[];
  seedQuery: string;
  validationQuery: string;
  tag: string;
};

const sha256 = (s: string) => createHash("sha256").update(s, "utf8").digest("hex");

function dollar(text: string): string {
  if (text.includes("$t$")) throw new Error("texto contém o delimitador $t$");
  return `$t$${text}$t$`;
}

function sourceHashExpr(alias: string): string {
  // Mesma expressão da 6136/6847 (timestamps em UTC).
  const a = alias;
  return `md5(string_agg(${a}.pokemon_species_id::text || '|' || ${a}.text_kind || '|' || ${a}.language_code || '|' || coalesce(${a}.source_version, '') || '|' || ${a}.content || '|' || ${a}.rights_status || '|' || coalesce(${a}.asset_source_id::text, '') || '|' || coalesce((${a}.retrieved_at at time zone 'UTC')::text, ''), E'\\n' order by ${a}.pokemon_species_id, ${a}.text_kind, ${a}.language_code))`;
}

export function generate(input: GenerateInput): { seed: string; validation: string } {
  const { lot, seedQuery: q, validationQuery: v, tag } = input;
  const published = publishedNumbers(input.published.map((p) => p.data));
  const findings = validateLot(lot, { published, snapshot: input.snapshot, requireApproved: true });
  const errors = findings.filter((f) => f.severity === "ERRO");
  if (errors.length) throw new Error(`lote não passa no validador (--require-approved): ${errors.map((e) => `${e.dex ?? "lote"} ${e.code}`).join(", ")}`);

  const baseline = (lot.publication as { baseline?: Baseline } | undefined)?.baseline;
  if (!baseline || !Number.isInteger(baseline.source_rows) || !/^[0-9a-f]{32}$/.test(baseline.source_md5)) {
    throw new Error("publication.baseline (source_rows, source_md5) ausente no lote");
  }

  const entries = [...lot.entries].sort((a, b) => a.national_dex_number - b.national_dex_number);
  const lotNums = entries.map((e) => e.national_dex_number);
  const pubRows: Array<[number, string, string]> = [];
  for (const p of input.published) {
    if (p.data.publication && p.data.publication.published !== true) continue;
    for (const e of p.data.entries) {
      pubRows.push([e.national_dex_number, "GENUS", e.content_md5.genus]);
      pubRows.push([e.national_dex_number, "FLAVOR", e.content_md5.description]);
    }
  }
  pubRows.sort((a, b) => a[0] - b[0] || a[1].localeCompare(b[1]));
  const pubNums = [...new Set(pubRows.map((r) => r[0]))];
  const nLot = entries.length;
  const nLotRows = nLot * 2;
  const nPubRows = pubRows.length;
  const nPub = pubNums.length;
  const totalRows = nLotRows + nPubRows;
  const totalSpecies = nLot + nPub;

  const provenance = [
    `-- Gerado por scripts/editorial/generate-editorial-lot-sql.ts — NÃO EDITAR À MÃO; regerar a partir do JSON.`,
    `-- Lote: ${lot.batch} · revisão ${lot.revision} · guia ${lot.guide_version} · sha256 do JSON ${input.lotSha256}`,
    ...input.published.map((p) => `-- Publicado preservado: ${p.path} · sha256 ${p.sha256}`),
  ].join("\n");

  const payload = entries
    .flatMap((e) => [
      `    (${String(e.national_dex_number).padStart(4)}, 'GENUS',  ${dollar(e.genus)}, '${e.content_md5.genus}')`,
      `    (${String(e.national_dex_number).padStart(4)}, 'FLAVOR', ${dollar(e.description)}, '${e.content_md5.description}')`,
    ])
    .join(",\n");

  const pubValues = pubRows.map(([n, k, h]) => `    (${String(n).padStart(4)}, '${k}', '${h}')`).join(",\n");
  const lotMd5Values = entries
    .flatMap((e) => [
      `    (${String(e.national_dex_number).padStart(4)}, 'GENUS',  '${e.content_md5.genus}')`,
      `    (${String(e.national_dex_number).padStart(4)}, 'FLAVOR', '${e.content_md5.description}')`,
    ])
    .join(",\n");

  const tmp = `${tag}_text`;
  const tmpPub = `${tag}_published_md5`;
  const srcExpr = sourceHashExpr("st");
  const sample = entries[0];

  const seed = `-- Query ${q} | Pokédex P3e — publicação do ${lot.batch}: editorial MMKYU pt-BR (${nLot} espécies, ${nLotRows} linhas)
--
-- Tipo: PUBLICAÇÃO DE DADOS EDITORIAIS (não é migration de esquema; sem DDL, funções ou grants).
-- Status: PROPOSTA (não executada). Executar no LIVE só com autorização explícita de Fabrício.
${provenance}
--
-- Objetivo
-- Gravar em public.pokemon_species_text a classificação (GENUS) e a descrição (FLAVOR) editoriais
-- MMKYU em pt-BR das ${nLot} espécies do lote aprovado. Conteúdo autoral MMKYU — nunca oficial.
--
-- Garantias (falha integral: qualquer violação lança exceção e nada é gravado)
-- 1. Payload: ${nLotRows} textos de ${nLot} espécies, md5 de cada texto igual ao aprovado no JSON; nenhuma
--    espécie de lote já publicado; conteúdo entre 1 e 2000 caracteres.
-- 2. Pré-condições: ${nLot} espécies ativas, perfil IMPORTED, com GENUS + FLAVOR SOURCE en;
--    SOURCE = ${baseline.source_rows} linhas com o hash de linha de base; editorial fora do lote = exatamente os
--    ${nPubRows} registros publicados (${nPub} espécies), com md5 iguais aos versionados.
-- 3. Escrita restrita a origin = 'MMKYU_EDITORIAL' das ${nLot} espécies (INSERT ... ON CONFLICT na
--    chave editorial; SOURCE nunca é alvo). Idempotente: reexecução não cria linhas.
-- 4. Pós-condições na mesma transação: ${nLotRows} linhas do lote com conteúdo exato; total editorial =
--    ${totalRows} linhas / ${totalSpecies} espécies; SOURCE inalterado; editoriais publicados inalterados (id,
--    conteúdo e updated_at).

begin;

do $pub$
declare
  v_lot constant integer[] := array[${lotNums.join(", ")}];
  v_published constant integer[] := array[${pubNums.join(", ")}];
  v_source_baseline_count constant integer := ${baseline.source_rows};
  v_source_baseline_md5 constant text := '${baseline.source_md5}';
  v_n integer;
  v_written integer;
  v_source_md5 text;
  v_published_before text;
  v_published_after text;
begin
  create temporary table ${tmp} (
    national_dex_number integer not null,
    text_kind text not null,
    content text not null,
    content_md5 text not null,
    primary key (national_dex_number, text_kind)
  ) on commit drop;

  insert into ${tmp} (national_dex_number, text_kind, content, content_md5) values
${payload};

  create temporary table ${tmpPub} (
    national_dex_number integer not null,
    text_kind text not null,
    content_md5 text not null,
    primary key (national_dex_number, text_kind)
  ) on commit drop;

  insert into ${tmpPub} (national_dex_number, text_kind, content_md5) values
${pubValues};

  -- 1. Payload
  if (select count(*) from ${tmp}) <> ${nLotRows}
     or (select count(distinct national_dex_number) from ${tmp}) <> ${nLot}
     or exists (select 1 from ${tmp} where not (national_dex_number = any (v_lot))) then
    raise exception '${q} FAIL: payload deve ter ${nLotRows} textos das ${nLot} espécies do lote';
  end if;
  if exists (select 1 from ${tmp} where national_dex_number = any (v_published)) then
    raise exception '${q} FAIL: payload contém espécie de lote já publicado';
  end if;
  select count(*) into v_n from ${tmp} where md5(content) <> content_md5;
  if v_n <> 0 then
    raise exception '${q} FAIL: % textos com md5 diferente do aprovado', v_n;
  end if;
  if exists (select 1 from ${tmp} where btrim(content) = '' or length(content) > 2000) then
    raise exception '${q} FAIL: conteúdo vazio ou acima de 2000 caracteres';
  end if;

  -- 2. Pré-condições
  select count(*) into v_n
    from (select distinct national_dex_number from ${tmp}) t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number and s.is_active
    join public.pokemon_species_profile p on p.pokemon_species_id = s.id and p.status = 'IMPORTED'
   where exists (select 1 from public.pokemon_species_text o
                  where o.pokemon_species_id = s.id and o.origin = 'SOURCE' and o.language_code = 'en' and o.text_kind = 'GENUS')
     and exists (select 1 from public.pokemon_species_text o
                  where o.pokemon_species_id = s.id and o.origin = 'SOURCE' and o.language_code = 'en' and o.text_kind = 'FLAVOR');
  if v_n <> ${nLot} then
    raise exception '${q} FAIL: % de ${nLot} espécies elegíveis (ativa, perfil IMPORTED, textos oficiais en)', v_n;
  end if;

  select count(*), ${srcExpr}
    into v_n, v_source_md5
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_n <> v_source_baseline_count or v_source_md5 is distinct from v_source_baseline_md5 then
    raise exception '${q} FAIL: SOURCE fora da linha de base antes da escrita (% linhas, hash %)', v_n, v_source_md5;
  end if;

  select count(*) into v_n
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot));
  if v_n <> ${nPubRows} then
    raise exception '${q} FAIL: % linhas editoriais fora do lote, esperado ${nPubRows} (publicados)', v_n;
  end if;

  select count(*) into v_n
    from ${tmpPub} e
    join public.pokemon_species s on s.national_dex_number = e.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = e.text_kind
     and st.origin = 'MMKYU_EDITORIAL' and st.language_code = 'pt-BR'
   where st.id is null or md5(st.content) <> e.content_md5;
  if v_n <> 0 then
    raise exception '${q} FAIL: % registros publicados divergentes dos md5 versionados', v_n;
  end if;

  select md5(coalesce(string_agg(st.id::text || '|' || st.content || '|' || st.updated_at::text, E'\\n' order by st.id), ''))
    into v_published_before
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot));

  -- 3. Escrita
  insert into public.pokemon_species_text as st (
    pokemon_species_id, text_kind, language_code, origin,
    asset_source_id, source_version, content, rights_status, retrieved_at
  )
  select s.id, t.text_kind, 'pt-BR', 'MMKYU_EDITORIAL',
         null, null, t.content, 'MMKYU_EDITORIAL', null
    from ${tmp} t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number and s.is_active
  on conflict on constraint uq_pokemon_species_text do update
     set content = excluded.content,
         rights_status = 'MMKYU_EDITORIAL'
   where st.origin = 'MMKYU_EDITORIAL'
     and (st.content is distinct from excluded.content or st.rights_status is distinct from 'MMKYU_EDITORIAL');
  get diagnostics v_written = row_count;

  -- 4. Pós-condições
  select count(*) into v_n
    from ${tmp} t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = t.text_kind
     and st.language_code = 'pt-BR' and st.origin = 'MMKYU_EDITORIAL'
   where st.id is null
      or st.content is distinct from t.content
      or md5(st.content) <> t.content_md5
      or st.rights_status <> 'MMKYU_EDITORIAL'
      or st.asset_source_id is not null or st.source_version is not null or st.retrieved_at is not null;
  if v_n <> 0 then
    raise exception '${q} FAIL: % textos do lote divergentes após a escrita', v_n;
  end if;

  select count(*) into v_n from public.pokemon_species_text where origin = 'MMKYU_EDITORIAL';
  if v_n <> ${totalRows} then
    raise exception '${q} FAIL: % linhas editoriais no total, esperado ${totalRows}', v_n;
  end if;
  select count(distinct pokemon_species_id) into v_n from public.pokemon_species_text where origin = 'MMKYU_EDITORIAL';
  if v_n <> ${totalSpecies} then
    raise exception '${q} FAIL: % espécies com editorial, esperado ${totalSpecies}', v_n;
  end if;

  select count(*), ${srcExpr}
    into v_n, v_source_md5
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_n <> v_source_baseline_count or v_source_md5 is distinct from v_source_baseline_md5 then
    raise exception '${q} FAIL: textos oficiais (SOURCE) alterados';
  end if;

  select md5(coalesce(string_agg(st.id::text || '|' || st.content || '|' || st.updated_at::text, E'\\n' order by st.id), ''))
    into v_published_after
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot));
  if v_published_after is distinct from v_published_before then
    raise exception '${q} FAIL: registros editoriais já publicados foram alterados';
  end if;

  raise notice '${q} OK: % linhas gravadas/atualizadas; lote = ${nLotRows} linhas / ${nLot} espécies; total editorial = ${totalRows} / ${totalSpecies}; SOURCE preservado (${baseline.source_rows})', v_written;
end
$pub$;

commit;

-- Resultado esperado
-- Primeira execução: "${q} OK: ${nLotRows} linhas gravadas/atualizadas; ...". Reexecução: "${q} OK: 0 linhas ...".
-- Qualquer FAIL desfaz a transação inteira (nada gravado).
--
-- Como validar: executar ${v}_validate_pokedex_editorial_ptbr_${tag.replace(/^p3e_/, "")}.sql → "${v} PASS".
--
-- Rollback (somente as ${nLotRows} linhas do lote; publicados anteriores e SOURCE intocados):
--   delete from public.pokemon_species_text st
--    using public.pokemon_species s
--    where s.id = st.pokemon_species_id and st.origin = 'MMKYU_EDITORIAL'
--      and st.language_code = 'pt-BR'
--      and s.national_dex_number in (${lotNums.join(", ")});
`;

  const validation = `-- Query ${v} | Validação independente da publicação do ${lot.batch} (Query ${q})
--
-- Somente leitura (BEGIN/ROLLBACK). Executar depois da ${q}.
${provenance}
--
-- Confere:
--   1. total editorial = ${totalRows} linhas / ${totalSpecies} espécies (${nLotRows} do lote + ${nPubRows} publicados antes);
--   2. forma: pt-BR, rights MMKYU_EDITORIAL, sem proveniência de fonte; uma GENUS e uma FLAVOR por espécie;
--   3. md5 dos ${nLotRows} textos do lote iguais aos aprovados no JSON;
--   4. md5 dos ${nPubRows} registros publicados antes iguais aos versionados (preservação do piloto);
--   5. SOURCE: ${baseline.source_rows} linhas com o hash de linha de base;
--   6. leitura da ficha (sessão autenticada simulada, nada gravado): espécie do lote em pt-BR devolve o
--      editorial; a mesma em en devolve o oficial com versão; piloto continua editorial; espécie fora de
--      ambos continua com o oficial en.
-- Resultado esperado: NOTICE "${v} PASS (...)"; qualquer divergência: "${v} FAIL: ...".

begin;

do $val$
declare
  v_lot constant integer[] := array[${lotNums.join(", ")}];
  v_published constant integer[] := array[${pubNums.join(", ")}];
  v_source_baseline_count constant integer := ${baseline.source_rows};
  v_source_baseline_md5 constant text := '${baseline.source_md5}';
  v_n integer;
  v_md5 text;
  v_user uuid;
  v_r record;
begin
  -- 1. Contagem e escopo
  select count(*) into v_n from public.pokemon_species_text where origin = 'MMKYU_EDITORIAL';
  if v_n <> ${totalRows} then raise exception '${v} FAIL: % linhas editoriais no total, esperado ${totalRows}', v_n; end if;

  select count(*) into v_n
    from public.pokemon_species_text st join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot || v_published));
  if v_n <> 0 then raise exception '${v} FAIL: % linhas editoriais fora do lote e dos publicados', v_n; end if;

  -- 2. Forma
  select count(*) into v_n
    from public.pokemon_species_text st
   where st.origin = 'MMKYU_EDITORIAL'
     and (st.language_code <> 'pt-BR' or st.rights_status <> 'MMKYU_EDITORIAL'
          or st.asset_source_id is not null or st.source_version is not null or st.retrieved_at is not null);
  if v_n <> 0 then raise exception '${v} FAIL: % linhas editoriais com idioma/direitos/proveniência incorretos', v_n; end if;

  select count(*) into v_n from (
    select s.national_dex_number
      from public.pokemon_species_text st join public.pokemon_species s on s.id = st.pokemon_species_id
     where st.origin = 'MMKYU_EDITORIAL'
     group by s.national_dex_number
    having count(*) filter (where st.text_kind = 'GENUS') = 1 and count(*) filter (where st.text_kind = 'FLAVOR') = 1
  ) ok;
  if v_n <> ${totalSpecies} then raise exception '${v} FAIL: % espécies com GENUS + FLAVOR editoriais, esperado ${totalSpecies}', v_n; end if;

  -- 3. Conteúdo do lote
  select count(*) into v_n
    from (values
${lotMd5Values}
    ) e(national_dex_number, text_kind, content_md5)
    join public.pokemon_species s on s.national_dex_number = e.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = e.text_kind
     and st.origin = 'MMKYU_EDITORIAL' and st.language_code = 'pt-BR'
   where st.id is null or md5(st.content) <> e.content_md5;
  if v_n <> 0 then raise exception '${v} FAIL: % textos do lote divergentes do aprovado', v_n; end if;

  -- 4. Preservação dos publicados antes
  select count(*) into v_n
    from (values
${pubValues}
    ) e(national_dex_number, text_kind, content_md5)
    join public.pokemon_species s on s.national_dex_number = e.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = e.text_kind
     and st.origin = 'MMKYU_EDITORIAL' and st.language_code = 'pt-BR'
   where st.id is null or md5(st.content) <> e.content_md5;
  if v_n <> 0 then raise exception '${v} FAIL: % registros publicados antes foram alterados', v_n; end if;

  -- 5. Textos oficiais preservados
  select count(*), ${srcExpr}
    into v_n, v_md5
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_n <> v_source_baseline_count or v_md5 <> v_source_baseline_md5 then
    raise exception '${v} FAIL: textos oficiais alterados (% linhas, hash %)', v_n, v_md5;
  end if;

  -- 6. Leitura da ficha (sessão autenticada simulada; nada é gravado)
  select id into v_user from auth.users order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  select * into v_r from public.get_pokedex_species_detail(${sample.national_dex_number}, 'pt-BR');
  if v_r.description_language <> 'pt-BR' or v_r.description_is_official
     or v_r.genus_language <> 'pt-BR' or v_r.genus_is_official or v_r.genus <> ${dollar(sample.genus)} then
    raise exception '${v} FAIL: ficha pt-BR de #${sample.national_dex_number} não devolve o editorial do lote';
  end if;
  select * into v_r from public.get_pokedex_species_detail(${sample.national_dex_number}, 'en');
  if v_r.description_language <> 'en' or not v_r.description_is_official or v_r.description_source_version is null then
    raise exception '${v} FAIL: leitura en de #${sample.national_dex_number} não devolve o texto oficial com versão';
  end if;
  select * into v_r from public.get_pokedex_species_detail(${pubNums[0]}, 'pt-BR');
  if v_r.description_language <> 'pt-BR' or v_r.description_is_official then
    raise exception '${v} FAIL: espécie já publicada #${pubNums[0]} deixou de devolver o editorial';
  end if;
  select * into v_r from public.get_pokedex_species_detail(2, 'pt-BR');
  if v_r.description_language <> 'en' or not v_r.description_is_official then
    raise exception '${v} FAIL: espécie fora dos lotes (#2) deixou de mostrar o oficial en';
  end if;

  raise notice '${v} PASS (editorial: ${totalRows} linhas / ${totalSpecies} espécies; lote: ${nLotRows} / ${nLot}; publicados preservados: ${nPubRows}; SOURCE: % linhas preservadas)', v_source_baseline_count;
end
$val$;

rollback;
`;

  if (lotNums.includes(2) || pubNums.includes(2)) throw new Error("#2 usado como controle fora dos lotes, mas está no lote");
  return { seed, validation };
}

function parseArgs(argv: string[]) {
  const a = { lot: "", published: [] as string[], snapshot: "", seedQuery: "", validationQuery: "", outDir: "", tag: "" };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const val = argv[++i] ?? "";
    if (k === "--lot") a.lot = val;
    else if (k === "--published") a.published.push(val);
    else if (k === "--snapshot") a.snapshot = val;
    else if (k === "--seed-query") a.seedQuery = val;
    else if (k === "--validation-query") a.validationQuery = val;
    else if (k === "--out-dir") a.outDir = val;
    else if (k === "--tag") a.tag = val;
    else throw new Error(`argumento desconhecido: ${k}`);
  }
  for (const [k, v] of Object.entries(a)) if (!v || (Array.isArray(v) && !v.length)) throw new Error(`informe --${k}`);
  if (!/^[a-z0-9_]+$/.test(a.tag)) throw new Error("--tag deve ser [a-z0-9_]");
  return a;
}

function main(): number {
  const a = parseArgs(process.argv.slice(2));
  const lotRaw = readFileSync(a.lot, "utf8");
  const published = a.published.map((p) => {
    const raw = readFileSync(p, "utf8");
    return { path: p.replace(/\\/g, "/"), sha256: sha256(raw), data: JSON.parse(raw) as PublishedLot };
  });
  const snapshot = loadJson<{ species: SnapshotSpecies[] }>(a.snapshot).species;
  const { seed, validation } = generate({
    lot: JSON.parse(lotRaw) as Lot,
    lotSha256: sha256(lotRaw),
    published,
    snapshot,
    seedQuery: a.seedQuery,
    validationQuery: a.validationQuery,
    tag: a.tag,
  });
  const slug = a.tag.replace(/^p3e_/, "");
  const seedPath = join(a.outDir, `${a.seedQuery}_publish_pokedex_editorial_ptbr_${slug}.sql`);
  const valPath = join(a.outDir, `${a.validationQuery}_validate_pokedex_editorial_ptbr_${slug}.sql`);
  writeFileSync(seedPath, seed, "utf8");
  writeFileSync(valPath, validation, "utf8");
  console.log(`${seedPath}  sha256 ${sha256(seed)}`);
  console.log(`${valPath}  sha256 ${sha256(validation)}`);
  return 0;
}

const isMain = (() => {
  const meta = import.meta as unknown as { main?: boolean; url: string };
  if (typeof meta.main === "boolean") return meta.main;
  const entry = process.argv[1];
  return !!entry && meta.url.endsWith(entry.replace(/\\/g, "/").split("/").pop() ?? "\u0000");
})();

if (isMain) {
  try {
    process.exitCode = main();
  } catch (e) {
    console.error(`ERRO  ${(e as Error).message}`);
    process.exitCode = 2;
  }
}

export { md5 };
