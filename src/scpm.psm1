# ====================================================================
# scpm (PowerShell Script Profile Manager)
# Module: scpm.psm1
# ====================================================================

$Script:ScpmVersion = "1.2.0"
$Script:ScpmHome = Join-Path $HOME ".scpm"
$Script:ConfigFile = Join-Path $Script:ScpmHome "config.json"
$Script:RegistryFile = Join-Path $Script:ScpmHome "registry.json"
$Script:LoaderFile = Join-Path $Script:ScpmHome "loader.ps1"

# --------------------------------------------------------------------
# 基础辅助函数 (Internal Helpers)
# --------------------------------------------------------------------

function Get-ScpmConfigInternal {
    if (Test-Path -LiteralPath $Script:ConfigFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($Script:ConfigFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xfeff)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                return ConvertFrom-Json $raw
            }
        } catch {
            Write-Warning "[scpm] 读取 config.json 失败: $($_.Exception.Message)"
        }
    }
    return $null
}

function Save-ScpmConfigInternal([object]$config) {
    if (-not (Test-Path -LiteralPath $Script:ScpmHome)) {
        New-Item -ItemType Directory -Path $Script:ScpmHome -Force | Out-Null
    }
    $json = $config | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Script:ConfigFile, $json, $utf8NoBom)
}

function Get-ScpmRegistryInternal {
    if (Test-Path -LiteralPath $Script:RegistryFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($Script:RegistryFile, [System.Text.Encoding]::UTF8).TrimStart([char]0xfeff)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $obj = ConvertFrom-Json $raw
                if ($null -ne $obj) { return $obj }
            }
        } catch {
            Write-Warning "[scpm] 读取 registry.json 失败: $($_.Exception.Message)"
        }
    }
    return [PSCustomObject]@{
        version = $Script:ScpmVersion
        scripts = [PSCustomObject]@{}
    }
}

function Save-ScpmRegistryInternal([object]$reg) {
    if (-not (Test-Path -LiteralPath $Script:ScpmHome)) {
        New-Item -ItemType Directory -Path $Script:ScpmHome -Force | Out-Null
    }
    $json = $reg | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Script:RegistryFile, $json, $utf8NoBom)
}

function ConvertTo-PortablePath([string]$absolutePath) {
    if ([string]::IsNullOrWhiteSpace($absolutePath)) { return $absolutePath }
    $normalizedHome = $HOME.TrimEnd('\', '/')
    if ($absolutePath.StartsWith($normalizedHome, [System.StringComparison]::OrdinalIgnoreCase)) {
        $sub = $absolutePath.Substring($normalizedHome.Length).TrimStart('\', '/')
        return "`$HOME\$sub"
    }
    return $absolutePath
}

function Resolve-PortablePathInternal([string]$portablePath) {
    if ([string]::IsNullOrWhiteSpace($portablePath)) { return $portablePath }
    if ($portablePath.StartsWith('$HOME\', [System.StringComparison]::OrdinalIgnoreCase) -or $portablePath.StartsWith('$HOME/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $sub = $portablePath.Substring(6)
        return (Join-Path $HOME $sub)
    }
    if ($portablePath.StartsWith('~\', [System.StringComparison]::OrdinalIgnoreCase) -or $portablePath.StartsWith('~/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $sub = $portablePath.Substring(2)
        return (Join-Path $HOME $sub)
    }
    return $portablePath
}

function Get-ScpmDisplayWidthInternal([string]$str) {
    if ([string]::IsNullOrEmpty($str)) { return 0 }
    $w = 0
    foreach ($ch in $str.ToCharArray()) {
        $cp = [int]$ch
        if (($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or
            ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
            ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
            ($cp -ge 0x3000 -and $cp -le 0x303F) -or
            ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or
            ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
            ($cp -ge 0x20000 -and $cp -le 0x2A6DF)) {
            $w += 2
        } else {
            $w += 1
        }
    }
    return $w
}

function Truncate-ScpmDisplayStringInternal([string]$str, [int]$maxWidth) {
    if ([string]::IsNullOrEmpty($str)) { return "" }
    $dw = Get-ScpmDisplayWidthInternal $str
    if ($dw -le $maxWidth) { return $str }
    if ($maxWidth -le 3) {
        $res = ""
        $w = 0
        foreach ($ch in $str.ToCharArray()) {
            $cw = if ([int]$ch -gt 255) { 2 } else { 1 }
            if ($w + $cw -gt $maxWidth) { break }
            $res += $ch
            $w += $cw
        }
        return $res
    }
    $targetWidth = $maxWidth - 3
    $curWidth = 0
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $str.ToCharArray()) {
        $cp = [int]$ch
        $cw = if (($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or
            ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
            ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
            ($cp -ge 0x3000 -and $cp -le 0x303F) -or
            ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or
            ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
            ($cp -ge 0x20000 -and $cp -le 0x2A6DF)) { 2 } else { 1 }
        if ($curWidth + $cw -gt $targetWidth) {
            [void]$sb.Append("...")
            return $sb.ToString()
        }
        [void]$sb.Append($ch)
        $curWidth += $cw
    }
    return $sb.ToString()
}

function Pad-ScpmDisplayStringInternal([string]$str, [int]$targetWidth) {
    $dw = Get-ScpmDisplayWidthInternal $str
    if ($dw -ge $targetWidth) { return $str }
    return $str + (" " * ($targetWidth - $dw))
}

function Update-ScpmLoaderInternal {
    $reg = Get-ScpmRegistryInternal
    $config = Get-ScpmConfigInternal
    
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# ====================================================================")
    [void]$sb.AppendLine("# This file is auto-generated by scpm (PowerShell Script Profile Manager).")
    [void]$sb.AppendLine("# Do not edit this file directly. Changes will be overwritten.")
    [void]$sb.AppendLine("# Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("# ====================================================================")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("# Ensure scpm CLI is always available")
    [void]$sb.AppendLine("if (-not (Get-Command scpm -ErrorAction SilentlyContinue)) {")
    [void]$sb.AppendLine("    `$__scpmPsm1 = Join-Path `$HOME '.scpm\scpm.psm1'")
    [void]$sb.AppendLine("    if (Test-Path -LiteralPath `$__scpmPsm1) {")
    [void]$sb.AppendLine("        Import-Module `$__scpmPsm1 -DisableNameChecking -ErrorAction SilentlyContinue")
    [void]$sb.AppendLine("    }")
    [void]$sb.AppendLine("}")
    [void]$sb.AppendLine("")

    $enabledCount = 0
    if ($reg.PSObject.Properties["scripts"]) {
        foreach ($prop in $reg.scripts.PSObject.Properties) {
            $item = $prop.Value
            if ($item.enabled -eq $true) {
                $enabledCount++
                $pPath = $item.path
                $desc = $item.description
                if (-not [string]::IsNullOrWhiteSpace($desc)) {
                    [void]$sb.AppendLine("# [$($item.name)] $desc")
                } else {
                    [void]$sb.AppendLine("# [$($item.name)]")
                }
                
                if ($pPath.StartsWith('$HOME\', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $rel = $pPath.Substring(6).Replace("'", "''")
                    [void]$sb.AppendLine("`$__s = Join-Path `$HOME '$rel'")
                    [void]$sb.AppendLine("if (Test-Path -LiteralPath `$__s) { . `$__s }")
                } else {
                    $escaped = $pPath.Replace("'", "''")
                    [void]$sb.AppendLine("if (Test-Path -LiteralPath '$escaped') { . '$escaped' }")
                }
                [void]$sb.AppendLine("")
            }
        }
    }

    if ($enabledCount -eq 0) {
        [void]$sb.AppendLine("# (No scripts currently enabled)")
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Script:LoaderFile, $sb.ToString(), $utf8Bom)
    return $enabledCount
}

function Detect-NutstoreCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()
    
    $potentialBases = @(
        (Join-Path $HOME "Nutstore\1\我的坚果云"),
        (Join-Path $HOME "Nutstore\我的坚果云")
    )

    foreach ($b in $potentialBases) {
        if (Test-Path -LiteralPath $b) {
            $scriptsSub = Join-Path $b "scripts"
            if (-not $candidates.Contains($scriptsSub)) {
                $candidates.Add($scriptsSub)
            }
        }
    }
    return $candidates
}

function Extract-ScriptSynopsisInternal([string]$filePath) {
    if (-not (Test-Path -LiteralPath $filePath)) { return "" }
    try {
        $lines = Get-Content -LiteralPath $filePath -TotalCount 35 -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line -match '^\.SYNOPSIS\s*(.*)$') {
                if (-not [string]::IsNullOrWhiteSpace($matches[1])) { return $matches[1].Trim() }
                if ($i + 1 -lt $lines.Count) { return $lines[$i + 1].Trim() }
            }
            if ($line -match '^#\s*description:\s*(.*)$' -or $line -match '^#\s*简介[：:]\s*(.*)$' -or $line -match '^#\s*(.*CLI.*模式切换.*)$') {
                return $matches[1].Trim()
            }
        }
    } catch {}
    return ""
}

function Get-ScpmScriptMethodsInternal([string]$filePath) {
    $result = [PSCustomObject]@{
        Path = $filePath
        FileExists = $false
        Synopsis = ""
        Description = ""
        Usage = ""
        Functions = [System.Collections.Generic.List[object]]::new()
        Aliases = [System.Collections.Generic.List[object]]::new()
        TopLevelFunctions = [System.Collections.Generic.List[string]]::new()
        Summary = ""
    }

    if (-not (Test-Path -LiteralPath $filePath)) {
        return $result
    }

    $result.FileExists = $true

    try {
        $raw = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)
    } catch {
        return $result
    }

    # 1. 提取帮助注释 (.SYNOPSIS, .DESCRIPTION, .USAGE)
    if ($raw -match '(?s)\.SYNOPSIS\s*(.*?)(?=\r?\n\s*\.[A-Z]+|\#\>)') {
        $result.Synopsis = $matches[1].Trim()
    }
    if ($raw -match '(?s)\.DESCRIPTION\s*(.*?)(?=\r?\n\s*\.[A-Z]+|\#\>)') {
        $result.Description = $matches[1].Trim()
    }
    if ($raw -match '(?s)\.USAGE\s*(.*?)(?=\r?\n\s*\.[A-Z]+|\#\>)') {
        $result.Usage = $matches[1].Trim()
    }

    # 2. 通过 AST 解析函数与别名
    try {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($raw, [ref]$tokens, [ref]$errors)

        if ($null -ne $ast) {
            $funcAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($f in $funcAsts) {
                # 检查是否为嵌套函数
                $isNested = $false
                $enclosing = ""
                $parent = $f.Parent
                while ($null -ne $parent) {
                    if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                        $isNested = $true
                        $enclosing = $parent.Name
                        break
                    }
                    $parent = $parent.Parent
                }

                $params = [System.Collections.Generic.List[object]]::new()
                $paramBlock = if ($f.Parameters) { $f.Parameters } elseif ($f.Body.ParamBlock) { $f.Body.ParamBlock.Parameters } else { $null }
                $sigParts = [System.Collections.Generic.List[string]]::new()

                if ($null -ne $paramBlock) {
                    foreach ($p in $paramBlock) {
                        $pName = "$" + $p.Name.VariablePath.UserPath
                        $typeName = if ($p.StaticType -and $p.StaticType.Name -ne "Object") { "[$($p.StaticType.Name)]" } else { "" }
                        $defaultVal = if ($p.DefaultValue) { $p.DefaultValue.Extent.Text } else { "" }

                        $valSet = $p.Attributes | Where-Object { $_.TypeName.Name -in @("ValidateSet", "ValidateSetAttribute") }
                        $valSetOptions = @()
                        if ($valSet) {
                            $valSetOptions = @($valSet.PositionalArguments | ForEach-Object {
                                if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value } else { $_.Extent.Text.Trim("'", '"') }
                            }) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        }

                        $params.Add([PSCustomObject]@{
                            Name = $pName
                            Type = $typeName
                            DefaultValue = $defaultVal
                            ValidateSet = $valSetOptions
                        })

                        if ($valSetOptions.Count -gt 0) {
                            $sigParts.Add("[$pName {$($valSetOptions -join ' | ')}]")
                        } elseif (-not [string]::IsNullOrWhiteSpace($defaultVal)) {
                            $sigParts.Add("[$pName = $defaultVal]")
                        } elseif (-not [string]::IsNullOrWhiteSpace($typeName)) {
                            $sigParts.Add("[$typeName$pName]")
                        } else {
                            $sigParts.Add("[$pName]")
                        }
                    }
                }

                $sig = if ($sigParts.Count -gt 0) { "$($f.Name) $($sigParts -join ' ')" } else { $f.Name }

                $funcObj = [PSCustomObject]@{
                    Name = $f.Name
                    IsNested = $isNested
                    Enclosing = $enclosing
                    Parameters = $params
                    Signature = $sig
                    Line = $f.Extent.StartLineNumber
                }
                $result.Functions.Add($funcObj)

                if (-not $isNested) {
                    $result.TopLevelFunctions.Add($f.Name)
                }
            }

            # 解析别名 (Set-Alias / New-Alias)
            $cmdAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
            foreach ($cmd in $cmdAsts) {
                $cmdName = $cmd.GetCommandName()
                if ($cmdName -in @("Set-Alias", "New-Alias", "sal")) {
                    $aliasName = ""
                    $aliasVal = ""
                    $elements = $cmd.CommandElements
                    for ($i = 1; $i -lt $elements.Count; $i++) {
                        $elemText = $elements[$i].Extent.Text
                        if ($elemText -in @("-Name", "-n") -and ($i + 1 -lt $elements.Count)) {
                            $aliasName = $elements[++$i].Extent.Text.Trim("'", '"')
                        } elseif ($elemText -in @("-Value", "-v") -and ($i + 1 -lt $elements.Count)) {
                            $aliasVal = $elements[++$i].Extent.Text.Trim("'", '"')
                        } elseif (-not $aliasName) {
                            $aliasName = $elemText.Trim("'", '"')
                        } elseif (-not $aliasVal) {
                            $aliasVal = $elemText.Trim("'", '"')
                        }
                    }
                    if (-not [string]::IsNullOrWhiteSpace($aliasName)) {
                        $result.Aliases.Add([PSCustomObject]@{
                            Name = $aliasName
                            Target = $aliasVal
                        })
                    }
                }
            }
        }
    } catch {}

    if ($result.TopLevelFunctions.Count -gt 0) {
        $result.Summary = ($result.TopLevelFunctions -join ", ")
    } elseif ($result.Functions.Count -gt 0) {
        $result.Summary = (($result.Functions | ForEach-Object { $_.Name }) -join ", ")
    } else {
        $result.Summary = "(直接执行脚本文件)"
    }

    return $result
}

function Resolve-ScpmScriptPropsInternal([string]$target, [array]$scriptProps) {
    $results = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($target)) { return $results }

    # 1. 尝试数字序号匹配 (1-based)
    $num = 0
    if ([int]::TryParse($target, [ref]$num) -and $num -ge 1 -and $num -le $scriptProps.Count) {
        $results.Add($scriptProps[$num - 1])
        return $results
    }

    # 2. 尝试名称精确匹配或加 .ps1 匹配
    $withExt = if ($target.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) { $target } else { "$target.ps1" }
    foreach ($p in $scriptProps) {
        if ($p.Name -eq $target -or $p.Name -eq $withExt) {
            $results.Add($p)
            return $results
        }
    }

    # 3. 尝试通配符或包含匹配
    foreach ($p in $scriptProps) {
        if ($p.Name -like $target -or $p.Name -like "*$target*") {
            if (-not $results.Contains($p)) {
                $results.Add($p)
            }
        }
    }

    return $results
}

