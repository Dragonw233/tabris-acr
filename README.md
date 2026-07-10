# Tabris BLM ACR Releases

PR 黑魔 ACR 发布。

这是一个简化版 ACR 发布库：不包含社区下载清单，不做历史版本目录，只从本机 ACR 目录打包并发布一个压缩包。

默认发布文件名：

```text
Tabris.zip
```

职业：黑魔法师 / Black Mage / `BLM`

默认 GitHub 仓库：`Dragonw233/tabris-acr`

默认打包目录：

```text
C:\Users\Administrator\AppData\Roaming\XIVLauncherCN\pluginConfigs\PromeRotation\ACR\Tabris
```

## 目录结构

| 路径 | 用途 |
| --- | --- |
| `Tabris.zip` | 发布脚本从本机 `Tabris` ACR 目录生成的压缩包。 |
| `scripts/Publish-AcrZip.ps1` | 压缩 ACR 目录、计算 sha256，可选创建 GitHub Release。 |

## 生成压缩包

在仓库根目录运行：

```powershell
.\scripts\Publish-AcrZip.ps1 `
  -Version "1.0.0.0"
```

脚本会把默认 ACR 目录压缩为：

```text
Tabris.zip
```

压缩包内部结构会保留顶层 `Tabris\` 目录，例如：

```text
Tabris/
  BlackMage.dll
  BlackMage.deps.json
  BlackMage.pdb
```

然后提交推送即可：

```powershell
git add Tabris.zip
git commit -m "release: v1.0.0.0"
git push origin main
```

## 发布到 GitHub Release

如果已安装并登录 GitHub CLI，可以让脚本直接创建 GitHub Release 并上传这个 zip：

```powershell
.\scripts\Publish-AcrZip.ps1 `
  -Version "1.0.0.0" `
  -UploadGitHubRelease
```

`GitHubOwner` 默认是 `Dragonw233`，`GitHubRepository` 默认是 `tabris-acr`。如果以后换仓库，再手动传 `-GitHubRepository "<仓库名>"`。

如果需要临时从别的目录打包，可以传：

```powershell
.\scripts\Publish-AcrZip.ps1 `
  -Version "1.0.0.0" `
  -AcrSourceDirectory "D:\path\to\Tabris"
```
