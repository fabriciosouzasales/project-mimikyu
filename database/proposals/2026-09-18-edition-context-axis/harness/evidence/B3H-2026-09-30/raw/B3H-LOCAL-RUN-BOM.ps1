#requires -Version 5.1
<#
BATCH12-E15-PROTOCOL-B-B3H-LOCAL-EXECUTION-01 — executor local (NÃO VERSIONADO) · RUNNER-CORRECTION-01

Faz, nesta ordem, e para no primeiro desvio:
  Gate A local (1–8) → B3H_representative.psql (HARDENING-01, captura dentro do container em UTF-8)
  → wall → A3 IMEDIATAMENTE → parsing/classificação fail-closed → checagem O-1/C2 (fail-closed)
  → B3H_verdict.txt → MANIFEST.md5 → ZIP de evidências → só então STOP se verdict != PASS-LOCAL ou A3 não conforme.
Nenhum acesso ao LIVE. Não roda A4a/A4b nem B-R. Não altera arquivos versionados. Não faz Git.

Uso (PowerShell, na máquina do Fabrício):
  powershell -ExecutionPolicy Bypass -File .\B3H-LOCAL-RUN.ps1 `
     -PkgZip 'C:\caminho\E15-PG17-RECOVERY.zip' -B1HZip 'C:\caminho\B1H-LIVE-2026-09-29.zip'
#>
param(
  [string]$Repo   = 'C:\Users\Administrador\Documents\Coleção Pokémon\00. Desenvolvimento do Sistema Mimikyu\02 - Repositório de Dados\project-mimikyu',
  [Parameter(Mandatory = $true)][string]$PkgZip,
  [Parameter(Mandatory = $true)][string]$B1HZip,
  [string]$W = 'C:\b12-pg17',
  [string]$C = 'b12-pg17'
)
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object Text.UTF8Encoding($false)
function Md5([string]$p) { (Get-FileHash -Algorithm MD5 -LiteralPath $p).Hash.ToLower() }
function Stop-B([string]$m) { throw "STOP (B3H): $m" }
function Say([string]$m) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) }
function Read-Utf8([string]$p) { if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p, $Utf8) } else { $null } }

$BASELINE = 'c19161b3cc8a9deda01062a4dadab1885bfc2d47'
$PKG_MD5  = 'cae73876909240bb8ae08602fc097835'
$B1HZ_MD5 = '3ee03f0ebbd0259240fb57bfbd0dfb61'
$EXP_MD5  = 'c059f993f01e22dcb1891bebb93d476f'
$Pins = [ordered]@{
  'e15b\B2H_local_synth.psql'   = '84e5f3516cf69ec38fed672a739d7660'
  'e15b\B2_static_indexes.psql' = '118f3b797ff588d829e52d48568da325'
  'e15b\B3H_representative.psql'= '0dfba7d5014138274bccf312ccd57343'
  'e15b\B_rep_gate.psql'        = '8d27f5d3b67525f7d7884f75f51899f5'
  'e15a\A_probe_v2.sql'         = 'f011590274445e9be704a2461bf142c8'
  'e15a\D1-ID-IDENTITY.sql'     = 'efb3217e4b5ce9d227f412739c3e1b18'
  'e15a\L_E15_unblocked.sql'    = '83e4d5d9a83958282cbc731725c8a298'
  'e15a\A3_residue.sql'         = 'cd73d1a05c4bf5e6ab9498709d174b71'
}
$OutB = Join-Path $W 'out\e15b'

# ============================================================ GATE A LOCAL
Say 'GATE A 1 — HEAD'
$head = (git -C $Repo rev-parse HEAD).Trim()
if ($head -ne $BASELINE) { Stop-B "HEAD=$head" }

Say 'GATE A 2 — árvore rastreada'
$ok = @('?? database/proposals/2026-09-18-edition-context-axis/harness/local-pg17/',
        '?? database/proposals/2026-09-18-edition-context-axis/harness/tools/b12gen/__pycache__/')
$extra = @(git -C $Repo status --porcelain | Where-Object { $ok -notcontains $_ })
if ($extra.Count) { Stop-B "working tree: $($extra -join '; ')" }

Say 'GATE A 3 — pacotes e pinos'
if ((Md5 $PkgZip) -ne $PKG_MD5) { Stop-B "E15-PG17-RECOVERY.zip md5 $(Md5 $PkgZip)" }
if ((Md5 $B1HZip) -ne $B1HZ_MD5) { Stop-B "B1H-LIVE-2026-09-29.zip md5 $(Md5 $B1HZip)" }
if ((Test-Path $OutB) -and @(Get-ChildItem $OutB -Force).Count) { Stop-B "GATE A 7: $OutB não está vazio — arquivar a rodada anterior antes" }
Expand-Archive -LiteralPath $PkgZip -DestinationPath $W -Force
foreach ($k in $Pins.Keys) { $m = Md5 (Join-Path $W $k); if ($m -ne $Pins[$k]) { Stop-B "pino $k = $m" } }

Say 'GATE A 6 — B1H_export.json'
$tmp = Join-Path $env:TEMP ('b1h_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $B1HZip -DestinationPath $tmp -Force
$srcExp = Join-Path $tmp 'B1H-LIVE-2026-09-29\B1H_export.json'
if ((Md5 $srcExp) -ne $EXP_MD5) { Stop-B "B1H_export.json no ZIP md5 $(Md5 $srcExp)" }
Copy-Item -LiteralPath $srcExp -Destination (Join-Path $W 'e15b\B1H_export.json') -Force
$exp = Join-Path $W 'e15b\B1H_export.json'
if ((Md5 $exp) -ne $EXP_MD5) { Stop-B "B1H_export.json copiado md5 $(Md5 $exp)" }
Remove-Item -Recurse -Force $tmp

Say 'GATE A 4 — container'
$ci = docker container inspect $C | ConvertFrom-Json | ForEach-Object { $_ }
if ($ci.Config.Image -ne 'supabase/postgres:17.6.1.147') { Stop-B "imagem $($ci.Config.Image)" }
if ($ci.State.Status -ne 'running') { Stop-B "container não está running ($($ci.State.Status))" }
$pb = @($ci.HostConfig.PortBindings.'5432/tcp')
if ($pb.Count -ne 1 -or $pb[0].HostIp -ne '127.0.0.1' -or "$($pb[0].HostPort)" -ne '55432') { Stop-B 'binding diferente de 127.0.0.1:55432' }
if (@($ci.Mounts | Where-Object { $_.Type -eq 'bind' -and $_.Destination -eq '/work' }).Count -ne 1) { Stop-B 'bind /work ausente' }
if ((docker exec $C sh -c 'test -r /work/e15b/B3H_representative.psql && test -r /work/e15b/B1H_export.json && echo ok') -ne 'ok') { Stop-B 'pacote/export não visíveis em /work' }

Say 'GATE A 5 — credenciais LIVE'
$envC = @(docker exec $C env)
if (@($envC | Where-Object { $_ -match '^(PGHOST|PGUSER|PGPASSFILE|PGSERVICE)=|supabase\.com|pooler' }).Count) { Stop-B 'variável LIVE no container' }
if (@(Get-ChildItem Env: | Where-Object { $_.Name -like 'PG*' }).Count) { Stop-B 'variáveis PG* na sessão do host' }

$pw = ([IO.File]::ReadAllText((Join-Path $W 'secrets\local_pw.txt'))).Trim()
New-Item -ItemType Directory -Force -Path $OutB | Out-Null

function Invoke-LocalPsqlCapture([string]$User, [string]$File, [string]$Base) {
    if ($User -notin @('postgres', 'supabase_admin')) { Stop-B "usuário inválido: $User" }
    foreach ($x in $File, $Base) { if ($x -notmatch '^/work/[A-Za-z0-9_./-]+$') { Stop-B "caminho fora da whitelist: $x" } }
    $cmd = "psql -X -h 127.0.0.1 -p 5432 -U $User -d postgres -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f $File > $Base.stdout 2> $Base.stderr; echo `$? > $Base.rc"
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & docker exec -e "PGPASSWORD=$pw" -e 'PGCLIENTENCODING=UTF8' $C sh -c $cmd | Out-Null
    $ErrorActionPreference = $prev
    $hb = Join-Path $W ($Base -replace '^/work/', '' -replace '/', '\')
    $rcTxt = Read-Utf8 "$hb.rc"
    if ($null -eq $rcTxt) { Stop-B "rc não gravado ($Base.rc): docker exec falhou antes do psql" }
    [pscustomobject]@{ rc = [int]$rcTxt.Trim(); stdout = Read-Utf8 "$hb.stdout"; stderr = Read-Utf8 "$hb.stderr" }
}

