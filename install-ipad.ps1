param(
    [string]$Ipa = "$PSScriptRoot\theos\PDFEditor.ipa",
    [string]$Pdf = "",
    [string]$Python = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $Ipa)) {
    Write-Error "IPA nao encontrado: $Ipa"
    exit 1
}

Write-Host "==> Instalando $Ipa no iPad..."
& $Python -m pymobiledevice3 apps install $Ipa
if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha na instalacao. O dispositivo precisa de AppSync Unified (jailbreak)."
    exit $LASTEXITCODE
}

if ($Pdf -ne "") {
    if (!(Test-Path $Pdf)) {
        Write-Error "PDF nao encontrado: $Pdf"
        exit 1
    }
    Write-Host "==> Copiando PDF para Documents do app..."
    $name = Split-Path $Pdf -Leaf
    & $Python -m pymobiledevice3 apps push com.lucaspdf.editor $Pdf "Documents/$name"
}

Write-Host "==> Concluido. Abra o app 'Leitor / Editor Pdf LM' no iPad."
