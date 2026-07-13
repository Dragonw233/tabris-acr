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

## 发布

直接运行：

```powershell
.\scripts\Publish-AcrZip.ps1
```

从 `scripts` 目录里运行也可以，输出仍会写到发布库根目录。

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

然后默认提交并推送到 GitHub `main`，再上传到 GitHub Release。版本号读取来源 `Tabris.json` 的 `version` 字段，同版本 Release 里的 `Tabris.zip` / `Tabris.json` 会自动覆盖。

默认版本号读取来源 `Tabris.json` 的 `version` 字段；如果要临时覆盖版本号：

```powershell
.\scripts\Publish-AcrZip.ps1 -Version "1.0.1"
```

## 只本地更新

如果只想复制文件，不上传 GitHub：

```powershell
.\scripts\Publish-AcrZip.ps1 -LocalOnly
```

如果只想更新 Release，不提交推送 `main`：

```powershell
.\scripts\Publish-AcrZip.ps1 -SkipGitPush
```

如果不想覆盖同版本 Release 里的已有资产：

```powershell
.\scripts\Publish-AcrZip.ps1 -NoClobberGitHubRelease
```