function Select-ScpmScriptSingleInteractive([string]$title, [array]$scriptProps) {
    if ($null -eq $scriptProps -or $scriptProps.Count -eq 0) {
        return $null
    }

    Write-Host "`n=== $title ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $scriptProps.Count; $i++) {
        $p = $scriptProps[$i]
        $st = if ($p.Value.enabled) { "[✓]" } else { "[✗]" }
        $stColor = if ($p.Value.enabled) { "Green" } else { "DarkGray" }
        Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor White
        Write-Host "$st " -NoNewline -ForegroundColor $stColor
        Write-Host "$($p.Name.PadRight(22))" -NoNewline -ForegroundColor Cyan
        Write-Host "$($p.Value.description)" -ForegroundColor Gray
    }

    $choice = Read-Host "`n请选择脚本编号 [1-$($scriptProps.Count)] (q 退出)"
    if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim().ToLower() -in @("q", "quit", "exit")) {
        Write-Host "已取消。" -ForegroundColor Gray
        return $null
    }

    $num = 0
    if ([int]::TryParse($choice.Trim(), [ref]$num) -and $num -ge 1 -and $num -le $scriptProps.Count) {
        return $scriptProps[$num - 1]
    }

    # 尝试按名称查
    $matched = Resolve-ScpmScriptPropsInternal $choice.Trim() $scriptProps
    if ($matched.Count -gt 0) {
        return $matched[0]
    }

    Write-Host "[错误] 无效的编号或名称。" -ForegroundColor Red
    return $null
}

# --------------------------------------------------------------------
# 核心业务命令实现
# --------------------------------------------------------------------

function Invoke-ScpmInit {
    $StoragePath = ""
    $Force = $false
    for ($i = 0; $i -lt $args.Count; $i++) {
        $curr = $args[$i]
        if ($curr -in @("-StoragePath", "-p", "--path") -and ($i + 1 -lt $args.Count)) {
            $StoragePath = $args[++$i]
        } elseif ($curr -in @("-Force", "-f", "--force")) {
            $Force = $true
        } elseif (-not $StoragePath) {
            $StoragePath = $curr
        }
    }

    Write-Host "`n=== [scpm] PowerShell 脚本管理器初始化向导 ===" -ForegroundColor Cyan
    
    $existingConfig = Get-ScpmConfigInternal
    if ($null -ne $existingConfig -and (-not $Force)) {
        Write-Host "检测到已存在的配置: $($existingConfig.storagePath)" -ForegroundColor Yellow
        $reinit = Read-Host "是否重新初始化？(y/N)"
        if ($reinit.Trim().ToLower() -ne "y") {
            Write-Host "已取消初始化。" -ForegroundColor Gray
            return
        }
    }

    # 1. 探测坚果云路径
    $nutstoreDirs = Detect-NutstoreCandidates
    $selectedPath = ""

    if (-not [string]::IsNullOrWhiteSpace($StoragePath)) {
        $selectedPath = $StoragePath
    } else {
        Write-Host "`n[步骤 1/3] 选择脚本存储目录：" -ForegroundColor Green
        $options = [System.Collections.Generic.List[string]]::new()
        
        $idx = 1
        foreach ($cand in $nutstoreDirs) {
            $displayPath = ConvertTo-PortablePath $cand
            Write-Host "  [$idx] 坚果云云同步目录 (推荐): $displayPath" -ForegroundColor Yellow
            $options.Add($cand)
            $idx++
        }

        $localDefault = Join-Path $Script:ScpmHome "scripts"
        $displayLocal = ConvertTo-PortablePath $localDefault
        Write-Host "  [$idx] 本地默认目录: $displayLocal" -ForegroundColor White
        $options.Add($localDefault)
        $idx++

        Write-Host "  [$idx] 自定义绝对路径" -ForegroundColor White
        $customIdx = $idx

        $promptText = "请选择目录 [1-$customIdx] (默认 1): "
        $choice = Read-Host $promptText
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

        $num = 0
        if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $options.Count) {
            $selectedPath = $options[$num - 1]
        } elseif ($num -eq $customIdx) {
            $inputPath = Read-Host "请输入自定义存储路径"
            if ([string]::IsNullOrWhiteSpace($inputPath)) {
                $selectedPath = $options[0]
            } else {
                $selectedPath = $inputPath.Trim()
            }
        } else {
            $selectedPath = $options[0]
        }
    }

    # 解析和创建存储目录
    $selectedPath = Resolve-PortablePathInternal $selectedPath
    if (-not (Test-Path -LiteralPath $selectedPath)) {
        New-Item -ItemType Directory -Path $selectedPath -Force | Out-Null
        Write-Host "已创建脚本存储目录: $selectedPath" -ForegroundColor Green
    } else {
        Write-Host "使用现有存储目录: $selectedPath" -ForegroundColor Green
    }

    # 2. 注入 Profile 引导钩子
    Write-Host "`n[步骤 2/3] 配置 PowerShell Profile 注入引导..." -ForegroundColor Green
    $profilesToHook = @(
        (Join-Path $HOME "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
        (Join-Path $HOME "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
    )

    $hookBlock = @'
# >>> scpm loader start >>>
$scpmLoader = Join-Path $HOME ".scpm\loader.ps1"
if (Test-Path -LiteralPath $scpmLoader) { . $scpmLoader }
# <<< scpm loader end <<<
'@

    foreach ($pf in $profilesToHook) {
        $pfDir = Split-Path $pf -Parent
        if (-not (Test-Path -LiteralPath $pfDir)) {
            New-Item -ItemType Directory -Path $pfDir -Force | Out-Null
        }

        $existingContent = ""
        if (Test-Path -LiteralPath $pf) {
            $existingContent = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8)
        }

        # 清理旧的手动引用或旧 hook
        $newContent = $existingContent
        if ($newContent -match '(?ms)# >>> scpm loader start >>>.*?# <<< scpm loader end <<<') {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($newContent, '(?ms)# >>> scpm loader start >>>.*?# <<< scpm loader end <<<(\r?\n)?', '')
        }
        
        if ($newContent -match '(?ms)# agy \(Antigravity CLI\) 模式切换.*?if \(Test-Path -LiteralPath \$agyScript\) \{ \. \$agyScript \}(\r?\n)?') {
            $newContent = [System.Text.RegularExpressions.Regex]::Replace($newContent, '(?ms)# agy \(Antigravity CLI\) 模式切换.*?if \(Test-Path -LiteralPath \$agyScript\) \{ \. \$agyScript \}(\r?\n)?', '')
        }

        $newContent = $newContent.TrimEnd() + "`n`n" + $hookBlock + "`n"
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($pf, $newContent, $utf8Bom)
        
        $relPf = ConvertTo-PortablePath $pf
        Write-Host "  [✓] 已注入 Hook: $relPf" -ForegroundColor Green
    }

    # 3. 扫描并自动导入现有脚本
    Write-Host "`n[步骤 3/3] 扫描并导入脚本库..." -ForegroundColor Green
    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts) {
        $reg | Add-Member -NotePropertyName "scripts" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    $nutstoreBase = Split-Path $selectedPath -Parent
    if (Test-Path -LiteralPath $nutstoreBase) {
        $rootAgy = Join-Path $nutstoreBase "agy-toggle.ps1"
        if ((Test-Path -LiteralPath $rootAgy) -and ($selectedPath -ne $nutstoreBase)) {
            $destAgy = Join-Path $selectedPath "agy-toggle.ps1"
            if (-not (Test-Path -LiteralPath $destAgy)) {
                Copy-Item -LiteralPath $rootAgy -Destination $destAgy -Force
                Write-Host "  [自动收录] 检测到现有坚果云脚本，已收纳至脚本库: agy-toggle.ps1" -ForegroundColor Yellow
            }
        }
    }

    $allScripts = Get-ChildItem -LiteralPath $selectedPath -Filter "*.ps1" -File -ErrorAction SilentlyContinue
    $importedCount = 0
    foreach ($file in $allScripts) {
        $name = $file.Name
        if (-not $reg.scripts.PSObject.Properties[$name]) {
            $desc = Extract-ScriptSynopsisInternal $file.FullName
            if ([string]::IsNullOrWhiteSpace($desc)) {
                if ($name -like "*agy*") { $desc = "Antigravity CLI 模式切换与状态管理" }
                else { $desc = "自定义 PowerShell 脚本: $name" }
            }
            $pPath = ConvertTo-PortablePath $file.FullName
            $reg.scripts | Add-Member -NotePropertyName $name -NotePropertyValue ([PSCustomObject]@{
                name = $name
                enabled = $true
                description = $desc
                path = $pPath
                addedAt = (Get-Date -Format "o")
            }) -Force
            Write-Host "  [✓] 已注册并启用: $name ($desc)" -ForegroundColor Green
            $importedCount++
        }
    }

    $configObj = [PSCustomObject]@{
        version = $Script:ScpmVersion
        storagePath = ConvertTo-PortablePath $selectedPath
        profiles = $profilesToHook | ForEach-Object { ConvertTo-PortablePath $_ }
        editor = if (Get-Command code -ErrorAction SilentlyContinue) { "code" } else { "notepad" }
        initializedAt = (Get-Date -Format "o")
    }

    Save-ScpmConfigInternal $configObj
    Save-ScpmRegistryInternal $reg
    $enabled = Update-ScpmLoaderInternal

    Write-Host "`n[成功] scpm 初始化完成！" -ForegroundColor Green
    Write-Host "  - 脚本存储库: $(ConvertTo-PortablePath $selectedPath)" -ForegroundColor Cyan
    Write-Host "  - 已管理脚本: $($reg.scripts.PSObject.Properties.Count) 个 (已启用: $enabled 个)" -ForegroundColor Cyan
    Write-Host "  - 快捷提示: 键入 'scpm list' 查看列表，'scpm help' 查看所有命令。" -ForegroundColor Gray
}

function Invoke-ScpmList {
    [CmdletBinding()]
    param([switch]$Detail)

    $reg = Get-ScpmRegistryInternal
    $config = Get-ScpmConfigInternal

    Write-Host "`n=== [scpm] 脚本管理清单 ===" -ForegroundColor Cyan
    if ($null -ne $config) {
        Write-Host "存储库路径: $($config.storagePath)`n" -ForegroundColor DarkGray
    }

    if ($null -eq $reg.scripts -or $reg.scripts.PSObject.Properties.Count -eq 0) {
        Write-Host "当前暂无受管理的脚本。使用 'scpm add <文件路径>' 或 'scpm new <名称>' 开始添加！" -ForegroundColor Yellow
        return
    }

    $total = 0
    $enabled = 0
    $disabled = 0
    $idx = 1

    foreach ($prop in $reg.scripts.PSObject.Properties) {
        $item = $prop.Value
        $total++
        $realPath = Resolve-PortablePathInternal $item.path
        $fileExists = Test-Path -LiteralPath $realPath
        $mInfo = Get-ScpmScriptMethodsInternal $realPath

        $statusMark = if ($item.enabled) {
            $enabled++
            " [✓] "
        } else {
            $disabled++
            " [✗] "
        }
        $statusColor = if ($item.enabled) { "Green" } else { "DarkGray" }
        $idxStr = "[$idx]".PadRight(5)

        Write-Host " $idxStr" -ForegroundColor DarkGray -NoNewline
        Write-Host $statusMark -ForegroundColor $statusColor -NoNewline
        Write-Host "$($item.name.PadRight(22))" -ForegroundColor Cyan -NoNewline
        Write-Host "$($item.description)" -ForegroundColor White

        $indent = "            "
        if (-not $fileExists) {
            Write-Host "$indent[文件缺失] $realPath" -ForegroundColor Red
        } else {
            Write-Host "${indent}路径: $($item.path)" -ForegroundColor DarkGray
            if (-not [string]::IsNullOrWhiteSpace($mInfo.Summary)) {
                Write-Host "${indent}方法: " -NoNewline -ForegroundColor DarkGray
                Write-Host "$($mInfo.Summary)" -ForegroundColor Yellow
            }
        }

        if ($Detail -and $fileExists) {
            if ($mInfo.Functions.Count -gt 0) {
                foreach ($fn in $mInfo.Functions) {
                    if (-not $fn.IsNested) {
                        Write-Host "$indent  └─ $($fn.Signature)" -ForegroundColor White
                    }
                }
            }
        }

        $idx++
    }

    Write-Host "`n-----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "总计: $total 个脚本 | 已启用: $enabled | 已禁用: $disabled" -ForegroundColor Gray
    Write-Host "提示: 运行 'sm toggle' 集中启停管理，'sm info <编号>' 查看方法详情。" -ForegroundColor DarkGray
}

