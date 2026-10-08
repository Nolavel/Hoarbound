## Installs the portable MSVC toolchain Jenova uses to compile .cpp scripts on Windows.
## Result: Jenova/Compilers/JenovaMSVCCompiler/{Bin,Include,Lib} (git-ignored, ~0.9 GB).
param(
	## An already extracted AiO toolchain (the Jenova builder's Toolchain folder); skips download.
	[string]$ToolchainRoot = "",
	## A local copy of AIO-Toolchain-v1.0-Win64.7z; skips download.
	[string]$Archive = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
## Jenova's own AiO toolchain (MSVC 14.38 cl/link + merged MSVC/Windows SDK headers and libs).
$archiveUrl = "https://www.dropbox.com/scl/fi/z7i7w74qr4m5ur20b2mg9/AIO-Toolchain-v1.0-Win64.7z?rlkey=jk7lmbmg3z63zoo7dmk559w8f&st=s7lzdm79&dl=1"
$archiveSha256 = "6C0536FD901A694FFCB97783E69F738D5F64B62D336C91F1A2FE2A7AE49D80FD"
$compilers = Join-Path $repoRoot "Jenova/Compilers"
$target = Join-Path $compilers "JenovaMSVCCompiler"

if (-not $ToolchainRoot) {
	$ToolchainRoot = Join-Path $compilers "AiO-Toolchain-v1.0"
	if (-not (Test-Path (Join-Path $ToolchainRoot "bin/cl.exe") -PathType Leaf)) {
		if (-not $Archive) {
			$Archive = Join-Path $env:TEMP "AIO-Toolchain-v1.0-Win64.7z"
			if (-not (Test-Path $Archive -PathType Leaf)) {
				Write-Host "[jenova-msvc] downloading AiO toolchain (157 MB)"
				Invoke-WebRequest -Uri $archiveUrl -OutFile $Archive
			}
		}
		$hash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
		if ($hash -ne $archiveSha256) {
			throw "AiO toolchain checksum mismatch: $hash (expected $archiveSha256). Delete $Archive and retry."
		}
		$pythonCommand = Get-Command "py" -ErrorAction SilentlyContinue
		$pythonArgs = @("-3")
		if (-not $pythonCommand) {
			$pythonCommand = Get-Command "python" -ErrorAction Stop
			$pythonArgs = @()
		}
		& $pythonCommand.Source @pythonArgs -m pip install --disable-pip-version-check -q py7zr
		if ($LASTEXITCODE -ne 0) {
			throw "Failed to install py7zr (Windows tar cannot read LZMA 7z archives)."
		}
		New-Item -ItemType Directory -Force -Path $ToolchainRoot | Out-Null
		Write-Host "[jenova-msvc] extracting bin + x86_64-msvc (about 0.9 GB)"
		$extract = @'
import sys, py7zr
archive, out = sys.argv[1], sys.argv[2]
with py7zr.SevenZipFile(archive, "r") as z:
    wanted = [n for n in z.getnames() if n.split("/")[0] in ("bin", "x86_64-msvc")]
with py7zr.SevenZipFile(archive, "r") as z:
    z.extract(path=out, targets=wanted)
'@
		$extract | & $pythonCommand.Source @pythonArgs - $Archive $ToolchainRoot
		if ($LASTEXITCODE -ne 0) {
			throw "AiO toolchain extraction failed."
		}
	}
}

foreach ($required in @("bin/cl.exe", "bin/link.exe", "x86_64-msvc/include", "x86_64-msvc/lib")) {
	if (-not (Test-Path (Join-Path $ToolchainRoot $required))) {
		throw "AiO toolchain is incomplete: missing $required in $ToolchainRoot"
	}
}

## Keeps Godot's file scan out of ~17k toolchain files.
New-Item -ItemType Directory -Force -Path $compilers | Out-Null
Set-Content -LiteralPath (Join-Path $compilers ".gdignore") -Value "" -Encoding ASCII

## Jenova resolves <compiler>/Bin/cl.exe, /Include and /Lib; junctions map that layout without copies.
if (Test-Path $target) {
	Get-ChildItem -LiteralPath $target -Force | ForEach-Object { $_.Delete() }
} else {
	New-Item -ItemType Directory -Force -Path $target | Out-Null
}
New-Item -ItemType Junction -Path (Join-Path $target "Bin") -Target (Join-Path $ToolchainRoot "bin") | Out-Null
New-Item -ItemType Junction -Path (Join-Path $target "Include") -Target (Join-Path $ToolchainRoot "x86_64-msvc/include") | Out-Null
New-Item -ItemType Junction -Path (Join-Path $target "Lib") -Target (Join-Path $ToolchainRoot "x86_64-msvc/lib") | Out-Null

Write-Host "[jenova-msvc] ready: $target -> $ToolchainRoot"
