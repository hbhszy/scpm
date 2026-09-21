<#
.SYNOPSIS
    scpm (PowerShell Script Profile Manager) 卸载脚本

.DESCRIPTION
    用于安全移除 scpm 模块及 Profile 中的 loader 钩子，
    默认完整保留你的坚果云/本地脚本源文件。
#>

[CmdletBinding()]
param(
    [switch]$PurgeAll
)

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

Write-Host "\n=== [scpm] 卸载向导 ===" -ForegroundColor Yellow

$profilesToClean = @(
    (Join-Path $HOME "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
    (Join-Path $HOME "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
)

# 1. 移除 Profile 中的 loader 钩子
foreach ($pf in $profilesToClean) {
    if (Test-Path -LiteralPath $pf) {
        $content = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8)
        if ($content -match '(?ms)# >>> scpm loader start >>>.*?# <<< scpm loader end <<<') {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($content, '(?ms)# >>> scpm loader start >>>.*?# <<< scpm loader end <<<(\r?\n)?', '')
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($pf, $newContent.TrimEnd() + "`n", $utf8Bom)
            Write-Host "  [✓] 已从 Profile 移除引导钩子: $pf" -ForegroundColor Green
        }
    }
}

# 2. 移除模块目录
$moduleDirs = @(
    (Join-Path $HOME "Documents\PowerShell\Modules\scpm"),
    (Join-Path $HOME "Documents\WindowsPowerShell\Modules\scpm")
)

foreach ($md in $moduleDirs) {
    if (Test-Path -LiteralPath $md) {
        Remove-Item -LiteralPath $md -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [✓] 已删除模块安装目录: $md" -ForegroundColor Green
    }
}

# 3. 询问是否清理 ~/.scpm 配置
$scpmHome = Join-Path $HOME ".scpm"
if (Test-Path -LiteralPath $scpmHome) {
    if ($PurgeAll) {
        Remove-Item -LiteralPath $scpmHome -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [✓] 已彻底清除 ~/.scpm 配置文件。" -ForegroundColor Green
    } else {
        Write-Host "  [保留] ~/.scpm 配置文件已安全保留 (如需彻底清理可指定 -PurgeAll)。" -ForegroundColor DarkGray
    }
}

Write-Host "\n[完成] scpm 卸载完毕！你的坚果云/本地自定义脚本文件均未被删除，保持原样。" -ForegroundColor Green