function Invoke-ScpmTui {
    [CmdletBinding()]
    param()

    # 1. 检测终端是否支持交互式 TUI
    $isInteractive = $false
    try {
        if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and [Environment]::UserInteractive) {
            $null = $Host.UI.RawUI.CursorPosition
            $isInteractive = $true
        }
    } catch {
        $isInteractive = $false
    }

    if (-not $isInteractive) {
        Write-Host "[scpm] 检测到当前终端处于非交互或重定向环境，为您展示清单：" -ForegroundColor Yellow
        Invoke-ScpmList
        return
    }

    function Refresh-TuiDataInternal {
        $reg = Get-ScpmRegistryInternal
        $scriptProps = @()
        if ($null -ne $reg.scripts) {
            $scriptProps = @($reg.scripts.PSObject.Properties)
        }

        $items = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $scriptProps.Count; $i++) {
            $p = $scriptProps[$i]
            $realPath = Resolve-PortablePathInternal $p.Value.path
            $mInfo = Get-ScpmScriptMethodsInternal $realPath
            $items.Add([PSCustomObject]@{
                Index = ($i + 1)
                Name = $p.Name
                Enabled = [bool]$p.Value.enabled
                Description = $p.Value.description
                Path = $p.Value.path
                RealPath = $realPath
                FileExists = (Test-Path -LiteralPath $realPath)
                MethodInfo = $mInfo
            })
        }
        return @{
            Registry = $reg
            Items = $items
        }
    }

    $data = Refresh-TuiDataInternal
    $items = $data.Items
    $reg = $data.Registry
    $config = Get-ScpmConfigInternal

    if ($items.Count -eq 0) {
        Write-Host "`n[scpm] 当前暂无受管理的脚本。使用 'sm add <路径>' 或 'sm new <名称>' 开始添加！" -ForegroundColor Yellow
        return
    }

    $cursor = 0
    $scrollOffset = 0
    $searchFilter = ""
    $inSearchMode = $false
    $statusMsg = "欢迎进入 scpm 控制台！[↑/↓] 导航，[空格] 启停，[/] 搜索，[q] 退出。"
    $statusMsgColor = "Gray"

    $esc = [char]27
    $savedCursorVisible = $true
    try {
        $savedCursorVisible = [Console]::CursorVisible
    } catch {}

    $fgMap = @{
        "Black"       = "$esc[30m"
        "DarkRed"     = "$esc[31m"
        "DarkGreen"   = "$esc[32m"
        "DarkYellow"  = "$esc[33m"
        "DarkBlue"    = "$esc[34m"
        "DarkMagenta" = "$esc[35m"
        "DarkCyan"    = "$esc[36m"
        "Gray"        = "$esc[37m"
        "DarkGray"    = "$esc[90m"
        "Red"         = "$esc[91m"
        "Green"       = "$esc[92m"
        "Yellow"      = "$esc[93m"
        "Blue"        = "$esc[94m"
        "Magenta"     = "$esc[95m"
        "Cyan"        = "$esc[96m"
        "White"       = "$esc[97m"
    }

    $bgMap = @{
        "Black"       = "$esc[40m"
        "DarkRed"     = "$esc[41m"
        "DarkGreen"   = "$esc[42m"
        "DarkYellow"  = "$esc[43m"
        "DarkBlue"    = "$esc[44m"
        "DarkMagenta" = "$esc[45m"
        "DarkCyan"    = "$esc[46m"
        "Gray"        = "$esc[47m"
        "DarkGray"    = "$esc[100m"
        "Cyan"        = "$esc[106m"
        "White"       = "$esc[107m"
    }

    $reset = "$esc[0m"

    function Out-Ansi {
        param(
            [string]$Text = "",
            [string]$Fg = $null,
            [string]$Bg = $null,
            [switch]$NoNewline
        )
        $prefix = ""
        if ($Fg -and $fgMap.ContainsKey($Fg)) { $prefix += $fgMap[$Fg] }
        if ($Bg -and $bgMap.ContainsKey($Bg)) { $prefix += $bgMap[$Bg] }

        $suffix = if ($prefix) { $reset } else { "" }
        $nl = if ($NoNewline) { "" } else { "`n" }
        [Console]::Write("$prefix$Text$suffix$nl")
    }

    # 启用备用屏幕缓冲区 (Alternate Screen Buffer) 并隐藏光标
    # 彻底隔离终端历史滚动，防止任何画面残影和上下漂移
    try {
        [Console]::Write("$esc[?1049h$esc[?25l")
    } catch {}
    Clear-Host

    try {
        while ($true) {
            # 过滤逻辑 (按 / 搜索过滤)
            if ([string]::IsNullOrWhiteSpace($searchFilter)) {
                $activeItems = $items
            } else {
                $activeItems = @($items | Where-Object {
                    $_.Name -like "*$searchFilter*" -or $_.Description -like "*$searchFilter*"
                })
            }

            if ($activeItems.Count -gt 0) {
                if ($cursor -ge $activeItems.Count) { $cursor = $activeItems.Count - 1 }
                if ($cursor -lt 0) { $cursor = 0 }
                $currItem = $activeItems[$cursor]
                $currMethodInfo = $currItem.MethodInfo
            } else {
                $cursor = 0
                $currItem = $null
                $currMethodInfo = $null
            }

            # 动态获取终端尺寸，并做安全宽度与行数约束 (杜绝横向换行与纵向滚屏)
            $winWidth = 84
            $winHeight = 25
            try {
                if ($Host.UI.RawUI.WindowSize.Width -gt 0) {
                    $winWidth = $Host.UI.RawUI.WindowSize.Width
                }
                if ($Host.UI.RawUI.WindowSize.Height -gt 0) {
                    $winHeight = $Host.UI.RawUI.WindowSize.Height
                }
            } catch {}

            $isWide = ($winWidth -ge 100)
            $storePathStr = if ($config) { $config.storagePath } else { "$HOME\.scpm\scripts" }
            $enabledCount = @($items | Where-Object { $_.Enabled }).Count

            # 重置光标至视口左上角 (1, 1)
            [Console]::Write("$esc[1;1H")
            try { [Console]::SetCursorPosition(0, 0) } catch {}

            # 通用单元格输出组件 (严格限制输出宽度与色彩)
            function Write-PanelCellInternal {
                param(
                    [object]$cell,
                    [int]$cellInnerWidth,
                    [string]$borderColor = "DarkCyan"
                )

                Out-Ansi "│ " -Fg $borderColor -NoNewline

                if ($null -eq $cell -or $cell.Type -eq 'Empty') {
                    [Console]::Write(" " * $cellInnerWidth)
                } elseif ($cell.Type -eq 'Full') {
                    $truncated = Truncate-ScpmDisplayStringInternal $cell.Text $cellInnerWidth
                    $padded = Pad-ScpmDisplayStringInternal $truncated $cellInnerWidth
                    Out-Ansi $padded -Fg $cell.Fg -Bg $cell.Bg -NoNewline
                } elseif ($cell.Type -eq 'Segments') {
                    $remW = $cellInnerWidth
                    foreach ($seg in $cell.Segments) {
                        if ($remW -le 0) { break }
                        $sw = Get-ScpmDisplayWidthInternal $seg.Text
                        $color = if ($seg.Fg) { $seg.Fg } else { $seg.Color }
                        $bg = if ($seg.Bg) { $seg.Bg } else { $null }
                        if ($sw -le $remW) {
                            Out-Ansi $seg.Text -Fg $color -Bg $bg -NoNewline
                            $remW -= $sw
                        } else {
                            $tr = Truncate-ScpmDisplayStringInternal $seg.Text $remW
                            Out-Ansi $tr -Fg $color -Bg $bg -NoNewline
                            $remW -= (Get-ScpmDisplayWidthInternal $tr)
                        }
                    }
                    if ($remW -gt 0) {
                        [Console]::Write(" " * $remW)
                    }
                }

                Out-Ansi " │" -Fg $borderColor -NoNewline
            }

            if ($isWide) {
                # ============================================================
                # 模式 A: 响应式宽屏双栏布局 (Side-by-Side Dual Panels)
                # ============================================================
                $totalW = [Math]::Max(70, $winWidth - 2)
                # 左栏宽度在宽屏下自适应扩展（占约 36%），最小 38，最大可达 75 列
                $leftW = [Math]::Max(38, [Math]::Min(75, [int]($totalW * 0.36)))
                $rightW = $totalW - $leftW - 1
                $leftInner = $leftW - 4
                $rightInner = $rightW - 4
                # 内容区域撑满终端视口高度（预留顶边框1行、底边框1行、快捷键1行、状态栏1行与安全裕量）
                $contentLines = [Math]::Max(8, $winHeight - 5)

                # --- 1. 构建左侧脚本列表行数据 ---
                $leftRows = [System.Collections.Generic.List[object]]::new()
                
                # 行 0: 存储库信息或搜索提示
                if (-not [string]::IsNullOrWhiteSpace($searchFilter)) {
                    $leftRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "搜索匹配: "; Fg = "DarkGray" },
                            @{ Text = "$($activeItems.Count) 项 (共 $($items.Count) 项)"; Fg = "Yellow" }
                        )
                    })
                } else {
                    $leftRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "存储: "; Fg = "DarkGray" },
                            @{ Text = (Truncate-ScpmDisplayStringInternal $storePathStr ($leftInner - 6)); Fg = "Cyan" }
                        )
                    })
                }

                $visibleListCount = $contentLines - 1
                if ($cursor -lt $scrollOffset) {
                    $scrollOffset = $cursor
                } elseif ($cursor -ge ($scrollOffset + $visibleListCount)) {
                    $scrollOffset = $cursor - $visibleListCount + 1
                }
                $scrollOffset = [Math]::Max(0, [Math]::Min($scrollOffset, [Math]::Max(0, $activeItems.Count - $visibleListCount)))

                # 动态计算当前活动脚本中最长名称，弹性调整名称列宽 (14 ~ 26 字符)
                $maxNameW = 14
                foreach ($ai in $activeItems) {
                    $w = Get-ScpmDisplayWidthInternal $ai.Name
                    if ($w -gt $maxNameW) { $maxNameW = $w }
                }
                $nameColW = [Math]::Min(26, [Math]::Max(14, $maxNameW))

                if ($activeItems.Count -eq 0) {
                    $leftRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "  未找到与 `"$searchFilter`" 匹配的脚本"; Fg = "Yellow" }
                        )
                    })
                    $leftRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "  (按 Esc 清除过滤，或按退格修改)"; Fg = "DarkGray" }
                        )
                    })
                } else {
                    $endIdx = [Math]::Min($activeItems.Count, $scrollOffset + $visibleListCount)
                    for ($i = $scrollOffset; $i -lt $endIdx; $i++) {
                        $it = $activeItems[$i]
                        $isCurrent = ($i -eq $cursor)

                        $ptr = if ($isCurrent) { " ❯ " } else { "   " }
                        $idxStr = "[$($it.Index)] "
                        $stStr = if ($it.Enabled) { "[●] " } else { "[○] " }
                        
                        $prefix = "$ptr$idxStr$stStr"
                        $prefixW = Get-ScpmDisplayWidthInternal $prefix
                        $nameStr = Pad-ScpmDisplayStringInternal (Truncate-ScpmDisplayStringInternal $it.Name $nameColW) $nameColW
                        $descMaxW = [Math]::Max(4, $leftInner - $prefixW - $nameColW - 1)
                        $descStr = Truncate-ScpmDisplayStringInternal $it.Description $descMaxW

                        if ($isCurrent) {
                            # 选中项：高亮青底纯黑字 (高对比度)
                            $fullRow = "$prefix$nameStr $descStr"
                            $leftRows.Add([PSCustomObject]@{
                                Type = 'Full'
                                Text = $fullRow
                                Fg = 'Black'
                                Bg = 'Cyan'
                            })
                        } else {
                            $stColor = if ($it.Enabled) { "Green" } else { "DarkGray" }
                            $leftRows.Add([PSCustomObject]@{
                                Type = 'Segments'
                                Segments = @(
                                    @{ Text = $ptr; Fg = "DarkGray" },
                                    @{ Text = $idxStr; Fg = "DarkGray" },
                                    @{ Text = $stStr; Fg = $stColor },
                                    @{ Text = $nameStr; Fg = "Cyan" },
                                    @{ Text = " $descStr"; Fg = "Gray" }
                                )
                            })
                        }
                    }
                }

                while ($leftRows.Count -lt $contentLines) {
                    $leftRows.Add([PSCustomObject]@{ Type = 'Empty' })
                }

                # --- 2. 构建右侧详细信息与方法预览行数据 ---
                $rightRows = [System.Collections.Generic.List[object]]::new()
                if ($null -ne $currItem) {
                    $mInfo = $currMethodInfo

                    # 路径行
                    $fStatus = if ($currItem.FileExists) { " [文件正常]" } else { " [文件缺失]" }
                    $fColor = if ($currItem.FileExists) { "Green" } else { "Red" }
                    $rightRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "文件路径: "; Fg = "DarkGray" },
                            @{ Text = (Truncate-ScpmDisplayStringInternal $currItem.Path ($rightInner - 22)); Fg = "Gray" },
                            @{ Text = $fStatus; Fg = $fColor }
                        )
                    })

                    # 描述行
                    $rightRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "功能说明: "; Fg = "DarkGray" },
                            @{ Text = (Truncate-ScpmDisplayStringInternal $currItem.Description ($rightInner - 11)); Fg = "White" }
                        )
                    })

                    # 方法与函数
                    $rightRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "⚙ 导出方法 / 全局函数 ($($mInfo.Functions.Count)):"; Fg = "Cyan" }
                        )
                    })

                    if ($mInfo.Functions.Count -eq 0) {
                        $rightRows.Add([PSCustomObject]@{
                            Type = 'Segments'
                            Segments = @(
                                @{ Text = "  • (该脚本未定义全局函数，作为独立脚本直接执行)"; Fg = "DarkGray" }
                            )
                        })
                    } else {
                        foreach ($fn in $mInfo.Functions) {
                            if ($rightRows.Count -ge ($contentLines - 5)) { break }
                            $rightRows.Add([PSCustomObject]@{
                                Type = 'Segments'
                                Segments = @(
                                    @{ Text = "  • "; Fg = "Cyan" },
                                    @{ Text = (Truncate-ScpmDisplayStringInternal $fn.Signature ($rightInner - 6)); Fg = "White" }
                                )
                            })
                            foreach ($p in $fn.Parameters) {
                                if ($rightRows.Count -ge ($contentLines - 5)) { break }
                                if ($p.ValidateSet -and $p.ValidateSet.Count -gt 0) {
                                    $opts = ($p.ValidateSet | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
                                    if (-not [string]::IsNullOrWhiteSpace($opts)) {
                                        $rightRows.Add([PSCustomObject]@{
                                            Type = 'Segments'
                                            Segments = @(
                                                @{ Text = "      $($p.Name) 可选值: "; Fg = "DarkGray" },
                                                @{ Text = (Truncate-ScpmDisplayStringInternal $opts ($rightInner - 20)); Fg = "Yellow" }
                                            )
                                        })
                                    }
                                }
                            }
                        }
                    }

                    # 用法示例
                    if (-not [string]::IsNullOrWhiteSpace($mInfo.Usage) -and ($rightRows.Count -lt ($contentLines - 2))) {
                        $rightRows.Add([PSCustomObject]@{
                            Type = 'Segments'
                            Segments = @(
                                @{ Text = "📖 用法示例 (USAGE):"; Fg = "Cyan" }
                            )
                        })
                        $uLines = $mInfo.Usage -split '\r?\n'
                        foreach ($ul in $uLines) {
                            if ($rightRows.Count -ge $contentLines) { break }
                            if (-not [string]::IsNullOrWhiteSpace($ul)) {
                                $rightRows.Add([PSCustomObject]@{
                                    Type = 'Segments'
                                    Segments = @(
                                        @{ Text = "  $(Truncate-ScpmDisplayStringInternal ($ul.Trim()) ($rightInner - 4))"; Fg = "Gray" }
                                    )
                                })
                            }
                        }
                    } elseif (-not [string]::IsNullOrWhiteSpace($mInfo.Description) -and ($rightRows.Count -lt ($contentLines - 2))) {
                        $rightRows.Add([PSCustomObject]@{
                            Type = 'Segments'
                            Segments = @(
                                @{ Text = "📖 详细说明:"; Fg = "Cyan" }
                            )
                        })
                        $dLines = $mInfo.Description -split '\r?\n'
                        foreach ($dl in $dLines) {
                            if ($rightRows.Count -ge $contentLines) { break }
                            if (-not [string]::IsNullOrWhiteSpace($dl)) {
                                $rightRows.Add([PSCustomObject]@{
                                    Type = 'Segments'
                                    Segments = @(
                                        @{ Text = "  $(Truncate-ScpmDisplayStringInternal ($dl.Trim()) ($rightInner - 4))"; Fg = "Gray" }
                                    )
                                })
                            }
                        }
                    }
                } else {
                    $rightRows.Add([PSCustomObject]@{
                        Type = 'Segments'
                        Segments = @(
                            @{ Text = "(暂无选中的脚本)"; Fg = "DarkGray" }
                        )
                    })
                }

                while ($rightRows.Count -lt $contentLines) {
                    $rightRows.Add([PSCustomObject]@{ Type = 'Empty' })
                }

                # --- 3. 渲染左右顶边框 ---
                $lTitle = if (-not [string]::IsNullOrWhiteSpace($searchFilter)) { "🔍 搜索: `"$searchFilter`"" } else { "受管理脚本列表" }
                $lBadge = if (-not [string]::IsNullOrWhiteSpace($searchFilter)) { "[$($activeItems.Count)/$($items.Count)]" } else { "[$($items.Count)脚本]" }
                $lTitleW = Get-ScpmDisplayWidthInternal $lTitle
                $lBadgeW = Get-ScpmDisplayWidthInternal $lBadge
                $lFillW = [Math]::Max(2, $leftW - (7 + $lTitleW + $lBadgeW))

                $rTitle = if ($null -ne $currItem) { "⚡ 详情与方法: $($currItem.Name)" } else { "⚡ 详情预览" }
                $rBadge = if ($null -ne $currItem) { if ($currItem.Enabled) { "[●已启用]" } else { "[○已禁用]" } } else { "[--]" }
                $rTitleW = Get-ScpmDisplayWidthInternal $rTitle
                $rBadgeW = Get-ScpmDisplayWidthInternal $rBadge
                $rFillW = [Math]::Max(2, $rightW - (7 + $rTitleW + $rBadgeW))

                # 左卡片顶边
                Out-Ansi "╭─ " -Fg "DarkCyan" -NoNewline
                Out-Ansi $lTitle -Fg "Cyan" -NoNewline
                Out-Ansi (" " + ("─" * $lFillW) + " ") -Fg "DarkCyan" -NoNewline
                Out-Ansi $lBadge -Fg "Green" -NoNewline
                Out-Ansi " ─╮ " -Fg "DarkCyan" -NoNewline

                # 右卡片顶边
                Out-Ansi "╭─ " -Fg "DarkCyan" -NoNewline
                Out-Ansi $rTitle -Fg "Yellow" -NoNewline
                Out-Ansi (" " + ("─" * $rFillW) + " ") -Fg "DarkCyan" -NoNewline
                $rColor = if ($null -ne $currItem -and $currItem.Enabled) { "Green" } else { "DarkGray" }
                Out-Ansi $rBadge -Fg $rColor -NoNewline
                Out-Ansi " ─╮" -Fg "DarkCyan" -NoNewline
                [Console]::Write("$esc[K`n")

                # --- 4. 逐行并排输出双栏内容 ---
                for ($r = 0; $r -lt $contentLines; $r++) {
                    Write-PanelCellInternal $leftRows[$r] $leftInner "DarkCyan"
                    [Console]::Write(" ")
                    Write-PanelCellInternal $rightRows[$r] $rightInner "DarkCyan"
                    [Console]::Write("$esc[K`n")
                }

                # --- 5. 渲染左右底边框 ---
                Out-Ansi ("╰" + ("─" * ($leftW - 2)) + "╯ ") -Fg "DarkCyan" -NoNewline
                Out-Ansi ("╰" + ("─" * ($rightW - 2)) + "╯") -Fg "DarkCyan" -NoNewline
                [Console]::Write("$esc[K`n")

            } else {
                # ============================================================
                # 模式 B: 紧凑堆叠模式 (Stacked Mode, 终端宽度 < 100)
                # ============================================================
                $cardWidth = [Math]::Max(40, $winWidth - 2)
                $innerWidth = $cardWidth - 4
                $maxLines = [Math]::Max(14, $winHeight - 4)
                $ctx = [PSCustomObject]@{ lines = 0 }

                function Out-CardInnerLine([string]$text = "", [string]$color = "White", [string]$bg = $null) {
                    if ($ctx.lines -ge ($maxLines - 3)) { return }
                    $t = Pad-ScpmDisplayStringInternal (Truncate-ScpmDisplayStringInternal $text $innerWidth) $innerWidth
                    Out-Ansi "│ " -Fg "DarkCyan" -NoNewline
                    Out-Ansi $t -Fg $color -Bg $bg -NoNewline
                    Out-Ansi " │" -Fg "DarkCyan" -NoNewline
                    [Console]::Write("$esc[K`n")
                    $ctx.lines++
                }

                function Out-CardMultiLine([array]$segments) {
                    if ($ctx.lines -ge ($maxLines - 3)) { return }
                    $totW = 0
                    foreach ($seg in $segments) { $totW += Get-ScpmDisplayWidthInternal $seg.Text }
                    Out-Ansi "│ " -Fg "DarkCyan" -NoNewline
                    if ($totW -gt $innerWidth) {
                        $remW = $innerWidth
                        foreach ($seg in $segments) {
                            if ($remW -le 0) { break }
                            $segW = Get-ScpmDisplayWidthInternal $seg.Text
                            $color = if ($seg.Fg) { $seg.Fg } else { $seg.Color }
                            $bg = if ($seg.Bg) { $seg.Bg } else { $null }
                            if ($segW -le $remW) {
                                Out-Ansi $seg.Text -Fg $color -Bg $bg -NoNewline
                                $remW -= $segW
                            } else {
                                $trunc = Truncate-ScpmDisplayStringInternal $seg.Text $remW
                                Out-Ansi $trunc -Fg $color -Bg $bg -NoNewline
                                $remW -= (Get-ScpmDisplayWidthInternal $trunc)
                            }
                        }
                        if ($remW -gt 0) { [Console]::Write(" " * $remW) }
                    } else {
                        foreach ($seg in $segments) {
                            $color = if ($seg.Fg) { $seg.Fg } else { $seg.Color }
                            $bg = if ($seg.Bg) { $seg.Bg } else { $null }
                            Out-Ansi $seg.Text -Fg $color -Bg $bg -NoNewline
                        }
                        $remW = $innerWidth - $totW
                        if ($remW -gt 0) { [Console]::Write(" " * $remW) }
                    }
                    Out-Ansi " │" -Fg "DarkCyan" -NoNewline
                    [Console]::Write("$esc[K`n")
                    $ctx.lines++
                }

                # 上卡片 [脚本列表]
                $title = if (-not [string]::IsNullOrWhiteSpace($searchFilter)) { "🔍 搜索: `"$searchFilter`"" } else { "[scpm] 脚本集中管理控制台 v$Script:ScpmVersion" }
                $badge = if (-not [string]::IsNullOrWhiteSpace($searchFilter)) { "[ 匹配 $($activeItems.Count) / 共 $($items.Count) ]" } else { "[ $($items.Count) 脚本 | $enabledCount 启用 ]" }
                $titleW = Get-ScpmDisplayWidthInternal $title
                $badgeW = Get-ScpmDisplayWidthInternal $badge
                $fillW = [Math]::Max(2, $cardWidth - (7 + $titleW + $badgeW))

                Out-Ansi "╭─ " -Fg "DarkCyan" -NoNewline
                Out-Ansi $title -Fg "Cyan" -NoNewline
                Out-Ansi (" " + ("─" * $fillW) + " ") -Fg "DarkCyan" -NoNewline
                Out-Ansi $badge -Fg "Green" -NoNewline
                Out-Ansi " ─╮" -Fg "DarkCyan" -NoNewline
                [Console]::Write("$esc[K`n")
                $ctx.lines++

                Out-CardMultiLine @(
                    @{ Text = "存储库: "; Color = "DarkGray" },
                    @{ Text = $storePathStr; Color = "Cyan" }
                )

                $visibleListCount = [Math]::Min($activeItems.Count, [Math]::Max(2, [Math]::Min(6, [int]($winHeight * 0.28))))
                if ($cursor -lt $scrollOffset) {
                    $scrollOffset = $cursor
                } elseif ($cursor -ge ($scrollOffset + $visibleListCount)) {
                    $scrollOffset = $cursor - $visibleListCount + 1
                }
                $scrollOffset = [Math]::Max(0, [Math]::Min($scrollOffset, [Math]::Max(0, $activeItems.Count - $visibleListCount)))

                if ($activeItems.Count -eq 0) {
                    Out-CardInnerLine "  未找到与 `"$searchFilter`" 匹配的脚本 (按 Esc 清除过滤)" "Yellow"
                } else {
                    $endIndex = [Math]::Min($activeItems.Count, $scrollOffset + $visibleListCount)
                    for ($i = $scrollOffset; $i -lt $endIndex; $i++) {
                        if ($ctx.lines -ge ($maxLines - 3)) { break }
                        $it = $activeItems[$i]
                        $isCurrent = ($i -eq $cursor)

                        $ptr = if ($isCurrent) { " ❯ " } else { "   " }
                        $idxStr = "[$($it.Index)] "
                        $st = if ($it.Enabled) { "[● 已启用] " } else { "[○ 已禁用] " }
                        $stColor = if ($it.Enabled) { "Green" } else { "DarkGray" }
                        
                        $nameW = 18
                        $nameStr = Pad-ScpmDisplayStringInternal (Truncate-ScpmDisplayStringInternal $it.Name $nameW) $nameW

                        $usedW = 3 + 4 + 11 + $nameW
                        $remW = [Math]::Max(10, $innerWidth - $usedW)
                        $descPadded = Pad-ScpmDisplayStringInternal (Truncate-ScpmDisplayStringInternal $it.Description $remW) $remW

                        if ($isCurrent) {
                            # 选中项：高对比度青底纯黑字
                            $rowContent = Pad-ScpmDisplayStringInternal (Truncate-ScpmDisplayStringInternal "$ptr$idxStr$st$nameStr$descPadded" $innerWidth) $innerWidth
                            Out-CardInnerLine $rowContent "Black" "Cyan"
                        } else {
                            Out-Ansi "│ " -Fg "DarkCyan" -NoNewline
                            Out-Ansi $ptr -Fg "DarkGray" -NoNewline
                            Out-Ansi $idxStr -Fg "DarkGray" -NoNewline
                            Out-Ansi $st -Fg $stColor -NoNewline
                            Out-Ansi $nameStr -Fg "Cyan" -NoNewline
                            Out-Ansi $descPadded -Fg "Gray" -NoNewline
                            Out-Ansi " │" -Fg "DarkCyan" -NoNewline
                            [Console]::Write("$esc[K`n")
                            $ctx.lines++
                        }
                    }
                }

                Out-Ansi ("╰" + ("─" * ($cardWidth - 2)) + "╯") -Fg "DarkCyan" -NoNewline
                [Console]::Write("$esc[K`n")
                $ctx.lines++

                # 下卡片 [方法与文档联动预览]
                if ($null -ne $currItem) {
                    $bTitle = "⚡ 实时方法与用法预览: $($currItem.Name)"
                    $bTitleW = Get-ScpmDisplayWidthInternal $bTitle
                    $bFillW = [Math]::Max(2, $cardWidth - (4 + $bTitleW + 3))

                    Out-Ansi "╭─ " -Fg "DarkCyan" -NoNewline
                    Out-Ansi $bTitle -Fg "Yellow" -NoNewline
                    Out-Ansi (" " + ("─" * $bFillW) + "─╮") -Fg "DarkCyan" -NoNewline
                    [Console]::Write("$esc[K`n")
                    $ctx.lines++

                    Out-CardMultiLine @(
                        @{ Text = "文件路径: "; Color = "DarkGray" },
                        @{ Text = $currItem.Path; Color = "Gray" }
                    )

                    Out-CardInnerLine "⚙ 导出方法 / 全局函数:" "Cyan"
                    if ($currMethodInfo.Functions.Count -eq 0) {
                        Out-CardInnerLine "  • (该脚本未定义全局函数，作为独立脚本直接执行)" "DarkGray"
                    } else {
                        $shownFuncCount = 0
                        foreach ($fn in $currMethodInfo.Functions) {
                            if ($ctx.lines -ge ($maxLines - 4)) { break }
                            if (-not $fn.IsNested -and $shownFuncCount -lt 3) {
                                Out-CardMultiLine @(
                                    @{ Text = "  • "; Color = "Cyan" },
                                    @{ Text = $fn.Signature; Color = "White" }
                                )
                                if ($fn.Parameters.Count -gt 0) {
                                    foreach ($param in $fn.Parameters) {
                                        if ($ctx.lines -ge ($maxLines - 4)) { break }
                                        if ($param.ValidateSet -and $param.ValidateSet.Count -gt 0) {
                                            $opts = ($param.ValidateSet | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
                                            if (-not [string]::IsNullOrWhiteSpace($opts)) {
                                                Out-CardMultiLine @(
                                                    @{ Text = "      $($param.Name) 可选值: "; Color = "DarkGray" },
                                                    @{ Text = $opts; Color = "Yellow" }
                                                )
                                            }
                                        }
                                    }
                                }
                                $shownFuncCount++
                            }
                        }
                    }

                    if (-not [string]::IsNullOrWhiteSpace($currMethodInfo.Usage) -and ($ctx.lines -lt ($maxLines - 4))) {
                        Out-CardInnerLine "📖 用法说明 (USAGE):" "Cyan"
                        $uLines = $currMethodInfo.Usage -split '\r?\n'
                        $shownUsage = 0
                        foreach ($ul in $uLines) {
                            if ($ctx.lines -ge ($maxLines - 4) -or $shownUsage -ge 3) { break }
                            if (-not [string]::IsNullOrWhiteSpace($ul)) {
                                Out-CardInnerLine "  $($ul.Trim())" "Gray"
                                $shownUsage++
                            }
                        }
                    }

                    Out-Ansi ("╰" + ("─" * ($cardWidth - 2)) + "╯") -Fg "DarkCyan" -NoNewline
                    [Console]::Write("$esc[K`n")
                    $ctx.lines++
                }
            }

            # --- 区域 3: 底部快捷键与状态条 ---
            Out-Ansi " 快捷键: " -Fg "DarkCyan" -NoNewline
            Out-Ansi "[↑/↓]" -Fg "Yellow" -NoNewline
            Out-Ansi "移动 " -Fg "DarkGray" -NoNewline
            Out-Ansi "[空格]" -Fg "Yellow" -NoNewline
            Out-Ansi "启停 " -Fg "DarkGray" -NoNewline
            Out-Ansi "[/]" -Fg "Yellow" -NoNewline
            Out-Ansi "搜索 " -Fg "DarkGray" -NoNewline
            Out-Ansi "[e]" -Fg "Cyan" -NoNewline
            Out-Ansi "编辑 " -Fg "DarkGray" -NoNewline
            Out-Ansi "[n]" -Fg "Cyan" -NoNewline
            Out-Ansi "新建 " -Fg "DarkGray" -NoNewline
            Out-Ansi "[s]" -Fg "Cyan" -NoNewline
            Out-Ansi "同步 " -Fg "DarkGray" -NoNewline
            Out-Ansi "[r]" -Fg "Red" -NoNewline
            Out-Ansi "注销 " -Fg "DarkGray" -NoNewline
            Out-Ansi "[q]" -Fg "Gray" -NoNewline
            Out-Ansi "退出" -Fg "DarkGray" -NoNewline
            [Console]::Write("$esc[K`n")

            if ($inSearchMode) {
                Out-Ansi " 🔍 搜索: " -Fg "Yellow" -NoNewline
                Out-Ansi "$searchFilter" -Fg "White" -NoNewline
                Out-Ansi "█" -Fg "Yellow" -NoNewline
                Out-Ansi " (回车锁定，Esc退出，↑/↓选择，空格启停)" -Fg "DarkGray" -NoNewline
                [Console]::Write("$esc[K")
            } elseif (-not [string]::IsNullOrWhiteSpace($searchFilter)) {
                Out-Ansi " [过滤中: `"$searchFilter`"] " -Fg "Yellow" -NoNewline
                Out-Ansi "(按 Esc 清除过滤) | 状态: " -Fg "DarkGray" -NoNewline
                Out-Ansi $statusMsg -Fg $statusMsgColor -NoNewline
                [Console]::Write("$esc[K")
            } else {
                Out-Ansi " 状态提示: " -Fg "DarkGray" -NoNewline
                Out-Ansi $statusMsg -Fg $statusMsgColor -NoNewline
                [Console]::Write("$esc[K")
            }

            # 清除视口底部可能残留的历史行
            [Console]::Write("$esc[J")

            # --- 键盘事件监听与实时窗口尺寸自适应检测 ---
            $resized = $false
            while (-not [Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 40
                $curW = 84
                $curH = 25
                try {
                    if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $curW = $Host.UI.RawUI.WindowSize.Width }
                    if ($Host.UI.RawUI.WindowSize.Height -gt 0) { $curH = $Host.UI.RawUI.WindowSize.Height }
                } catch {}

                if ($curW -ne $winWidth -or $curH -ne $winHeight) {
                    $resized = $true
                    [Console]::Write("$esc[2J$esc[1;1H")
                    break
                }
            }

            if ($resized) {
                continue
            }

            $key = [Console]::ReadKey($true)

            if ($inSearchMode) {
                switch ($key.Key) {
                    ([ConsoleKey]::Escape) {
                        $inSearchMode = $false
                        $searchFilter = ""
                        $cursor = 0
                        $statusMsg = "已退出搜索模式。"
                        $statusMsgColor = "Gray"
                    }
                    ([ConsoleKey]::Enter) {
                        $inSearchMode = $false
                        $statusMsg = if ($searchFilter) { "已锁定过滤: `"$searchFilter`" (按 Esc 清除)。" } else { "就绪。" }
                        $statusMsgColor = "Cyan"
                    }
                    ([ConsoleKey]::Backspace) {
                        if ($searchFilter.Length -gt 0) {
                            $searchFilter = $searchFilter.Substring(0, $searchFilter.Length - 1)
                            $cursor = 0
                            $scrollOffset = 0
                        } else {
                            $inSearchMode = $false
                        }
                    }
                    ([ConsoleKey]::UpArrow) {
                        if ($activeItems.Count -gt 0) {
                            $cursor = ($cursor - 1 + $activeItems.Count) % $activeItems.Count
                        }
                    }
                    ([ConsoleKey]::DownArrow) {
                        if ($activeItems.Count -gt 0) {
                            $cursor = ($cursor + 1) % $activeItems.Count
                        }
                    }
                    ([ConsoleKey]::Spacebar) {
                        if ($null -ne $currItem) {
                            $currItem.Enabled = -not $currItem.Enabled
                            $reg.scripts.PSObject.Properties[$currItem.Name].Value.enabled = $currItem.Enabled
                            Save-ScpmRegistryInternal $reg
                            Update-ScpmLoaderInternal | Out-Null
                            if ($currItem.Enabled) {
                                if (Test-Path -LiteralPath $currItem.RealPath) {
                                    try {
                                        & { . $currItem.RealPath } *>$null
                                        $statusMsg = "[✓] 已启用 $($currItem.Name)！"
                                        $statusMsgColor = "Green"
                                    } catch {
                                        $statusMsg = "[✓] 已启用 $($currItem.Name) (载入告警)"
                                        $statusMsgColor = "Yellow"
                                    }
                                }
                            } else {
                                $statusMsg = "[✗] 已禁用 $($currItem.Name)。"
                                $statusMsgColor = "Yellow"
                            }
                        }
                    }
                    default {
                        if (-not [char]::IsControl($key.KeyChar)) {
                            $searchFilter += $key.KeyChar
                            $cursor = 0
                            $scrollOffset = 0
                        }
                    }
                }
                continue
            }

            # 正常浏览模式
            switch ($key.Key) {
                ([ConsoleKey]::UpArrow) {
                    if ($activeItems.Count -gt 0) {
                        $cursor = ($cursor - 1 + $activeItems.Count) % $activeItems.Count
                    }
                }
                ([ConsoleKey]::DownArrow) {
                    if ($activeItems.Count -gt 0) {
                        $cursor = ($cursor + 1) % $activeItems.Count
                    }
                }
                ([ConsoleKey]::Home) {
                    $cursor = 0
                }
                ([ConsoleKey]::End) {
                    if ($activeItems.Count -gt 0) {
                        $cursor = $activeItems.Count - 1
                    }
                }
                ([ConsoleKey]::PageUp) {
                    $cursor = [Math]::Max(0, $cursor - $visibleListCount)
                }
                ([ConsoleKey]::PageDown) {
                    if ($activeItems.Count -gt 0) {
                        $cursor = [Math]::Min($activeItems.Count - 1, $cursor + $visibleListCount)
                    }
                }
                ([ConsoleKey]::Spacebar) {
                    if ($null -ne $currItem) {
                        $currItem.Enabled = -not $currItem.Enabled
                        $reg.scripts.PSObject.Properties[$currItem.Name].Value.enabled = $currItem.Enabled
                        Save-ScpmRegistryInternal $reg
                        Update-ScpmLoaderInternal | Out-Null

                        if ($currItem.Enabled) {
                            if (Test-Path -LiteralPath $currItem.RealPath) {
                                try {
                                    & { . $currItem.RealPath } *>$null
                                    $statusMsg = "[✓] 已启用 $($currItem.Name) 并即时载入当前终端！"
                                    $statusMsgColor = "Green"
                                } catch {
                                    $statusMsg = "[✓] 已启用 $($currItem.Name) (载入告警: $($_.Exception.Message))"
                                    $statusMsgColor = "Yellow"
                                }
                            }
                        } else {
                            $statusMsg = "[✗] 已禁用 $($currItem.Name) (新开终端将不再载入)。"
                            $statusMsgColor = "Yellow"
                        }
                    }
                }
                default {
                    $ch = [string]$key.KeyChar
                    if ($key.Key -eq [ConsoleKey]::Escape) {
                        if (-not [string]::IsNullOrWhiteSpace($searchFilter)) {
                            $searchFilter = ""
                            $cursor = 0
                            $statusMsg = "已清除搜索过滤。"
                            $statusMsgColor = "Gray"
                        } else {
                            break
                        }
                    } elseif ($ch -in @("q", "Q")) {
                        break
                    } elseif ($ch -eq "/") {
                        $inSearchMode = $true
                        $searchFilter = ""
                        $cursor = 0
                        $scrollOffset = 0
                    } elseif ($ch -in @("e", "E")) {
                        if ($null -ne $currItem -and (Test-Path -LiteralPath $currItem.RealPath)) {
                            if (Get-Command code -ErrorAction SilentlyContinue) {
                                Start-Process "code" -ArgumentList "`"$($currItem.RealPath)`""
                            } else {
                                Start-Process "notepad.exe" -ArgumentList "`"$($currItem.RealPath)`""
                            }
                            $statusMsg = "已在编辑器中打开 $($currItem.Name)。"
                            $statusMsgColor = "Cyan"
                        }
                    } elseif ($ch -in @("n", "N")) {
                        [Console]::Write("$esc[?25h$esc[2J$esc[1;1H")
                        Write-Host "`n=== [scpm] 创建新脚本 ===" -ForegroundColor Cyan
                        $newName = Read-Host "请输入新脚本名称 (回车取消)"
                        if (-not [string]::IsNullOrWhiteSpace($newName)) {
                            $newDesc = Read-Host "请输入脚本描述 (可选)"
                            Invoke-ScpmNew $newName -Desc $newDesc -NoEdit
                            $data = Refresh-TuiDataInternal
                            $items = $data.Items
                            $reg = $data.Registry
                            $cursor = $items.Count - 1
                            $searchFilter = ""
                            $statusMsg = "[✓] 成功创建新脚本: $newName！"
                            $statusMsgColor = "Green"
                        }
                        [Console]::Write("$esc[?25l$esc[2J$esc[1;1H")
                    } elseif ($ch -in @("s", "S")) {
                        $syncRes = Invoke-ScpmSync -Silent
                        $data = Refresh-TuiDataInternal
                        $items = $data.Items
                        $reg = $data.Registry
                        if ($syncRes.Added -gt 0) {
                            $statusMsg = "[✓] 存储库同步完成: 发现并收录 $($syncRes.Added) 个新脚本 ($($syncRes.NewScripts -join ', '))！"
                            $statusMsgColor = "Green"
                        } elseif ($syncRes.Missing -gt 0) {
                            $statusMsg = "[!] 存储库同步告警: 检测到 $($syncRes.Missing) 个脚本文件缺失！"
                            $statusMsgColor = "Yellow"
                        } else {
                            $statusMsg = "[✓] 存储库同步完毕：所有脚本均已是最新的 (共 $($items.Count) 个)。"
                            $statusMsgColor = "Green"
                        }
                    } elseif ($ch -in @("r", "R") -or $key.Key -eq [ConsoleKey]::Delete) {
                        if ($null -ne $currItem) {
                            $it = $currItem
                            [Console]::Write("$esc[?25h$esc[2J$esc[1;1H")
                            Write-Host "`n=== [scpm] 注销受管理脚本 ===" -ForegroundColor Cyan
                            $confirm = Read-Host "确认从管理清单注销 $($it.Name) 吗？(y/N)"
                            if ($confirm.Trim().ToLower() -eq "y") {
                                Invoke-ScpmRemove $it.Name | Out-Null
                                $data = Refresh-TuiDataInternal
                                $items = $data.Items
                                $reg = $data.Registry
                                if ($cursor -ge $items.Count) { $cursor = [Math]::Max(0, $items.Count - 1) }
                                $statusMsg = "[✓] 已注销脚本: $($it.Name)。"
                                $statusMsgColor = "Yellow"
                            }
                            [Console]::Write("$esc[?25l$esc[2J$esc[1;1H")
                        }
                    } elseif ($ch -in @("a", "A")) {
                        foreach ($it in $activeItems) {
                            $it.Enabled = $true
                            $reg.scripts.PSObject.Properties[$it.Name].Value.enabled = $true
                            if (Test-Path -LiteralPath $it.RealPath) {
                                try { & { . $it.RealPath } *>$null } catch {}
                            }
                        }
                        Save-ScpmRegistryInternal $reg
                        Update-ScpmLoaderInternal | Out-Null
                        $statusMsg = "[✓] 已全部启用并即时注入当前会话！"
                        $statusMsgColor = "Green"
                    } elseif ($ch -in @("d", "D")) {
                        foreach ($it in $activeItems) {
                            $it.Enabled = $false
                            $reg.scripts.PSObject.Properties[$it.Name].Value.enabled = $false
                        }
                        Save-ScpmRegistryInternal $reg
                        Update-ScpmLoaderInternal | Out-Null
                        $statusMsg = "[✗] 已全部禁用。"
                        $statusMsgColor = "Yellow"
                    } elseif ($ch -in @("k", "K")) {
                        if ($activeItems.Count -gt 0) {
                            $cursor = ($cursor - 1 + $activeItems.Count) % $activeItems.Count
                        }
                    } elseif ($ch -in @("j", "J")) {
                        if ($activeItems.Count -gt 0) {
                            $cursor = ($cursor + 1) % $activeItems.Count
                        }
                    } elseif ($ch -in @("?", "h", "H")) {
                        $statusMsg = "[↑/↓]移动 [空格]启停 [/]搜索 [e]编辑 [n]新建 [s]同步 [r]注销 [q]退出"
                        $statusMsgColor = "Cyan"
                    } else {
                        $num = 0
                        if ([int]::TryParse($ch, [ref]$num) -and $num -ge 1 -and $num -le $activeItems.Count) {
                            $cursor = $num - 1
                        }
                    }
                }
            }

            if ($key.Key -eq [ConsoleKey]::Escape -and [string]::IsNullOrWhiteSpace($searchFilter)) {
                break
            }
            if ($key.KeyChar -in @("q", "Q")) {
                break
            }
        }
    } finally {
        # 退出备用屏幕缓冲区并恢复光标
        try {
            [Console]::Write("$esc[?25h$esc[?1049l")
            [Console]::CursorVisible = $savedCursorVisible
        } catch {}
        Write-Host "`n[scpm] 已退出控制台。" -ForegroundColor Gray
    }
}

