Set-StrictMode -Version Latest
$OutputEncoding = New-Object -typename System.Text.UTF8Encoding
$ErrorActionPreference = 'Stop'

######################### Configurations #########################
$apiUrl = "https://steam.ihainan.me/ISteamApps/GetAppList/v2/"       # @ihainan 反代的官方 API，用于提升在大陆地区的下载速度
# $apiUrl = "https://api.steampowered.com/ISteamApps/GetAppList/v2/" # Steam 官方 API 地址
$fileExtensions = @("*.png", "*.avif")                               # 将会被整理的文件类型
$uncategorizedFolder = "Uncategorized Screenshots"                   # 没有被识别的截图文件（比如手工添加到 Steam 的游戏）会被挪到这个目录
##################################################################

######################### Global variables #######################
$gameListFilePath = "app.json"                                       # Steam app list 会被存储到这个文件当中
$appMap = @{}                                                        # Steam app list 会被解析成一个 Map，key 为 ID，value 为 name
##################################################################

# 过滤目录名中的无效字符
function RemoveInvalidFileNameChars {
    param (
        [string]$inputString
    )

    # 获取操作系统不允许用于文件名的字符
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

    # 构建正则表达式模式，用于匹配无效字符
    $regexPattern = [String]::Join('|', ($invalidChars | ForEach-Object { [Regex]::Escape($_) }))

    # 使用正则表达式替换无效字符为空字符串
    $cleanString = [Regex]::Replace($inputString, $regexPattern, '')

    # 删除末尾的 .，因为创建目录的时候会把 . 去掉，但是删除的时候却不会
    $cleanString = $cleanString -replace '\.*$'

    # 最后再做一次 Trim
    $cleanString = $cleanString.Trim()

    return $cleanString
}

# 通过 Steam 的 GetAppList v2 API 获取完整的 App 列表
function Get-SteamAppList {
    Write-Output "Downloading Steam's app list via the GetAppList v2 API $apiUrl"
    $response = Invoke-RestMethod -Uri $apiUrl -Method GET
    $response | ConvertTo-Json -Depth 100 | Out-File -FilePath $gameListFilePath
    Write-Output "The app list has been saved in the app.json file"          
}

# 解析 JSON 文件，提取 appId 和 name，存储到一个 map 中
function Import-SteamAppListFile {
    Write-Output "Parsing the $gameListFilePath file"
    $jsonContent = Get-Content -Path $gameListFilePath -Raw | ConvertFrom-Json
    foreach ($app in $jsonContent.applist.apps) {
        # 部分游戏名存在多余空格，创建目录时候空格会被自动删除，但是移动目录时候则不会被自动处理
        $appMap[$app.appid.ToString().Trim()] = $app.name.Trim()
    }

    # 部分名字过长或者包含特殊字符的 app，需要做特殊处理
    $appMap["2192280"] = "Architect"
    $appMap["1009190"] = "Burning Rainbow"
    $appMap["1034230"] = "1034230"
    $appMap["17760"] = "17760"
    $appMap["1644070"] = "COGEN: Sword of Rewind"
    $appMap["952500"] = "NASCAR Heat 3"

    Write-Output "The app list has been parsed into a Map"
}

# 扫描和移动截图文件到对应的游戏目录中
function Move-SteamScreenshots {
    param (
        [bool]$ShouldCheckIfLocalAppListExpires
    )

    # 扫描当前目录下的截图文件
    Write-Output "Scanning PNG and AVIF screenshot files"
    $files = @()
    foreach ($extension in $fileExtensions) {
        $files += Get-ChildItem -Path . -Filter $extension
    }
    Write-Output "Scan finished"

    # 检查是否需要更新本地的 app list
    $willRefreshAppList = $false
    if ($ShouldCheckIfLocalAppListExpires) {
        foreach ($file in $files) {
            if ($file.Name -match "^(\d+)_") {
                $appId = $matches[1]
                if (-not $appMap.ContainsKey($appId)) {
                    # ID 长度小于等于 7，说明 app 为 Steam 商店 app 而非手工添加的 Steam 外 app
                    if ($appId.Length -le 7) {
                        $willRefreshAppList = $true
                    }
                }
            }
        }
    }

    if ($willRefreshAppList) {
        Write-Output "Local app list may be expired, a refresh is required"
        Get-SteamAppList
        Import-SteamAppListFile
        Move-SteamScreenshots -ShouldCheckIfLocalAppListExpires $false
    } else {
        foreach ($file in $files) {
            if ($file.Name -match "^(\d+)_") {
                $appId = $matches[1]
                if ($appMap.ContainsKey($appId)) {
                    # 去除文件名中的非法字符
                    $appName = $appMap[$appId]
                    $cleanAppName = RemoveInvalidFileNameChars -inputString $appName
                    $dirPath = Join-Path -Path . -ChildPath $cleanAppName
                } else {
                    $dirPath = Join-Path -Path . -ChildPath $uncategorizedFolder
                }
                
                # 如果目录不存在则创建
                if (-not (Test-Path -LiteralPath $dirPath)) {
                    Write-Output "Creating directory $dirPath"
                    New-Item -Path $dirPath -ItemType Directory
                    Write-Output "Directory $dirPath created"
                }        
                
                # 将文件移到游戏对应的目录中
                $newFilePath = Join-Path -Path $dirPath -ChildPath $file.Name
                Write-Output "Moving $($file.FullName) to $newFilePath"
                Move-Item -LiteralPath $file.FullName -Destination $newFilePath -Force        
            }
        }
    }
}

# 首次使用脚本，将会下载 $gameListFilePath
if (-not (Test-Path -Path $gameListFilePath)) {
    Write-Output "The $gameListFilePath file doesn't exist"
    Get-SteamAppList
}

# 解析 JSON 文件
Import-SteamAppListFile

# 扫描和移动截图文件
Move-SteamScreenshots -ShouldCheckIfLocalAppListExpires $true