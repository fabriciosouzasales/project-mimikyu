<#
.SYNOPSIS
  V1-13 - prova negativa do executor por arquivo (STD-005 par. 3), SEM banco e SEM rede.

.DESCRIPTION
  Roda o Invoke-ReviewedSql.ps1 REAL (sem modificacao) contra um repositorio temporario falso:
  - "npx.cmd" falso a frente no PATH: nao contata o registro npm nem o Supabase; devolve
    respostas pre-gravadas (<arquivo>.out / <arquivo>.exit) e registra cada chamada;
  - projeto ficticio aaaaaaaaaaaaaaaaaaaa (o linked-project.json falso aponta para ele);
  - confirmacao digitada fornecida por stdin.
  Cenario de controle (tudo aprovado) precisa chegar ao fim: se nao chegar, o resultado e
  INCONCLUSIVO (o harness nao prova nada), nunca PASS.
  Para cada cenario negativo verifica: termina em STOP (codigo <> 0), a etapa write NAO e
  chamada, nenhum arquivo e enviado mais de uma vez, toda chamada usa o projeto ficticio.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\v1-13\Test-InvokeReviewedSql.ps1
#>
param([string]$Executor = (Join-Path $PSScriptRoot 'Invoke-ReviewedSql.ps1'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$REF = 'aaaaaaaaaaaaaaaaaaaa'
$root = Join-Path ([IO.Path]::GetTempPath()) ('mmkyu-exec-test-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $root 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

# CLI falsa: nunca abre conexao; responde pelo arquivo <sql>.out e sai com <sql>.exit (padrao 0).
Set-Content -LiteralPath (Join-Path $bin 'fake-cli.ps1') -Encoding ASCII -Value @'
$log = $env:MMKYU_FAKE_LOG
Add-Content -LiteralPath $log -Value ($args -join ' ')
if ($args -contains '--version') { Write-Output '3.2.0'; exit 0 }
$q = [array]::IndexOf($args, 'query')
$depois = @($args | Select-Object -Skip ($q + 1))
if (-not ($depois -contains '--yes') -and -not ($depois -contains '--read-only')) {
  [Console]::Error.WriteLine('Confirmation required: Run a SQL statement. Nothing was changed. Re-run with --yes to confirm.')
  exit 1
}
$i = [array]::IndexOf($args, '--file')
$f = $args[$i + 1]
if (Test-Path -LiteralPath "$f.out") { Write-Output (Get-Content -LiteralPath "$f.out" -Raw) }
if (Test-Path -LiteralPath "$f.exit") { exit [int](Get-Content -LiteralPath "$f.exit") }
exit 0
'@
Set-Content -LiteralPath (Join-Path $bin 'npx.cmd') -Encoding ASCII -Value "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-cli.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n"

function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
$ok = '[{"s":{"executor":"postgres","barreira":"CLOSED","identidades_teste":0,"criterio":true,"escritores_md5":"m1","escritores_atribuicao":"a_fn, b_fn","escritores_representante":"r_fn"}}]'
$expJson = '{"escritores_atribuicao":["a_fn","b_fn"],"escritores_representante":["r_fn"]}'

function New-Scenario([string]$nome, [string]$pre, [string]$post, [int]$migExit, [switch]$alterarDepois, [string]$preSql = '', [switch]$semExp, [switch]$expShaErrada) {
  $repo = Join-Path $root $nome
  $pkg = Join-Path $repo 'pkg'
  New-Item -ItemType Directory -Force -Path (Join-Path $repo 'supabase\.temp'), $pkg | Out-Null
  Set-Content -LiteralPath (Join-Path $repo 'supabase\.temp\linked-project.json') -Encoding ASCII -Value ('{"ref":"' + $REF + '"}')
  foreach ($n in 'PRE', 'MIG', 'POST') { Set-Content -LiteralPath (Join-Path $pkg "$n.sql") -Encoding ASCII -Value "select 1; -- $nome $n" }
  if ($preSql) { Set-Content -LiteralPath (Join-Path $pkg 'PRE.sql') -Encoding ASCII -Value $preSql }
  Set-Content -LiteralPath (Join-Path $pkg 'PRE.sql.out') -Encoding ASCII -Value $pre
  Set-Content -LiteralPath (Join-Path $pkg 'POST.sql.out') -Encoding ASCII -Value $post
  if ($migExit -ne 0) { Set-Content -LiteralPath (Join-Path $pkg 'MIG.sql.exit') -Encoding ASCII -Value "$migExit" }
  $man = @('# teste', "1|pkg\PRE.sql|$(Sha (Join-Path $pkg 'PRE.sql'))|gate", "2|pkg\MIG.sql|$(Sha (Join-Path $pkg 'MIG.sql'))|write",
           "3|pkg\POST.sql|$(Sha (Join-Path $pkg 'POST.sql'))|gate")
  Set-Content -LiteralPath (Join-Path $pkg 'MAN.txt') -Encoding ASCII -Value $man
  $sha = Sha (Join-Path $pkg 'MAN.txt')
  if ($alterarDepois) { Add-Content -LiteralPath (Join-Path $pkg 'MIG.sql') -Value '-- alterado depois do manifesto' }
  Set-Content -LiteralPath (Join-Path $repo 'confirm.txt') -Encoding ASCII -Value ("EXECUTAR $REF " + $sha.Substring(0, 8))
  Set-Content -LiteralPath (Join-Path $pkg 'EXP.json') -Encoding ASCII -Value $expJson
  $expSha = Sha (Join-Path $pkg 'EXP.json')
  if ($expShaErrada) { $expSha = ('0' * 64) }
  return @{ repo = $repo; sha = $sha; inicio = (Get-Date).ToUniversalTime().AddSeconds(-1); semExp = [bool]$semExp; expSha = $expSha }
}

function Invoke-Scenario($s) {
  $log = Join-Path $s.repo 'calls.log'
  New-Item -ItemType File -Force -Path $log | Out-Null
  $env:MMKYU_FAKE_LOG = $log
  $oldPath = $env:PATH
  $env:PATH = "$bin;$oldPath"
  try {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $Executor + '"'), '-Repo', ('"' + $s.repo + '"'),
           '-Manifesto', 'pkg\MAN.txt', '-Projeto', $REF, '-ShaManifestoEsperado', $s.sha, '-DirRegistro', ('"' + (Join-Path $s.repo 'reg') + '"'))
    if (-not $s.semExp) { $a += @('-Expectativas', 'pkg\EXP.json', '-ShaExpectativas', $s.expSha) }
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList ($a -join ' ') -NoNewWindow -PassThru `
              -RedirectStandardInput (Join-Path $s.repo 'confirm.txt') `
              -RedirectStandardOutput (Join-Path $s.repo 'exec.out') -RedirectStandardError (Join-Path $s.repo 'exec.err')
    $null = $proc.Handle   # sem obter o handle logo, ExitCode volta $null depois de WaitForExit(timeout)
    if (-not $proc.WaitForExit(180000)) { $proc.Kill(); return @{ exit = $null; calls = @(); out = 'TIMEOUT'; runs = @() } }
    $proc.WaitForExit()    # garante a saida completa antes de ler ExitCode
    $code = $proc.ExitCode
  } finally { $env:PATH = $oldPath }
  $calls = @(Get-Content -LiteralPath $log)
  $out = (Get-Content -LiteralPath (Join-Path $s.repo 'exec.out') -Raw) + (Get-Content -LiteralPath (Join-Path $s.repo 'exec.err') -Raw)
  # So registros desta execucao: diretorio de registro novo por cenario, gravado depois do inicio.
  $runs = @()
  $regDir = Join-Path $s.repo 'reg'
  if (Test-Path -LiteralPath $regDir) {
    foreach ($d in @(Get-ChildItem -LiteralPath $regDir -Directory -Filter 'run-*')) {
      $rj = Join-Path $d.FullName 'run.json'
      if ((Test-Path -LiteralPath $rj) -and (Get-Item -LiteralPath $rj).LastWriteTimeUtc -ge $s.inicio) {
        $runs += (Get-Content -LiteralPath $rj -Raw -Encoding UTF8 | ConvertFrom-Json)
      } else { $runs += $null }
    }
  }
  # A mensagem de erro do PowerShell vem quebrada na largura do console: compara sem as quebras.
  $flat = ''
  if ($out) { $flat = [regex]::Replace($out, '\r?\n\s*', '') }
  return @{ exit = $code; calls = $calls; out = $flat; runs = $runs }
}

$cenarios = @(
  @{ nome = 'controle';            pre = $ok; post = $ok; mig = 0; alterar = $false; espera = 'PASS' },
  @{ nome = 'pre_booleano_falso';  pre = $ok.Replace('"criterio":true', '"criterio":false'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE' },
  @{ nome = 'pre_json_invalido';   pre = 'isto nao e json {'; post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE' },
  @{ nome = 'pre_sem_criterio';    pre = '[{"s":{"executor":"postgres","barreira":"CLOSED","identidades_teste":0}}]'; post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE' },
  @{ nome = 'barreira_open';       pre = $ok.Replace('"CLOSED"', '"OPEN"'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE' },
  @{ nome = 'identidades_teste';   pre = $ok.Replace('"identidades_teste":0', '"identidades_teste":1'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE' },
  @{ nome = 'executor_errado';     pre = $ok.Replace('"postgres"', '"authenticator"'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE' },
  @{ nome = 'hash_divergente';     pre = $ok; post = $ok; mig = 0; alterar = $true;  espera = 'STOP_ANTES' },
  @{ nome = 'migration_falha';     pre = $ok; post = $ok; mig = 1; alterar = $false; espera = 'STOP_WRITE' },
  @{ nome = 'post_md5_divergente'; pre = $ok; post = $ok.Replace('"m1"', '"m2"'); mig = 0; alterar = $false; espera = 'STOP_POST' },
  @{ nome = 'gate_com_escrita';    pre = $ok; post = $ok; mig = 0; alterar = $false; espera = 'STOP_RO';
     preSql = "select 1; delete from public.collection_membership;" },
  # Inventario de escritores obrigatorio (v1.4); o controle acima cobre "inventario exatamente igual".
  @{ nome = 'escritor_adicional';  pre = $ok.Replace('"a_fn, b_fn"', '"a_fn, b_fn, c_fn"'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE';
     motivo = 'escritores_atribuicao diferente do esperado' },
  @{ nome = 'escritor_ausente';    pre = $ok.Replace('"a_fn, b_fn"', '"a_fn"'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE';
     motivo = 'escritores_atribuicao diferente do esperado' },
  @{ nome = 'inventario_vazio';    pre = $ok.Replace('"a_fn, b_fn"', '""'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE';
     motivo = 'escritores_atribuicao diferente do esperado' },
  @{ nome = 'campo_ausente';       pre = $ok.Replace(',"escritores_representante":"r_fn"', ''); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE';
     motivo = 'ausente: escritores_representante' },
  @{ nome = 'sobrecarga';          pre = $ok.Replace('"a_fn, b_fn"', '"a_fn, a_fn, b_fn"'); post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE';
     motivo = 'escritores_atribuicao diferente do esperado' },
  @{ nome = 'sem_expectativas';    pre = $ok; post = $ok; mig = 0; alterar = $false; espera = 'STOP_PRE'; semExp = $true;
     motivo = 'sem expectativa auditada' },
  @{ nome = 'expectativa_hash';    pre = $ok; post = $ok; mig = 0; alterar = $false; espera = 'STOP_EXP'; expShaErrada = $true }
)

$falhas = 0
$inconclusivo = 0
$controleOk = $false
foreach ($c in $cenarios) {
  $preSql = ''
  if ($c.ContainsKey('preSql')) { $preSql = $c.preSql }
  $semExp = $c.ContainsKey('semExp') -and $c.semExp
  $expErr = $c.ContainsKey('expShaErrada') -and $c.expShaErrada
  $s = New-Scenario $c.nome $c.pre $c.post $c.mig -alterarDepois:$c.alterar -preSql $preSql -semExp:$semExp -expShaErrada:$expErr
  $r = Invoke-Scenario $s
  $calls = @($r.calls)
  $mig = @($calls | Where-Object { $_ -match 'MIG\.sql' }).Count
  $pre = @($calls | Where-Object { $_ -match 'PRE\.sql' }).Count
  $post = @($calls | Where-Object { $_ -match 'POST\.sql' }).Count
  $alvo = @($calls | Where-Object { $_ -match '--file' -and $_ -notmatch "--remote=$REF" }).Count -eq 0
  # Gate e write no papel da escrita: PRE/POST/MIG sempre terminam com --yes e nunca usam --read-only.
  $papel = (@($calls | Where-Object { $_ -match '--file' -and $_ -match '--read-only' }).Count -eq 0) -and
           (@($calls | Where-Object { $_ -match '(PRE|POST|MIG)\.sql' -and $_ -notmatch ' --yes$' }).Count -eq 0)
  $semRepeticao = ($pre -le 1) -and ($mig -le 1) -and ($post -le 1) -and (@($calls | Where-Object { $_ -match '--version' }).Count -le 1)
  # Ordem das chamadas: --version -> PRE -> MIG -> POST (somente as que ocorreram).
  $pos = @()
  foreach ($pat in '--version', 'PRE\.sql', 'MIG\.sql', 'POST\.sql') {
    for ($i = 0; $i -lt $calls.Count; $i++) { if ($calls[$i] -match $pat) { $pos += $i; break } }
  }
  $emOrdem = ($pos -join ',') -eq ((@($pos | Sort-Object)) -join ',')
  $runs = @($r.runs)
  $res = ''
  if ($runs.Count -eq 1 -and $null -ne $runs[0]) { $res = [string]$runs[0].resultado }
  if ($null -eq $r.exit) {
    $inconclusivo++
    $estado = 'INCONCLUSIVO'
  } else {
    $passou = $false
    switch ($c.espera) {
      'PASS'       { $passou = ($r.exit -eq 0) -and $pre -eq 1 -and $mig -eq 1 -and $post -eq 1 -and ($res -like 'PASS*') }
      'STOP_PRE'   { $passou = ($r.exit -eq 2) -and $pre -eq 1 -and $mig -eq 0 -and $post -eq 0 -and ($res -like 'STOP*')
                     if ($c.ContainsKey('motivo')) { $passou = $passou -and ($r.out -match $c.motivo) } }
      'STOP_ANTES' { $passou = ($r.exit -eq 1) -and $calls.Count -eq 0 -and $runs.Count -eq 0 -and ($r.out -match 'SHA-256 divergente: pkg\\MIG\.sql') }
      'STOP_EXP'   { $passou = ($r.exit -eq 1) -and $calls.Count -eq 0 -and $runs.Count -eq 0 -and ($r.out -match 'expectativas diferentes das auditadas') }
      'STOP_RO'    { $passou = ($r.exit -eq 1) -and $calls.Count -eq 0 -and $runs.Count -eq 0 -and ($r.out -match 'somente leitura: pkg\\PRE\.sql') }
      'STOP_WRITE' { $passou = ($r.exit -eq 2) -and $pre -eq 1 -and $mig -eq 1 -and $post -eq 0 -and ($res -like 'STOP*') }
      'STOP_POST'  { $passou = ($r.exit -eq 2) -and $pre -eq 1 -and $mig -eq 1 -and $post -eq 1 -and ($res -like 'STOP*') -and ($r.out -match 'diferente do gate anterior') }
    }
    # Defeito de codigo (nao um STOP esperado): os throw do executor aparecem como RuntimeException e sao validos.
    $prematuro = $r.out -match 'PropertyNotFound|VariableIsUndefined|MethodNotFound|ParameterBinding|CommandNotFoundException|ParseException'
    $passou = $passou -and $alvo -and $semRepeticao -and $emOrdem -and $papel -and -not $prematuro
    if ($c.espera -eq 'PASS') { $controleOk = $passou }
    if (-not $passou) { $falhas++ }
    $estado = 'FAIL'
    if ($passou) { $estado = 'PASS' }
  }
  if ($estado -ne 'PASS') {
    $diag = @(($r.out -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -Last 3) -join ' | '
    Write-Host ('             diagnostico: {0}' -f $diag)
  }
  $exitTxt = 'NULO'
  if ($null -ne $r.exit) { $exitTxt = [string]$r.exit }
  $resTxt = '-'
  if ($res) { $resTxt = $res.Split(' ')[0] }
  Write-Host ('{0,-12} {1,-22} exit={2,-4} PRE={3} WRITE={4} POST={5} em_ordem={6} alvo_ficticio={7} sem_repeticao={8} papel_escrita={9} run.json={10}' -f `
    $estado, $c.nome, $exitTxt, $pre, $mig, $post, $emOrdem, $alvo, $semRepeticao, $papel, $resTxt)
}
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
if ($inconclusivo) { Write-Host "INCONCLUSIVO: $inconclusivo cenario(s) sem codigo de saida capturado (harness sem validade)."; exit 3 }
if (-not $controleOk) { Write-Host 'INCONCLUSIVO: o cenario de controle nao chegou ao fim (harness sem validade).'; exit 3 }
if ($falhas) { Write-Host "PROVA NEGATIVA: $falhas FALHA(S)"; exit 1 }
Write-Host 'PROVA NEGATIVA DO EXECUTOR: PASS (todos os cenarios terminaram como esperado)'