function Invoke-ScpmToggle {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Targets
    )

    $cleanTargets = @()
    if ($null -ne $Targets) {
        $cleanTargets = @($Targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($cleanTargets.Count -gt 0) {
        $reg = Get-ScpmRegistryInternal
        if ($null -eq $reg.scripts -or $reg.scripts.PSObject.Properties.Count -eq 0) {
            Write-Host "当前暂无受管理的脚本。使用 'scpm add <路径>' 添加脚本。" -ForegroundColor Yellow
            return
        }
        $scriptProps = @($reg.scripts.PSObject.Properties)
        $updated = $false
        foreach ($t in $cleanTargets) {
            $matchedProps = Resolve-ScpmScriptPropsInternal $t $scriptProps
            if ($matchedProps.Count -eq 0) {
                Write-Host "[错误] 未找到匹配 '$t' 的脚本。" -ForegroundColor Red
                continue
            }
            foreach ($prop in $matchedProps) {
                $item = $prop.Value
                $item.enabled = -not $item.enabled
                $updated = $true
                if ($item.enabled) {
                    Write-Host "[✓] 已启用: $($prop.Name)" -ForegroundColor Green
                    $realPath = Resolve-PortablePathInternal $item.path
                    if (Test-Path -LiteralPath $realPath) {
                        try {
                            . $realPath
                            Write-Host "    已即时载入当前终端会话。" -ForegroundColor Gray
                        } catch {
                            Write-Warning "    即时载入失败: $($_.Exception.Message)"
                        }
                    }
                } else {
                    Write-Host "[✗] 已禁用: $($prop.Name) (将在新终端会话生效)" -ForegroundColor Yellow
                }
            }
        }
        if ($updated) {
            Save-ScpmRegistryInternal $reg
            Update-ScpmLoaderInternal | Out-Null
        }
    } else {
        Invoke-ScpmTui
    }
}

function Invoke-ScpmEnable {
    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts -or $reg.scripts.PSObject.Properties.Count -eq 0) {
        Write-Host "当前暂无受管理的脚本。使用 'scpm add <路径>' 添加脚本。" -ForegroundColor Yellow
        return
    }

    if ($args.Count -eq 0) {
        Invoke-ScpmToggle
        return
    }

    $scriptProps = @($reg.scripts.PSObject.Properties)
    $updated = $false

    foreach ($rawName in $args) {
        $matchedProps = Resolve-ScpmScriptPropsInternal $rawName $scriptProps
        if ($matchedProps.Count -eq 0) {
            Write-Host "[错误] 未找到名为或序号为 '$rawName' 的脚本。" -ForegroundColor Red
            continue
        }

        foreach ($prop in $matchedProps) {
            $item = $prop.Value
            if (-not $item.enabled) {
                $item.enabled = $true
                $updated = $true
                Write-Host "[✓] 已启用: $($prop.Name)" -ForegroundColor Green
                
                $realPath = Resolve-PortablePathInternal $item.path
                if (Test-Path -LiteralPath $realPath) {
                    try {
                        . $realPath
                        $mInfo = Get-ScpmScriptMethodsInternal $realPath
                        $m = if ($mInfo.Summary) { " (导出方法: $($mInfo.Summary))" } else { "" }
                        Write-Host "    已即时载入当前终端会话$m。" -ForegroundColor Gray
                    } catch {
                        Write-Warning "    即时载入失败: $($_.Exception.Message)"
                    }
                }
            } else {
                Write-Host "[提示] $($prop.Name) 已经是启用状态。" -ForegroundColor Yellow
            }
        }
    }

    if ($updated) {
        Save-ScpmRegistryInternal $reg
        Update-ScpmLoaderInternal | Out-Null
    }
}

