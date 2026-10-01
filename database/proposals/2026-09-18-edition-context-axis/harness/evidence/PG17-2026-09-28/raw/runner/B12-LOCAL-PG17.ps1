<#
============================================================================
 B12 LOCAL PG17 — ambiente isolado para P9B-M1/M2/M3, E12 e E13
============================================================================
 Uso (PowerShell 5.1 ou 7), a partir desta pasta:
   .\B12-LOCAL-PG17.ps1 -Step SelfTest    # 0. contraprovas locais (aliases, hashes, exceção ⇒ sem PASS)
   .\B12-LOCAL-PG17.ps1 -Step Diagnose    # 1. máquina: Docker, imagem, porta, disco, HEAD, MD5
   .\B12-LOCAL-PG17.ps1 -Step Setup       # 2. container PG17 isolado (127.0.0.1, volume próprio)
   .\B12-LOCAL-PG17.ps1 -Step RestoreSelfTest   # 2b. contraprova dump/restore com RLS+triggers na imagem (sem LIVE)
   .\B12-LOCAL-PG17.ps1 -Step NewRoCredential   #     senha local (DPAPI) + verificador SCRAM
   .\B12-LOCAL-PG17.ps1 -Step ScramLocalProof   #     verificador aceito no PG17 local; reset garantido
   .\B12-LOCAL-PG17.ps1 -Step ProbeLiveRo -LiveHost <pooler> -LiveUser b12_export_ro.<ref> -LiveFpRef <LiveFpRefExport>
   .\B12-LOCAL-PG17.ps1 -Step Extract -LiveHost <pooler> -LiveUser b12_export_ro.<ref> -LiveFpRef <LiveFpRefExport>  # 3. LIVE SOMENTE LEITURA
   .\B12-LOCAL-PG17.ps1 -Step Load        # 4. restauração local + ajustes de paridade do planner
   .\B12-LOCAL-PG17.ps1 -Step RestoreProof      # 4b. RLS/políticas/triggers nos dados reais restaurados
   .\B12-LOCAL-PG17.ps1 -Step Parity -LiveFpRef <LiveFpRefExport>  # 5. gates P1..P8 (STOP se qualquer um falhar)
   .\B12-LOCAL-PG17.ps1 -Step P9B         # 6. somente M1..M3 (prefixo byte a byte do P9B publicado; M4 fora desta fase)
   .\B12-LOCAL-PG17.ps1 -Step Envelopes   # 7. rodadas locais E12 e E13 (E00→pre→envelope→E99[/E98])
   .\B12-LOCAL-PG17.ps1 -Step Cleanup     # 8. remove container, volume, dump, cópias e senha local
 Cada etapa grava evidência em $WorkDir\out e para (throw "STOP: ...") no primeiro gate falso.

 Garantias
   * Porta só em 127.0.0.1. Senha do container é LOCAL (gerada aqui). Nenhuma
     credencial do LIVE entra no container persistente.
   * Senha do LIVE: pedida só em -Step Extract (Read-Host -AsSecureString) e
     entregue por STDIN a um container efêmero (--rm, --log-driver none), que a
     grava num pgpass em tmpfs (/secret, 0700) — nunca em argv, -e/inspect,
     arquivo persistente ou log (ver extract_live_ro.sh). Host/usuário (não
     secretos) via -LiveHost/-LiveUser. Sessão provada READ ONLY (RO1) antes de
     qualquer leitura; pg_dump usa transação READ ONLY própria. Nenhuma escrita,
     DDL ou envelope no LIVE.
   * SQL publicado não é alterado: cópia byte a byte com MD5 conferido no host e
     dentro do container. E99/E98 recebem só a substituição contratual dos
     marcadores entre aspas, em CÓPIA local (sql\run).
   * Comandos do container são gravados como scripts .sh (LF, UTF-8 sem BOM) e
     executados com `sh arquivo` — sem aspas aninhadas em argumentos nativos e sem
     SQL atravessando pipes do PowerShell.
============================================================================
#>
[CmdletBinding()]
param(
    [ValidateSet('SelfTest','Diagnose','Setup','RestoreSelfTest','NewRoCredential','ScramLocalProof','FpVisibilityProof','RenderS2','ProbeLiveRo','Extract','Load','LoadAudit','RestoreProof','CkProof','CkRepair','Parity','P9B','Envelopes','Cleanup')]
    [string]$Step = 'Diagnose',
    [string]$WorkDir = 'C:\b12-pg17',
    [string]$Image = 'supabase/postgres:17.6.1.147',
    [int]$Port = 55432,
    [string]$Cpus = '2',
    [string]$Memory = '2g',
    [int]$MinFreeGB = 10,
    # Conexão do LIVE — só não-segredos por parâmetro; a senha é pedida em Extract (SecureString → stdin)
    [string]$LiveHost,                       # ex.: aws-0-sa-east-1.pooler.supabase.com (Session pooler)
    [int]$LivePort = 5432,
    [string]$LiveUser,                       # ex.: b12_export_ro.qjfutqujxrbzgrtkpgkg (Session pooler)
    [string]$ExpectRole = 'b12_export_ro',   # papel que a sessão DEVE ser (RO3); nunca postgres
    # referência de paridade do LIVE; com as políticas b12_export_ro_select ativas, usar o
    # LiveFpRefExport medido como postgres na §2b de B12-EXPORT-RO-ROLE.sql (ProbeLiveRo recusa o padrão)
    [string]$LiveFpRef = 'a8a1efb3645f3b1233f07500382b76af',
    [string]$LiveDb = 'postgres',
    [switch]$RotateCredential,               # NewRoCredential: substituir credencial local existente
    [switch]$NoSessionReadOnly               # só se o pooler rejeitar PGOPTIONS; RO por transação continua obrigatório
)
# 'Stop': qualquer exceção interrompe a etapa (nenhum PASS depois de erro). Chamadas nativas cujo
# stderr precisa ser descartado passam por Invoke-NativeQuiet (EAP local 'Continue', rc explícito).
$ErrorActionPreference = 'Stop'
$Container    = 'b12-pg17'
$Volume       = 'b12-pg17-data'
$Harness      = Split-Path -Parent $PSScriptRoot
$Repo         = (Resolve-Path (Join-Path $Harness '..\..\..\..')).Path
$ExpectedHead = 'ded269f7fd16be0aeaf074c9d4f6612d724e0f2f'
$Utf8NoBom    = New-Object System.Text.UTF8Encoding($false)

$Pinned = [ordered]@{
    '2830H_E00_precheck_inventory.sql'          = '45b6c35cca849ffbf49d22ec18e8283c'
    '2830H_E12P_precheck_section_b.sql'         = '79a647ec2f03e3a94f09f2e2e07f5c9a'
    '2830H_E12_section_b_backfill_semantic.sql' = '232b857087aa63732a7be5ade55108f8'
    '2830H_E13P_precheck_section_m.sql'         = '50b5c1227b69f59f417b68bd42eb0a6f'
    '2830H_E13_section_m_state_machine.sql'     = '5907e85df7fbe9545e97c4584b446827'
    '2830H_E99_postcheck_residue.sql'           = 'f0b91183a8649b990b080637dd56e74b'
    '2830H_E98_postcheck_extended_residue.sql'  = '094d1bc4db7d6abee6f91f6a236ab708'
    '2830H_P9B_isolated_timing.sql'             = '6df4f0cd18daee39b67ea27e996121f5'
    'local-pg17\parity_fingerprint.sql'         = 'bc11f919941e449381a1000d5730c217'
    'local-pg17\extract_live_ro.sh'             = '688cf5a8cca9d4e38a8ab96ec07ad3b1'
    'local-pg17\export_ro_probe.sql'            = 'ed4f674ce5c7755c5eaa764fbf5adf1f'
}
# Referência SEM as políticas b12 (antes da ativação) e sessão fixada do fingerprint (idêntica à §2b)
$LiveFpRefPreRole = 'a8a1efb3645f3b1233f07500382b76af'   # search_path='' (medido 2026-09-28, papel revogado)
$PinnedSearchPath = '""'   # SET search_path = '' → current_setting devolve "" (caminho efetivo {} para qualquer papel)
# P9B nesta fase: SOMENTE M1/M2/M3 = prefixo byte a byte do arquivo publicado (linhas 1–171).
# M4 (DERIV-5X, E15) começa na linha 172 e lê pricing_* — fora do inventário; não é executado.
$P9BSliceLines = 171
$P9BSliceMd5   = '9da8bd45ce76adc1bcbca0922ccea8f3'
# ADAPTAÇÃO LOCAL de controles (réplica de escopo reduzido; o SQL canônico NÃO muda).
# public.catalog_admin_action_log não é exportada (fora das 22). E00 e E99 a leem SOMENTE na chave
# 'action_log' do BASELINE-BUILDER (controle de resíduo por contagem; sem valor no FREEZE-CANON; não
# alimenta nenhum gate do E00). A cópia local remove EXATAMENTE essa linha, na posição conhecida, dos
# dois arquivos (mesmo padrão do recorte P9B: derivação byte a byte + md5 pinado). Nenhum valor é
# inventado: a chave some dos dois lados e o controle é declarado NOT_EXECUTED_LOCAL no resultado.
$LocalAdaptLine = "        'action_log',             (SELECT count(*) FROM public.catalog_admin_action_log),"
$LocalAdapt = [ordered]@{
    'L_E00_precheck_inventory.sql' = @{ src = '2830H_E00_precheck_inventory.sql'; line = 447; md5 = '8539badcf7a637e59948858538dfcca7' }
    'L_E99_postcheck_residue.sql'  = @{ src = '2830H_E99_postcheck_residue.sql';  line = 103; md5 = '4fbb939b2b805ef3007f83afda1cbbe4' }
}
$NotReplicated = @(
    [ordered]@{ control = 'd_baseline.action_log (E00) / g_baseline_equal[action_log] (E99)'
                relation = 'public.catalog_admin_action_log'; status = 'NOT_EXECUTED_LOCAL'
                reason = 'relação fora do export (22 tabelas); sem snapshot nem valor canônico que fixe o estado esperado'
                coverage = 'nenhuma função do fecho (37) nem E12/E13/E12P/E13P/E98/P9B M1–M3 a referencia; verificação real só nas rodadas LIVE com o E00/E99 canônicos' }
)
# CHECK com lista IN sobre coluna varchar: o PostgreSQL grava ArrayCoerceExpr(varchar[]→text[]) e o
# pg_get_constraintdef rende "(ARRAY['x'::character varying, …])::text[]". Ao RECARREGAR esse texto (o
# que o pg_dump/restore faz), o parser empurra o cast para cada elemento e a definição passa a
# "ARRAY[('x'::character varying)::text, …]" — mesma regra, outra árvore/renderização. Pinos: definição
# LIVE (lida em 2026-09-28, search_path='' e UTC, somente leitura) e definição local observada (md5
# do P3 confirmado por pré-imagem). CkProof demonstra; CkRepair (explícito) recria na forma LIVE.
$CkPairs = @(
    [ordered]@{ rel = 'card_printing_external_mapping'; con = 'ck_card_printing_external_mapping_raw_field'; col = 'raw_field'
                vals = @('subtype','stamp')
                live_def  = "CHECK (((raw_field)::text = ANY ((ARRAY['subtype'::character varying, 'stamp'::character varying])::text[])))"
                live_md5  = '8ebcee645389f5c2246671ecc6387ef9'
                local_def = "CHECK (((raw_field)::text = ANY (ARRAY[('subtype'::character varying)::text, ('stamp'::character varying)::text])))"
                local_md5 = '4ccbe66702383269da3366ec970756b6' }
    [ordered]@{ rel = 'card_set'; con = 'ck_card_set_type'; col = 'set_type'
                vals = @('REGULAR','SPECIAL','PROMO','ENERGY')
                live_def  = "CHECK (((set_type)::text = ANY ((ARRAY['REGULAR'::character varying, 'SPECIAL'::character varying, 'PROMO'::character varying, 'ENERGY'::character varying])::text[])))"
                live_md5  = '2b548c67bd0ba97cdbc58c3d7761b261'
                local_def = "CHECK (((set_type)::text = ANY (ARRAY[('REGULAR'::character varying)::text, ('SPECIAL'::character varying)::text, ('PROMO'::character varying)::text, ('ENERGY'::character varying)::text])))"
                local_md5 = '544de5d9acc63a3c2570ea1cb57437c9' }
)
# Esquemas cujas referências qualificadas o preflight de dependências resolve na réplica
$DepSchemas = 'public|internal|extensions|auth|storage|vault|cron|net|graphql|graphql_public|pgmq|realtime|supabase_functions'

# ---- CRITÉRIOS DE PARIDADE (fixados antes da extração) -------------------------------
# BLOQUEANTE (qualquer diferença = STOP, tempos não representativos):
#   P1 server_version igual (17.6) · P2 LIVE sem deriva vs referência $LiveFpRef
#   P3 d_fp_core idêntico: funções do fecho (md5 do corpo LF, linguagem, volatilidade,
#      SECURITY DEFINER, proconfig, tipo de retorno), colunas/tipos/defaults/NOT NULL,
#      índices (definição completa), constraints (tipo, deferrable, definição), triggers
#      (definição + enabled), dono/RLS/FORCE, policies, conteúdo linha a linha e contagem
#      das 22 tabelas, distribuições job×row×decisão, chave EC por op, universos M1/M2/M3
#   P4 planner: timezone, search_path, work_mem, random_page_cost, effective_cache_size,
#      jit, max_parallel_workers_per_gather, shared_buffers
#   P5 E12P/E13P gate_pass=true · P6 E00 local sem gate falso fora da lista ambiental
#   P7 erro de restauração que cite objeto do escopo (tabela, função do fecho, schema internal)
#      E LoadAudit reprovado/ausente (erro de schema não explicado pelo plano de carga = STOP)
#   E00/E99 locais = L_E00/L_E99 (canônico − 1 linha 'action_log'; ver $LocalAdapt). Antes de executar
#   qualquer controle, Test-SqlDependencies resolve toda referência qualificada na réplica (STOP
#   específico se faltar). parity_result.classification separa: equivalência do escopo exportado ·
#   ambiental/não reproduzível (NOT_EXECUTED_LOCAL declarado) · bloqueio real de integridade.
# AMBIENTAL (registrado, não bloqueia): arquitetura/compilação (aarch64 × x86_64), CPU/RAM,
#   estatísticas físicas (relpages/reltuples/dead tuples/OIDs), objetos FORA do escopo que
#   falhem na restauração, extensões fora do escopo (pg_cron/pg_net/vault/graphql),
#   lock_timeout/statement_timeout da sessão de extração (PGOPTIONS), contagem de
#   catalog_admin_action_log (não carregada; fora do canon), pg_db_role_setting (E99 compara
#   local×local), checked_at/pid/current_user. Único gate do E00 admitido como ambiental:
#   g_evt_all_adjudicated (identidade dos event triggers da imagem; envelopes não emitem DDL).
$ParityEnvKeys   = @('timezone','search_path','work_mem','random_page_cost','effective_cache_size','jit','max_parallel_workers_per_gather','shared_buffers')
$E00EnvGatesOnly = @('g_evt_all_adjudicated')
# Inventário exato de dados: tabelas lidas pelo fecho de funções do escopo
# (2211/2176/2192/axis_identity_token/guard 2214 + triggers) e fecho de FK.
# Fora de propósito: auth.* (só stub de id), pricing_* (M4/E15), action logs, coleções, usuários.
$DataTables = @(
    'game','asset_source','expansion','card_set','card_set_external_reference',
    'card_category','rarity','card','card_variant_type',
    'card_printing_trait','card_printing_profile','card_printing_profile_trait',
    'card_printing_external_mapping','card_printing_external_mapping_trait',
    'card_edition_context_trait','card_edition_context_profile','card_edition_context_profile_trait',
    'card_edition_context_external_mapping','card_edition_context_external_mapping_trait',
    'card_variant','catalog_variant_import_job','catalog_variant_import_row'
)
$Envelopes = [ordered]@{
    E12 = @{ file='2830H_E12_section_b_backfill_semantic.sql'; pre='2830H_E12P_precheck_section_b.sql'; n=14; ctx=712; e98=$false }
    E13 = @{ file='2830H_E13_section_m_state_machine.sql';     pre='2830H_E13P_precheck_section_m.sql'; n=11; ctx=960; e98=$true  }
}

