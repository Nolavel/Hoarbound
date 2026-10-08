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

Push-Location $apiRoot
try {
	& $GodotExe --headless --path $apiRoot --dump-extension-api
	if ($LASTEXITCODE -ne 0) {
		throw "Godot failed to dump the GDExtension API."
	}
	& $GodotExe --headless --path $apiRoot --dump-gdextension-interface-json
	if ($LASTEXITCODE -ne 0) {
		throw "Godot failed to dump the GDExtension interface."
	}
} finally {
	Pop-Location
}

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
if (-not (Test-Path (Join-Path $windowsSdk "gdextension_interface.h") -PathType Leaf) -or
	-not (Test-Path (Join-Path $windowsSdk "Godot/godot.hpp") -PathType Leaf) -or
	-not (Test-Path $windowsGodotSdkLibrary -PathType Leaf)) {
	throw "Jenova build did not produce the custom Windows GodotSDK."
}
if (-not (Test-Path $windowsJenovaSdk -PathType Leaf)) {
	throw "Jenova build did not produce Win64/JenovaSDK/Jenova.SDK.x64.lib."
}
$oversizedFiles = @(
	Get-ChildItem -LiteralPath (Join-Path $sourceRoot "Win64") -File -Recurse |
		Where-Object { $_.Length -ge 100MB }
)
if ($oversizedFiles.Count -gt 0) {
	$oversizedList = $oversizedFiles | ForEach-Object { "$($_.Length) bytes: $($_.FullName)" }
	throw "Jenova generated files exceed GitHub's 100 MiB file limit; do not vendor this output:`n$($oversizedList -join "`n")"
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

$editorLog = Join-Path $workRoot "godot-editor-load.log"
& $GodotExe --headless --editor --path $repoRoot --quit 2>&1 | Tee-Object -FilePath $editorLog
if ($LASTEXITCODE -ne 0) {
	throw "Godot editor failed while scanning the clean Jenova project layout."
}
if (Select-String -LiteralPath $editorLog -Pattern "No loader found for frost_window\.cpp" -Quiet) {
	throw "Godot did not recognize frost_window.cpp as a Jenova Script."
}

$sceneLog = Join-Path $workRoot "godot-frost-scene.log"
& $GodotExe --headless --path $repoRoot --quit-after 2 "res://scenes/experimental/jenova_frost_lab.tscn" 2>&1 |
	Tee-Object -FilePath $sceneLog
if ($LASTEXITCODE -ne 0) {
	throw "Godot failed to instantiate the Jenova frost lab scene."
}
if (Select-String -LiteralPath $sceneLog -Pattern "No loader found for frost_window\.cpp" -Quiet) {
	throw "Godot did not recognize frost_window.cpp while opening the frost lab scene."
}
if (-not (Select-String -LiteralPath $sceneLog -Pattern "\[jenova-frost\] C\+\+ controller ready" -Quiet)) {
	throw "Godot opened the frost scene without running the Jenova C++ controller."
}

Write-Host "[jenova-bootstrap] Windows runtime + custom Godot 4.8-dev6 SDK ready"
Write-Host "[jenova-bootstrap] source revision: $jenovaRef"
Write-Host "[jenova-bootstrap] runtime bytes: $((Get-Item (Join-Path $vendorRoot 'Jenova.Runtime.Win64.dll')).Length)"