function Invoke-ScpmDisable {
    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts -or $reg.scripts.PSObject.Properties.Count -eq 0) {
        Write-Host "当前暂无受管理的脚本。" -ForegroundColor Yellow
        return
    }

    if ($args.Count -eq 0) {
        Invoke-ScpmToggle
        return
    }

    $scriptProps = @($reg.scripts.PSObject.Properties)
    $updated = $false

    foreach ($rawName in $args) {
        $matchedProps = Resolve-ScpmScriptPropsInternal $rawName $scriptProps
        if ($matchedProps.Count -eq 0) {
            Write-Host "[错误] 未找到名为或序号为 '$rawName' 的脚本。" -ForegroundColor Red
            continue
        }

        foreach ($prop in $matchedProps) {
            $item = $prop.Value
            if ($item.enabled) {
                $item.enabled = $false
                $updated = $true
                Write-Host "[✗] 已禁用: $($prop.Name) (将在下次新开会话生效)" -ForegroundColor Yellow
            } else {
                Write-Host "[提示] $($prop.Name) 已经是禁用状态。" -ForegroundColor Gray
            }
        }
    }

    if ($updated) {
        Save-ScpmRegistryInternal $reg
        Update-ScpmLoaderInternal | Out-Null
    }
}

function Show-SingleScriptInfoInternal([int]$index, [string]$name, [object]$item) {
    $realPath = Resolve-PortablePathInternal $item.path
    $mInfo = Get-ScpmScriptMethodsInternal $realPath

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " [$index] 脚本: " -NoNewline -ForegroundColor Cyan
    Write-Host "$name" -ForegroundColor Yellow -NoNewline
    if ($item.enabled) {
        Write-Host "  [✓ 已启用 - 自动注入当前终端]" -ForegroundColor Green
    } else {
        Write-Host "  [✗ 已禁用]" -ForegroundColor DarkGray
    }
    Write-Host "================================================================================" -ForegroundColor Cyan

    Write-Host "  文件路径: " -NoNewline -ForegroundColor DarkGray
    if ($mInfo.FileExists) {
        Write-Host "$($item.path)" -ForegroundColor White
    } else {
        Write-Host "$($item.path) [文件缺失!]" -ForegroundColor Red
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($item.description)) {
        Write-Host "  脚本简介: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($item.description)" -ForegroundColor Gray
    }

    Write-Host "`n  [提供的方法 / 导出函数]" -ForegroundColor Green
    if ($mInfo.Functions.Count -eq 0) {
        Write-Host "    • (该脚本未定义函数，作为脚本文件直接执行)" -ForegroundColor DarkGray
    } else {
        foreach ($fn in $mInfo.Functions) {
            if (-not $fn.IsNested) {
                Write-Host "    • " -NoNewline -ForegroundColor Cyan
                Write-Host "$($fn.Signature)" -ForegroundColor White
                if ($fn.Parameters.Count -gt 0) {
                    foreach ($param in $fn.Parameters) {
                        if ($param.ValidateSet.Count -gt 0) {
                            Write-Host "        $($param.Name) 可选值: " -NoNewline -ForegroundColor DarkGray
                            Write-Host "$($param.ValidateSet -join ', ')" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
        $nestedFuncs = @($mInfo.Functions | Where-Object { $_.IsNested })
        if ($nestedFuncs.Count -gt 0) {
            $nestedNames = ($nestedFuncs | ForEach-Object { $_.Name }) -join ", "
            Write-Host "    (内部辅助函数: $nestedNames)" -ForegroundColor DarkGray
        }
    }

    if ($mInfo.Aliases.Count -gt 0) {
        Write-Host "`n  [导出的别名 (Aliases)]" -ForegroundColor Green
        foreach ($al in $mInfo.Aliases) {
            Write-Host "    • $($al.Name) -> $($al.Target)" -ForegroundColor Cyan
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($mInfo.Usage)) {
        Write-Host "`n  [用法示例 (USAGE)]" -ForegroundColor Green
        $uLines = $mInfo.Usage -split '\r?\n'
        foreach ($ul in $uLines) {
            Write-Host "    $ul" -ForegroundColor Gray
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($mInfo.Description)) {
        Write-Host "`n  [详细说明 (DESCRIPTION)]" -ForegroundColor Green
        $dLines = $mInfo.Description -split '\r?\n'
        foreach ($dl in $dLines) {
            Write-Host "    $dl" -ForegroundColor Gray
        }
    }

    Write-Host ""
}

function Invoke-ScpmInfo {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Targets,

        [switch]$All
    )

    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts -or $reg.scripts.PSObject.Properties.Count -eq 0) {
        Write-Host "当前暂无受管理的脚本。使用 'scpm add <路径>' 添加脚本。" -ForegroundColor Yellow
        return
    }

    $scriptProps = @($reg.scripts.PSObject.Properties)

    # 1. 检查是否查看全部
    $showAll = $All.IsPresent -or ($Targets -contains "-All") -or ($Targets -contains "--all") -or ($Targets -contains "-a") -or ($Targets -contains "all")

    if ($showAll) {
        Write-Host "`n=== [scpm] 全部受管理脚本方法与函数总览 ===" -ForegroundColor Cyan
        for ($i = 0; $i -lt $scriptProps.Count; $i++) {
            $p = $scriptProps[$i]
            Show-SingleScriptInfoInternal ($i + 1) $p.Name $p.Value
        }
        return
    }

    # 2. 如果没有传参，进行交互式选择
    if ($null -eq $Targets -or $Targets.Count -eq 0) {
        Write-Host "`n=== [scpm] 脚本方法与命令详情查询 ===" -ForegroundColor Cyan
        for ($i = 0; $i -lt $scriptProps.Count; $i++) {
            $p = $scriptProps[$i]
            $st = if ($p.Value.enabled) { "[✓]" } else { "[✗]" }
            $stColor = if ($p.Value.enabled) { "Green" } else { "DarkGray" }
            Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor White
            Write-Host "$st " -NoNewline -ForegroundColor $stColor
            Write-Host "$($p.Name.PadRight(22))" -NoNewline -ForegroundColor Cyan
            Write-Host "$($p.Value.description)" -ForegroundColor Gray
        }
        Write-Host "  [a] 查看所有脚本提供的方法清单" -ForegroundColor Yellow

        $choice = Read-Host "`n请选择要查看的脚本编号 [1-$($scriptProps.Count)] (输入 a 查看全部, q 退出)"
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim().ToLower() -in @("q", "quit", "exit")) {
            return
        }
        if ($choice.Trim().ToLower() -in @("a", "all")) {
            Invoke-ScpmInfo -All
            return
        }
        $Targets = @($choice.Trim())
    }

    # 3. 显示指定的脚本详情
    foreach ($t in $Targets) {
        $matchedProps = Resolve-ScpmScriptPropsInternal $t $scriptProps
        if ($matchedProps.Count -eq 0) {
            Write-Host "[错误] 未找到匹配 '$t' 的脚本。" -ForegroundColor Red
            continue
        }
        foreach ($prop in $matchedProps) {
            $idx = ($scriptProps.IndexOf($prop) + 1)
            Show-SingleScriptInfoInternal $idx $prop.Name $prop.Value
        }
    }
}

function Invoke-ScpmAdd {
    $Path = ""
    $Name = ""
    $Desc = ""
    $NoCopy = $false
    $Disable = $false

    for ($i = 0; $i -lt $args.Count; $i++) {
        $curr = $args[$i]
        if ($curr -in @("-Name", "-n", "--name") -and ($i + 1 -lt $args.Count)) {
            $Name = $args[++$i]
        } elseif ($curr -in @("-Desc", "-d", "--desc") -and ($i + 1 -lt $args.Count)) {
            $Desc = $args[++$i]
        } elseif ($curr -in @("-NoCopy", "--no-copy")) {
            $NoCopy = $true
        } elseif ($curr -in @("-Disable", "--disable")) {
            $Disable = $true
        } elseif (-not $Path) {
            $Path = $curr
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "[错误] 指定的文件不存在: $Path" -ForegroundColor Red
        return
    }

    $config = Get-ScpmConfigInternal
    if ($null -eq $config) {
        Write-Host "[错误] scpm 尚未初始化，请先运行 'scpm init'。" -ForegroundColor Red
        return
    }

    $sourceItem = Get-Item -LiteralPath $Path
    $targetName = if (-not [string]::IsNullOrWhiteSpace($Name)) {
        if ($Name.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) { $Name } else { "$Name.ps1" }
    } else {
        $sourceItem.Name
    }

    $storageDir = Resolve-PortablePathInternal $config.storagePath
    $destPath = Join-Path $storageDir $targetName

    if ((-not $NoCopy) -and ($sourceItem.FullName -ne $destPath)) {
        Copy-Item -LiteralPath $sourceItem.FullName -Destination $destPath -Force
        Write-Host "[文件] 已拷贝到脚本仓库: $destPath" -ForegroundColor Gray
        $finalPath = $destPath
    } else {
        $finalPath = $sourceItem.FullName
    }

    if ([string]::IsNullOrWhiteSpace($Desc)) {
        $Desc = Extract-ScriptSynopsisInternal $finalPath
        if ([string]::IsNullOrWhiteSpace($Desc)) {
            $Desc = "自定义脚本: $targetName"
        }
    }

    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts) {
        $reg | Add-Member -NotePropertyName "scripts" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    $reg.scripts | Add-Member -NotePropertyName $targetName -NotePropertyValue ([PSCustomObject]@{
        name = $targetName
        enabled = (-not $Disable)
        description = $Desc
        path = ConvertTo-PortablePath $finalPath
        addedAt = (Get-Date -Format "o")
    }) -Force

    Save-ScpmRegistryInternal $reg
    Update-ScpmLoaderInternal | Out-Null

    $statusStr = if (-not $Disable) { "并已启用注入" } else { "处于禁用状态" }
    Write-Host "[成功] 脚本 '$targetName' 已添加成功 ($statusStr)！" -ForegroundColor Green
}

function Invoke-ScpmNew {
    $Name = ""
    $Desc = ""
    $NoEdit = $false

    for ($i = 0; $i -lt $args.Count; $i++) {
        $curr = $args[$i]
        if ($curr -in @("-Desc", "-d", "--desc") -and ($i + 1 -lt $args.Count)) {
            $Desc = $args[++$i]
        } elseif ($curr -in @("-NoEdit", "-n", "--no-edit")) {
            $NoEdit = $true
        } elseif (-not $Name) {
            $Name = $curr
        }
    }

    $config = Get-ScpmConfigInternal
    if ($null -eq $config) {
        Write-Host "[错误] scpm 尚未初始化，请先运行 'scpm init'。" -ForegroundColor Red
        return
    }

    $targetName = if ($Name.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) { $Name } else { "$Name.ps1" }
    $storageDir = Resolve-PortablePathInternal $config.storagePath
    $targetFile = Join-Path $storageDir $targetName

    if (Test-Path -LiteralPath $targetFile) {
        Write-Host "[错误] 脚本 '$targetName' 已存在于存储目录中。" -ForegroundColor Red
        return
    }

    if ([string]::IsNullOrWhiteSpace($Desc)) {
        $Desc = "PowerShell 脚本 $targetName"
    }

    $fnName = [System.IO.Path]::GetFileNameWithoutExtension($targetName)

    $template = @"
<#
.SYNOPSIS
    $Desc
.DESCRIPTION
    由 scpm (PowerShell Script Profile Manager) 创建
#>

function $fnName {
    [CmdletBinding()]
    param()
    
    Write-Host "[$fnName] 脚本正在运行..." -ForegroundColor Green
}
"@

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($targetFile, $template, $utf8Bom)

    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts) {
        $reg | Add-Member -NotePropertyName "scripts" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    $reg.scripts | Add-Member -NotePropertyName $targetName -NotePropertyValue ([PSCustomObject]@{
        name = $targetName
        enabled = $true
        description = $Desc
        path = ConvertTo-PortablePath $targetFile
        addedAt = (Get-Date -Format "o")
    }) -Force

    Save-ScpmRegistryInternal $reg
    Update-ScpmLoaderInternal | Out-Null

    Write-Host "[成功] 已创建新脚本: $targetName (默认启用)" -ForegroundColor Green

    if (-not $NoEdit) {
        Invoke-ScpmEdit $targetName
    }
}

function Invoke-ScpmEdit {
    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts -or $reg.scripts.PSObject.Properties.Count -eq 0) {
        Write-Host "当前暂无受管理的脚本。" -ForegroundColor Yellow
        return
    }

    $scriptProps = @($reg.scripts.PSObject.Properties)
    $targetProp = $null

    if ($args.Count -eq 0) {
        $targetProp = Select-ScpmScriptSingleInteractive "请选择要编辑的脚本" $scriptProps
        if ($null -eq $targetProp) { return }
    } else {
        $matchedProps = Resolve-ScpmScriptPropsInternal $args[0] $scriptProps
        if ($matchedProps.Count -eq 0) {
            Write-Host "[错误] 未找到脚本: $($args[0])" -ForegroundColor Red
            return
        }
        $targetProp = $matchedProps[0]
    }

    $realPath = Resolve-PortablePathInternal $targetProp.Value.path
    if (-not (Test-Path -LiteralPath $realPath)) {
        Write-Host "[错误] 脚本文件不存在: $realPath" -ForegroundColor Red
        return
    }

    if (Get-Command code -ErrorAction SilentlyContinue) {
        Start-Process "code" -ArgumentList "`"$realPath`""
    } else {
        Start-Process "notepad.exe" -ArgumentList "`"$realPath`""
    }
    Write-Host "[编辑] 已用编辑器打开: $realPath" -ForegroundColor Gray
}

function Invoke-ScpmRemove {
    $Name = ""
    $DeleteFile = $false

    foreach ($curr in $args) {
        if ($curr -in @("-DeleteFile", "-Delete", "-d", "--delete")) {
            $DeleteFile = $true
        } elseif (-not $Name) {
            $Name = $curr
        }
    }

    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts -or $reg.scripts.PSObject.Properties.Count -eq 0) {
        Write-Host "当前暂无受管理的脚本。" -ForegroundColor Yellow
        return
    }

    $scriptProps = @($reg.scripts.PSObject.Properties)
    $targetProp = $null

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $targetProp = Select-ScpmScriptSingleInteractive "请选择要从清单移除的脚本" $scriptProps
        if ($null -eq $targetProp) { return }
    } else {
        $matchedProps = Resolve-ScpmScriptPropsInternal $Name $scriptProps
        if ($matchedProps.Count -eq 0) {
            Write-Host "[错误] 未在管理列表中找到: $Name" -ForegroundColor Red
            return
        }
        $targetProp = $matchedProps[0]
    }

    $toRemove = $targetProp.Name
    $filePath = Resolve-PortablePathInternal $targetProp.Value.path

    $reg.scripts.PSObject.Properties.Remove($toRemove)
    Save-ScpmRegistryInternal $reg
    Update-ScpmLoaderInternal | Out-Null
    Write-Host "[✓] 已从管理清单注销: $toRemove" -ForegroundColor Green

    if ($DeleteFile -and (Test-Path -LiteralPath $filePath)) {
        Remove-Item -LiteralPath $filePath -Force
        Write-Host "    [已删除物理文件] $filePath" -ForegroundColor Yellow
    }
}

function Invoke-ScpmSync {
    [CmdletBinding()]
    param(
        [switch]$Silent
    )

    $config = Get-ScpmConfigInternal
    if ($null -eq $config) {
        if (-not $Silent) { Write-Host "[错误] scpm 尚未初始化。" -ForegroundColor Red }
        return [PSCustomObject]@{ Success = $false; Added = 0; Missing = 0; Enabled = 0; NewScripts = @() }
    }

    $storageDir = Resolve-PortablePathInternal $config.storagePath
    if (-not (Test-Path -LiteralPath $storageDir)) {
        if (-not $Silent) { Write-Host "[错误] 存储目录不存在: $storageDir" -ForegroundColor Red }
        return [PSCustomObject]@{ Success = $false; Added = 0; Missing = 0; Enabled = 0; NewScripts = @() }
    }

    $reg = Get-ScpmRegistryInternal
    if ($null -eq $reg.scripts) {
        $reg | Add-Member -NotePropertyName "scripts" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    if (-not $Silent) {
        Write-Host "`n=== [scpm] 正在同步存储库 ===`n" -ForegroundColor Cyan
    }
    $files = Get-ChildItem -LiteralPath $storageDir -Filter "*.ps1" -File

    $added = 0
    $newScriptNames = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) {
        if (-not $reg.scripts.PSObject.Properties[$f.Name]) {
            $desc = Extract-ScriptSynopsisInternal $f.FullName
            if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "自定义脚本: $($f.Name)" }
            $pPath = ConvertTo-PortablePath $f.FullName

            $reg.scripts | Add-Member -NotePropertyName $f.Name -NotePropertyValue ([PSCustomObject]@{
                name = $f.Name
                enabled = $true
                description = $desc
                path = $pPath
                addedAt = (Get-Date -Format "o")
            }) -Force
            if (-not $Silent) {
                Write-Host "  [发现新脚本] 已添加并启用: $($f.Name) ($desc)" -ForegroundColor Green
            }
            $newScriptNames.Add($f.Name)
            $added++
        }
    }

    # 检查缺失
    $missing = 0
    foreach ($prop in $reg.scripts.PSObject.Properties) {
        $p = Resolve-PortablePathInternal $prop.Value.path
        if (-not (Test-Path -LiteralPath $p)) {
            if (-not $Silent) {
                Write-Host "  [警告] 脚本文件缺失: $($prop.Name) ($p)" -ForegroundColor Yellow
            }
            $missing++
        }
    }

    Save-ScpmRegistryInternal $reg
    $enabled = Update-ScpmLoaderInternal
    if (-not $Silent) {
        Write-Host "`n同步完毕: 新增 $added 个脚本，文件缺失 $missing 个，当前共启用 $enabled 个。" -ForegroundColor Gray
    }

    return [PSCustomObject]@{
        Success = $true
        Added = $added
        Missing = $missing
        Enabled = $enabled
        NewScripts = $newScriptNames
    }
}

function Invoke-ScpmDoctor {
    [CmdletBinding()]
    param()

    Write-Host "`n=== [scpm] 环境健康检查与体检报告 ===" -ForegroundColor Cyan
    
    # 1. 核心目录与配置
    Write-Host "`n[1/4] 配置与元数据状态" -ForegroundColor Green
    if (Test-Path -LiteralPath $Script:ConfigFile) {
        Write-Host "  [✓] 配置文件正常: $Script:ConfigFile" -ForegroundColor Green
    } else {
        Write-Host "  [✗] 配置文件不存在 (请运行 scpm init)" -ForegroundColor Red
    }

    if (Test-Path -LiteralPath $Script:RegistryFile) {
        Write-Host "  [✓] 注册表文件正常: $Script:RegistryFile" -ForegroundColor Green
    } else {
        Write-Host "  [✗] 注册表文件不存在" -ForegroundColor Red
    }

    # 2. 存储库可达性
    Write-Host "`n[2/4] 存储库可达性与坚果云同步" -ForegroundColor Green
    $config = Get-ScpmConfigInternal
    if ($null -ne $config) {
        $realStorage = Resolve-PortablePathInternal $config.storagePath
        if (Test-Path -LiteralPath $realStorage) {
            $isNutstore = $realStorage -like "*Nutstore*" -or $realStorage -like "*坚果云*"
            $tag = if ($isNutstore) { "[坚果云云同步]" } else { "[本地目录]" }
            Write-Host "  [✓] 存储库路径正常 ${tag}: $realStorage" -ForegroundColor Green
        } else {
            Write-Host "  [✗] 存储库路径无法访问: $realStorage" -ForegroundColor Red
        }
    } else {
        Write-Host "  [!] 暂无配置信息" -ForegroundColor Yellow
    }

    # 3. Profile 钩子状态
    Write-Host "`n[3/4] PowerShell Profile 注入检查" -ForegroundColor Green
    $profiles = @(
        @{ Name = "PowerShell 7"; Path = (Join-Path $HOME "Documents\PowerShell\Microsoft.PowerShell_profile.ps1") },
        @{ Name = "Windows PowerShell 5.1"; Path = (Join-Path $HOME "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1") }
    )

    foreach ($pf in $profiles) {
        if (Test-Path -LiteralPath $pf.Path) {
            $content = [System.IO.File]::ReadAllText($pf.Path, [System.Text.Encoding]::UTF8)
            if ($content -match 'scpm loader start') {
                Write-Host "  [✓] $($pf.Name): 已挂载 scpm loader" -ForegroundColor Green
            } else {
                Write-Host "  [!] $($pf.Name): 尚未注入 loader 钩子 (可执行 scpm init 自动挂载)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [!] $($pf.Name): Profile 文件不存在" -ForegroundColor DarkGray
        }
    }

    # 4. 脚本完整度
    Write-Host "`n[4/4] 脚本健康度检查" -ForegroundColor Green
    $reg = Get-ScpmRegistryInternal
    $valid = 0
    $broken = 0
    foreach ($prop in $reg.scripts.PSObject.Properties) {
        $real = Resolve-PortablePathInternal $prop.Value.path
        if (Test-Path -LiteralPath $real) {
            $valid++
        } else {
            $broken++
            Write-Host "  [✗] 缺失文件: $($prop.Name) -> $real" -ForegroundColor Red
        }
    }
    if ($broken -eq 0) {
        Write-Host "  [✓] 所有已登记脚本文件完整 ($valid/$valid)" -ForegroundColor Green
    }

    Write-Host "`n检查完成！" -ForegroundColor Cyan
}

function Invoke-ScpmUpdate {
    $Force = $false
    foreach ($curr in $args) {
        if ($curr -in @("-Force", "-f", "--force")) {
            $Force = $true
        }
    }

    Write-Host "`n=== [scpm] 正在检查更新... ===" -ForegroundColor Cyan
    $repoBase = "https://raw.githubusercontent.com/hbhszy/scpm/main/src"
    $psd1Url = "$repoBase/scpm.psd1"
    $psm1Url = "$repoBase/scpm.psm1"

    try {
        Write-Host "正在连接 GitHub 检查最新版本..." -ForegroundColor Gray
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        
        $cacheBuster = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $remotePsd1 = $wc.DownloadString("${psd1Url}?t=$cacheBuster")
        $remoteVer = "1.0.1"
        if ($remotePsd1 -match "ModuleVersion\s*=\s*['""]([^'""]+)['""]") {
            $remoteVer = $matches[1]
        }

        Write-Host "当前版本: v$Script:ScpmVersion | 远程版本: v$remoteVer" -ForegroundColor White
        
        if ($remoteVer -le $Script:ScpmVersion -and (-not $Force)) {
            Write-Host "[✓] 当前已经是最新版本 (v$Script:ScpmVersion)。如需强制重装可运行: sm update -Force" -ForegroundColor Green
            return
        }

        Write-Host "正在下载更新组件..." -ForegroundColor Yellow
        $remotePsm1 = $wc.DownloadString("${psm1Url}?t=$cacheBuster")

        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        $targets = @(
            (Join-Path $HOME ".scpm"),
            (Join-Path $HOME "Documents\PowerShell\Modules\scpm"),
            (Join-Path $HOME "Documents\WindowsPowerShell\Modules\scpm")
        )

        foreach ($dir in $targets) {
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText((Join-Path $dir "scpm.psm1"), $remotePsm1, $utf8Bom)
            [System.IO.File]::WriteAllText((Join-Path $dir "scpm.psd1"), $remotePsd1, $utf8Bom)
        }

        Update-ScpmLoaderInternal | Out-Null
        Import-Module (Join-Path $HOME ".scpm\scpm.psm1") -Force -DisableNameChecking -ErrorAction SilentlyContinue

        Write-Host "[✓] scpm 成功更新至 v$remoteVer！已即时载入当前会话。" -ForegroundColor Green
    } catch {
        Write-Host "[scpm] 更新检查失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "提示: 也可通过一键安装脚本进行重装/升级:" -ForegroundColor Yellow
        Write-Host "  irm https://raw.githubusercontent.com/hbhszy/scpm/main/install.ps1 | iex" -ForegroundColor White
    }
}

# --------------------------------------------------------------------
# 主入口命令: scpm (别名 sm)
# --------------------------------------------------------------------

function Invoke-ScpmHelp {
    [CmdletBinding()]
    param([string]$Topic = "")

    switch ($Topic) {
        { $_ -in @("on", "enable") } {
            Write-Host "`n用法: sm on [脚本名称/序号...]" -ForegroundColor Cyan
            Write-Host "说明: 启用指定脚本的自启注入，并在当前终端会话立即生效。" -ForegroundColor White
            Write-Host "示例:" -ForegroundColor Gray
            Write-Host "  sm on               # 启动集中启停管理面板 (按空格键切换)" -ForegroundColor White
            Write-Host "  sm on pxy           # 启用 pxy.ps1" -ForegroundColor White
            Write-Host "  sm on 1 2           # 批量启用序号 1 和 2 的脚本" -ForegroundColor White
            Write-Host "  sm on *             # 启用所有脚本" -ForegroundColor White
            return
        }
        { $_ -in @("off", "disable") } {
            Write-Host "`n用法: sm off [脚本名称/序号...]" -ForegroundColor Cyan
            Write-Host "说明: 禁用指定脚本的自启注入 (新开终端将不再载入)。" -ForegroundColor White
            Write-Host "示例:" -ForegroundColor Gray
            Write-Host "  sm off              # 启动集中启停管理面板 (按空格键切换)" -ForegroundColor White
            Write-Host "  sm off pxy          # 禁用 pxy.ps1" -ForegroundColor White
            Write-Host "  sm off 2            # 禁用序号 2 的脚本" -ForegroundColor White
            return
        }
        { $_ -in @("toggle", "switch", "manage", "t") } {
            Write-Host "`n用法: sm toggle [脚本名称/序号...]" -ForegroundColor Cyan
            Write-Host "说明: 集中管理脚本启停状态，或一键翻转目标脚本的启停。" -ForegroundColor White
            Write-Host "示例:" -ForegroundColor Gray
            Write-Host "  sm toggle           # 打开集中管理面板 (↑/↓ 移动光标，空格翻转启停，回车保存生效)" -ForegroundColor White
            Write-Host "  sm toggle pxy       # 翻转 pxy.ps1 的启停状态" -ForegroundColor White
            Write-Host "  sm toggle 1         # 翻转序号 1 脚本的启停状态" -ForegroundColor White
            return
        }
        { $_ -in @("info", "show", "methods", "inspect", "detail") } {
            Write-Host "`n用法: sm info [脚本名称/序号] [-All]" -ForegroundColor Cyan
            Write-Host "说明: 查看脚本提供的具体方法、函数签名、参数选项及用法示例。" -ForegroundColor White
            Write-Host "示例:" -ForegroundColor Gray
            Write-Host "  sm info             # 交互式选择要查看方法的脚本" -ForegroundColor White
            Write-Host "  sm info pxy         # 查看 pxy.ps1 导出的函数与用法" -ForegroundColor White
            Write-Host "  sm info 1           # 查看序号 1 脚本的具体方法" -ForegroundColor White
            Write-Host "  sm info -All        # 查看所有脚本提供的方法总览" -ForegroundColor White
            return
        }
        { $_ -in @("list", "ls") } {
            Write-Host "`n用法: sm list [-Detail]" -ForegroundColor Cyan
            Write-Host "说明: 列出所有受管理的脚本、序号、启停状态、存储路径及提供的方法。" -ForegroundColor White
            Write-Host "选项:" -ForegroundColor Gray
            Write-Host "  -Detail, -d         # 显示完整的函数参数签名" -ForegroundColor White
            return
        }
        default {
            Write-Host "`n=== scpm (PowerShell Script Profile Manager) v$Script:ScpmVersion ===" -ForegroundColor Cyan
            Write-Host "轻量、零依赖的 PowerShell 脚本与云同步管理器`n" -ForegroundColor White
            Write-Host "常用命令 (别名: sm):" -ForegroundColor Green
            Write-Host "  sm / sm ui / sm tui      # 打开全键盘交互式 TUI 管理控制台 (双区实时联动预览)" -ForegroundColor Yellow
            Write-Host "  sm list / ls [-d]        # 查看受管理脚本清单及导出方法 (加 -d 查看函数签名)" -ForegroundColor White
            Write-Host "  sm toggle / t [名称/序号]# 集中启停管理面板 (无参唤起，空格键交互翻转)" -ForegroundColor Yellow
            Write-Host "  sm on [名称/序号]        # 启用脚本注入 (当前会话即时生效，无参唤起控制台)" -ForegroundColor White
            Write-Host "  sm off [名称/序号]       # 禁用脚本注入 (无参唤起控制台)" -ForegroundColor White
            Write-Host "  sm info [名称/序号]      # 查看脚本具体导出的函数、参数及用法示例" -ForegroundColor Cyan
            Write-Host "  sm edit [名称/序号]      # 在编辑器中打开脚本 (无参交互选择)" -ForegroundColor White
            Write-Host "  sm new <名称>            # 快速创建新脚本脚手架模板并打开" -ForegroundColor White
            Write-Host "  sm add <路径>            # 收录现有本地脚本到存储库" -ForegroundColor White
            Write-Host "  sm rm [名称/序号]        # 从管理清单移除脚本 (追加 -DeleteFile 删除物理文件)" -ForegroundColor White
            Write-Host "  sm sync / refresh        # 同步存储库目录（如坚果云中新同步的文件）" -ForegroundColor White
            Write-Host "  sm doctor / status       # 环境健康检查 (配置、路径、Profile 挂载)" -ForegroundColor White
            Write-Host "  sm update / upgrade      # 从 GitHub 检查并一键更新 scpm" -ForegroundColor White
            Write-Host "  sm -h / help [命令]      # 查看帮助说明 (或特定子命令帮助)" -ForegroundColor White
            Write-Host "  sm -v / version          # 查看 scpm 当前版本" -ForegroundColor White
            Write-Host "`n💡 交互式 TUI 快捷提示:" -ForegroundColor DarkGray
            Write-Host "  • 直接运行 'sm' 或 'sm ui' 即可进入 TUI 控制台！" -ForegroundColor DarkGray
            Write-Host "  • [↑/↓] 移动聚焦，下半区实时刷新该脚本导出的方法与文档" -ForegroundColor DarkGray
            Write-Host "  • [空格] 原地秒切启用/禁用，[e] 打开编辑，[n] 新建，[s] 同步，[q] 退出" -ForegroundColor DarkGray
            Write-Host ""
        }
    }
}

function scpm {
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param(
        [Parameter(Position = 0)]
        [string]$Subcommand,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs,

        [Alias("h", "?")]
        [switch]$Help,

        [Alias("v")]
        [switch]$Version,

        [Alias("d")]
        [switch]$Detail
    )

    $isHelp = $Help.IsPresent -or ($Subcommand -in @("help", "-h", "--help", "-?")) -or ($RemainingArgs -contains "-h") -or ($RemainingArgs -contains "--help")
    $isVersion = $Version.IsPresent -or ($Subcommand -in @("version", "-v", "--version")) -or ($RemainingArgs -contains "-v") -or ($RemainingArgs -contains "--version")

    if ($isVersion) {
        Write-Host "scpm version v$Script:ScpmVersion" -ForegroundColor Cyan
        return
    }

    if ($isHelp) {
        $topic = ""
        if ($Subcommand -notin @("help", "-h", "--help", "-?", "")) {
            $topic = $Subcommand
        } elseif ($null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
            $topic = $RemainingArgs[0]
        }
        Invoke-ScpmHelp $topic
        return
    }

    switch ($Subcommand) {
        "init" {
            Invoke-ScpmInit @RemainingArgs
        }
        { $_ -in @("ui", "tui") } {
            Invoke-ScpmTui
        }
        { $_ -in @("list", "ls") } {
            Invoke-ScpmList -Detail:$Detail
        }
        "" {
            if ($Detail.IsPresent) {
                Invoke-ScpmList -Detail:$true
            } else {
                $isInteractive = $false
                try {
                    if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and [Environment]::UserInteractive) {
                        $null = $Host.UI.RawUI.CursorPosition
                        $isInteractive = $true
                    }
                } catch { $isInteractive = $false }

                if ($isInteractive) {
                    Invoke-ScpmTui
                } else {
                    Invoke-ScpmList
                }
            }
        }
        { $_ -in @("toggle", "switch", "manage", "t") } {
            if ($null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
                Invoke-ScpmToggle @RemainingArgs
            } else {
                Invoke-ScpmTui
            }
        }
        { $_ -in @("enable", "on") } {
            if ($null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
                Invoke-ScpmEnable @RemainingArgs
            } else {
                Invoke-ScpmTui
            }
        }
        { $_ -in @("disable", "off") } {
            if ($null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
                Invoke-ScpmDisable @RemainingArgs
            } else {
                Invoke-ScpmTui
            }
        }
        { $_ -in @("info", "show", "methods", "inspect", "detail") } {
            if ($null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
                Invoke-ScpmInfo @RemainingArgs
            } else {
                Invoke-ScpmInfo
            }
        }
        "add" {
            if ($null -eq $RemainingArgs -or $RemainingArgs.Count -eq 0) {
                Write-Host "用法: scpm add <脚本路径> [-Name <名称>] [-Desc <描述>]" -ForegroundColor Yellow
                return
            }
            Invoke-ScpmAdd @RemainingArgs
        }
        "new" {
            if ($null -eq $RemainingArgs -or $RemainingArgs.Count -eq 0) {
                Write-Host "用法: scpm new <脚本名称> [-Desc <描述>]" -ForegroundColor Yellow
                return
            }
            Invoke-ScpmNew @RemainingArgs
        }
        "edit" {
            if ($null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
                Invoke-ScpmEdit @RemainingArgs
            } else {
                Invoke-ScpmEdit
            }
        }
        { $_ -in @("remove", "rm") } {
            if ($null -ne $RemainingArgs -and $RemainingArgs.Count -gt 0) {
                Invoke-ScpmRemove @RemainingArgs
            } else {
                Invoke-ScpmRemove
            }
        }
        { $_ -in @("sync", "refresh") } {
            Invoke-ScpmSync | Out-Null
        }
        { $_ -in @("doctor", "status") } {
            Invoke-ScpmDoctor
        }
        { $_ -in @("update", "upgrade") } {
            Invoke-ScpmUpdate @RemainingArgs
        }
        default {
            # 如果输入的不是已知命令，检查是否是脚本名称或序号
            $reg = Get-ScpmRegistryInternal
            if ($null -ne $reg.scripts -and $reg.scripts.PSObject.Properties.Count -gt 0) {
                $scriptProps = @($reg.scripts.PSObject.Properties)
                $matched = Resolve-ScpmScriptPropsInternal $Subcommand $scriptProps
                if ($matched.Count -gt 0) {
                    Invoke-ScpmInfo $Subcommand
                    return
                }
            }
            Invoke-ScpmHelp $Subcommand
        }
    }
}

# 导出函数与别名
Set-Alias -Name sm -Value scpm -Scope Global
Export-ModuleMember -Function scpm -Alias sm

# --------------------------------------------------------------------
# 自动补全支持 (Argument Completion)
# --------------------------------------------------------------------
try {
    $scriptCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $elements = $commandAst.CommandElements
        $subcommand = if ($elements.Count -gt 1) { $elements[1].Extent.Text } else { "" }

        if ($elements.Count -eq 2 -and (-not $elements[1].Extent.Text.EndsWith(" "))) {
            $subs = @("init", "ui", "tui", "list", "ls", "toggle", "switch", "manage", "t", "enable", "on", "disable", "off", "info", "show", "methods", "inspect", "add", "new", "edit", "remove", "rm", "sync", "refresh", "doctor", "status", "update", "upgrade", "help", "version")
            $subs | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        } elseif ($subcommand -in @("enable", "on", "disable", "off", "toggle", "t", "switch", "manage", "info", "show", "methods", "inspect", "edit", "remove", "rm")) {
            $reg = Get-ScpmRegistryInternal
            if ($null -ne $reg.scripts) {
                $reg.scripts.PSObject.Properties | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Value.description)
                }
            }
        }
    }

    Register-ArgumentCompleter -CommandName ('scpm', 'sm') -ScriptBlock $scriptCompleter -ErrorAction SilentlyContinue
} catch {}