function Say($m)  { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) }
function Fail($m) { throw "STOP: $m" }
function Write-WorkText([string]$rel, [string]$text) { [IO.File]::WriteAllText((Join-Path $WorkDir $rel), ($text -replace "`r`n", "`n"), $Utf8NoBom) }
function Read-WorkText([string]$rel) { return [IO.File]::ReadAllText((Join-Path $WorkDir $rel), $Utf8NoBom) }
function Md5File([string]$p) { return (Get-FileHash -Algorithm MD5 -LiteralPath $p).Hash.ToLower() }
function Dirs { foreach ($d in 'sql','sql\run','dump','out','secrets') { New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir $d) | Out-Null } }
function LocalPw {
    $f = Join-Path $WorkDir 'secrets\local_pw.txt'
    if (-not (Test-Path $f)) {
        $b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
        [IO.File]::WriteAllText($f, ([Convert]::ToBase64String($b) -replace '[+/=]','x'), $Utf8NoBom)
    }
    return ([IO.File]::ReadAllText($f)).Trim()
}
# Chamada nativa com stderr descartado sem virar exceção (EAP local); devolve rc e stdout.
function Invoke-NativeQuiet([scriptblock]$Block) {
    # stdout e stderr capturados SEPARADAMENTE (stderr não é mais descartado: diagnóstico de falha real)
    $ErrorActionPreference = 'Continue'
    $all = @(& $Block 2>&1)
    $rc  = $LASTEXITCODE
    $err = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() })
    $std = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    return [pscustomobject]@{ rc = $rc; out = ($std -join "`n").Trim(); err = ($err -join "`n").Trim() }
}
# Valida a configuração de um container existente a partir do JSON de `docker container inspect`
# (sem --format/template Go: nada de chaves, espaços ou aspas passando pela linha de comando nativa).
function Assert-ContainerConfig([string]$json) {
    # PS 5.1 devolve o array JSON como UM objeto; o ForEach-Object o desenrola (PS 7 já desenrola)
    try { $items = @($json | ConvertFrom-Json | ForEach-Object { $_ }) } catch { Fail "docker inspect: JSON ilegível ($($_.Exception.Message))" }
    if ($items.Count -ne 1) { Fail "docker inspect: esperado 1 container, obtidos $($items.Count)" }
    $c = $items[0]
    if ($null -eq $c -or $null -eq $c.Config -or $null -eq $c.State -or $null -eq $c.HostConfig) { Fail 'docker inspect: JSON sem Config/State/HostConfig' }
    if (@('running','exited','created') -notcontains "$($c.State.Status)") { Fail "estado do container existente não reaproveitável: $($c.State.Status)" }
    if ($c.Config.Image -ne $Image) { Fail "container existente usa outra imagem ($($c.Config.Image)) — Cleanup explícito necessário" }
    $pb = $c.HostConfig.PortBindings
    $keys = @(); if ($pb) { $keys = @($pb.PSObject.Properties.Name) }
    if ($keys.Count -ne 1 -or $keys[0] -ne '5432/tcp') { Fail "portas publicadas do container existente diferem ($($keys -join ','))" }
    $b = @($pb.'5432/tcp')
    if ($b.Count -ne 1 -or $b[0].HostIp -ne '127.0.0.1' -or "$($b[0].HostPort)" -ne "$Port") {
        Fail "binding do container existente difere ($(@($b | ForEach-Object { "$($_.HostIp):$($_.HostPort)" }) -join ','); esperado 127.0.0.1:$Port)" }
    $m = @($c.Mounts)
    if (@($m | Where-Object { $_.Type -eq 'volume' -and $_.Name -eq $Volume -and $_.Destination -eq '/var/lib/postgresql/data' }).Count -ne 1) {
        Fail "volume $Volume não montado em /var/lib/postgresql/data no container existente" }
    if (@($m | Where-Object { $_.Type -eq 'bind' -and $_.Destination -eq '/work' }).Count -ne 1) {
        Fail 'bind /work ausente no container existente' }
    return "$($c.State.Status)"
}
# Arquivos esperados em /work/sql (nome -> md5): artefatos pinados + recorte P9B.
function Get-ExpectedContainerHashes {
    $h = @{}
    foreach ($k in $Pinned.Keys) { $h[(Split-Path $k -Leaf)] = $Pinned[$k] }
    $h['P9B_M1_M3.sql'] = $P9BSliceMd5
    foreach ($k in $LocalAdapt.Keys) { $h[$k] = $LocalAdapt[$k].md5 }
    return $h
}
# Deriva as cópias locais L_E00/L_E99 dos canônicos JÁ conferidos em sql\ (fail-closed em qualquer desvio).
function Build-LocalControls {
    foreach ($k in $LocalAdapt.Keys) {
        $a = $LocalAdapt[$k]; $srcPath = Join-Path $WorkDir ('sql\' + $a.src)
        if ((Md5File $srcPath) -ne $Pinned[$a.src]) { Fail "canônico $($a.src) divergente do pino — rodar -Step Setup" }
        $lines = [IO.File]::ReadAllText($srcPath, $Utf8NoBom) -split "`n", 0
        $hits = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -ceq $LocalAdaptLine) { $i + 1 } })
        if ($hits.Count -ne 1 -or $hits[0] -ne $a.line) { Fail "adaptação local de $($a.src): linha action_log esperada 1x na linha $($a.line), encontrada em [$($hits -join ',')]" }
        $out = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($i -ne $a.line - 1) { $lines[$i] } }) -join "`n"
        $dst = Join-Path $WorkDir ('sql\' + $k)
        [IO.File]::WriteAllText($dst, $out, $Utf8NoBom)
        if ((Md5File $dst) -ne $a.md5) { Fail "md5 da cópia local $k divergente do pino" }
    }
    # os blocos compartilhados continuam byte a byte idênticos entre as duas cópias locais
    $blk = { param($f, $tag) $t = Read-WorkText ('sql\' + $f); $m = [regex]::Match($t, "(?s)-- $tag`:BEGIN.*?-- $tag`:END"); if (-not $m.Success) { Fail "bloco $tag ausente em $f" }; $m.Value }
    foreach ($tag in 'BASELINE-BUILDER','FREEZE-CANON') {
        if ((& $blk 'L_E00_precheck_inventory.sql' $tag) -cne (& $blk 'L_E99_postcheck_residue.sql' $tag)) { Fail "bloco $tag difere entre L_E00 e L_E99" }
    }
}
# PREFLIGHT DE DEPENDÊNCIAS (antes de executar qualquer controle na réplica): toda referência
# qualificada schema.objeto (fora de comentários, literais e dos padrões $re$) precisa existir como
# relação, tipo ou função. Canônicos (diagnóstico) × executados (gate): os ausentes dos executados
# ⇒ STOP com arquivo:linha:objeto; ausente no canônico que a adaptação local não cobre ⇒ STOP.
function Get-SqlRefs([string]$file) {
    $t = Read-WorkText ('sql\' + $file)
    $lex = '--[^\n]*|/\*[\s\S]*?\*/|\$re\$[\s\S]*?\$re\$|''(?:[^'']|'''')*'''
    $t = [regex]::Replace($t, $lex, { param($m) ($m.Value -replace '[^\n]', '') })
    $rx = '(?<![A-Za-z0-9_."$])(' + $DepSchemas + ')\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)(\()?'
    $refs = @()
    foreach ($m in [regex]::Matches($t, $rx)) {
        $line = ($t.Substring(0, $m.Index) -split "`n").Count
        $refs += [pscustomobject]@{ file = $file; line = $line; ref = "$($m.Groups[1].Value).$($m.Groups[2].Value)"; kind = $(if ($m.Groups[3].Success) { 'FN' } else { 'REL' }) }
    }
    return $refs
}
function Test-SqlDependencies([string]$tag, [string[]]$gated, [string[]]$diagnostic) {
    $all = @(); foreach ($f in @($gated) + @($diagnostic)) { $all += Get-SqlRefs $f }
    $distinct = @($all | ForEach-Object { $_.ref } | Sort-Object -Unique)
    $vals = ($distinct | ForEach-Object { "('" + $_ + "')" }) -join ','
    Write-WorkText "sql\run\deps_$tag.sql" @"
SELECT COALESCE(jsonb_agg(r ORDER BY r), '[]'::jsonb) FROM (VALUES $vals) v(r)
 WHERE to_regclass(r) IS NULL AND to_regtype(r) IS NULL
   AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = lower(split_part(r, '.', 1)) AND p.proname = lower(split_part(r, '.', 2)));
"@
    if (InC "deps_$tag" "`$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/run/deps_$tag.sql -o /work/out/deps_${tag}_missing.json || exit 1") { Fail "preflight de dependências ($tag) não executou" }
    $missing = @((JsonOut "out\deps_${tag}_missing.json") | ForEach-Object { $_ })
    $hit = { param($files) @($all | Where-Object { $files -contains $_.file -and $missing -contains $_.ref } | ForEach-Object { "$($_.file):$($_.line):$($_.ref)" }) }
    $gatedMissing = & $hit $gated
    $diagMissing  = & $hit $diagnostic
    # todo ausente num canônico precisa ser exatamente uma linha removida pela adaptação local
    $covered = @($LocalAdapt.Keys | ForEach-Object { "$($LocalAdapt[$_].src):$($LocalAdapt[$_].line):public.catalog_admin_action_log" })
    $uncovered = @($diagMissing | Where-Object { $covered -notcontains $_ })
    $res = [ordered]@{ tag = $tag; refs_checked = $distinct.Count; missing_in_executed = $gatedMissing
                       canonical_external_dependencies = $diagMissing; canonical_uncovered = $uncovered
                       pass = ($gatedMissing.Count -eq 0 -and $uncovered.Count -eq 0) }
    Write-WorkText "out\deps_$tag.json" ($res | ConvertTo-Json -Depth 5)
    if ($gatedMissing.Count) { Fail ("dependência ausente na réplica ANTES de executar ($tag): " + ($gatedMissing -join '; ') + ' — objeto fora do export; exige adaptação local declarada ou ampliação do escopo, não execução') }
    if ($uncovered.Count)    { Fail ("canônico com dependência externa não coberta pela adaptação local ($tag): " + ($uncovered -join '; ')) }
    Say "DEPS ${tag}: $($distinct.Count) referências resolvidas; externas do canônico cobertas: $($diagMissing -join ', ')"
    return $res
}
# Validação FAIL-CLOSED de saída md5sum: arquivo ausente/vazio, linha malformada, nome duplicado,
# ausente ou excedente, ou hash divergente => Fail. Devolve a quantidade conferida.
function Assert-HashFile([string]$path, [hashtable]$expected) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "arquivo de hashes ausente: $path" }
    $lines = @([IO.File]::ReadAllText($path, $Utf8NoBom) -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne '' })
    if ($lines.Count -eq 0) { Fail "arquivo de hashes vazio: $path" }
    $seen = @{}
    foreach ($l in $lines) {
        if ($l -notmatch '^([0-9a-f]{32}) [ *]([^\s/]+)$') { Fail "linha de hash malformada: '$l'" }
        $h = $Matches[1]; $name = $Matches[2]
        if ($seen.ContainsKey($name)) { Fail "arquivo duplicado na lista de hashes: $name" }
        if (-not $expected.ContainsKey($name)) { Fail "arquivo inesperado na lista de hashes: $name" }
        if ($expected[$name] -ne $h) { Fail "md5 divergente: $name ($h <> $($expected[$name]))" }
        $seen[$name] = $h
    }
    $missing = @($expected.Keys | Where-Object { -not $seen.ContainsKey($_) })
    if ($missing.Count) { Fail "arquivo(s) ausente(s) na lista de hashes: $($missing -join ', ')" }
    return $seen.Count
}
# Executa um script sh (texto) dentro do container persistente. PSQL_A/PSQL_P = atalhos de conexão local.
function InC([string]$name, [string]$body) {
    $hdr = "set -u`nPSQL_A='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d postgres'`nPSQL_P='psql -X -h 127.0.0.1 -p 5432 -U postgres -d postgres'`n"
    Write-WorkText "sql\run\$name.sh" ($hdr + $body + "`n")
    & docker exec -e "PGPASSWORD=$(LocalPw)" $Container sh "/work/sql/run/$name.sh" | Out-Host
    return $LASTEXITCODE
}
function WaitReady {
    for ($i = 0; $i -lt 90; $i++) {
        if ((Invoke-NativeQuiet { docker exec $Container pg_isready -h 127.0.0.1 -p 5432 }).rc -eq 0) { Start-Sleep 3; return }
        Start-Sleep 2
    }
    Fail 'container não ficou pronto em 180 s'
}
function JsonOut([string]$rel) { return ((Read-WorkText $rel).Trim() | ConvertFrom-Json) }

# ---------------------------------------------------------------- 0. SELFTEST (sem Docker, sem LIVE)
function Step-SelfTest {
    $res = [ordered]@{}; $ok = $true
    # (0) sintaxe integral do próprio arquivo pelo parser nativo: qualquer ParseError ⇒ SELFTEST reprovado
    $tok = $null; $perr = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tok, [ref]$perr)
    $res.parser_errors = @($perr | ForEach-Object { "L$($_.Extent.StartLineNumber):$($_.ErrorId): $($_.Message)" })
    $res.script_md5 = (Md5File $PSCommandPath)
    if (@($perr).Count -ne 0) { $ok = $false }
    # (a) nenhuma função deste script colide com alias (alias tem precedência: 'r' = Invoke-History)
    $mine = @(Get-Command -CommandType Function | Where-Object { $_.ScriptBlock.File -eq $PSCommandPath } | ForEach-Object { $_.Name })
    $coll = @($mine | Where-Object { Get-Alias -Name $_ -ErrorAction SilentlyContinue })
    $res.functions = $mine.Count; $res.alias_collisions = $coll; if ($coll.Count) { $ok = $false }
    foreach ($fn in 'Read-WorkText','Write-WorkText','Assert-HashFile','Assert-ContainerConfig','Invoke-NativeQuiet') {
        if ((Get-Command $fn).CommandType -ne 'Function') { $ok = $false; $res["resolve_$fn"] = 'NOT_FUNCTION' }
    }
    # (b) contraprovas do verificador de hashes (arquivos sintéticos em out\selftest)
    $d = Join-Path $WorkDir 'out\selftest'; New-Item -ItemType Directory -Force -Path $d | Out-Null
    $exp = @{ 'a.sql' = ('0' * 32); 'b.sh' = ('1' * 32) }
    $cases = [ordered]@{
        'T1_ausente'      = @{ content = $null;                                                           expect = 'FAIL' }
        'T2_vazio'        = @{ content = '';                                                              expect = 'FAIL' }
        'T3_malformado'   = @{ content = "xyz  a.sql`n$('1'*32)  b.sh`n";                                 expect = 'FAIL' }
        'T4_faltando'     = @{ content = "$('0'*32)  a.sql`n";                                            expect = 'FAIL' }
        'T5_excedente'    = @{ content = "$('0'*32)  a.sql`n$('1'*32)  b.sh`n$('2'*32)  c.sql`n";         expect = 'FAIL' }
        'T6_hash_errado'  = @{ content = "$('0'*32)  a.sql`n$('9'*32)  b.sh`n";                           expect = 'FAIL' }
        'T7_duplicado'    = @{ content = "$('0'*32)  a.sql`n$('0'*32)  a.sql`n$('1'*32)  b.sh`n";         expect = 'FAIL' }
        'T8_valido'       = @{ content = "$('0'*32)  a.sql`n$('1'*32)  b.sh`n";                           expect = 'PASS' }
    }
    foreach ($name in $cases.Keys) {
        $f = Join-Path $d "$name.txt"; Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        if ($null -ne $cases[$name].content) { [IO.File]::WriteAllText($f, $cases[$name].content, $Utf8NoBom) }
        $got = 'FAIL'
        try { Assert-HashFile $f $exp | Out-Null; $got = 'PASS' } catch { $got = 'FAIL' }
        $res[$name] = "$got (esperado $($cases[$name].expect))"
        if ($got -ne $cases[$name].expect) { $ok = $false }
    }
    # (b2) contraprovas do validador de container (JSON no formato de `docker container inspect`)
    $base = '[{"Config":{"Image":"IMG"},"State":{"Status":"running"},"HostConfig":{"PortBindings":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"PORT"}]}},"Mounts":[{"Type":"volume","Name":"VOL","Source":"VOL","Destination":"/var/lib/postgresql/data"},{"Type":"bind","Source":"C:\\b12-pg17","Destination":"/work"}]}]'
    $okJson = $base.Replace('IMG', $Image).Replace('PORT', "$Port").Replace('VOL', $Volume)
    $ccases = [ordered]@{
        'C1_valido'        = @{ json = $okJson;                                           expect = 'PASS' }
        'C2_porta_publica' = @{ json = $okJson.Replace('"127.0.0.1"', '"0.0.0.0"');       expect = 'FAIL' }
        'C3_outra_imagem'  = @{ json = $okJson.Replace($Image, 'postgres:17');            expect = 'FAIL' }
        'C4_sem_volume'    = @{ json = $okJson.Replace('"volume"', '"tmpfs"');            expect = 'FAIL' }
        'C5_sem_bind_work' = @{ json = $okJson.Replace('"/work"', '"/outro"');            expect = 'FAIL' }
        'C6_json_invalido' = @{ json = '{nao json';                                       expect = 'FAIL' }
        'C7_estado_pausado'= @{ json = $okJson.Replace('"running"', '"paused"');          expect = 'FAIL' }
    }
    foreach ($name in $ccases.Keys) {
        $got = 'FAIL'
        try { Assert-ContainerConfig $ccases[$name].json | Out-Null; $got = 'PASS' } catch { $got = 'FAIL' }
        $res[$name] = "$got (esperado $($ccases[$name].expect))"
        if ($got -ne $ccases[$name].expect) { $ok = $false }
    }
    # (b3) o wrapper nativo devolve rc real e stderr (não é falso negativo)
    $nq = Invoke-NativeQuiet { cmd.exe /c "echo out& echo err 1>&2& exit /b 3" }
    $res.native_wrapper = "rc=$($nq.rc) out=$($nq.out) err=$($nq.err)"
    if ($nq.rc -ne 3 -or $nq.out -ne 'out' -or $nq.err -notlike '*err*') { $ok = $false }
    # (b4) SCRAM-SHA-256: vetor oficial RFC 7677 + formato do verificador PostgreSQL
    $res.scram_rfc7677 = (Test-ScramRfc7677); if (-not $res.scram_rfc7677) { $ok = $false }
    $v = New-ScramVerifier (New-RandomSecret 40)
    $res.scram_verifier_format = ($v -match '^SCRAM-SHA-256\$4096:[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=:[A-Za-z0-9+/]{43}=$')
    if (-not $res.scram_verifier_format) { $ok = $false }
    # (b5) ScramLocalProof: o reset NOLOGIN/PASSWORD NULL está num bloco finally que envolve o ALTER ROLE ... LOGIN
    #      (prova estrutural pelo AST do próprio script, sem Docker)
    $ast = (Get-Command Step-ScramLocalProof).ScriptBlock.Ast
    $tries = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.TryStatementAst] -and $n.Finally }, $true))
    $guard = @($tries | Where-Object { $_.Finally.Extent.Text -match "'scram_reset'" -and $_.Body.Extent.Text -match "'scram_set'" -and $_.Body.Extent.Text -match 'scram_probe\.sh' })
    $res.scram_reset_in_finally = ($guard.Count -eq 1); if (-not $res.scram_reset_in_finally) { $ok = $false }
    # (b6) semântica do finally sob exceção no PowerShell em uso (o reset roda e a exceção original prossegue)
    $ran = $false; $propagated = $false
    try { try { throw 'simulada' } finally { $ran = $true } } catch { $propagated = ($_.Exception.Message -eq 'simulada') }
    $res.finally_runs_on_exception = ($ran -and $propagated); if (-not $res.finally_runs_on_exception) { $ok = $false }
    # (c) exceção de cmdlet interrompe o bloco antes do "PASS" (EAP = Stop)
    $reached = $false
    try { Get-Item -LiteralPath (Join-Path $d 'nao_existe.xyz') | Out-Null; $reached = $true } catch { }
    $res.exception_blocks_pass = (-not $reached); if ($reached) { $ok = $false }
    $res | ConvertTo-Json | Tee-Object -FilePath (Join-Path $WorkDir 'out\selftest.json')
    if (-not $ok) { Fail 'SELFTEST reprovado (out\selftest.json)' }
    Say 'SELFTEST: PASS'
}


