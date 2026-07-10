# Tabris BLM ACR Releases

PR 黑魔 ACR 发布。

这个仓库只发布 `Tabris.json` 和 `Tabris.zip`。后续发布脚本会直接从本机 PromeRotation 生成的包目录复制这两个文件，不再重新压缩 ACR 目录。

默认来源目录：

```text
C:\Users\Administrator\AppData\Roaming\XIVLauncherCN\pluginConfigs\PromeRotation\ACRPackages\Tabris
```

社区下载清单 raw 链接：

```text
https://raw.githubusercontent.com/Dragonw233/tabris-acr/main/Tabris.json
```

## 文件

| 路径 | 用途 |
| --- | --- |
| `Tabris.json` | PromeRotation 社区下载清单。 |
| `Tabris.zip` | PromeRotation ACR 压缩包。 |
| `scripts/Publish-AcrZip.ps1` | 从 `ACRPackages\Tabris` 复制 zip/json，修正 raw 下载链接和 sha256，可选上传 GitHub Release。 |

## 本地更新

在仓库根目录运行：

```powershell
.\scripts\Publish-AcrZip.ps1
```

脚本会从 `ACRPackages\Tabris` 复制：

```text
Tabris.json
Tabris.zip
```

并把发布库里的 `Tabris.json` 自动修正为：

```text
downloadUrl = https://raw.githubusercontent.com/Dragonw233/tabris-acr/main/Tabris.zip
sha256      = 当前 Tabris.zip 的 SHA256
```

默认版本号读取来源 `Tabris.json` 的 `version` 字段；如果要临时覆盖版本号：

```powershell
.\scripts\Publish-AcrZip.ps1 -Version "1.0.1"
```

## 上传 GitHub Release

已安装并登录 GitHub CLI 后运行：

```powershell
.\scripts\Publish-AcrZip.ps1 -UploadGitHubRelease -ClobberGitHubRelease
```

`-ClobberGitHubRelease` 用于覆盖同版本 Release 里已存在的 `Tabris.zip` / `Tabris.json`。发布新版本时可以不加。
