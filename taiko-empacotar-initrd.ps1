param(
    [string]$Pasta = (Join-Path $PSScriptRoot 'Taiko-Retain'),
    [string]$HashEsperado = '3f680e441f05a8815ac81fedad52636e23e0cc67a813f986340efea15c5edd37'
)

$ErrorActionPreference = 'Stop'
$Origem = Join-Path $Pasta 'coleta\taiko-loader-initrd.bin'
$Saida = Join-Path $Pasta 'partes-initrd'
$Manifesto = Join-Path $Saida 'MANIFESTO-SHA256.txt'
$TamanhoEsperado = 63707665L
$TamanhoParte = 16MB

if (-not (Test-Path -LiteralPath $Origem)) { throw "Arquivo ausente: $Origem" }
if ((Get-Item -LiteralPath $Origem).Length -ne $TamanhoEsperado) {
    throw "Tamanho inesperado para taiko-loader-initrd.bin. Esperado: $TamanhoEsperado"
}

$hashOrigem = (Get-FileHash -Algorithm SHA256 -LiteralPath $Origem).Hash.ToLowerInvariant()
if ($hashOrigem -ne $HashEsperado.ToLowerInvariant()) {
    throw "SHA256 inesperado.`nEsperado: $HashEsperado`nObtido:  $hashOrigem"
}

New-Item -ItemType Directory -Force -Path $Saida | Out-Null
Get-ChildItem -LiteralPath $Saida -Force | Remove-Item -Force -Recurse

$entrada = [IO.File]::OpenRead($Origem)
$buffer = New-Object byte[] $TamanhoParte
$partes = @()
try {
    $numero = 1
    while (($lidos = $entrada.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $nome = 'taiko-loader-initrd.part{0:D2}.bin' -f $numero
        $caminho = Join-Path $Saida $nome
        $arquivo = [IO.File]::Create($caminho)
        try { $arquivo.Write($buffer, 0, $lidos) }
        finally { $arquivo.Dispose() }
        $partes += Get-Item -LiteralPath $caminho
        $numero++
    }
}
finally { $entrada.Dispose() }

$linhas = @(
    'TAIKO LOADER INITRD - PARTES PARA ANALISE',
    "original_size=$TamanhoEsperado",
    "original_sha256=$hashOrigem",
    "part_count=$($partes.Count)"
)
foreach ($parte in $partes) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $parte.FullName).Hash.ToLowerInvariant()
    $linhas += "$($parte.Name) size=$($parte.Length) sha256=$hash"
}
$linhas | Set-Content -Encoding ASCII -LiteralPath $Manifesto

$zips = @()
foreach ($parte in $partes) {
    $zip = Join-Path $Saida ($parte.BaseName + '.zip')
    Compress-Archive -CompressionLevel Optimal -LiteralPath @($parte.FullName, $Manifesto) -DestinationPath $zip
    $zips += Get-Item -LiteralPath $zip
}

Write-Host ''
Write-Host 'PACOTES CRIADOS. Envie estes quatro arquivos:'
foreach ($zip in $zips) {
    Write-Host ("{0}  ({1:N1} MB)" -f $zip.FullName, ($zip.Length / 1MB))
}