# ---- SCRAM-SHA-256 (RFC 5802/7677) — verificador no formato do PostgreSQL:
#      SCRAM-SHA-256$<iter>:<salt b64>$<StoredKey b64>:<ServerKey b64>
function Get-ScramKeys([byte[]]$pw, [byte[]]$salt, [int]$iter) {
    $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($pw, $salt, $iter, [Security.Cryptography.HashAlgorithmName]::SHA256)
    $salted = $kdf.GetBytes(32); $kdf.Dispose()
    $h = [Security.Cryptography.HMACSHA256]::new($salted)
    $clientKey = $h.ComputeHash([Text.Encoding]::ASCII.GetBytes('Client Key'))
    $serverKey = $h.ComputeHash([Text.Encoding]::ASCII.GetBytes('Server Key')); $h.Dispose()
    $sha = [Security.Cryptography.SHA256]::Create(); $storedKey = $sha.ComputeHash($clientKey); $sha.Dispose()
    [Array]::Clear($salted, 0, $salted.Length)
    return [pscustomobject]@{ ClientKey = $clientKey; StoredKey = $storedKey; ServerKey = $serverKey }
}
function New-ScramVerifier([Security.SecureString]$sec, [int]$iter = 4096) {
    $salt = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $pw = [Text.Encoding]::UTF8.GetBytes([Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    try { $k = Get-ScramKeys $pw $salt $iter } finally { [Array]::Clear($pw, 0, $pw.Length) }
    return ('SCRAM-SHA-256$' + $iter + ':' + [Convert]::ToBase64String($salt) + '$' +
            [Convert]::ToBase64String($k.StoredKey) + ':' + [Convert]::ToBase64String($k.ServerKey))
}
# Vetor de teste do RFC 7677 §3 (user/pencil): ClientProof e ServerSignature exatos.
function Test-ScramRfc7677 {
    $k = Get-ScramKeys ([Text.Encoding]::UTF8.GetBytes('pencil')) ([Convert]::FromBase64String('W22ZaJ0SNY7soEsUEjb6gQ==')) 4096
    $sn = 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0'
    $am = [Text.Encoding]::ASCII.GetBytes("n=user,r=rOprNGfwEbeRWgbNEkqO,r=$sn,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096,c=biws,r=$sn")
    $h1 = [Security.Cryptography.HMACSHA256]::new($k.StoredKey); $csig = $h1.ComputeHash($am)
    $proof = New-Object byte[] 32; for ($i = 0; $i -lt 32; $i++) { $proof[$i] = $k.ClientKey[$i] -bxor $csig[$i] }
    $h2 = [Security.Cryptography.HMACSHA256]::new($k.ServerKey); $ssig = $h2.ComputeHash($am)
    return ([Convert]::ToBase64String($proof) -eq 'dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=') -and
           ([Convert]::ToBase64String($ssig)  -eq '6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=')
}
# Senha aleatória ASCII alfanumérica (SASLprep = identidade), amostragem sem viés.
function New-RandomSecret([int]$len = 40) {
    $alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $sec = New-Object Security.SecureString; $b = New-Object byte[] 1
    while ($sec.Length -lt $len) { $rng.GetBytes($b); if ($b[0] -lt 248) { $sec.AppendChar($alpha[$b[0] % 62]) } }
    $sec.MakeReadOnly(); return $sec
}
$RoSecretFile   = 'secrets\b12_live_ro.dpapi'   # DPAPI (usuário atual do Windows); nunca texto claro
$RoVerifierFile = 'out\b12_live_ro.verifier'     # verificador SCRAM (não é a senha)
function Get-RoSecret {
    $f = Join-Path $WorkDir $RoSecretFile
    if (-not (Test-Path -LiteralPath $f)) { Fail 'credencial local ausente — rodar -Step NewRoCredential' }
    return (Get-Content -LiteralPath $f -Raw).Trim() | ConvertTo-SecureString
}
# Container efêmero de leitura do LIVE: senha SÓ por stdin → pgpass em tmpfs (extract_live_ro.sh).
function Invoke-LiveRoContainer([Security.SecureString]$sec, [bool]$probeOnly) {
    if (-not $LiveHost -or -not $LiveUser) { Fail 'informar -LiveHost e -LiveUser (Session pooler, usuário b12_export_ro.<ref>)' }
    $tArgs = @(); foreach ($x in $DataTables) { $tArgs += '-t'; $tArgs += "public.$x" }
    $noOpt = $(if ($NoSessionReadOnly) { '1' } else { '0' }); $po = $(if ($probeOnly) { '1' } else { '0' })
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec); $prevEnc = $OutputEncoding
    try {
        $OutputEncoding = $Utf8NoBom
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $plain | & docker run --rm -i --log-driver none `
            --tmpfs '/secret:rw,noexec,nosuid,size=1m,mode=0700' `
            -e "LIVE_HOST=$LiveHost" -e "LIVE_PORT=$LivePort" -e "LIVE_USER=$LiveUser" -e "LIVE_DB=$LiveDb" `
            -e "EXPECT_ROLE=$ExpectRole" -e "B12_NO_PGOPTIONS=$noOpt" -e "B12_PROBE_ONLY=$po" -v "${WorkDir}:/work" --entrypoint sh $Image `
            /work/sql/extract_live_ro.sh @tArgs | Out-Host
        $rc = $LASTEXITCODE
        $leak = @(Get-ChildItem -LiteralPath $WorkDir -Recurse -File | Where-Object { $_.Length -lt 200MB -and $_.Name -notlike '*.dpapi' } |
                  Select-String -SimpleMatch -Pattern $plain -List | ForEach-Object { $_.Path })
    } finally { $plain = $null; $OutputEncoding = $prevEnc; [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    Write-WorkText 'out\extract_leak_scan.txt' ("files_containing_secret=" + $leak.Count + "`n" + ($leak -join "`n"))
    if ($leak.Count) { Fail "segredo encontrado em arquivo local: $($leak -join ', ')" }
    if ($rc) { Fail "leitura do LIVE falhou (código $rc; 13 = sessão não read-only; 14 = identidade ≠ $ExpectRole ou privilegiada). Nada foi escrito no LIVE." }
    $ro = (Read-WorkText 'out\extract_readonly_probe.txt').Trim().Split('|')
    if ($ro[0] -ne 'on' -or $ro[2] -ne $ExpectRole -or $ro[4] -ne 'false' -or $ro[5] -ne $ExpectRole) { Fail "RO1/RO3 reprovados: $($ro -join '|')" }
    Say "RO1 transaction_read_only=on · RO2 sessão=$($ro[1]) · RO3 current_user=session_user=$($ro[2]) (sem super/BYPASSRLS)"
}
# ---------------------------------------------------------------- 1. DIAGNOSE
function Step-Diagnose {
    $r = [ordered]@{}
    $r.docker_cli = [bool](Get-Command docker -ErrorAction SilentlyContinue)
    $r.docker_ok = $false; $r.image_tag_exists = $false
    if ($r.docker_cli) {
        $v = Invoke-NativeQuiet { docker version --format '{{.Server.Version}}' }; $r.docker_server = $v.out; $r.docker_ok = ($v.rc -eq 0)
        $r.docker_info   = (Invoke-NativeQuiet { docker info --format '{{.OSType}}/{{.Architecture}} cpus={{.NCPU}} mem={{.MemTotal}}' }).out
        $r.image_local   = ((Invoke-NativeQuiet { docker image inspect $Image }).rc -eq 0)
        $r.image_tag_exists = $r.image_local -or ((Invoke-NativeQuiet { docker manifest inspect $Image }).rc -eq 0)
    }
    $r.port_free = -not [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    $r.free_gb = [math]::Round((Get-PSDrive -Name $WorkDir.Substring(0,1)).Free / 1GB, 1)
    $r.free_ok = ($r.free_gb -ge $MinFreeGB)
    $r.host_psql    = [bool](Get-Command psql -ErrorAction SilentlyContinue)     # informativo (usa-se o do container)
    $r.host_pg_dump = [bool](Get-Command pg_dump -ErrorAction SilentlyContinue)  # informativo
    $r.git_head     = (Invoke-NativeQuiet { git -C $Repo rev-parse HEAD }).out
    $r.git_head_ok  = ($r.git_head -eq $ExpectedHead)
    $bad = @(); foreach ($k in $Pinned.Keys) { $p = Join-Path $Harness $k; if (-not (Test-Path -LiteralPath $p) -or (Md5File $p) -ne $Pinned[$k]) { $bad += $k } }
    $r.artifacts_md5_ok = ($bad.Count -eq 0); $r.artifacts_bad = $bad
    $r | ConvertTo-Json -Depth 4 | Tee-Object -FilePath (Join-Path $WorkDir 'out\diagnose.json')
    if (-not ($r.docker_ok -and $r.image_tag_exists -and $r.port_free -and $r.free_ok -and $r.git_head_ok -and $r.artifacts_md5_ok)) {
        Fail 'diagnóstico reprovado (out\diagnose.json). Sem Docker: instalar Docker Desktop com WSL2. Tag inexistente: -Image supabase/postgres:<17.6.1.x publicada>.'
    }
    Say 'DIAGNOSE: PASS'
}

# ---------------------------------------------------------------- 2. SETUP
function Step-Setup {
    # (1) entradas no host: cópia byte a byte + MD5 obrigatório
    foreach ($k in $Pinned.Keys) {
        $dst = Join-Path $WorkDir ('sql\' + (Split-Path $k -Leaf))
        Copy-Item -LiteralPath (Join-Path $Harness $k) -Destination $dst -Force
        if ((Md5File $dst) -ne $Pinned[$k]) { Fail "cópia divergente: $k" }
    }
    # recorte M1–M3: prefixo exato em bytes do P9B publicado (nenhum predicado alterado)
    $bytes = [IO.File]::ReadAllBytes((Join-Path $WorkDir 'sql\2830H_P9B_isolated_timing.sql'))
    $n = 0; $cut = -1
    for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10) { $n++; if ($n -eq $P9BSliceLines) { $cut = $i + 1; break } } }
    if ($cut -lt 0) { Fail 'P9B menor que o recorte esperado' }
    $rest = $Utf8NoBom.GetString($bytes, $cut, [Math]::Min(40, $bytes.Length - $cut))
    if (-not $rest.StartsWith('-- M4')) { Fail 'fronteira do recorte P9B não é o início de M4' }
    $slice = New-Object byte[] $cut; [Array]::Copy($bytes, $slice, $cut)
    $slicePath = Join-Path $WorkDir 'sql\P9B_M1_M3.sql'
    [IO.File]::WriteAllBytes($slicePath, $slice)
    if ((Md5File $slicePath) -ne $P9BSliceMd5) { Fail 'md5 do recorte P9B M1–M3 divergente' }
    Build-LocalControls   # L_E00/L_E99 (adaptação local declarada; canônicos intactos)

    # (2) imagem: só baixa se ainda não existir localmente
    if ((Invoke-NativeQuiet { docker image inspect $Image }).rc -ne 0) {
        & docker pull $Image | Out-Host; if ($LASTEXITCODE) { Fail 'docker pull' }
    }

    # (3) container: reaproveita com segurança; nunca apaga volume nem recria dados
    $pwFile  = Join-Path $WorkDir 'secrets\local_pw.txt'
    $exists  = ((Invoke-NativeQuiet { docker container inspect $Container }).rc -eq 0)
    $volExists = ((Invoke-NativeQuiet { docker volume inspect $Volume }).rc -eq 0)
    if ($exists -or $volExists) {
        # volume já inicializado: a senha local registrada é a única válida — não gerar outra
        if (-not (Test-Path -LiteralPath $pwFile)) { Fail "container/volume já existem, mas secrets\local_pw.txt não — senha desconhecida. Rodar -Step Cleanup e depois -Step Setup." }
    }
    $pw = LocalPw
    if (-not $exists) {
        & docker volume create $Volume | Out-Null; if ($LASTEXITCODE) { Fail 'docker volume create' }
        & docker run -d --name $Container --cpus $Cpus --memory $Memory -e "POSTGRES_PASSWORD=$pw" `
            -p "127.0.0.1:${Port}:5432" -v "${Volume}:/var/lib/postgresql/data" -v "${WorkDir}:/work" $Image | Out-Null
        if ($LASTEXITCODE) { Fail 'docker run' }
        Say "container $Container criado"
    } else {
        $ins = Invoke-NativeQuiet { docker container inspect $Container }
        Write-WorkText 'out\container_inspect.json' $ins.out
        if ($ins.rc -ne 0) { Fail "docker container inspect falhou (rc=$($ins.rc)): $($ins.err)" }
        $status = Assert-ContainerConfig $ins.out
        if ($status -ne 'running') { & docker start $Container | Out-Null; if ($LASTEXITCODE) { Fail 'docker start' } }
        Say "container $Container reaproveitado (estado anterior: $status)"
    }
    WaitReady

    # (4) o /work do container é este $WorkDir (sentinela aleatória)
    $token = [guid]::NewGuid().ToString('N')
    Write-WorkText 'out\.mount_probe' $token
    $seen = Invoke-NativeQuiet { docker exec $Container cat /work/out/.mount_probe }
    if ($seen.rc -ne 0 -or $seen.out -ne $token) { Fail "o bind /work do container não aponta para $WorkDir" }

    # (5) hashes DENTRO do container — fail-closed
    Remove-Item -LiteralPath (Join-Path $WorkDir 'out\md5_in_container.txt') -Force -ErrorAction SilentlyContinue
    if (InC 'setup_md5' 'cd /work/sql && md5sum *.sql *.sh > /work/out/md5_in_container.txt') { Fail 'md5sum no container' }
    $nOk = Assert-HashFile (Join-Path $WorkDir 'out\md5_in_container.txt') (Get-ExpectedContainerHashes)
    Say "hashes no container: $nOk/$nOk conferidos"

    # (6) login local
    $probe = @'
$PSQL_A -At -c 'select current_user, (select rolsuper from pg_roles where rolname = current_user), version()' > /work/out/probe_supabase_admin.txt 2>&1 || exit 1
$PSQL_P -At -c 'select current_user, (select rolsuper from pg_roles where rolname = current_user), current_setting($$search_path$$)' > /work/out/probe_postgres.txt 2>&1 || exit 2
'@
    if (InC 'setup_probe' $probe) { Fail 'login local falhou (out\probe_*.txt). Se a imagem não aplicar POSTGRES_PASSWORD a supabase_admin, ajustar só a autenticação local.' }
    Say "SETUP: PASS (127.0.0.1:$Port, $Image)"
}

# ---------------------------------------------------------------- 3. EXTRACT (LIVE, somente leitura)
function Step-Extract {
    # Pré-requisito: -Step ProbeLiveRo PASS com a MESMA -LiveFpRef (prova de leitura integral sob b12_export_ro).
    $pr = Join-Path $WorkDir 'out\probe_live_ro_result.json'
    if (-not (Test-Path -LiteralPath $pr) -or -not ((Get-Content -LiteralPath $pr -Raw | ConvertFrom-Json).pass)) { Fail 'rodar -Step ProbeLiveRo (PASS) antes do Extract' }
    Invoke-LiveRoContainer (Get-RoSecret) $false
    $copies = ([regex]::Matches((Read-WorkText 'dump\data.sql'), '(?m)^COPY public\.')).Count
    if ($copies -ne $DataTables.Count) { Fail "data.sql tem $copies blocos COPY (esperado $($DataTables.Count))" }
    $fp = JsonOut 'out\fp_live.json'
    if ($fp.d_fp_core_md5 -ne $LiveFpRef) { Fail "LIVE derivou desde a referência ($($fp.d_fp_core_md5) <> $LiveFpRef) — verificar FREEZE" }
    Say "EXTRACT: PASS (schema + $copies tabelas; fingerprint LIVE $($fp.d_fp_core_md5))"
}


# ---------------------------------------------------------------- CREDENCIAL DO PAPEL TEMPORÁRIO
function Step-NewRoCredential {
    $f = Join-Path $WorkDir $RoSecretFile
    if ((Test-Path -LiteralPath $f) -and -not $RotateCredential) { Fail "credencial já existe ($RoSecretFile); use -RotateCredential para substituí-la" }
    if (-not (Test-ScramRfc7677)) { Fail 'implementação SCRAM reprovada no vetor RFC 7677' }
    $sec = New-RandomSecret 40
    $verifier = New-ScramVerifier $sec
    [IO.File]::WriteAllText($f, ($sec | ConvertFrom-SecureString), $Utf8NoBom)     # DPAPI, usuário atual
    Write-WorkText $RoVerifierFile $verifier
    $md5 = ([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier))) -replace '-','').ToLower()
    Write-WorkText 'out\B12-EXPORT-RO-SET-VERIFIER.sql' ("-- Gerado localmente em $(Get-Date -Format o). Contém SOMENTE o verificador SCRAM-SHA-256 (não a senha).`n" +
        "-- Colar no SQL Editor APÓS a §1 de B12-EXPORT-RO-ROLE.sql. md5(verificador) = $md5 (usar em __B12_VERIFIER_MD5__ na §2).`n" +
        "ALTER ROLE b12_export_ro PASSWORD '$verifier';`n")
    Write-WorkText 'out\b12_live_ro.verifier.md5' $md5
    Say "NEWROCREDENTIAL: senha gerada e guardada só via DPAPI ($RoSecretFile); verificador em out\B12-EXPORT-RO-SET-VERIFIER.sql (md5 $md5)"
}
# Prova no PG17 local (mesma imagem do LIVE) de que o VERIFICADOR gerado aceita a SENHA gerada e recusa outra.
function Step-ScramLocalProof {
    $verifier = (Read-WorkText $RoVerifierFile).Trim()
    $hba = @'
$PSQL_A -At -c "select string_agg(line_number || ':' || type || ':' || coalesce(address,'-') || ':' || auth_method, ' ; ' order by line_number) from pg_hba_file_rules where type like 'host%'" > /work/out/scram_local_hba.txt 2>&1 || exit 1
'@
    if (InC 'scram_hba' $hba) { Fail 'leitura de pg_hba_file_rules' }
    # (1) Endereço NÃO-loopback do próprio container (rede Docker), lido do docker inspect: as regras trust
    #     de loopback (127.0.0.1/::1) não podem casar. O HBA da instância NÃO é alterado.
    $ins = Invoke-NativeQuiet { docker container inspect $Container }
    if ($ins.rc -ne 0) { Fail "docker container inspect falhou: $($ins.err)" }
    $nets = ($ins.out | ConvertFrom-Json)[0].NetworkSettings.Networks
    $ips = @($nets.PSObject.Properties | ForEach-Object { $_.Value.IPAddress } |
             Where-Object { $_ -match '^(\d{1,3}\.){3}\d{1,3}$' -and $_ -notmatch '^127\.' })
    if ($ips.Count -lt 1) { Fail 'container sem IPv4 não-loopback na rede Docker' }
    $ip = $ips[0]
    # (2) Regra HBA que casa ESSE endereço para (postgres, b12_export_ro): primeira em ordem de linha,
    #     tratando all/samehost/samenet como casamento (conservador). Tem de ser scram-sha-256 — antes do LOGIN.
    Write-WorkText 'sql\run\scram_hba_match.sql' @'
SELECT line_number || '|' || type || '|' || address || '|' || coalesce(netmask, '') || '|' || auth_method
  FROM pg_hba_file_rules
 WHERE type IN ('host', 'hostssl', 'hostnossl') AND error IS NULL
   AND ('all' = ANY (database) OR 'postgres' = ANY (database))
   AND ('all' = ANY (user_name) OR 'b12_export_ro' = ANY (user_name))
   AND (address IN ('all', 'samehost', 'samenet')
        OR (address ~ '^[0-9.]+$' AND netmask ~ '^[0-9.]+$'
            AND (:'ip'::inet & netmask::inet) = (address::inet & netmask::inet)))
 ORDER BY line_number
 LIMIT 1;
'@
    if (InC 'scram_hba_match' "`$PSQL_A -At -v ON_ERROR_STOP=1 -v ip=$ip -f /work/sql/run/scram_hba_match.sql > /work/out/scram_hba_match.txt 2>&1 || exit 1") { Fail 'casamento HBA' }
    $hm = (Read-WorkText 'out\scram_hba_match.txt').Trim()
    $hp = $hm.Split('|')
    if ($hp.Count -ne 5 -or $hp[4] -ne 'scram-sha-256') { Fail "regra HBA para $ip não é scram-sha-256: '$hm' — prova não seria conclusiva; HBA não será alterado" }
    $sql = "DO `$`$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'b12_export_ro') THEN CREATE ROLE b12_export_ro NOLOGIN NOINHERIT NOBYPASSRLS; END IF; END `$`$;`nALTER ROLE b12_export_ro LOGIN PASSWORD '$verifier';`n"
    # (3) Senha só por STDIN. Sem .pgpass (PGPASSFILE=/dev/null), sem prompt (-w), TCP para o IP da rede Docker.
    #     Cada rc é gravado IMEDIATAMENTE após o psql (sem pipeline/comando intermediário que o mascare).
    #     system_user (PG>=16) = método:identidade autenticada; é NULL sob trust.
    $probe = @'
IFS= read -r PGPASSWORD
# PowerShell 5.1 anexa CRLF ao canalizar para executável nativo; read -r só remove o \n. Mesmo tratamento
# do extract_live_ro.sh. Registra apenas se havia CR e se o tamanho é o gerado (40) — nunca o valor.
CR=$(printf '\r')
case "$PGPASSWORD" in *"$CR"*) echo 1 > /work/out/scram_local_stdin_cr.txt ;; *) echo 0 > /work/out/scram_local_stdin_cr.txt ;; esac
PGPASSWORD=$(printf '%s' "$PGPASSWORD" | tr -d '\r\n')
if [ ${#PGPASSWORD} -eq 40 ]; then echo 1 > /work/out/scram_local_len40.txt; else echo 0 > /work/out/scram_local_len40.txt; unset PGPASSWORD; exit 11; fi
export PGPASSWORD
export PGPASSFILE=/dev/null PGCONNECT_TIMEOUT=10
Q='select current_user || $$|$$ || session_user || $$|$$ || coalesce(system_user, $$<null>$$) || $$|$$ || host(inet_client_addr()) || $$|$$ || host(inet_server_addr())'
psql -X -w -h __IP__ -p 5432 -U b12_export_ro -d postgres -At -c "$Q" > /work/out/scram_local_ok.txt 2> /work/out/scram_local_ok.err
echo $? > /work/out/scram_local_ok.rc
PGPASSWORD="${PGPASSWORD}x"
psql -X -w -h __IP__ -p 5432 -U b12_export_ro -d postgres -At -c 'select 1' > /work/out/scram_local_bad.txt 2> /work/out/scram_local_bad.err
echo $? > /work/out/scram_local_bad.rc
unset PGPASSWORD
exit 0
'@
    $probe = $probe.Replace('__IP__', $ip)
    # A partir do ALTER ROLE ... LOGIN, o reset NOLOGIN/PASSWORD NULL é GARANTIDO (finally), inclusive se
    # o ALTER, a leitura DPAPI, o docker exec ou qualquer cmdlet lançar exceção. O reset é verificado.
    $resetSql = "ALTER ROLE b12_export_ro NOLOGIN PASSWORD NULL;`n" +
                "SELECT CASE WHEN rolcanlogin OR rolpassword IS NOT NULL THEN 'RESET_FAIL' ELSE 'RESET_OK' END || '|rolcanlogin=' || rolcanlogin || '|rolpassword_null=' || (rolpassword IS NULL) FROM pg_authid WHERE rolname = 'b12_export_ro';`n"
    Write-WorkText 'sql\run\scram_local_reset.sql' $resetSql
    foreach ($o in 'scram_local_reset.log','scram_local_ok.txt','scram_local_ok.err','scram_local_ok.rc','scram_local_bad.txt','scram_local_bad.err','scram_local_bad.rc','scram_local_stdin_cr.txt','scram_local_len40.txt') {
        Remove-Item -LiteralPath (Join-Path $WorkDir "out\$o") -Force -ErrorAction SilentlyContinue
    }
    $probeRc = $null
    try {
        Write-WorkText 'sql\run\scram_local_set.sql' $sql
        try {
            if (InC 'scram_set' '$PSQL_A -v ON_ERROR_STOP=1 -f /work/sql/run/scram_local_set.sql > /work/out/scram_local_set.log 2>&1') { Fail 'ALTER ROLE local' }
        } finally { Remove-Item -LiteralPath (Join-Path $WorkDir 'sql\run\scram_local_set.sql') -Force -ErrorAction SilentlyContinue }
        Write-WorkText 'sql\run\scram_probe.sh' ($probe + "`n")
        $sec = Get-RoSecret; $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec); $prevEnc = $OutputEncoding
        try {
            $OutputEncoding = $Utf8NoBom
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) | & docker exec -i $Container sh /work/sql/run/scram_probe.sh | Out-Host
            $probeRc = $LASTEXITCODE
        } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr); $OutputEncoding = $prevEnc }
    } finally {
        # executa mesmo sob exceção; falha do próprio reset é reportada e impede PASS
        $resetOk = $false
        try {
            $rrc = InC 'scram_reset' '$PSQL_A -At -v ON_ERROR_STOP=1 -f /work/sql/run/scram_local_reset.sql > /work/out/scram_local_reset.log 2>&1'
            $resetOk = ($rrc -eq 0) -and ((Read-WorkText 'out\scram_local_reset.log') -match 'RESET_OK\|rolcanlogin=false\|rolpassword_null=true')
        } catch { $resetOk = $false }
        if (-not $resetOk) { Write-Host '[SCRAM] ATENÇÃO: reset NOLOGIN/PASSWORD NULL do b12_export_ro LOCAL não confirmado — ver out\scram_local_reset.log' -ForegroundColor Red }
    }
    if (-not $resetOk) { Fail 'reset do role local (NOLOGIN/PASSWORD NULL) não confirmado' }
    if ($probeRc -ne 0) { Fail "script da prova SCRAM terminou com rc=$probeRc" }
    $okF  = @((Read-WorkText 'out\scram_local_ok.txt').Trim().Split('|'))
    $okRc = [int](Read-WorkText 'out\scram_local_ok.rc').Trim(); $badRc = [int](Read-WorkText 'out\scram_local_bad.rc').Trim()
    $badErr = (Read-WorkText 'out\scram_local_bad.err').Trim(); $badOut = (Read-WorkText 'out\scram_local_bad.txt').Trim()
    $r = [ordered]@{
        hba_host_rules      = (Read-WorkText 'out\scram_local_hba.txt').Trim()
        target_ip           = $ip
        hba_rule_matched    = $hm                       # linha|tipo|endereço|máscara|método
        ok_rc               = $okRc
        ok_session          = ($okF -join '|')          # current_user|session_user|system_user|client_addr|server_addr
        ok_stderr           = (Read-WorkText 'out\scram_local_ok.err').Trim()
        stdin_had_cr        = (Read-WorkText 'out\scram_local_stdin_cr.txt').Trim()   # 1 = CR removido antes do psql
        secret_len_is_40    = (Read-WorkText 'out\scram_local_len40.txt').Trim()
        bad_rc              = $badRc
        bad_stderr          = $badErr                   # mensagem do servidor; nunca contém a senha
        final_role_state    = (Read-WorkText 'out\scram_local_reset.log').Trim()
    }
    $r.G1_hba_scram_not_loopback = ($hp[4] -eq 'scram-sha-256') -and ($hp[2] -notmatch '^(127\.|::1)')
    $r.G2_correct_password       = ($okRc -eq 0) -and ($okF.Count -eq 5) -and ($okF[0] -eq 'b12_export_ro') -and ($okF[1] -eq 'b12_export_ro') -and
                                   ($okF[2] -eq 'scram-sha-256:b12_export_ro') -and ($okF[3] -eq $ip) -and ($okF[4] -eq $ip)
    $r.G3_wrong_password_refused = ($badRc -ne 0) -and ($badOut -eq '') -and ($badErr -match 'password authentication failed for user "b12_export_ro"')
    $r.G4_final_nologin_nopass   = $resetOk
    $r.pass = $r.G1_hba_scram_not_loopback -and $r.G2_correct_password -and $r.G3_wrong_password_refused -and $r.G4_final_nologin_nopass
    $r | ConvertTo-Json | Tee-Object -FilePath (Join-Path $WorkDir 'out\scram_local_proof.json')
    if (-not $r.pass) { Fail 'prova SCRAM local reprovada (out\scram_local_proof.json)' }
    Say "SCRAMLOCALPROOF: PASS (TCP $ip → regra HBA $($hp[0]) scram-sha-256; senha certa autenticada por SCRAM; errada recusada; role local NOLOGIN/PASSWORD NULL)"
}
# ---------------------------------------------------------------- CONTRAPROVA: visibilidade × fingerprint
# Reproduz na imagem 17.6.1.147 a divergência do ProbeLiveRo (G4) e prova a correção, sem LIVE:
# um papel SEM USAGE em extensions renderiza pg_get_indexdef de um índice gin_trgm_ops de forma
# diferente de um superusuário quando o caminho é "$user", public, extensions (o esquema sem USAGE
# some do caminho EFETIVO); com search_path = '' as duas renderizações são idênticas.
function Step-FpVisibilityProof {
    Write-WorkText 'sql\run\fpv.sql' @'
CREATE SCHEMA extensions;
CREATE EXTENSION pg_trgm WITH SCHEMA extensions;
CREATE TABLE public.fpv_card (id int PRIMARY KEY, name text NOT NULL);
CREATE INDEX ix_fpv_trgm ON public.fpv_card USING gin (lower(name) extensions.gin_trgm_ops);
CREATE ROLE b12_fpv_ro NOLOGIN NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA public TO b12_fpv_ro;
GRANT SELECT ON public.fpv_card TO b12_fpv_ro;
REVOKE ALL ON SCHEMA extensions FROM PUBLIC;
SET search_path = "$user", public, extensions;
SELECT 'OLD_ADMIN|' || md5(pg_get_indexdef('public.ix_fpv_trgm'::regclass));
SET ROLE b12_fpv_ro;
SELECT 'OLD_RO|' || md5(pg_get_indexdef('public.ix_fpv_trgm'::regclass)) || '|' || current_schemas(false)::text;
RESET ROLE;
SET search_path = '';
SELECT 'NEW_ADMIN|' || md5(pg_get_indexdef('public.ix_fpv_trgm'::regclass));
SET ROLE b12_fpv_ro;
SELECT 'NEW_RO|' || md5(pg_get_indexdef('public.ix_fpv_trgm'::regclass)) || '|' || current_schemas(false)::text;
RESET ROLE;
'@
    $body = @'
PSQL_V='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d b12_fpv'
cleanup() { $PSQL_A -q -c 'DROP DATABASE IF EXISTS b12_fpv WITH (FORCE)' -c 'DROP ROLE IF EXISTS b12_fpv_ro' > /work/out/fpv_cleanup.log 2>&1; }
cleanup
trap cleanup EXIT
$PSQL_A -v ON_ERROR_STOP=1 -q -c 'CREATE DATABASE b12_fpv' > /work/out/fpv_pre.log 2>&1 || exit 1
$PSQL_V -v ON_ERROR_STOP=1 -q -At -f /work/sql/run/fpv.sql -o /work/out/fpv.txt 2> /work/out/fpv.err || exit 2
exit 0
'@
    $rc = InC 'fp_visibility' $body
    if ($rc) { Fail "FPVISIBILITYPROOF falhou (rc=$rc; out\fpv.err)" }
    $m = @{}; foreach ($l in ((Read-WorkText 'out\fpv.txt') -split "`n" | Where-Object { $_ -match '\|' })) { $p = $l.Trim().Split('|'); $m[$p[0]] = $p }
    $r = [ordered]@{}
    $r.V1_reproduces_divergence = ($m['OLD_ADMIN'][1] -ne $m['OLD_RO'][1]) -and ($m['OLD_RO'][2] -eq '{public}')
    $r.V2_fixed_with_empty_path = ($m['NEW_ADMIN'][1] -eq $m['NEW_RO'][1]) -and ($m['NEW_RO'][2] -eq '{}')
    $r.pass = $r.V1_reproduces_divergence -and $r.V2_fixed_with_empty_path
    $r.raw = (Read-WorkText 'out\fpv.txt').Trim()
    $r | ConvertTo-Json | Tee-Object -FilePath (Join-Path $WorkDir 'out\fp_visibility_proof.json')
    if (-not $r.pass) { Fail 'FPVISIBILITYPROOF reprovado (out\fp_visibility_proof.json)' }
    Say "FPVISIBILITYPROOF: PASS (pin antigo diverge por USAGE em extensions; search_path='' renderiza igual para superusuário e papel sem USAGE)"
}

