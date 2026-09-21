# ====================================================================
# scpm (PowerShell Script Profile Manager) 安装与升级脚本
# 项目主页: https://github.com/hbhszy/scpm
#
# 一键在线安装 / 升级：
#   irm https://raw.githubusercontent.com/hbhszy/scpm/main/install.ps1 | iex
#
# 本地克隆安装：
#   git clone https://github.com/hbhszy/scpm.git
#   cd scpm; .\install.ps1
# ====================================================================

& {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$NonInteractive
    )

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {}

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   [*] 正在安装 / 升级 scpm (Script Profile Manager)       " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""

    $scpmHome = Join-Path $HOME ".scpm"
    $ps7ModDir = Join-Path $HOME "Documents\PowerShell\Modules\scpm"
    $ps5ModDir = Join-Path $HOME "Documents\WindowsPowerShell\Modules\scpm"

    $targetDirs = @($scpmHome, $ps7ModDir, $ps5ModDir)
    foreach ($td in $targetDirs) {
        if (-not (Test-Path -LiteralPath $td)) {
            New-Item -ItemType Directory -Path $td -Force | Out-Null
        }
    }

    $localSrc = if ($PSScriptRoot) { Join-Path $PSScriptRoot "src" } else { "" }
    $isLocal = ($localSrc -and (Test-Path -LiteralPath (Join-Path $localSrc "scpm.psm1")))

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)

    if ($isLocal) {
        Write-Host "[模式] 检测到本地源文件，正在安装... " -ForegroundColor Green
        $psm1Content = [System.IO.File]::ReadAllText((Join-Path $localSrc "scpm.psm1"), [System.Text.Encoding]::UTF8)
        $psd1Content = [System.IO.File]::ReadAllText((Join-Path $localSrc "scpm.psd1"), [System.Text.Encoding]::UTF8)
    } else {
        Write-Host "[模式] 正在从 GitHub 官方仓库下载最新版... " -ForegroundColor Green
        $repoBase = "https://raw.githubusercontent.com/hbhszy/scpm/main/src"
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $cacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        try {
            $psm1Content = $wc.DownloadString("$repoBase/scpm.psm1?t=$cacheBuster")
            $psd1Content = $wc.DownloadString("$repoBase/scpm.psd1?t=$cacheBuster")
        } catch {
            Write-Error "下载组件失败: $($_.Exception.Message)。 请检查网络连接。 "
            return
        }
    }

    # 复制到各模块路径
    foreach ($td in $targetDirs) {
        [System.IO.File]::WriteAllText((Join-Path $td "scpm.psm1"), $psm1Content, $utf8Bom)
        [System.IO.File]::WriteAllText((Join-Path $td "scpm.psd1"), $psd1Content, $utf8Bom)
    }

    Write-Host "  [OK] scpm 核心模块与元数据部署完成。 " -ForegroundColor Green

    # 尝试导入模块并执行检查 (以 Global 作用域生效)
    $scpmModule = Join-Path $scpmHome "scpm.psm1"
    Import-Module $scpmModule -Force -DisableNameChecking -Global -ErrorAction SilentlyContinue
    Set-Alias -Name sm -Value scpm -Scope Global -ErrorAction SilentlyContinue

    $configFile = Join-Path $scpmHome "config.json"
    if (-not (Test-Path -LiteralPath $configFile)) {
        Write-Host "`n检测到首次使用，将自动启动初始化向导... " -ForegroundColor Yellow
        if (Get-Command scpm -ErrorAction SilentlyContinue) {
            scpm init
        }
    } else {
        if (Get-Command scpm -ErrorAction SilentlyContinue) {
            scpm sync | Out-Null
        }
        Write-Host "  [OK] 现有脚本 Loader 已自动刷新同步。 " -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "   [OK] scpm 安装完成！ 输入 sm help 或 sm ls 即可体验。 " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
} @args
