param(
	[string]$GodotExe = $env:GODOT_BIN
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$jenovaRef = "63ecdcb385fbcd8a59e1ed5896a6c03e0d0aacb2"
$workRoot = Join-Path $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }) "hoarbound-jenova-windows"
$sourceRoot = Join-Path $workRoot "Jenova-Runtime"
$apiRoot = Join-Path $workRoot "godot-api"

if (-not $GodotExe) {
	$godotCommand = Get-Command "godot.exe" -ErrorAction SilentlyContinue
	if (-not $godotCommand) {
		$godotCommand = Get-Command "godot" -ErrorAction SilentlyContinue
	}
	if (-not $godotCommand) {
		throw "Set GODOT_BIN to the Godot 4.8-dev6 executable or add godot.exe to PATH."
	}
	$GodotExe = $godotCommand.Source
}
if (-not (Test-Path $GodotExe -PathType Leaf)) {
	throw "Godot executable does not exist: $GodotExe"
}

$godotVersion = (& $GodotExe --headless --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $godotVersion -notmatch "^4\.8\.dev6(?:\.|$)") {
	throw "Expected Godot 4.8-dev6, got '$godotVersion'."
}

if (Test-Path $workRoot) {
	Remove-Item -LiteralPath $workRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $workRoot, $apiRoot | Out-Null
git clone --quiet https://github.com/Jenova-Framework/Jenova-Runtime.git $sourceRoot
if ($LASTEXITCODE -ne 0) {
	throw "Failed to clone the Jenova Runtime source."
}
git -C $sourceRoot checkout --quiet $jenovaRef
if ($LASTEXITCODE -ne 0) {
	throw "Failed to check out pinned Jenova revision $jenovaRef."
}

## Hoarbound vendors its GodotSDK and installs a local MSVC toolchain. As on Linux, keep
## Jenova's compiler pipeline but resolve both paths in the project instead of the package DB.
$compilerPatch = @'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8-sig")
start = s.index("// Windows Compilers")
end = s.index("// Jenova MinGW Compiler Implementation", start)
win = s[start:end]
old = """String selectedCompilerPath = jenova::GetInstalledCompilerPathFromPackages(compilerSettings["cpp_toolchain_path"], GetCompilerModel());
            String selectedGodotKitPath = jenova::GetInstalledGodotKitPathFromPackages(compilerSettings["cpp_godotsdk_path"]);"""
new = """String selectedCompilerPath = jenova::GetJenovaProjectDirectory() + "Jenova/Compilers/JenovaMSVCCompiler";
            String selectedGodotKitPath = jenova::GetJenovaProjectDirectory() + "Jenova/GodotSDK";"""
if win.count(old) != 1:
    raise SystemExit(f"expected one Windows MSVC compiler path block, found {win.count(old)}")
p.write_text(s[:start] + win.replace(old, new) + s[end:], encoding="utf-8")
'@

$pythonCommand = Get-Command "py" -ErrorAction SilentlyContinue
if ($pythonCommand) {
	$pythonExe = $pythonCommand.Source
	$pythonPrefix = @("-3")
} else {
	$pythonCommand = Get-Command "python" -ErrorAction SilentlyContinue
	if (-not $pythonCommand) {
		throw "Python 3 is required to build Jenova."
	}
	$pythonExe = $pythonCommand.Source
	$pythonPrefix = @()
}

& $pythonExe @pythonPrefix -m pip install --disable-pip-version-check requests py7zr colored
if ($LASTEXITCODE -ne 0) {
	throw "Failed to install Jenova builder dependencies."
}

@'
[application]
config/name="Hoarbound Jenova API Dump"

[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $apiRoot "project.godot") -Encoding ASCII

function Invoke-GodotApiDump([string[]]$GodotArguments) {
	$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $GodotExe
	$startInfo.WorkingDirectory = $apiRoot
	$startInfo.UseShellExecute = $false
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	foreach ($argument in $GodotArguments) {
		$startInfo.ArgumentList.Add($argument)
	}
	$process = [System.Diagnostics.Process]::Start($startInfo)
	$stdout = $process.StandardOutput.ReadToEnd()
	$stderr = $process.StandardError.ReadToEnd()
	$process.WaitForExit()
	if ($stdout) {
		Write-Host $stdout
	}
	if ($stderr) {
		Write-Host $stderr
	}
	if ($process.ExitCode -ne 0) {
		throw "Godot failed with exit code $($process.ExitCode): $($GodotArguments -join ' ')"
	}
}

Invoke-GodotApiDump @("--headless", "--path", $apiRoot, "--dump-extension-api")
Invoke-GodotApiDump @("--headless", "--path", $apiRoot, "--dump-gdextension-interface-json")

$extensionApi = Join-Path $apiRoot "extension_api.json"
$interfaceApi = Join-Path $apiRoot "gdextension_interface.json"
if (-not (Test-Path $extensionApi -PathType Leaf) -or -not (Test-Path $interfaceApi -PathType Leaf)) {
	throw "Godot did not produce both required API dump files."
}

$setupDependencies = @'
import importlib.util
spec = importlib.util.spec_from_file_location("jenova_builder", "Jenova.Builder.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.deps_version = "4.7"
mod.deploy_mode = True
mod.install_dependencies()
'@
$compilerPatch | & $pythonExe @pythonPrefix - (Join-Path $sourceRoot "Source/script_compiler.cpp")
if ($LASTEXITCODE -ne 0) {
	throw "Failed to patch Jenova's Windows compiler path resolution."
}

Push-Location $sourceRoot
try {
	$setupDependencies | & $pythonExe @pythonPrefix -
	if ($LASTEXITCODE -ne 0) {
		throw "Failed to fetch Jenova's pinned 4.7 dependency bundle."
	}
	$godotExtensionDir = Join-Path $sourceRoot "Dependencies/libgodot/gdextension"
	if (-not (Test-Path $godotExtensionDir -PathType Container)) {
		throw "Jenova dependency bundle is missing Dependencies/libgodot/gdextension."
	}
	Copy-Item -LiteralPath $extensionApi -Destination (Join-Path $godotExtensionDir "extension_api.json") -Force
	Copy-Item -LiteralPath $interfaceApi -Destination (Join-Path $godotExtensionDir "gdextension_interface.json") -Force

	& $pythonExe @pythonPrefix "Jenova.Builder.py" `
		--skip-packaging `
		--deploy-mode `
		--deps-version 4.7 `
		--compiler win-msvc `
		--generate-gdsdk
	if ($LASTEXITCODE -ne 0) {
		throw "Jenova's Windows MSVC runtime build failed."
	}
} finally {
	Pop-Location
}

$vendorRoot = Join-Path $repoRoot "Jenova"
$windowsRuntime = Join-Path $sourceRoot "Win64/Jenova.Runtime.Win64.dll"
$windowsSdk = Join-Path $sourceRoot "Win64/GodotSDK"
$windowsGodotSdkLibrary = Join-Path $windowsSdk "libGodot.x64.lib"
$windowsJenovaSdk = Join-Path $sourceRoot "Win64/JenovaSDK/Jenova.SDK.x64.lib"
if (-not (Test-Path $windowsRuntime -PathType Leaf)) {
	throw "Jenova build did not produce Win64/Jenova.Runtime.Win64.dll."
}
if ((Get-Item -LiteralPath $windowsRuntime).Length -eq 0) {
	throw "Jenova generated an empty Win64/Jenova.Runtime.Win64.dll."
}
if (-not (Test-Path (Join-Path $windowsSdk "gdextension_interface.h") -PathType Leaf) -or
	-not (Test-Path (Join-Path $windowsSdk "Godot/godot.hpp") -PathType Leaf) -or
	-not (Test-Path $windowsGodotSdkLibrary -PathType Leaf)) {
	throw "Jenova build did not produce the custom Windows GodotSDK."
}
if (-not (Test-Path $windowsJenovaSdk -PathType Leaf)) {
	throw "Jenova build did not produce Win64/JenovaSDK/Jenova.SDK.x64.lib."
}
if ((Get-Item -LiteralPath $windowsGodotSdkLibrary).Length -eq 0) {
	throw "Jenova generated an empty Windows GodotSDK library."
}
$lfsAttribute = & git -C $repoRoot check-attr filter -- "Jenova/GodotSDK/libGodot.x64.lib"
if ($LASTEXITCODE -ne 0 -or $lfsAttribute -notmatch ": filter: lfs$") {
	throw "Jenova/GodotSDK/libGodot.x64.lib must be tracked by Git LFS."
}

New-Item -ItemType Directory -Path $vendorRoot, (Join-Path $vendorRoot "GodotSDK"), (Join-Path $vendorRoot "JenovaSDK") -Force | Out-Null
Copy-Item -LiteralPath $windowsRuntime -Destination (Join-Path $vendorRoot "Jenova.Runtime.Win64.dll") -Force
Copy-Item -Path (Join-Path $windowsSdk "*") -Destination (Join-Path $vendorRoot "GodotSDK") -Recurse -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "Source/JenovaSDK.h") -Destination (Join-Path $vendorRoot "JenovaSDK/JenovaSDK.h") -Force
Copy-Item -LiteralPath $windowsJenovaSdk -Destination (Join-Path $vendorRoot "JenovaSDK/Jenova.SDK.x64.lib") -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "Jenova.Runtime.gdextension") -Destination (Join-Path $vendorRoot "Jenova.Runtime.gdextension") -Force

$extensionText = Get-Content -LiteralPath (Join-Path $vendorRoot "Jenova.Runtime.gdextension") -Raw
foreach ($requiredEntry in @(
	'windows\.debug\.x86_64\s*=\s*"res://Jenova/Jenova\.Runtime\.Win64\.dll"',
	'windows\.release\.x86_64\s*=\s*"res://Jenova/Jenova\.Runtime\.Win64\.dll"',
	'linux\.debug\.x86_64\s*=\s*"res://Jenova/Jenova\.Runtime\.Linux64\.so"',
	'linux\.release\.x86_64\s*=\s*"res://Jenova/Jenova\.Runtime\.Linux64\.so"'
)) {
	if ($extensionText -notmatch $requiredEntry) {
		throw "The generated GDExtension descriptor is missing a required platform library mapping: $requiredEntry"
	}
}
if (-not (Test-Path (Join-Path $vendorRoot "Jenova.Runtime.Linux64.so") -PathType Leaf)) {
	throw "The Linux runtime is missing; run tools/ci/bootstrap_jenova_linux.sh before the Windows bootstrap."
}
foreach ($requiredFile in @(
	"Jenova.Runtime.Win64.dll",
	"Jenova.Runtime.Linux64.so",
	"Jenova.Runtime.gdextension",
	"GodotSDK/gdextension_interface.h",
	"GodotSDK/Godot/godot.hpp",
	"GodotSDK/libGodot.x64.lib",
	"GodotSDK/libGodot.x64.a",
	"JenovaSDK/JenovaSDK.h",
	"JenovaSDK/Jenova.SDK.x64.lib"
)) {
	if (-not (Test-Path (Join-Path $vendorRoot $requiredFile) -PathType Leaf)) {
		throw "Jenova vendor layout is incomplete: missing Jenova/$requiredFile"
	}
}

## The editor compiles .cpp scripts with this toolchain; reuse the one the builder just fetched.
& (Join-Path $repoRoot "tools/jenova/install_msvc_compiler.ps1") -ToolchainRoot (Join-Path $sourceRoot "Toolchain")

$buildInfo = Join-Path $vendorRoot "HOARBOUND_JENOVA_BUILD.txt"
$windowsLine = "Windows script compiler: Jenova MicrosoftCompiler -> Jenova/Compilers/JenovaMSVCCompiler (AiO toolchain, Hoarbound patch)"
if (-not (Select-String -LiteralPath $buildInfo -SimpleMatch $windowsLine -Quiet)) {
	Add-Content -LiteralPath $buildInfo -Value $windowsLine -Encoding ASCII
}

$editorLog = Join-Path $workRoot "godot-editor-load.log"
& $GodotExe --headless --editor --path $repoRoot --quit 2>&1 | Tee-Object -FilePath $editorLog
if ($LASTEXITCODE -ne 0) {
	throw "Godot editor failed while scanning the clean Jenova project layout."
}
if (Select-String -LiteralPath $editorLog -Pattern "No loader found for frost_window\.cpp" -Quiet) {
	throw "Godot did not recognize frost_window.cpp as a Jenova Script."
}

Write-Host "[jenova-bootstrap] Windows runtime + custom Godot 4.8-dev6 SDK ready"
Write-Host "[jenova-bootstrap] source revision: $jenovaRef"
Write-Host "[jenova-bootstrap] runtime bytes: $((Get-Item (Join-Path $vendorRoot 'Jenova.Runtime.Win64.dll')).Length)"