# ---------------------------------------------------------------- §2 PRONTA (sem edição manual)
# Gera out\B12-EXPORT-RO-S2-READY.sql = bloco §2 de B12-EXPORT-RO-ROLE.sql com o marcador substituído
# pelo md5 do verificador SCRAM ISOLADO da credencial DPAPI existente. Nada é escrito no LIVE.
$RoleSql     = 'B12-EXPORT-RO-ROLE.sql'
$RoleSqlMd5  = '6c9667d9ba706c60564bd4e60dc55e54'
$S2Marker    = '__B12_VERIFIER_MD5__'
function Step-RenderS2 {
    $g = [ordered]@{}
    # G0 fonte fixada
    $src = Join-Path $PSScriptRoot $RoleSql
    $g.G0_role_sql_md5_pinned = ((Md5File $src) -eq $RoleSqlMd5)
    if (-not $g.G0_role_sql_md5_pinned) { Fail "$RoleSql alterado (md5 $(Md5File $src) <> $RoleSqlMd5)" }
    $text = [IO.File]::ReadAllText($src, $Utf8NoBom) -replace "`r`n", "`n"
    # extrai o bloco §2: do BEGIN após o cabeçalho da §2 até o primeiro COMMIT seguinte
    $h = $text.IndexOf('-- §2 — VERIFICAÇÃO'); if ($h -lt 0) { Fail 'cabeçalho da §2 não encontrado' }
    $b = $text.IndexOf("`nBEGIN TRANSACTION READ ONLY;", $h); $c = $text.IndexOf("`nCOMMIT;", $b)
    if ($b -lt 0 -or $c -lt 0) { Fail 'delimitadores BEGIN/COMMIT da §2 não encontrados' }
    $block = $text.Substring($b + 1, ($c + 8) - ($b + 1))
    # G1 marcador ocorre exatamente uma vez (no arquivo e no bloco)
    $g.G1_marker_once_file  = ([regex]::Matches($text,  [regex]::Escape($S2Marker)).Count -eq 1)
    $g.G1_marker_once_block = ([regex]::Matches($block, [regex]::Escape($S2Marker)).Count -eq 1)
    # G2 md5 = md5 do verificador SCRAM isolado (recalculado; confere com o .md5 gravado no NewRoCredential)
    $verifier = (Read-WorkText $RoVerifierFile).Trim()
    $vm = [regex]::Match($verifier, '^SCRAM-SHA-256\$(\d+):([A-Za-z0-9+/=]+)\$([A-Za-z0-9+/=]+):([A-Za-z0-9+/=]+)$')
    $g.G2_verifier_format = $vm.Success
    $md5 = ([BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier))) -replace '-','').ToLower()
    $g.G2_md5_hex32          = ($md5 -match '^[0-9a-f]{32}$')
    $g.G2_md5_eq_saved_file  = ($md5 -eq (Read-WorkText 'out\b12_live_ro.verifier.md5').Trim())
    # G3 o verificador corresponde à senha DPAPI existente (StoredKey/ServerKey recalculados; senha só em memória)
    $sec = Get-RoSecret; $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec); $plain = $null; $pw = $null
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $pw = [Text.Encoding]::UTF8.GetBytes($plain)
        $k = Get-ScramKeys $pw ([Convert]::FromBase64String($vm.Groups[2].Value)) ([int]$vm.Groups[1].Value)
        $g.G3_verifier_matches_dpapi = ([Convert]::ToBase64String($k.StoredKey) -eq $vm.Groups[3].Value) -and ([Convert]::ToBase64String($k.ServerKey) -eq $vm.Groups[4].Value)
        # G4 substituição + G5 ausência de segredos na saída
        $out = $block.Replace($S2Marker, $md5)
        $hdr = "-- B12 §2 PRONTA — gerada por -Step RenderS2 em $(Get-Date -Format o). Colar INTEGRALMENTE no SQL Editor.`n" +
               "-- Origem: $RoleSql (md5 $RoleSqlMd5). Marcador substituído automaticamente. Critério: v14_verifier_status = 'OK'.`n"
        $out = $hdr + $out
        $g.G4_no_marker_left       = (-not $out.Contains($S2Marker))
        $g.G4_md5_inserted_once    = ([regex]::Matches($out, $md5).Count -eq 1)
        $g.G4_v14_requires_ok      = ($out -match "WHEN md5\(a\.rolpassword\) = k\.m\s+THEN 'OK'") -and ($out -match 'AS v14_verifier_status')
        $g.G5_no_password          = (-not $out.Contains($plain))
        $g.G5_no_full_verifier     = (-not $out.Contains($verifier)) -and (-not $out.Contains($vm.Groups[2].Value)) -and
                                     (-not $out.Contains($vm.Groups[3].Value)) -and (-not $out.Contains($vm.Groups[4].Value))
    } finally {
        $plain = $null; if ($pw) { [Array]::Clear($pw, 0, $pw.Length) }; [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $pass = (@($g.Values | Where-Object { $_ -ne $true }).Count -eq 0)
    $dst = 'out\B12-EXPORT-RO-S2-READY.sql'
    Remove-Item -LiteralPath (Join-Path $WorkDir $dst) -Force -ErrorAction SilentlyContinue
    if ($pass) { Write-WorkText $dst $out }
    $res = [ordered]@{ gates = $g; pass = $pass; output = $(if ($pass) { "C:\b12-pg17\$dst" } else { $null })
                       output_sha256 = $(if ($pass) { (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $WorkDir $dst)).Hash.ToLower() } else { $null }) }
    $res | ConvertTo-Json -Depth 4 | Tee-Object -FilePath (Join-Path $WorkDir 'out\s2_render_result.json')
    if (-not $pass) { Fail 'RENDERS2 reprovado (out\s2_render_result.json) — nenhum SQL gerado' }
    Say "RENDERS2: PASS — colar integralmente $($res.output) no SQL Editor (sha256 $($res.output_sha256))"
}
# Prova OBRIGATÓRIA, via Session pooler real, de leitura integral das 22 tabelas sob b12_export_ro.
function Step-ProbeLiveRo {
    # a8a1efb3… é a referência SEM as políticas b12 (search_path=''); com o papel ativo o núcleo muda (policies_md5).
    if ($LiveFpRef -eq $LiveFpRefPreRole) { Fail "informar -LiveFpRef <LiveFpRefExport medido como postgres na §2b de B12-EXPORT-RO-ROLE.sql> (o padrão $LiveFpRefPreRole é anterior às políticas)" }
    foreach ($o in 'export_ro_probe.json','fp_live_ro_probe.json','live_ro_counts.txt','probe_live_ro_result.json') { Remove-Item -LiteralPath (Join-Path $WorkDir "out\$o") -Force -ErrorAction SilentlyContinue }
    Invoke-LiveRoContainer (Get-RoSecret) $true
    $xp = JsonOut 'out\export_ro_probe.json'
    $fp = JsonOut 'out\fp_live_ro_probe.json'
    $counts = @{}; foreach ($l in ((Read-WorkText 'out\live_ro_counts.txt') -split "`n" | Where-Object { $_ -match '\|' })) { $p = $l.Trim().Split('|'); $counts[$p[0]] = [long]$p[1] }
    $r = [ordered]@{}
    # G1 identidade e atributos (conexão real: current_user = session_user = b12_export_ro; RO3 já exigido)
    $r.G1_identity_attrs   = ($xp.gates.x1_identity -and $xp.gates.x2_role_attrs -and $xp.gates.x3_no_memberships -and $xp.gates.x4_no_privileged_roles)
    # G2 ausência de escrita, de BYPASSRLS e de leitura fora das 22; RLS ativa e política é a nossa
    $r.G2_no_write_no_bypass = ($xp.gates.x6_no_write_22 -and $xp.gates.x7_no_other_select -and $xp.gates.x8_no_create_no_auth_internal -and
                                $xp.gates.x9_rls_enabled_22 -and $xp.gates.x10_policy_is_ours -and $xp.gates.x11_session_ro_rls -and $xp.gates.x12_is_admin_not_executable)
    # G3 leitura completa: SELECT nas 22 e count(*) real > 0 em cada uma, igual ao content do fingerprint
    $mm = @(); foreach ($t in $DataTables) {
        $cc = $fp.d_fp_core.content.$t
        if (-not $counts.ContainsKey($t) -or $counts[$t] -le 0 -or $null -eq $cc -or [long]$cc[0] -ne $counts[$t]) { $mm += $t }
    }
    $r.G3_full_read_22     = ($xp.gates.x5_select_22 -and $counts.Count -eq $DataTables.Count -and $mm.Count -eq 0)
    # G4 conteúdo equivalente ao do dono: núcleo integral (catálogo + content linha a linha + distribuições)
    #    idêntico ao LiveFpRefExport medido por postgres com a MESMA sessão fixada
    $r.G4_content_eq_owner = ($fp.d_fp_core_md5 -eq $LiveFpRef) -and ($fp.d_env.search_path -eq $PinnedSearchPath) -and ($fp.d_env.timezone -eq 'UTC') -and ($fp.d_env.current_user -eq $ExpectRole)
    $res = [ordered]@{ gates = $r; pass = (@($r.Values | Where-Object { $_ -ne $true }).Count -eq 0)
                       count_mismatches = $mm; fp_md5 = $fp.d_fp_core_md5; expected_ref = $LiveFpRef
                       fp_session = [ordered]@{ user = $fp.d_env.current_user; search_path = $fp.d_env.search_path; timezone = $fp.d_env.timezone }
                       export_probe = $xp }
    $res | ConvertTo-Json -Depth 6 | Tee-Object -FilePath (Join-Path $WorkDir 'out\probe_live_ro_result.json')
    if (-not $res.pass) { Fail 'PROBE LIVE RO reprovado (out\probe_live_ro_result.json) — não extrair; nenhuma concessão adicional sem nova decisão' }
    Say "PROBELIVERO: PASS (G1 identidade · G2 sem escrita/BYPASSRLS · G3 22/22 lidas · G4 núcleo = $LiveFpRef)"
}
# ---------------------------------------------------------------- 4. LOAD
function Step-Load {
    Write-WorkText 'sql\run\local_pre.sql' @"
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS unaccent    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm     WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
-- papel apenas nominal (NOLOGIN) para que GRANTs/políticas b12_export_ro_select restaurem idênticos
DO `$`$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'b12_export_ro') THEN
    CREATE ROLE b12_export_ro NOLOGIN NOINHERIT NOBYPASSRLS;
  END IF;