Say 'GATE A 8 — Pricing ausente na réplica (+ versão/host), read-only'
$pre = '/work/out/e15b/GATEA8_precheck.sql'
[IO.File]::WriteAllText((Join-Path $OutB 'GATEA8_precheck.sql'),
  "SELECT (to_regclass('public.pricing_source_card_identity') IS NULL AND to_regclass('public.pricing_source_variant_mapping') IS NULL)::text || '|' || current_setting('server_version_num') || '|' || host(inet_server_addr()) AS gate_a8;`n", $Utf8)
$g8 = Invoke-LocalPsqlCapture 'postgres' $pre '/work/out/e15b/GATEA8'
if ($g8.rc -ne 0 -or $g8.stdout -notmatch 'true\|170006\|127\.0\.0\.1') { Stop-B "GATE A 8: $($g8.stdout) $($g8.stderr)" }
Say 'GATE A: PASS (1–8)'

# ============================================================ EXECUÇÃO B3H
Say 'B3H — B2H → sonda v2 → D1 → B_rep_gate → EXPLAIN ANALYZE D1X → envelope → ROLLBACK'
$sw = [Diagnostics.Stopwatch]::StartNew()
$run = Invoke-LocalPsqlCapture 'postgres' '/work/e15b/B3H_representative.psql' '/work/out/e15b/B3H_run'
$sw.Stop(); [IO.File]::WriteAllText((Join-Path $OutB 'B3H_wall.txt'), "wall_ms=$($sw.ElapsedMilliseconds) rc=$($run.rc)`n", $Utf8)

