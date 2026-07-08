# GitHub Script Entrance

**一句话，以管理员权限运行任意 GitHub / 网络 / 本地脚本 —— 免下载、免手动提权、免切目录。**

把脚本存到 GitHub（或任意可访问的 URL），然后用一行命令就能：**自动请求管理员权限 → 通过国内可达的镜像下载 → 直接运行**。再也不用「先下载 → 右键以管理员打开 → `cd` 切目录 → 敲一堆 `-ExecutionPolicy Bypass -File`」。

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [快速开始](#快速开始)
- [参数说明](#参数说明)
- [目标地址的三种写法](#目标地址的三种写法)
- [支持的文件类型与运行方式](#支持的文件类型与运行方式)
- [工作原理](#工作原理)
- [镜像与 ISP 封锁](#镜像与-isp-封锁)
- [常见问题](#常见问题)

---

## 它解决什么问题

平时运行一个网上的 `.ps1` / `.bat` 脚本，你得：

1. 打开浏览器，找到并下载脚本
2. 右键「以管理员身份运行 PowerShell」
3. `Set-ExecutionPolicy` 或每次带 `-ExecutionPolicy Bypass`（脚本没签名会被拦）
4. `cd` 切换到脚本所在目录
5. 才能 `.\脚本.ps1` 跑起来

而且在国内，`raw.githubusercontent.com` 经常被 ISP 干扰下载失败。

**GitHub Script Entrance 把这一切压缩成一行命令。** 它是一个极小的「引导壳」`launch.ps1`，负责自动提权、镜像下载、按类型运行，跑完自动清理临时文件。

---

## 快速开始

### 方式 A：Win + R 运行框

按 `Win + R`，粘贴下面这行，回车（弹出 UAC 时点「是」）：

```
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r '你要运行的脚本'"
```

### 方式 B：命令提示符 (CMD) / PowerShell

同一行命令，粘贴回车即可。

### 真实例子

```powershell
# 1) 跑另一个 GitHub 仓库里的脚本（直接用好记的网页地址）
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r 'https://github.com/lcxxjmsg-cyber/SMBProxy/blob/main/server/setup-server.ps1'"

# 2) 跑任意网站上的脚本
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r 'https://example.com/tool.ps1'"

# 3) 跑本机脚本（绝对路径，自动提权）
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r 'C:\tools\install.bat'"

# 4) 给目标脚本传参数
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r 'https://example.com/tool.ps1' -a '-Port','1445'"

# 5) 目标 ps1 需要读取同目录文件 -> 加 -d 落地运行
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -r 'https://github.com/user/repo/blob/main/setup.ps1' -d"
```

> 💡 **命令由两部分组成**：
> - 前半段 `irm 'https://gh-proxy.com/.../launch.ps1'` 是**拉取引导壳本身**，地址固定、不用改。
> - 后半段 `-r '...'` 才是**你要运行的目标**，这里随便换。

---

## 参数说明

| 参数 | 全名 | 必填 | 说明 |
|------|------|:---:|------|
| `-r` | `-Run` | ✅ | 要运行的目标：完整 URL / GitHub 网页地址 / 本地文件绝对路径 |
| `-a` | `-ScriptArgs` | | 转发给目标脚本的参数（数组），如 `-a '-Port','1445'` |
| `-d` | `-Disk` | | 让 `.ps1` 落地到临时文件再运行（默认内存运行）。脚本依赖同目录文件时用 |
| `-n` | `-NoElevate` | | 跳过自动提权（已是管理员或无需管理员时用） |

> 参数用短名 `-r/-a/-d/-n` 即可；PowerShell 也接受全名或任意不歧义的前缀。

---

## 目标地址的三种写法

`-r` 会自动识别下列三种形态：

| 写法 | 示例 | 处理方式 |
|------|------|---------|
| **GitHub 网页地址** | `https://github.com/user/repo/blob/main/x.ps1` | 自动转成 raw，走镜像加速 |
| **raw / 任意 URL** | `https://raw.githubusercontent.com/...`<br>`https://example.com/x.ps1` | GitHub 走镜像；其他站直连 |
| **本地文件路径** | `C:\tools\x.ps1` | 不下载，直接运行（仅绝对路径） |

---

## 支持的文件类型与运行方式

只支持脚本类：`.ps1` / `.bat` / `.cmd`。

| 类型 | 运行方式 |
|------|---------|
| `.ps1` | **默认内存运行**（不落地）；加 `-d` 则下载到临时文件再运行 |
| `.bat` / `.cmd` | 下载到临时文件，用 `cmd.exe` 运行，跑完删除 |

> 所有落地的临时文件都会在运行结束后**自动清理**。所有目标都继承引导壳的**管理员权限**。

**关于 `.ps1` 内存运行的一个注意点：** 内存运行时脚本没有对应磁盘文件，因此 `$PSScriptRoot` / `$MyInvocation.MyCommand.Path` 为空。如果脚本要找「和自己放在一起的文件」（配置、插件等），请加 `-d` 落地运行。

---

## 工作原理

```
一行命令
   │
   ▼
irm 拉取 launch.ps1 (引导壳, 走 gh 镜像, 内存执行)
   │
   ▼
scriptblock 传参执行 launch.ps1 -r <目标>
   │
   ├─ 非管理员? → UAC 提权, 原样带参重新拉起 (自身也走镜像)
   │
   ├─ 识别 -r:  GitHub网页→raw | raw/URL | 本地文件(绝对路径)
   │
   ├─ 远程? → 多镜像回退下载 (github 类自动加速)
   │
   ├─ 运行:
   │     ps1  → 默认内存运行 (加 -d 落地)
   │     bat/cmd → 落地临时文件, cmd /c 运行
   │
   └─ finally: 清理所有临时文件
```

---

## 镜像与 ISP 封锁

针对 GitHub 域名（`github.com` / `raw.githubusercontent.com`），引导壳会**按顺序尝试多个镜像**，任一成功即用，全部失败才报错：

1. `gh-proxy.com`（实时转发，永远最新）
2. `ghproxy.net`
3. `ghfast.top`
4. `cdn.jsdelivr.net`（CDN 回退）
5. `fastly.jsdelivr.net`
6. `raw.githubusercontent.com`（原始源，最后兜底）

> **只有 GitHub 系地址会走镜像**（这些镜像是 GitHub 专用反代）。指向其他平台（GitLab、你自己的服务器等）的 URL 会**直连下载**，不经过镜像。如果那些站点本身被墙，本工具无法代理。

---

## 常见问题

**Q：为什么前半段拉壳必须用 raw 地址，不能用 github 网页地址？**

A：前半段是 PowerShell 的 `irm` 直接下载，没有任何智能转换；`gh-proxy.com/` 后面必须跟真实的 `raw.githubusercontent.com` 地址。而「github 网页地址自动转 raw」是**引导壳内部**的功能，只对后半段 `-r` 的目标生效（那时壳已加载）。

**Q：`.ps1` 默认内存运行，会不会留在磁盘上？**

A：不会。`.ps1` 默认在内存中执行，不写文件。只有你加了 `-d`、或运行 `.bat`/`.cmd` 时才会写临时文件，且运行结束即删除。

**Q：我的 ps1 要读取同目录的配置文件，内存运行报错找不到？**

A：加 `-d`。内存运行没有脚本文件路径（`$PSScriptRoot` 为空），落地运行即可恢复正常。

**Q：`.bat` 也是管理员权限吗？**

A：是。引导壳启动即提权为管理员，之后它运行的 `cmd` 继承管理员权限。

**Q：能运行 GitLab / 其他被墙平台的脚本吗？**

A：能下载能运行，但**不走 GitHub 镜像加速**（那些镜像只服务 GitHub）。若目标平台本身被 ISP 封锁，需要你自备通用代理。

---

## License

MIT