END `$`$;
"@
    # stub mínimo de auth.users: SÓ o id referenciado por initiated_by (sem e-mail, senha ou metadados)
    $ids = @((Read-WorkText 'dump\auth_stub_ids.txt') -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[0-9a-f-]{36}$' })
    Write-WorkText 'sql\run\local_auth_stub.sql' ((($ids | ForEach-Object { "INSERT INTO auth.users (id) VALUES ('$_') ON CONFLICT (id) DO NOTHING;" }) -join "`n") + "`n")
    Write-WorkText 'sql\run\local_post.sql' @"
ALTER DATABASE postgres SET "TimeZone" = 'UTC';
ALTER DATABASE postgres SET search_path = "`$user", public, extensions;
ALTER DATABASE postgres SET jit = off;
ALTER DATABASE postgres SET work_mem = '2184kB';
ALTER DATABASE postgres SET random_page_cost = 1.1;
ALTER DATABASE postgres SET effective_cache_size = '384MB';
ALTER DATABASE postgres SET max_parallel_workers_per_gather = 1;
ALTER DATABASE postgres SET statement_timeout = '2min';
ALTER SYSTEM SET shared_buffers = '224MB';
"@
    # Load exige banco vazio (não é reexecutável sobre uma carga existente; para auditar a carga atual: -Step LoadAudit)
    $fresh = Invoke-NativeQuiet { docker exec -e "PGPASSWORD=$(LocalPw)" $Container psql -X -At -h 127.0.0.1 -p 5432 -U postgres -d postgres -c "SELECT to_regclass('public.card_variant') IS NULL AND to_regnamespace('internal') IS NULL" }
    if ($fresh.rc -ne 0 -or "$($fresh.out)".Trim() -ne 't') { Fail 'banco local já contém o schema carregado (ou não respondeu) — Load exige banco vazio; auditar a carga existente com -Step LoadAudit' }
    $null = Get-SchemaLoadPlan   # gera out\schema.load.sql + out\schema_load_plan.json (dump\schema.sql intacto)
    # schema: transação única e ON_ERROR_STOP=1 — qualquer erro desfaz tudo e para a carga (fail-closed)
    $body = @'
$PSQL_A -v ON_ERROR_STOP=1 -f /work/sql/run/local_pre.sql > /work/out/load_pre.log 2>&1 || exit 1
$PSQL_A -v ON_ERROR_STOP=1 --single-transaction -f /work/out/schema.load.sql > /work/out/load_schema.log 2>&1 || exit 2
$PSQL_A -v ON_ERROR_STOP=1 -f /work/sql/run/local_auth_stub.sql > /work/out/load_stub.log 2>&1 || exit 3
$PSQL_A -v ON_ERROR_STOP=1 -f /work/dump/data.sql > /work/out/load_data.log 2>&1 || exit 4
$PSQL_A -v ON_ERROR_STOP=1 -f /work/sql/run/local_post.sql > /work/out/load_post.log 2>&1 || exit 5
'@
    $dataTxt = Read-WorkText 'dump\data.sql'
    # pg_dump grava o modo de RLS no cabeçalho; a restauração como superusuário ignora RLS em qualquer dos dois
    if ($dataTxt -notmatch '(?m)^SET row_security = (on|off);') { Fail 'data.sql sem diretiva SET row_security (dump inesperado)' }
    if ((Read-WorkText 'out\probe_supabase_admin.txt') -notmatch '^supabase_admin\|t\|') { Fail 'restauração exige supabase_admin superusuário (COPY em tabela com RLS)' }
    $rc = InC 'load' $body
    if ($rc) { Fail "carga local falhou (código $rc; ver out\load_*.log)" }
    & docker restart $Container | Out-Null; WaitReady
    $an = ($DataTables | ForEach-Object { "`$PSQL_A -q -v ON_ERROR_STOP=1 -c 'VACUUM (ANALYZE) public.$_' >> /work/out/load_analyze.log 2>&1 || exit 1" }) -join "`n"
    if (InC 'analyze' $an) { Fail 'VACUUM ANALYZE' }
    Step-LoadAudit
    Say 'LOAD: concluído e auditado (out\load_audit.json)'
}

# ---------------------------------------------------------------- 4a. PLANO DE CARGA DO SCHEMA (local, sem LIVE)
# O --filter do pg_dump 17 exclui as demais RELAÇÕES de public, mas não aceita objetos do tipo função:
# funções/COMMENT/ACL continuam no dump. Uma função cuja ASSINATURA (argumentos/retorno) usa o tipo-linha
# de uma relação excluída não pode existir na réplica; ela e seus COMMENT/ACL viram comandos órfãos.
# O plano DERIVA esses órfãos (sem lista fixa) do filtro gravado no Extract, remove as entradas TOC
# inteiras numa CÓPIA (out\schema.load.sql — dump\schema.sql nunca é alterado) e remove somente a linha
# "CREATE SCHEMA public;" (o schema já existe na imagem; ALTER OWNER/COMMENT/GRANT do schema permanecem,
# idênticos ao LIVE). Nenhum tipo ou função substituta é criado.
# STOP se: um órfão for do escopo (22 tabelas, fecho de funções do fp_live, schema internal); houver
# sobrecarga ambígua; ou uma entrada estrutural (trigger, default, constraint, policy, view, índice,
# tipo...) referir o órfão. Corpos de outras funções podem citá-lo (plpgsql não é validado na carga):
# ficam como estão e só falhariam se executados — nenhuma está no fecho (verificado pelo gate de escopo).
function Get-SchemaLoadPlan {
    $src   = Join-Path $WorkDir 'dump\schema.sql'
    $lines = [IO.File]::ReadAllLines($src, $Utf8NoBom)
    $excl  = @((Read-WorkText 'out\pgdump_schema_filter.txt') -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
        if ($_ -notmatch '^exclude table public\.("?)([^"]+)\1$') { Fail "linha inesperada no filtro do pg_dump: $_" }
        $Matches[2] })
    if ($excl.Count -eq 0) { Fail 'filtro do pg_dump vazio' }
    # entradas TOC do formato plain: "--" / "-- Name: X; Type: T; Schema: S; Owner: O" / "--"
    $ents = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i-1] -eq '--' -and $lines[$i+1] -eq '--' -and $lines[$i] -match '^-- Name: (.+); Type: ([^;]+); Schema: ([^;]+); Owner: ?(.*)$') {
            [void]$ents.Add([pscustomobject]@{ Name = $Matches[1]; Type = $Matches[2]; Schema = $Matches[3]; Start = $i - 1; End = -1 })
        }
    }
    $tail = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -eq '-- PostgreSQL database dump complete') { $tail = $i; break } }
    if ($ents.Count -eq 0 -or $tail -lt 1) { Fail 'schema.sql sem entradas TOC ou sem rodapé do pg_dump' }
    for ($k = 0; $k -lt $ents.Count; $k++) { $ents[$k].End = $(if ($k -lt $ents.Count - 1) { $ents[$k+1].Start - 1 } else { $tail - 2 }) }
    $text = { param($e) ($lines[$e.Start..$e.End] -join "`n") }
    $fnTypes = @('FUNCTION','PROCEDURE','AGGREGATE')
    # 1) órfãos: função cuja assinatura (antes de "AS $" / "BEGIN ATOMIC") cita public.<relação excluída>
    $orph = @()
    foreach ($e in @($ents | Where-Object { $fnTypes -contains $_.Type })) {
        $t = & $text $e
        $sig = ($t -split '(?m)^\s*AS \$|BEGIN ATOMIC', 2)[0]
        $hit = @($excl | Where-Object { $sig -match ('(?<![\w."])public\."?' + [regex]::Escape($_) + '"?(?![\w"])') })
        if ($hit.Count) { $orph += [pscustomobject]@{ Schema = $e.Schema; Base = ($e.Name -split '\(', 2)[0]; Tag = $e.Name; ViaType = $hit; Entry = $e } }
    }
    # 2) gate de escopo: nenhum órfão pode pertencer ao que o B12 carrega/compara
    $closure = @((JsonOut 'out\fp_live.json').d_fp_core.functions.PSObject.Properties.Name | ForEach-Object { ($_ -split '\(')[0] })
    foreach ($o in $orph) {
        $q = "$($o.Schema).$($o.Base)"
        if ($o.Schema -ne 'public' -or $closure -contains $q -or $DataTables -contains $o.Base) { Fail "órfão pertence ao escopo: $q — não remover; decisão necessária" }
        if (@($ents | Where-Object { $fnTypes -contains $_.Type -and $_.Schema -eq $o.Schema -and ($_.Name -split '\(', 2)[0] -eq $o.Base }).Count -ne 1) { Fail "sobrecarga ambígua de $q — não remover automaticamente" }
    }
    # 3) entradas a remover: FUNCTION + COMMENT/ACL "FUNCTION <base>(...)" do mesmo schema, conferidas pelo texto
    $drop = New-Object System.Collections.ArrayList
    foreach ($o in $orph) {
        [void]$drop.Add($o.Entry)
        foreach ($e in @($ents | Where-Object { @('COMMENT','ACL') -contains $_.Type -and $_.Schema -eq $o.Schema -and $_.Name -like "FUNCTION $($o.Base)(*" })) {
            if ((& $text $e) -notmatch ('ON FUNCTION ' + [regex]::Escape("$($o.Schema).$($o.Base)") + '\(')) { Fail "entrada $($e.Type) '$($e.Name)' não corresponde ao órfão" }
            [void]$drop.Add($e)
        }
    }
    # 4) nenhuma entrada estrutural remanescente pode referir o órfão
    foreach ($o in $orph) {
        $rx = '(?<![\w])' + [regex]::Escape("$($o.Schema).$($o.Base)") + '\s*\('
        $bad = @($ents | Where-Object { $drop -notcontains $_ -and ($fnTypes + @('COMMENT','ACL')) -notcontains $_.Type -and ((& $text $_) -match $rx) })
        if ($bad.Count) { Fail ("entrada estrutural refere o órfão $($o.Base): " + (($bad | ForEach-Object { "$($_.Type) $($_.Name)" }) -join '; ')) }
    }
    # 5) schema public: remover só "CREATE SCHEMA public;" (o resto da entrada permanece)
    $spLine = $null
    $sp = @($ents | Where-Object { $_.Type -eq 'SCHEMA' -and $_.Name -eq 'public' })
    if ($sp.Count -gt 1) { Fail 'mais de uma entrada SCHEMA public' }
    if ($sp.Count -eq 1) {
        $idx = @($sp[0].Start..$sp[0].End | Where-Object { $lines[$_] -eq 'CREATE SCHEMA public;' })
        if ($idx.Count -ne 1) { Fail "entrada SCHEMA public com $($idx.Count) linha(s) 'CREATE SCHEMA public;'" }
        $spLine = $idx[0]
    }
    # 6) cópia sanitizada + plano
    $skip = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($e in $drop) { foreach ($i in $e.Start..$e.End) { [void]$skip.Add($i) } }
    if ($null -ne $spLine) { [void]$skip.Add($spLine) }
    $keep = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) { if (-not $skip.Contains($i)) { $keep.Add($lines[$i]) } }
    Write-WorkText 'out\schema.load.sql' (($keep -join "`n") + "`n")
    $cnt = { param($s) @($ents | Where-Object { $fnTypes -contains $_.Type -and $_.Schema -eq $s }).Count }
    $plan = [ordered]@{
        source = 'dump\schema.sql'; source_md5 = (Md5File $src); load_md5 = (Md5File (Join-Path $WorkDir 'out\schema.load.sql'))
        excluded_relations = $excl.Count
        orphans = @($orph | ForEach-Object { [ordered]@{ function = "$($_.Schema).$($_.Tag)"; via_type = $_.ViaType } })
        removed_entries = @($drop | ForEach-Object { [ordered]@{ type = $_.Type; name = $_.Name; from_line = $_.Start + 1; to_line = $_.End + 1 } })
        schema_public_create_line = $(if ($null -ne $spLine) { $spLine + 1 } else { $null })
        tables_public_in_dump = @($ents | Where-Object { $_.Type -eq 'TABLE' -and $_.Schema -eq 'public' }).Count
        expected_functions = [ordered]@{ public = (& $cnt 'public') - @($orph | Where-Object { $_.Schema -eq 'public' }).Count; internal = (& $cnt 'internal') }
    }
    if ($plan.tables_public_in_dump -ne $DataTables.Count) { Fail "dump com $($plan.tables_public_in_dump) tabelas em public (esperado $($DataTables.Count))" }
    Write-WorkText 'out\schema_load_plan.json' ($plan | ConvertTo-Json -Depth 6)
    Say ("PLANO: {0} órfão(s) [{1}], {2} entrada(s) TOC removida(s), CREATE SCHEMA public na linha {3}" -f $orph.Count, (($orph | ForEach-Object { $_.Base }) -join ', '), $drop.Count, $plan.schema_public_create_line)
    return $plan
}