# ============================================================ A3 IMEDIATAMENTE (antes de qualquer parsing do B3H)
# CORRECTION-01: A3 roda logo após o B3H; nenhum parsing de gate/envelope/plano acontece antes dele.
Say 'A3 — resíduo'
$resOk = $false; $resNote = ''
try {
    $res = Invoke-LocalPsqlCapture 'postgres' '/work/e15a/A3_residue.sql' '/work/out/e15b/B3H_residue'
    $r = $null
    if ("$($res.stdout)" -match '(\{.*\})') { try { $r = $Matches[1] | ConvertFrom-Json } catch { $r = $null; $resNote = 'A3 JSON inválido' } }
    $resOk = ($res.rc -eq 0) -and ($null -ne $r) -and ($r.stub_pscid_absent -eq $true) -and ($r.stub_psvm_absent -eq $true) -and
             ($r.cv_total -eq 24893) -and ($r.open_xacts_other -eq 0)
} catch { $resOk = $false; $resNote = "A3 exceção: $($_.Exception.Message)" }

# ============================================================ PARSING / CLASSIFICAÇÃO FAIL-CLOSED
# Nenhuma exceção evitável aqui: arquivo ausente/malformado => condição false (STOP), nunca abort antes da evidência.
$envTxt = Read-Utf8 "$OutB\B3H_4_envelope_result.txt"
$envS = $null; $envM = $null
if ($envTxt -and $envTxt -match '(?m)^sqlstate=\s*(\S+)') { $envS = $Matches[1] }
if ($envTxt -and $envTxt -match '(?m)^message=\s(.*)$') { $envM = $Matches[1].TrimEnd("`r") }
$errS = @([regex]::Matches("$($run.stderr)", '(?m):\s+([0-9A-Z]{5}):\s') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^0[012]' })

# Gate: JSON com EXATAMENTE 18 propriedades, todas boolean true.
$gateOk = $false; $gateN = 0; $gateNote = ''
try {
    $gRaw = Read-Utf8 "$OutB\B3H_2g_rep_gate.json"
    if ($gRaw) {
        $gObj = $gRaw.Trim() | ConvertFrom-Json
        $gProps = @($gObj.PSObject.Properties)
        $gateN = $gProps.Count
        $gateOk = ($gateN -eq 18) -and (@($gProps | Where-Object { -not (($_.Value -is [bool]) -and $_.Value) }).Count -eq 0)
    } else { $gateNote = 'gate ausente' }
} catch { $gateOk = $false; $gateNote = 'gate JSON inválido' }

# EXPLAIN do D1X concluído.
$planTxt = Read-Utf8 "$OutB\B3H_3_d1x_analyze.txt"
$explainOk = ($null -ne $planTxt) -and ($planTxt -match 'Execution Time')

# O-1 fail-closed: nós de plano (linhas iniciadas por "->") que citem C2/2211/lineage devem estar "(never executed)".
$c2Lines = @()
if ($planTxt) {
    $c2Lines = @($planTxt -split "`r?`n" | Where-Object {
        $_ -match '^\s*->' -and $_ -match 'catalog_variant_import_row|resolve_variant_mapping_scope|resolve_variant_row_axes' })
}
$c2Nodes = $c2Lines.Count
$c2Executed = @($c2Lines | Where-Object { $_ -notmatch '\(never executed\)' }).Count
$c2RuntimeOk = $explainOk -and ($c2Executed -eq 0)
[IO.File]::WriteAllLines((Join-Path $OutB 'B3H_3_c2_nodes.txt'), [string[]]$(if ($c2Lines.Count) { $c2Lines } else { @('<nenhum nó C2/2211/lineage em linhas "->">') }), $Utf8)

$verdict =
  if ($run.rc -eq 0 -and $envS -eq 'H283P' -and $envM -and
      $envM -match '^H2830_ROLLBACK_PASS: envelope=E15_SECAO_5_LEGADO_HOLD pass=5/5 casos=5\.1,5\.2,5\.3,5\.6,5\.7 ' -and
      "$($run.stdout)" -match 'B-REP GATE: PASS \(18/18\)' -and "$($run.stdout)" -match 'ENVELOPE: H283P ROLLBACK_PASS 5/5' -and
      $gateOk -and $explainOk -and $c2RuntimeOk -and ($errS -join ',') -eq 'H283P') { 'PASS-LOCAL' }
  elseif ($envS) {
      if ($envS -eq 'H283F') { 'STOP-SEMANTICA' } elseif ($envS -in @('57014','55P03')) { 'INCONCLUSIVO' } else { 'STOP' } }
  elseif ($errS.Count -ge 1 -and $errS[0] -eq 'H28RG') { 'STOP-REPRESENTATIVIDADE' }
  elseif ($errS.Count -ge 1 -and $errS[0] -in @('57014','55P03')) { 'INCONCLUSIVO' }
  else { 'STOP' }
# c2RuntimeOk=false nunca produz PASS-LOCAL (condição acima); sem nova classificação.

$vlines = @(
  "verdict=$verdict",
  "rc=$($run.rc)",
  "env_sqlstate=$envS",
  "envelope_message=$envM",
  "first_err=$(if ($errS.Count) { $errS[0] } else { '<nenhum>' })",
  "all_err_sqlstates=$($errS -join ',')",
  "gate_props=$gateN",
  "gate18_all_true=$gateOk $gateNote",
  "explain_ok=$explainOk",
  "c2_nodes=$c2Nodes",
  "c2_executed=$c2Executed",
  "c2_runtime_ok=$c2RuntimeOk",
  "a3_residue_ok=$resOk $resNote"
)
[IO.File]::WriteAllLines((Join-Path $OutB 'B3H_verdict.txt'), [string[]]$vlines, $Utf8)
$vlines | ForEach-Object { Say $_ }

# ============================================================ MANIFESTO + ZIP (sempre que o B3H foi disparado)
$man = Get-ChildItem $OutB -File | Where-Object { $_.Name -ne 'MANIFEST.md5' } | Sort-Object Name |
       ForEach-Object { '{0}  {1}' -f (Md5 $_.FullName), $_.Name }
[IO.File]::WriteAllLines((Join-Path $OutB 'MANIFEST.md5'), [string[]]$man, $Utf8)
$zip = Join-Path $W ("B3H-LOCAL-EVIDENCE-{0:yyyyMMddTHHmmss}.zip" -f (Get-Date).ToUniversalTime())
Compress-Archive -Path (Join-Path $OutB '*') -DestinationPath $zip
Say "evidência: $zip md5 $(Md5 $zip)"
$man | ForEach-Object { Write-Host $_ }
Remove-Variable pw

# ============================================================ SÓ AGORA: STOP se aplicável
if (-not $resOk) { Stop-B "resíduo após B3H (A3 não conforme) $resNote" }
if ($verdict -ne 'PASS-LOCAL') { Stop-B "B3H: $verdict (ver B3H_verdict.txt / B3H_run.stderr / B3H_4_envelope_result.txt / B3H_2g_rep_gate.json / B3H_3_c2_nodes.txt)" }
Say 'B3H: PASS-LOCAL · A3 conforme · STOP (fim da rodada)'