# ---------------------------------------------------------------- 4b. LOADAUDIT (fail-closed; sem recarga)
# Julga a carga pelo LOG e pelo ESTADO, nunca pelo código de saída do psql:
#  A1 todo "ERROR:" do log de schema é explicado pelo plano — carga sanitizada: zero erros; carga
#     legada (dump\schema.sql com ON_ERROR_STOP=0): cada erro cai numa entrada removida pelo plano
#     (mensagem type/function do órfão) ou é exatamente 'schema "public" already exists' na linha
#     do CREATE SCHEMA public; e cada entrada removida produziu ao menos um erro. Qualquer outro → STOP.
#  A2 órfãos ausentes · A3 contagem de funções public/internal = dump − órfãos · A4 exatamente as 22
#     tabelas em public, todas presentes · A5 nenhum índice inválido/não pronto em public/internal.
#  Escopo integral (funções do fecho, colunas, índices, constraints, triggers, policies, conteúdo): Parity P3.
function Step-LoadAudit {
    $plan = Get-SchemaLoadPlan
    $log  = Read-WorkText 'out\load_schema.log'
    $errLines = @([regex]::Matches($log, '(?m)^.*ERROR:.*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
    Write-WorkText 'out\load_schema_errors.txt' ($errLines -join "`n")
    $excl = @((Read-WorkText 'out\pgdump_schema_filter.txt') -split "`n" | ForEach-Object { if ($_.Trim() -match '^exclude table public\.("?)([^"]+)\1$') { $Matches[2] } })
    $orphBases = @($plan.orphans | ForEach-Object { (($_.function -split '\(', 2)[0]) })
    $rows = @(); $unexplained = @()
    foreach ($l in $errLines) {
        if ($l -notmatch '^psql:(/work/[^:]+):(\d+): ERROR:\s+(.*)$') { $unexplained += $l; continue }
        $file = $Matches[1]; $n = [int]$Matches[2]; $msg = $Matches[3]; $why = $null
        if ($file -eq '/work/dump/schema.sql') {
            if ($n -eq $plan.schema_public_create_line -and $msg -eq 'schema "public" already exists') { $why = 'SCHEMA_PUBLIC_PREEXISTS' }
            else {
                $in = @($plan.removed_entries | Where-Object { $n -ge $_.from_line -and $n -le $_.to_line })
                $okMsg = (@($excl | Where-Object { $msg -eq ('type "public.' + $_ + '" does not exist') }).Count -gt 0) -or
                         (@($orphBases | Where-Object { $msg -match ('^function ' + [regex]::Escape($_) + '\(.*\) does not exist$') }).Count -gt 0)
                if ($in.Count -eq 1 -and $okMsg) { $why = "ORPHAN:$($in[0].type):$($in[0].name)" }
            }
        }
        if ($why) { $rows += [ordered]@{ line = $n; message = $msg; class = $why } } else { $unexplained += $l }
    }
    $legacy = ($log -match '/work/dump/schema\.sql')
    $uncovered = @()
    if ($legacy) { $uncovered = @($plan.removed_entries | Where-Object { $e = $_; @($rows | Where-Object { $_.line -ge $e.from_line -and $_.line -le $e.to_line }).Count -eq 0 } | ForEach-Object { "$($_.type) $($_.name)" }) }
    $orphList = (@($orphBases) | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ','
    if (-not $orphList) { $orphList = "NULL" }
    Write-WorkText 'sql\run\load_audit.sql' @"
SELECT jsonb_build_object(
  'fn_public',   (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace),
  'fn_internal', (SELECT count(*) FROM pg_proc WHERE pronamespace = 'internal'::regnamespace),
  'orphans_present', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname || '.' || p.proname = ANY (ARRAY[$orphList]::text[])),
  'tables_public', (SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r','p')),
  'scope_tables_present', (SELECT count(*) FROM unnest(ARRAY['$($DataTables -join "','")']::text[]) t WHERE to_regclass('public.' || t) IS NOT NULL),
  'invalid_indexes', (SELECT count(*) FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
                       WHERE c.relnamespace IN ('public'::regnamespace, 'internal'::regnamespace) AND NOT (i.indisvalid AND i.indisready)),
  'public_owner', (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'public'),
  'public_acl',   (SELECT nspacl::text FROM pg_namespace WHERE nspname = 'public'));
"@
    if (InC 'load_audit' '$PSQL_P -At -v ON_ERROR_STOP=1 -f /work/sql/run/load_audit.sql -o /work/out/load_audit_local.json || exit 1') { Fail 'consulta de estado local (load_audit.sql) falhou' }
    $st = JsonOut 'out\load_audit_local.json'
    $g = [ordered]@{}
    $g.A1_errors_explained  = ($unexplained.Count -eq 0) -and ($uncovered.Count -eq 0) -and ($legacy -or $errLines.Count -eq 0)
    $g.A2_orphans_absent    = ([int]$st.orphans_present -eq 0)
    $g.A3_function_counts   = ([int]$st.fn_public -eq [int]$plan.expected_functions.public) -and ([int]$st.fn_internal -eq [int]$plan.expected_functions.internal)
    $g.A4_scope_tables      = ([int]$st.tables_public -eq $DataTables.Count) -and ([int]$st.scope_tables_present -eq $DataTables.Count)
    $g.A5_indexes_valid     = ([int]$st.invalid_indexes -eq 0)
    $res = [ordered]@{ pass = (@($g.Values | Where-Object { $_ -ne $true }).Count -eq 0); gates = $g
                       mode = $(if ($legacy) { 'LEGACY_ON_ERROR_STOP_0' } else { 'SANITIZED_SINGLE_TRANSACTION' })
                       errors_classified = $rows; errors_unexplained = $unexplained; removed_entries_without_error = $uncovered
                       expected_functions = $plan.expected_functions; local_state = $st; plan_source_md5 = $plan.source_md5 }
    $res | ConvertTo-Json -Depth 6 | Tee-Object -FilePath (Join-Path $WorkDir 'out\load_audit.json')
    if (-not $res.pass) { Fail 'LOADAUDIT reprovado (out\load_audit.json) — carga não confiável; não seguir para RestoreProof/Parity' }
    Say "LOADAUDIT: PASS ($($res.mode); $($errLines.Count) erro(s), todos explicados pelo plano)"
}

# ---------------------------------------------------------------- 2b. RESTORESELFTEST (imagem, sem LIVE)
# Contraprova objetiva, NA MESMA IMAGEM (17.6.1.147), do mecanismo exato do Extract/Load:
# pg_dump data-only --enable-row-security --disable-triggers sob papel SEM BYPASSRLS (--role),
# restauração como supabase_admin, e comportamento de RLS/políticas/triggers/FK no destino.
# Usa bancos e papel descartáveis (b12_rt_*); não toca o banco postgres nem o LIVE.
function Step-RestoreSelfTest {
    $ins = Invoke-NativeQuiet { docker container inspect $Container }
    if ($ins.rc -ne 0) { Fail "container $Container ausente — rodar -Step Setup" }
    if ((Assert-ContainerConfig $ins.out) -ne 'running') { Fail "container $Container não está running" }
    Write-WorkText 'sql\run\rt_src.sql' @'
CREATE SCHEMA rt;
CREATE TABLE rt.item (id int PRIMARY KEY, v text NOT NULL, updated_at timestamptz NOT NULL DEFAULT '2000-01-01 00:00:00+00');
CREATE TABLE rt.tag (id int PRIMARY KEY, item_id int NOT NULL REFERENCES rt.item (id), label text NOT NULL);
CREATE FUNCTION rt.mark_fired() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN NEW.v := NEW.v || '_fired'; RETURN NEW; END $f$;
CREATE FUNCTION rt.forbid_update() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'RT_UPDATE_FORBIDDEN'; END $f$;
CREATE TRIGGER trg_item_mark BEFORE INSERT ON rt.item FOR EACH ROW EXECUTE FUNCTION rt.mark_fired();
CREATE TRIGGER trg_tag_forbid BEFORE UPDATE ON rt.tag FOR EACH ROW EXECUTE FUNCTION rt.forbid_update();
ALTER TABLE rt.item ENABLE ROW LEVEL SECURITY;
ALTER TABLE rt.tag  ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_admin ON rt.item FOR SELECT TO public USING (false);
CREATE POLICY p_admin ON rt.tag  FOR SELECT TO public USING (false);
CREATE POLICY b12_rt_ro_select ON rt.item FOR SELECT TO b12_rt_ro USING (true);
CREATE POLICY b12_rt_ro_select ON rt.tag  FOR SELECT TO b12_rt_ro USING (true);
GRANT USAGE ON SCHEMA rt TO b12_rt_ro;
GRANT SELECT ON rt.item, rt.tag TO b12_rt_ro;
INSERT INTO rt.item (id, v) SELECT g, 'v' || g FROM generate_series(1, 500) g;   -- trigger dispara na origem: v = 'vN_fired'
INSERT INTO rt.tag SELECT g, g, 'l' || g FROM generate_series(1, 500) g;
'@
    # estado comparável origem × destino (conteúdo, RLS, políticas, triggers); 'double_fired' > 0 ⇒ trigger disparou na carga
    Write-WorkText 'sql\run\rt_state.sql' @'
SELECT jsonb_build_object(
  'item_n', (SELECT count(*) FROM rt.item), 'item_md5', (SELECT md5(string_agg(id || ':' || v || ':' || updated_at, '|' ORDER BY id)) FROM rt.item),
  'tag_n',  (SELECT count(*) FROM rt.tag),  'tag_md5',  (SELECT md5(string_agg(id || ':' || item_id || ':' || label, '|' ORDER BY id)) FROM rt.tag),
  'double_fired', (SELECT count(*) FROM rt.item WHERE v LIKE '%_fired_fired'),
  'rls', (SELECT string_agg(relname || ':' || relrowsecurity || ':' || relforcerowsecurity, ',' ORDER BY relname) FROM pg_class WHERE relnamespace = 'rt'::regnamespace AND relkind = 'r'),
  -- ordem determinística por (tabela, política); definição completa: comando, permissividade, papéis, USING, WITH CHECK
  'policies', (SELECT md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || permissive || ':' || array_to_string(roles, '|')
                                     || ':' || COALESCE(qual, '') || ':' || COALESCE(with_check, ''), E'\n' ORDER BY tablename, policyname))
                 FROM pg_policies WHERE schemaname = 'rt'),
  'policies_list', (SELECT jsonb_agg(jsonb_build_array(tablename, policyname, cmd, permissive, roles, qual, with_check) ORDER BY tablename, policyname)
                      FROM pg_policies WHERE schemaname = 'rt'),
  'triggers', (SELECT string_agg(tgname || ':' || tgenabled::text, ',' ORDER BY tgname) FROM pg_trigger WHERE tgrelid IN ('rt.item'::regclass, 'rt.tag'::regclass) AND NOT tgisinternal),
  'grants_ro', (SELECT has_table_privilege('b12_rt_ro', 'rt.item', 'SELECT') AND has_table_privilege('b12_rt_ro', 'rt.tag', 'SELECT')));
'@
    Write-WorkText 'sql\run\rt_behavior.sql' @'
BEGIN;
CREATE ROLE b12_rt_other NOLOGIN NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA rt TO b12_rt_other;
GRANT SELECT ON rt.item TO b12_rt_other;
DO $b$
DECLARE n bigint; ok boolean;
BEGIN
    IF current_setting('session_replication_role') <> 'origin' THEN RAISE EXCEPTION 'T0 FAIL session_replication_role=%', current_setting('session_replication_role'); END IF;
    -- B1 RLS aplicada: papel com SELECT mas só a política negadora vê 0 linhas
    SET LOCAL ROLE b12_rt_other; SELECT count(*) INTO n FROM rt.item; RESET ROLE;
    IF n <> 0 THEN RAISE EXCEPTION 'B1 FAIL (RLS não aplicada): %', n; END IF;
    -- B2 política restaurada: b12_rt_ro (sem BYPASSRLS) vê todas as linhas
    SET LOCAL ROLE b12_rt_ro; SELECT count(*) INTO n FROM rt.item; RESET ROLE;
    IF n <> 500 THEN RAISE EXCEPTION 'B2 FAIL (política não restaurada): %', n; END IF;
    -- B3 row_security=off sob papel sem bypass ⇒ ERRO (nunca filtragem silenciosa)
    ok := false;
    BEGIN
        SET LOCAL row_security = off; SET LOCAL ROLE b12_rt_other; PERFORM count(*) FROM rt.item;
    EXCEPTION WHEN insufficient_privilege THEN ok := true;
    END;
    RESET ROLE;
    IF NOT ok THEN RAISE EXCEPTION 'B3 FAIL (row_security=off não recusou)'; END IF;
    -- T1 trigger BEFORE INSERT reativado após a carga
    INSERT INTO rt.item (id, v) VALUES (100001, 'x');
    SELECT count(*) INTO n FROM rt.item WHERE id = 100001 AND v = 'x_fired';
    IF n <> 1 THEN RAISE EXCEPTION 'T1 FAIL (trigger de INSERT não disparou)'; END IF;
    -- T2 trigger-guarda BEFORE UPDATE reativado
    ok := false;
    BEGIN UPDATE rt.tag SET label = label WHERE id = 1;
    EXCEPTION WHEN raise_exception THEN ok := (SQLERRM = 'RT_UPDATE_FORBIDDEN');
    END;
    IF NOT ok THEN RAISE EXCEPTION 'T2 FAIL (guarda de UPDATE não disparou)'; END IF;
    -- T3 FK válida após a carga
    ok := false;
    BEGIN INSERT INTO rt.tag VALUES (999999, 999999, 'z');
    EXCEPTION WHEN foreign_key_violation THEN ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'T3 FAIL (FK não aplicada)'; END IF;
    RAISE NOTICE 'RT_BEHAVIOR_OK';
END
$b$;
ROLLBACK;
'@
    $body = @'
PSQL_S='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d b12_rt_src'
PSQL_D='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d b12_rt_dst'
DUMP='pg_dump -h 127.0.0.1 -p 5432 -U supabase_admin -d b12_rt_src'
mkdir -p /work/out/rt && rm -f /work/out/rt/*
cleanup() {
  $PSQL_A -q -c 'DROP DATABASE IF EXISTS b12_rt_src WITH (FORCE)' -c 'DROP DATABASE IF EXISTS b12_rt_dst WITH (FORCE)' \
          -c 'DROP ROLE IF EXISTS b12_rt_other' -c 'DROP ROLE IF EXISTS b12_rt_ro' >> /work/out/rt/cleanup.log 2>&1
}
cleanup
trap cleanup EXIT
$PSQL_A -v ON_ERROR_STOP=1 -At -c 'SELECT version()' > /work/out/rt/version.txt 2>&1 || exit 1
$PSQL_A -v ON_ERROR_STOP=1 -q -c 'CREATE ROLE b12_rt_ro NOLOGIN NOINHERIT NOBYPASSRLS' -c 'CREATE DATABASE b12_rt_src' -c 'CREATE DATABASE b12_rt_dst' > /work/out/rt/pre.log 2>&1 || exit 2
$PSQL_S -v ON_ERROR_STOP=1 -q -f /work/sql/run/rt_src.sql > /work/out/rt/src.log 2>&1 || exit 3
$DUMP --schema-only -n rt -f /work/out/rt/schema.sql > /work/out/rt/dump_schema.log 2>&1 || exit 4
# NEG: sem --enable-row-security, papel sem BYPASSRLS tem de ser RECUSADO (não pode exportar em silêncio)
$DUMP --data-only --role=b12_rt_ro -n rt -f /work/out/rt/data_neg.sql > /work/out/rt/dump_neg.log 2>&1; echo "rc_neg=$?" >> /work/out/rt/dump_neg.log
# POS: mecanismo do Extract (RLS ligada no COPY + triggers desativados na carga)
$DUMP --data-only --disable-triggers --enable-row-security --role=b12_rt_ro -n rt -f /work/out/rt/data.sql > /work/out/rt/dump_data.log 2>&1 || exit 5
$PSQL_D -v ON_ERROR_STOP=1 -q -f /work/out/rt/schema.sql > /work/out/rt/load_schema.log 2>&1 || exit 6
$PSQL_D -v ON_ERROR_STOP=1 -q -f /work/out/rt/data.sql > /work/out/rt/load_data.log 2>&1 || exit 7
# Fases 8–10: stdout (-o) e stderr (.err) em arquivos SEPARADOS; em falha, registra fase + comando lógico
# (sem credenciais: a senha local só existe em PGPASSWORD do docker exec, nunca na linha registrada).
fail_phase() { printf '%s|%s\n' "$1" "$2" > /work/out/rt/failed_phase.txt; exit "$1"; }
$PSQL_S -v ON_ERROR_STOP=1 -At -f /work/sql/run/rt_state.sql -o /work/out/rt/state_src.json 2> /work/out/rt/state_src.err \
  || fail_phase 8 'psql -U supabase_admin -d b12_rt_src -At -f rt_state.sql -o state_src.json (estado da ORIGEM)'
$PSQL_D -v ON_ERROR_STOP=1 -At -f /work/sql/run/rt_state.sql -o /work/out/rt/state_dst.json 2> /work/out/rt/state_dst.err \
  || fail_phase 9 'psql -U supabase_admin -d b12_rt_dst -At -f rt_state.sql -o state_dst.json (estado do DESTINO restaurado)'
$PSQL_D -v ON_ERROR_STOP=1 -f /work/sql/run/rt_behavior.sql > /work/out/rt/behavior.log 2> /work/out/rt/behavior.err \
  || fail_phase 10 'psql -U supabase_admin -d b12_rt_dst -f rt_behavior.sql (RLS/triggers/FK no destino)'
exit 0
'@
    $rc = InC 'restore_selftest' $body
    $d = 'out\rt\'
    $r = [ordered]@{ rc = $rc; image = $Image; server = (Read-WorkText ($d + 'version.txt')).Trim() }
    if ($rc -ne 0) {
        $r.pass = $false
        $fp = Join-Path $WorkDir ($d + 'failed_phase.txt')
        if (Test-Path -LiteralPath $fp) { $r.failed_phase = (Read-WorkText ($d + 'failed_phase.txt')).Trim() }
        $errName = @{ 8 = 'state_src.err'; 9 = 'state_dst.err'; 10 = 'behavior.err' }[[int]$rc]
        if ($errName -and (Test-Path -LiteralPath (Join-Path $WorkDir ($d + $errName)))) { $r.stderr = (Read-WorkText ($d + $errName)).Trim() }
        $r | ConvertTo-Json | Tee-Object -FilePath (Join-Path $WorkDir 'out\restore_selftest.json')
        Fail "RESTORESELFTEST falhou na fase $rc ($($r.failed_phase)) — stderr: $($r.stderr)"
    }
    $data = Read-WorkText ($d + 'data.sql'); $neg = Read-WorkText ($d + 'dump_neg.log')
    $src = (Read-WorkText ($d + 'state_src.json')).Trim(); $dst = (Read-WorkText ($d + 'state_dst.json')).Trim()
    $r.S0_image_pg17          = ($r.server -match '^PostgreSQL 17\.6\b')
    $r.S1_neg_refused         = ($neg -notmatch 'rc_neg=0') -and ($neg -match 'row-level security')
    $r.S2_dump_rls_header     = ($data -match '(?m)^SET row_security = on;')
    $r.S3_disable_enable_pair = ([regex]::Matches($data, '(?m)^ALTER TABLE rt\.\S+ DISABLE TRIGGER ALL;').Count -eq 2) -and ([regex]::Matches($data, '(?m)^ALTER TABLE rt\.\S+ ENABLE TRIGGER ALL;').Count -eq 2)
    $r.S4_state_identical     = ($src -eq $dst) -and ((ConvertFrom-Json $dst).double_fired -eq 0) -and ((ConvertFrom-Json $dst).item_n -eq 500)
    # RAISE NOTICE sai no stderr do psql (behavior.err desde a separação de stdout/stderr); rc 0 já prova ausência de exceção
    $r.S5_behavior            = ((Read-WorkText ($d + 'behavior.err')) -match 'NOTICE:\s+RT_BEHAVIOR_OK')
    $r.state_src = $src; $r.state_dst = $dst
    $r.pass = $r.S0_image_pg17 -and $r.S1_neg_refused -and $r.S2_dump_rls_header -and $r.S3_disable_enable_pair -and $r.S4_state_identical -and $r.S5_behavior
    $r | ConvertTo-Json | Tee-Object -FilePath (Join-Path $WorkDir 'out\restore_selftest.json')
    if (-not $r.pass) { Fail 'RESTORESELFTEST reprovado (out\restore_selftest.json)' }
    Say 'RESTORESELFTEST: PASS (17.6: dump sob RLS sem BYPASSRLS, restauração preserva conteúdo/RLS/políticas; triggers não disparam na carga e voltam ativos; FK válida)'
}

# ---------------------------------------------------------------- 4b. RESTOREPROOF (dados reais, pós-Load)
function Step-RestoreProof {
    $data = Read-WorkText 'dump\data.sql'
    $nDis = [regex]::Matches($data, '(?m)^ALTER TABLE public\.\S+ DISABLE TRIGGER ALL;').Count
    $nEna = [regex]::Matches($data, '(?m)^ALTER TABLE public\.\S+ ENABLE TRIGGER ALL;').Count
    $L = JsonOut 'out\fp_live.json'
    $nTrgLive = @($L.d_fp_core.triggers.PSObject.Properties).Count
    $inList = ($DataTables | ForEach-Object { "'$_'" }) -join ','
    Write-WorkText 'sql\run\rp_behavior.sql' (@'
BEGIN;
CREATE ROLE b12_rp_other NOLOGIN NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA public TO b12_rp_other;
GRANT SELECT ON public.card_set_external_reference TO b12_rp_other;
DO $b$
DECLARE t text; n_own bigint; n_ro bigint; bad text := ''; ok boolean; v_ts timestamptz;
BEGIN
    IF current_setting('session_replication_role') <> 'origin' THEN RAISE EXCEPTION 'T0 FAIL session_replication_role'; END IF;
    -- T0 todos os triggers de usuário das 22 ativos ('O') e na mesma quantidade do LIVE
    SELECT count(*) INTO n_own FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid
     WHERE c.relnamespace = 'public'::regnamespace AND c.relname IN (__IN__) AND NOT tg.tgisinternal AND tg.tgenabled = 'O';
    IF n_own <> __NTRG__ THEN RAISE EXCEPTION 'T0 FAIL triggers ativos % <> %', n_own, __NTRG__; END IF;
    -- R1 políticas b12 restauradas e efetivas: b12_export_ro (NOLOGIN local, sem BYPASSRLS) vê o mesmo que o dono nas 22
    FOREACH t IN ARRAY ARRAY[__IN__] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n_own;
        SET LOCAL ROLE b12_export_ro; EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n_ro; RESET ROLE;
        IF n_ro IS DISTINCT FROM n_own OR n_own = 0 THEN bad := bad || format(' %s(%s/%s)', t, n_ro, n_own); END IF;
    END LOOP;
    IF bad <> '' THEN RAISE EXCEPTION 'R1 FAIL%', bad; END IF;
    -- R2 RLS aplicada: papel com SELECT e sem política própria vê 0 em card_set_external_reference
    SET LOCAL ROLE b12_rp_other; SELECT count(*) INTO n_ro FROM public.card_set_external_reference; RESET ROLE;
    IF n_ro <> 0 THEN RAISE EXCEPTION 'R2 FAIL (RLS não aplicada): %', n_ro; END IF;
    -- R3 row_security=off sob papel sem bypass ⇒ erro
    ok := false;
    BEGIN SET LOCAL row_security = off; SET LOCAL ROLE b12_rp_other; PERFORM count(*) FROM public.card_set_external_reference;
    EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
    RESET ROLE;
    IF NOT ok THEN RAISE EXCEPTION 'R3 FAIL'; END IF;
    -- T1 set_updated_at dispara (game)
    UPDATE public.game SET updated_at = '2000-01-01 00:00:00+00' WHERE ctid = (SELECT ctid FROM public.game LIMIT 1) RETURNING updated_at INTO v_ts;
    IF v_ts IS DISTINCT FROM CURRENT_TIMESTAMP THEN RAISE EXCEPTION 'T1 FAIL (set_updated_at não disparou): %', v_ts; END IF;
    -- T2 guarda de composição dispara (card_printing_profile_trait)
    ok := false;
    BEGIN UPDATE public.card_printing_profile_trait SET profile_id = profile_id WHERE ctid = (SELECT ctid FROM public.card_printing_profile_trait LIMIT 1);
    EXCEPTION WHEN raise_exception THEN ok := (SQLERRM LIKE 'CARD_PRINTING_PROFILE_TRAIT_UPDATE_FORBIDDEN%'); END;
    IF NOT ok THEN RAISE EXCEPTION 'T2 FAIL (guarda não disparou)'; END IF;
    RAISE NOTICE 'RP_BEHAVIOR_OK';
END
$b$;
ROLLBACK;
'@).Replace('__IN__', $inList).Replace('__NTRG__', "$nTrgLive")
    $rc = InC 'restore_proof' '$PSQL_A -v ON_ERROR_STOP=1 -f /work/sql/run/rp_behavior.sql > /work/out/restore_proof.log 2>&1'
    $r = [ordered]@{ rc = $rc; disable_trigger_all = $nDis; enable_trigger_all = $nEna; live_triggers = $nTrgLive }
    $r.D1_disable_enable_22 = ($nDis -eq $DataTables.Count) -and ($nEna -eq $DataTables.Count)
    $r.D2_behavior          = ($rc -eq 0) -and ((Read-WorkText 'out\restore_proof.log') -match 'RP_BEHAVIOR_OK')
    $r.pass = $r.D1_disable_enable_22 -and $r.D2_behavior
    $r | ConvertTo-Json | Tee-Object -FilePath (Join-Path $WorkDir 'out\restore_proof.json')
    if (-not $r.pass) { Fail 'RESTOREPROOF reprovado (out\restore_proof.json / out\restore_proof.log)' }
    Say "RESTOREPROOF: PASS (22 tabelas: RLS/políticas efetivas, $nTrgLive triggers ativos e disparando, carga sem disparo)"
}

# ---------------------------------------------------------------- 4c. CHECK IN-LIST: CONTRAPROVA E REPARO LOCAL
function Q([string]$s) { return "'" + $s.Replace("'", "''") + "'" }
function Get-FpConMd5([string]$def) {   # mesma fórmula do parity_fingerprint (con): contype:deferrable:deferred:def
    $b = [Text.Encoding]::UTF8.GetBytes("c:false:false:$def")
    return (-join ([Security.Cryptography.MD5]::Create().ComputeHash($b) | ForEach-Object { $_.ToString('x2') }))
}
# Estado das duas constraints na réplica (somente leitura, search_path='' e UTC) + valores reais das colunas
function Get-CkLocalState([string]$tag) {
    $sel = ($CkPairs | ForEach-Object {
        "SELECT $(Q $_.con) AS con, pg_get_constraintdef(c.oid) AS def, c.contype::text AS contype, c.condeferrable AS deferrable, c.condeferred AS deferred," +
        " c.convalidated AS validated, c.connoinherit AS noinherit, c.conislocal AS islocal, a.attname::text AS col, format_type(a.atttypid, a.atttypmod) AS coltype," +
        " md5(c.conbin::text) AS conbin_md5, (SELECT jsonb_agg(DISTINCT x.$($_.col)) FROM public.$($_.rel) x) AS real_values, (SELECT count(*) FROM public.$($_.rel)) AS n_rows" +
        " FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]" +
        " WHERE c.conrelid = 'public.$($_.rel)'::regclass AND c.conname = $(Q $_.con) AND cardinality(c.conkey) = 1" }) -join "`nUNION ALL`n"
    Write-WorkText "sql\run\ck_state_$tag.sql" "BEGIN TRANSACTION READ ONLY;`nSET LOCAL search_path = '';`nSET LOCAL TimeZone = 'UTC';`nSELECT jsonb_agg(to_jsonb(s) ORDER BY s.con) FROM (`n$sel`n) s;`nCOMMIT;`n"
    if (InC "ck_state_$tag" "`$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/run/ck_state_$tag.sql -o /work/out/ck_state_$tag.json || exit 1") { Fail "leitura do estado das constraints ($tag) falhou" }
    $st = @{}; foreach ($o in @((JsonOut "out\ck_state_$tag.json") | ForEach-Object { $_ })) { $st[$o.con] = $o }
    if ($st.Count -ne $CkPairs.Count) { Fail "constraints esperadas não encontradas na réplica ($tag)" }
    return $st
}
# CKPROOF — não altera o banco da réplica: lê dump e réplica e reproduz o fenômeno num banco descartável.
#  K1 dump = forma LIVE (texto exato, 1x) · K2 réplica = forma local pinada, validada, mesmos atributos
#  K3 na imagem: CHECK (col IN (…)) rende a forma LIVE; recarregar o TEXTO LIVE rende a forma local
#  K4 semântica: tabela-verdade idêntica (valores permitidos, variantes de caixa/espaço, '', NULL, estranho
#     e TODOS os valores reais da coluna) · K5 hashes do fingerprint reproduzidos pelas duas formas
function Step-CkProof {
    $dump = Read-WorkText 'dump\schema.sql'
    $st = Get-CkLocalState 'proof'
    $ddl = @(); $tt = @(); $i = 0
    foreach ($p in $CkPairs) {
        $i++; $s = $st[$p.con]
        $ddl += "CREATE TABLE public.ck_a$i ($($p.col) $($s.coltype), CONSTRAINT ck CHECK ($($p.col) IN ($(($p.vals | ForEach-Object { Q $_ }) -join ', '))));"
        $ddl += "CREATE TABLE public.ck_b$i ($($p.col) $($s.coltype), CONSTRAINT ck $($p.live_def));"
        $vec = @($p.vals) + @($p.vals | ForEach-Object { $_.ToLower(); $_.ToUpper(); "$_ "; " $_" }) + @('', 'x', 'NULL') + @($s.real_values | Where-Object { $null -ne $_ })
        # Select-Object -Unique diferencia caixa (Sort-Object -Unique fundiria 'stamp' e 'STAMP')
        $arr = (@($vec | Select-Object -Unique | ForEach-Object { Q $_ }) + @('NULL')) -join ', '
        $tt += @"
DO `$tt`$ DECLARE v text; ra text; rb text; BEGIN
  FOREACH v IN ARRAY ARRAY[$arr]::text[] LOOP
    BEGIN INSERT INTO public.ck_a$i VALUES (v); ra := 'OK'; EXCEPTION WHEN check_violation THEN ra := 'CHECK'; WHEN string_data_right_truncation THEN ra := 'LEN'; END;
    BEGIN INSERT INTO public.ck_b$i VALUES (v); rb := 'OK'; EXCEPTION WHEN check_violation THEN rb := 'CHECK'; WHEN string_data_right_truncation THEN rb := 'LEN'; END;
    INSERT INTO public.ck_tt VALUES ($i, v, ra, rb);
  END LOOP; END `$tt`$;
"@
    }
    Write-WorkText 'sql\run\ckproof.sql' (@("SET search_path = '';", 'CREATE TABLE public.ck_tt (pair int, v text, ra text, rb text);') + $ddl + $tt + @(
        "SELECT jsonb_build_object('defs', (SELECT jsonb_object_agg(c.conrelid::regclass::text, pg_get_constraintdef(c.oid)) FROM pg_constraint c WHERE c.conname = 'ck'),",
        "  'tt_rows', (SELECT count(*) FROM public.ck_tt), 'tt_mismatch', (SELECT count(*) FROM public.ck_tt WHERE ra IS DISTINCT FROM rb),",
        "  'tt', (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.pair, t.v NULLS FIRST) FROM public.ck_tt t));") -join "`n")
    $body = @'
PSQL_V='psql -X -h 127.0.0.1 -p 5432 -U supabase_admin -d b12_ckp'
cleanup() { $PSQL_A -q -c 'DROP DATABASE IF EXISTS b12_ckp WITH (FORCE)' > /work/out/ckp_cleanup.log 2>&1; }
cleanup
trap cleanup EXIT
$PSQL_A -v ON_ERROR_STOP=1 -q -c 'CREATE DATABASE b12_ckp' > /work/out/ckp_pre.log 2>&1 || exit 1
$PSQL_V -v ON_ERROR_STOP=1 -q -At -f /work/sql/run/ckproof.sql -o /work/out/ckproof_raw.json 2> /work/out/ckproof.err || exit 2
exit 0
'@
    if (InC 'ckproof' $body) { Fail 'CKPROOF: execução no banco descartável falhou (out\ckproof.err)' }
    $x = JsonOut 'out\ckproof_raw.json'
    $res = [ordered]@{}; $i = 0; $all = $true
    foreach ($p in $CkPairs) {
        $i++; $s = $st[$p.con]
        $defA = $x.defs."public.ck_a$i"; $defB = $x.defs."public.ck_b$i"
        $rows = @($x.tt | Where-Object { $_.pair -eq $i })
        $k = [ordered]@{
            K1_dump_is_live_form = (([regex]::Matches($dump, [regex]::Escape("CONSTRAINT $($p.con) $($p.live_def)"))).Count -eq 1) -and (-not $dump.Contains($p.local_def))
            K2_local_state       = ($s.def -ceq $p.local_def) -and ((Get-FpConMd5 $s.def) -eq $p.local_md5) -and $s.validated -and ($s.contype -eq 'c') -and
                                   (-not $s.deferrable) -and (-not $s.deferred) -and (-not $s.noinherit) -and $s.islocal -and ($s.col -eq $p.col)
            K3_reproduced        = ($defA -ceq $p.live_def) -and ($defB -ceq $p.local_def)
            K4_same_truth_table  = ($rows.Count -ge ($p.vals.Count + 3)) -and (@($rows | Where-Object { $_.ra -ne $_.rb }).Count -eq 0) -and
                                   (@($rows | Where-Object { $p.vals -ccontains $_.v -and $_.ra -ne 'OK' }).Count -eq 0) -and
                                   (@($rows | Where-Object { $_.v -eq 'x' -and $_.ra -eq 'CHECK' }).Count -eq 1) -and
                                   (@($rows | Where-Object { $null -eq $_.v -and $_.ra -eq 'OK' }).Count -eq 1) -and
                                   (@($s.real_values | Where-Object { $null -ne $_ -and $p.vals -cnotcontains $_ }).Count -eq 0)
            K5_hashes            = ((Get-FpConMd5 $defA) -eq $p.live_md5) -and ((Get-FpConMd5 $defB) -eq $p.local_md5)
        }
        if (@($k.Values | Where-Object { $_ -ne $true }).Count) { $all = $false }
        $res[$p.con] = [ordered]@{ gates = $k; live_def = $p.live_def; local_def = $s.def; image_in_list_def = $defA; image_reloaded_def = $defB
                                   conbin_md5_local = $s.conbin_md5; n_rows = $s.n_rows; real_values = $s.real_values; truth_table = $rows }
    }
    $out = [ordered]@{ pass = $all; dump_md5 = (Md5File (Join-Path $WorkDir 'dump\schema.sql')); pairs = $res
                       verdict = $(if ($all) { 'RENDERING_ONLY: forma de expressão diferente (ArrayCoerceExpr × cast por elemento), mesma regra' } else { 'NOT_PROVEN' }) }
    $out | ConvertTo-Json -Depth 7 | Tee-Object -FilePath (Join-Path $WorkDir 'out\ck_proof.json') | Out-Null
    if (-not $all) { Fail 'CKPROOF reprovado — equivalência NÃO demonstrada; não reparar (out\ck_proof.json)' }
    Say 'CKPROOF: PASS (dump = LIVE; réplica = recarga do texto LIVE; mesma tabela-verdade; hashes reproduzidos)'
}
# CKREPAIR — SÓ na réplica, SÓ após CkProof PASS com o mesmo dump. TODAS as constraints numa ÚNICA transação:
# confere a forma local pinada, recria com a lista IN original (DROP + ADD na MESMA transação, com
# AccessExclusive até o COMMIT: ninguém vê a tabela sem a regra; ADD valida todas as linhas) e exige a forma/hash LIVE exatos,
# senão ROLLBACK. Já na forma LIVE ⇒ nada a fazer (idempotente).
function Step-CkRepair {
    $pf = Join-Path $WorkDir 'out\ck_proof.json'
    if (-not (Test-Path -LiteralPath $pf)) { Fail 'CKREPAIR exige -Step CkProof PASS antes' }
    $pr = JsonOut 'out\ck_proof.json'
    if ($pr.pass -ne $true -or $pr.dump_md5 -ne (Md5File (Join-Path $WorkDir 'dump\schema.sql'))) { Fail 'CKREPAIR: CkProof ausente/reprovado ou de outro dump' }
    $before = Get-CkLocalState 'before'
    $stmts = @()
    foreach ($p in $CkPairs) {
        $d = $before[$p.con].def
        if ($d -ceq $p.live_def) { continue }
        if ($d -cne $p.local_def) { Fail "CKREPAIR: $($p.con) em forma inesperada — nada alterado: $d" }
        $stmts += @"
DO `$g`$ BEGIN
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'public.$($p.rel)'::regclass AND conname = $(Q $p.con)) IS DISTINCT FROM $(Q $p.local_def) THEN
    RAISE EXCEPTION 'CKREPAIR_PRE %', $(Q $p.con); END IF; END `$g`$;
ALTER TABLE public.$($p.rel) DROP CONSTRAINT $($p.con);
ALTER TABLE public.$($p.rel) ADD CONSTRAINT $($p.con) CHECK ($($p.col) IN ($(($p.vals | ForEach-Object { Q $_ }) -join ', ')));
DO `$g`$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.$($p.rel)'::regclass AND c.conname = $(Q $p.con)
                   AND c.contype = 'c' AND c.convalidated AND NOT c.condeferrable AND NOT c.connoinherit
                   AND pg_get_constraintdef(c.oid) = $(Q $p.live_def)
                   AND md5(c.contype::text || ':' || c.condeferrable || ':' || c.condeferred || ':' || pg_get_constraintdef(c.oid)) = $(Q $p.live_md5)) THEN
    RAISE EXCEPTION 'CKREPAIR_POST %', $(Q $p.con); END IF; END `$g`$;
"@
    }
    if ($stmts.Count) {
        # UMA transação para todas: qualquer falha (pré, ALTER/validação, pós) ⇒ ON_ERROR_STOP encerra o psql
        # com a transação aberta ⇒ ROLLBACK integral (nenhuma constraint fica parcialmente reparada)
        Write-WorkText 'sql\run\ckrepair.sql' ((@('BEGIN;', "SET LOCAL search_path = '';", "SET LOCAL lock_timeout = '5s';") + $stmts + @('COMMIT;')) -join "`n")
        if (InC 'ckrepair' '$PSQL_P -v ON_ERROR_STOP=1 -f /work/sql/run/ckrepair.sql > /work/out/ckrepair.log 2>&1 || exit 1') { Fail 'CKREPAIR falhou e foi desfeito por transação (out\ckrepair.log)' }
    }
    $after = Get-CkLocalState 'after'
    $r = [ordered]@{ repaired = $stmts.Count; pairs = [ordered]@{} }; $ok = $true
    foreach ($p in $CkPairs) {
        $a = $after[$p.con]; $b = $before[$p.con]
        $g = ($a.def -ceq $p.live_def) -and ((Get-FpConMd5 $a.def) -eq $p.live_md5) -and $a.validated -and ($a.n_rows -eq $b.n_rows) -and
             ((@($a.real_values) | ConvertTo-Json -Compress) -eq (@($b.real_values) | ConvertTo-Json -Compress))
        if (-not $g) { $ok = $false }
        $r.pairs[$p.con] = [ordered]@{ pass = $g; def_before = $b.def; def_after = $a.def; md5_after = (Get-FpConMd5 $a.def); n_rows = $a.n_rows }
    }
    $r.pass = $ok
    $r | ConvertTo-Json -Depth 5 | Tee-Object -FilePath (Join-Path $WorkDir 'out\ck_repair.json')
    if (-not $ok) { Fail 'CKREPAIR: estado final diverge da forma LIVE (out\ck_repair.json)' }
    Say "CKREPAIR: PASS ($($stmts.Count) recriada(s) na forma LIVE; dados intactos) — reexecutar -Step Parity"
}

# ---------------------------------------------------------------- 5. PARITY
function Compare-Section($a, $b, [string]$name) {
    $diff = @(); $ka = @(); $kb = @()
    if ($a) { $ka = @($a.PSObject.Properties.Name) }; if ($b) { $kb = @($b.PSObject.Properties.Name) }
    foreach ($k in (@($ka) + @($kb) | Sort-Object -Unique)) {
        $va = if ($ka -contains $k) { $a.$k | ConvertTo-Json -Depth 6 -Compress } else { '<ausente>' }
        $vb = if ($kb -contains $k) { $b.$k | ConvertTo-Json -Depth 6 -Compress } else { '<ausente>' }
        if ($va -ne $vb) { $diff += "$name.$k LIVE=$va LOCAL=$vb" }
    }
    return $diff
}
function Step-Parity {
    Build-LocalControls
    # dependências resolvidas ANTES de executar qualquer controle (mensagem específica, não erro do psql)
    $deps = Test-SqlDependencies 'parity' @('parity_fingerprint.sql','2830H_E12P_precheck_section_b.sql','2830H_E13P_precheck_section_m.sql','L_E00_precheck_inventory.sql') `
                                          @('2830H_E00_precheck_inventory.sql')
    $body = @'
$PSQL_P -q -At -v ON_ERROR_STOP=1 -c "SET search_path = ''" -c 'SET TimeZone = $$UTC$$' -f /work/sql/parity_fingerprint.sql -o /work/out/fp_local.json 2> /work/out/fp_local.err || exit 1
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/2830H_E12P_precheck_section_b.sql -o /work/out/parity_E12P.json 2> /work/out/parity_E12P.err || exit 2
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/2830H_E13P_precheck_section_m.sql -o /work/out/parity_E13P.json 2> /work/out/parity_E13P.err || exit 3
$PSQL_P -q -At -v ON_ERROR_STOP=1 -f /work/sql/L_E00_precheck_inventory.sql -o /work/out/parity_E00.json 2> /work/out/parity_E00.err || exit 4
'@
    $rc = InC 'parity' $body
    if ($rc) { Fail "execução do fingerprint/prechecks locais falhou (código $rc; ver out\*.err)" }
    $L = JsonOut 'out\fp_live.json'; $C = JsonOut 'out\fp_local.json'
    $g = [ordered]@{}
    $g.P1_pg_version        = ($L.d_env.server_version -eq $C.d_env.server_version)
    $g.P2_live_no_drift     = ($L.d_fp_core_md5 -eq $LiveFpRef)
    $g.P3_core_identical    = ($L.d_fp_core_md5 -eq $C.d_fp_core_md5)  # funções, colunas, índices, constraints, triggers, dono/RLS, policies, conteúdo, distribuições, universos M1/M2/M3
    $g.P4_planner_settings  = (@($ParityEnvKeys | Where-Object { $L.d_env.$_ -ne $C.d_env.$_ })).Count -eq 0
    $g.P5_E12P_gate_pass    = ((JsonOut 'out\parity_E12P.json').gate_pass -eq $true)
    $g.P5_E13P_gate_pass    = ((JsonOut 'out\parity_E13P.json').gate_pass -eq $true)
    # P6 — viabilidade do E00 na réplica: nenhum gate falso fora da lista ambiental fixada
    $e00 = JsonOut 'out\parity_E00.json'
    $e00False = @($e00.PSObject.Properties | Where-Object { $_.Name -like 'g_*' -and $_.Value -ne $true } | ForEach-Object { $_.Name })
    $g.P6_E00_viable        = (@($e00False | Where-Object { $E00EnvGatesOnly -notcontains $_ })).Count -eq 0
    # P7 — erro de restauração que cite objeto do escopo é bloqueante; os demais são ambientais
    $scoped = @($DataTables) + @($L.d_fp_core.functions.PSObject.Properties.Name | ForEach-Object { ($_ -split '\(')[0].Split('.')[-1] }) + @('internal')
    $errs = @((Read-WorkText 'out\load_schema_errors.txt') -split "`n" | Where-Object { $_ })
    $blockingErr = @($errs | Where-Object { $e = $_; @($scoped | Where-Object { $e -match ('\b' + [regex]::Escape($_) + '\b') }).Count -gt 0 })
    # e a carga precisa ter passado no LoadAudit (todo erro explicado pelo plano; estado conferido) — fail-closed
    $la = Join-Path $WorkDir 'out\load_audit.json'
    $g.P7_no_scoped_restore_error = ($blockingErr.Count -eq 0) -and (Test-Path -LiteralPath $la) -and ((JsonOut 'out\load_audit.json').pass -eq $true)
    # P8 — restauração com RLS e triggers provada por comportamento (RestoreSelfTest na imagem + RestoreProof nos dados reais)
    $st = Join-Path $WorkDir 'out\restore_selftest.json'; $rp = Join-Path $WorkDir 'out\restore_proof.json'
    $g.P8_restore_rls_triggers = (Test-Path -LiteralPath $st) -and (Test-Path -LiteralPath $rp) -and
                                 ((JsonOut 'out\restore_selftest.json').pass -eq $true) -and ((JsonOut 'out\restore_proof.json').pass -eq $true)
    $diff = @()
    if (-not $g.P3_core_identical) {
        foreach ($s in 'functions','columns','indexes','constraints','triggers','ownership','content','distribution') { $diff += Compare-Section $L.d_fp_core.$s $C.d_fp_core.$s $s }
        if ($L.d_fp_core.policies_md5 -ne $C.d_fp_core.policies_md5) { $diff += 'policies_md5 divergente' }
        if ($L.d_fp_core.pg_major -ne $C.d_fp_core.pg_major) { $diff += 'pg_major divergente' }
    }
    $failed = @($g.Keys | Where-Object { $g[$_] -ne $true })
    $res = [ordered]@{ gates = $g; diff = $diff; live_md5 = $L.d_fp_core_md5; local_md5 = $C.d_fp_core_md5
                       live_env = $L.d_env; local_env = $C.d_env
                       e00_false_gates = $e00False; e00_env_allowed = $E00EnvGatesOnly
                       restore_errors_blocking = $blockingErr
                       restore_errors_environmental = @($errs | Where-Object { $blockingErr -notcontains $_ })
                       # três classes, nunca misturadas
                       classification = [ordered]@{
                           scope_equivalence = [ordered]@{ proven = ($g.P1_pg_version -and $g.P2_live_no_drift -and $g.P3_core_identical -and $g.P4_planner_settings)
                                                           fp_core_md5 = $C.d_fp_core_md5; live_fp_ref = $LiveFpRef }
                           environmental_not_reproducible = [ordered]@{
                               e00_gates_false_admitted = @($e00False | Where-Object { $E00EnvGatesOnly -contains $_ })
                               not_executed_local = $NotReplicated
                               local_adaptations = @($LocalAdapt.Keys | ForEach-Object { [ordered]@{ file = $_; from = $LocalAdapt[$_].src; removed_line = $LocalAdapt[$_].line; md5 = $LocalAdapt[$_].md5 } })
                               canonical_external_dependencies = $deps.canonical_external_dependencies }
                           integrity_blocking = [ordered]@{ failed_gates = $failed
                               e00_gates_false_not_admitted = @($e00False | Where-Object { $E00EnvGatesOnly -notcontains $_ })
                               restore_errors = $blockingErr } } }
    $res | ConvertTo-Json -Depth 7 | Tee-Object -FilePath (Join-Path $WorkDir 'out\parity_result.json')
    if ($failed.Count) { Fail "paridade insuficiente — bloqueio real: $($failed -join ', ') (out\parity_result.json)" }
    Say "PARITY: PASS (escopo exportado equivalente; ambiental admitido: $((@($e00False) + @($NotReplicated | ForEach-Object { $_.relation })) -join ', '))"
}

# ---------------------------------------------------------------- 6. P9B
function Step-P9B {
    if (-not ((JsonOut 'out\parity_result.json').gates.PSObject.Properties.Value -notcontains $false)) { Fail 'Parity não está PASS' }
    if ((Md5File (Join-Path $WorkDir 'sql\P9B_M1_M3.sql')) -ne $P9BSliceMd5) { Fail 'recorte P9B M1–M3 alterado' }
    # somente M1/M2/M3 (prefixo byte a byte do arquivo publicado); M4/E15 não é executado nesta fase
    $rc = InC 'p9b' "`$PSQL_P -v ON_ERROR_STOP=1 -c '\timing on' -f /work/sql/P9B_M1_M3.sql > /work/out/p9b.txt 2>&1"
    if ($rc) { Fail 'P9B falhou (out\p9b.txt): classificar erro SQL real × infraestrutura antes de qualquer correção' }
    $t = @([regex]::Matches((Read-WorkText 'out\p9b.txt'), 'Execution Time: ([0-9.]+) ms') | ForEach-Object { [double]$_.Groups[1].Value })
    if ($t.Count -ne 3) { Fail "esperadas 3 medições (M1..M3), obtidas $($t.Count)" }
    $m = [ordered]@{ M1_VREC_ms = $t[0]; M2_V1c_ms = $t[1]; M3_SMREC_ms = $t[2] }
    $m.pass = ($t[0] -lt 60000 -and $t[1] -lt 60000 -and $t[2] -lt 60000)
    $m | ConvertTo-Json | Tee-Object -FilePath (Join-Path $WorkDir 'out\p9b_result.json')
    if (-not $m.pass) { Fail 'P9B >= 60 s — analisar o plano em out\p9b.txt (sem alterar predicados)' }
    Say 'P9B: PASS (M1/M2/M3 < 60 s)'
}

# ---------------------------------------------------------------- 7. ENVELOPES (rodadas locais completas)
function JsonField([string]$outRel, [string]$path) {
    # extrai o campo com o próprio PostgreSQL (texto jsonb canônico; nada é reserializado no PowerShell)
    $body = "E=`$(cat /work/$outRel)`nprintf '%s\n' `"SELECT (:'e'::jsonb) #>> '{$path}';`" | `$PSQL_P -q -At -v ON_ERROR_STOP=1 -v e=`"`$E`" > /work/out/_field.txt || exit 1"
    if (InC 'field' $body) { Fail "extração de $path de $outRel" }
    return (Read-WorkText 'out\_field.txt').TrimEnd("`r", "`n")
}
function Substitute([string]$src, [string]$dst, $map) {
    $s = [IO.File]::ReadAllText((Join-Path $WorkDir "sql\$src"), $Utf8NoBom)
    foreach ($k in $map.Keys) {
        $q = "'$k'"; if (-not $s.Contains($q)) { Fail "marcador $q ausente em $src" }
        $s = $s.Replace($q, "'" + $map[$k].Replace("'", "''") + "'")
    }
    [IO.File]::WriteAllText((Join-Path $WorkDir "sql\run\$dst"), $s, $Utf8NoBom)
}
function RunJson([string]$sqlPath, [string]$out) {
    if (InC "json_$out" "`$PSQL_P -q -At -v ON_ERROR_STOP=1 -f $sqlPath -o /work/out/$out.json 2> /work/out/$out.err || exit 1") { Fail "$sqlPath falhou (out\$out.err)" }
    return (JsonOut "out\$out.json")
}
function Step-Envelopes {
    if (-not (JsonOut 'out\p9b_result.json').pass) { Fail 'P9B não está PASS' }
    Build-LocalControls
    $null = Test-SqlDependencies 'envelopes' @('L_E00_precheck_inventory.sql','L_E99_postcheck_residue.sql','2830H_E98_postcheck_extended_residue.sql',
                                               '2830H_E12P_precheck_section_b.sql','2830H_E12_section_b_backfill_semantic.sql',
                                               '2830H_E13P_precheck_section_m.sql','2830H_E13_section_m_state_machine.sql') `
                                             @('2830H_E00_precheck_inventory.sql','2830H_E99_postcheck_residue.sql')
    $summary = [ordered]@{ not_executed_local = $NotReplicated }
    foreach ($id in $Envelopes.Keys) {
        $e = $Envelopes[$id]; $r = [ordered]@{}
        $e00 = RunJson '/work/sql/L_E00_precheck_inventory.sql' "${id}_E00"
        $false_ = @($e00.PSObject.Properties | Where-Object { $_.Name -like 'g_*' -and $_.Value -ne $true } | ForEach-Object { $_.Name })
        $r.e00_false_gates = $false_
        # única divergência ambiental admitida: identidade de event triggers da imagem local (envelopes não emitem DDL)
        if (@($false_ | Where-Object { $E00EnvGatesOnly -notcontains $_ }).Count) { Fail "$id E00 local com gates falsos: $($false_ -join ',')" }
        $pre = RunJson "/work/sql/$($e.pre)" "${id}_PRE"
        if ($pre.gate_pass -ne $true) { Fail "$id precheck gate_pass=false (out\${id}_PRE.json)" }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        InC "env_$id" "`$PSQL_P -v ON_ERROR_STOP=1 -f /work/sql/$($e.file) > /work/out/${id}_ENVELOPE.txt 2>&1" | Out-Null   # UMA submissão
        $sw.Stop()
        $txt = Read-WorkText "out\${id}_ENVELOPE.txt"
        $m = [regex]::Match($txt, 'H2830_ROLLBACK_PASS: envelope=(\S+) pass=(\d+)/(\d+) casos=(\S+) marker=(\S+) elapsed_ms=(\d+)')
        $c = [regex]::Match($txt, 'line (\d+) at RAISE')
        $r.terminal   = ([regex]::Match($txt, '(?m)^.*H2830_(ROLLBACK_PASS|FAIL).*$')).Value
        $r.context    = $c.Groups[1].Value
        $r.wall_ms    = $sw.ElapsedMilliseconds
        $r.elapsed_ms = $(if ($m.Success) { [int]$m.Groups[6].Value } else { $null })
        $r.pass       = $m.Success -and ([int]$m.Groups[2].Value -eq $e.n) -and ([int]$m.Groups[3].Value -eq $e.n) -and $c.Success -and ([int]$c.Groups[1].Value -eq $e.ctx) -and ([int]$m.Groups[6].Value -lt 120000)
        Substitute 'L_E99_postcheck_residue.sql' "${id}_E99.sql" ([ordered]@{
            '__E00_D_BASELINE__'        = (JsonField "out/${id}_E00.json" 'd_baseline')
            '__E00_D_BASELINE_MD5__'    = (JsonField "out/${id}_E00.json" 'd_baseline_md5')
            '__E00_ROLE_SETTING_ROWS__' = (JsonField "out/${id}_E00.json" 'd_session,db_role_setting_rows') })
        $e99 = RunJson "/work/sql/run/${id}_E99.sql" "${id}_E99"
        $r.e99_gate_pass = $e99.gate_pass; $r.e99_d_diff = $e99.d_diff; $r.e99_d_canon_diff = $e99.d_canon_diff
        if ($e.e98) {
            Substitute '2830H_E98_postcheck_extended_residue.sql' "${id}_E98.sql" ([ordered]@{
                '__XP_D_XBASELINE__'     = (JsonField "out/${id}_PRE.json" 'd_xbaseline')
                '__XP_D_XBASELINE_MD5__' = (JsonField "out/${id}_PRE.json" 'd_xbaseline_md5') })
            $r.e98_gate_pass = (RunJson "/work/sql/run/${id}_E98.sql" "${id}_E98").gate_pass
        }
        $summary[$id] = $r
    }
    $summary | ConvertTo-Json -Depth 6 | Tee-Object -FilePath (Join-Path $WorkDir 'out\envelopes_result.json')
    $ok = $summary.E12.pass -and $summary.E12.e99_gate_pass -and $summary.E13.pass -and $summary.E13.e99_gate_pass -and $summary.E13.e98_gate_pass
    if (-not $ok) { Fail 'E12/E13 local não passou — classificar erro SQL real × infraestrutura (out\*_ENVELOPE.txt)' }
    Say 'ENVELOPES: PASS local (E12 14/14 ctx 712, E13 11/11 ctx 960, E99/E98 limpos, < 120 s)'
}

# ---------------------------------------------------------------- 8. CLEANUP
function Step-Cleanup {
    Invoke-NativeQuiet { docker rm -f $Container } | Out-Null
    Invoke-NativeQuiet { docker volume rm $Volume } | Out-Null
    Remove-Item -Recurse -Force (Join-Path $WorkDir 'dump'), (Join-Path $WorkDir 'secrets'), (Join-Path $WorkDir 'sql') -ErrorAction SilentlyContinue
    Say "CLEANUP: container, volume, dump, cópias SQL e senha local removidos; evidências preservadas em $WorkDir\out"
    Say "Opcional: docker image rm $Image"
}

try {
    Dirs
    switch ($Step) {
        'SelfTest'  { Step-SelfTest }
        'Diagnose'  { Step-Diagnose }
        'Setup'     { Step-Setup }
        'Extract'   { Step-Extract }
        'Load'      { Step-Load }
        'LoadAudit' { Step-LoadAudit }
        'CkProof'   { Step-CkProof }
        'CkRepair'  { Step-CkRepair }
        'Parity'    { Step-Parity }
        'P9B'       { Step-P9B }
        'Envelopes' { Step-Envelopes }
        'NewRoCredential' { Step-NewRoCredential }
        'ScramLocalProof' { Step-ScramLocalProof }
        'FpVisibilityProof' { Step-FpVisibilityProof }
        'RenderS2'        { Step-RenderS2 }
        'ProbeLiveRo'     { Step-ProbeLiveRo }
        'RestoreSelfTest' { Step-RestoreSelfTest }
        'RestoreProof'    { Step-RestoreProof }
        'Cleanup'   { Step-Cleanup }
    }
} catch {
    # qualquer exceção (Fail ou erro de cmdlet) encerra a etapa SEM "PASS" e com código 1
    Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $_.Exception.Message) -ForegroundColor Red
    Write-Host ("  em: {0}" -f $_.InvocationInfo.PositionMessage) -ForegroundColor DarkRed
    exit 1
}
exit 0
