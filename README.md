# GitHub Script Entrance

**一句话，以管理员权限运行任意 GitHub / 网络 / 本地脚本 —— 免下载、免手动提权、免切目录。**

把脚本存到 GitHub（或任意可访问的 URL），然后用一行命令就能：**自动请求管理员权限 → 通过国内可达的镜像下载 → 直接运行**。再也不用「先下载 → 手动以管理员打开 PowerShell / CMD → `cd` 切到脚本目录 → 敲一堆 `-ExecutionPolicy Bypass -File`」。

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [快速开始](#快速开始)
- [参数说明](#参数说明)
- [目标地址的四种写法](#目标地址的四种写法)
- [支持的文件类型](#支持的文件类型)
- [工作原理](#工作原理)
- [镜像与 ISP 封锁](#镜像与-isp-封锁)
- [常见问题](#常见问题)

---

## 它解决什么问题

平时运行一个网上的 `.ps1` / `.bat` 脚本，你得：

1. 打开浏览器，找到并下载脚本
2. 右键「以管理员身份运行 PowerShell」
3. `Set-ExecutionPolicy` 或每次带 `-ExecutionPolicy Bypass`
4. `cd` 切换到脚本所在目录
5. 才能 `.\脚本.ps1` 跑起来

而且在国内，`raw.githubusercontent.com` 经常被 ISP 干扰下载失败。

**GitHub Script Entrance 把这一切压缩成一行命令。** 它是一个极小的「引导壳」`launch.ps1`，负责自动提权、镜像下载、按类型运行、跑完清理临时文件。

---

## 快速开始

### 方式 A：Win + R 运行框

按 `Win + R`，粘贴下面这行，回车（弹出 UAC 时点「是」）：

```
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -Run '你要运行的脚本'"
```

### 方式 B：命令提示符 (CMD) / PowerShell

同一行命令，粘贴回车即可。

### 真实例子

```powershell
# 1) 跑另一个 GitHub 仓库里的脚本（直接用好记的网页地址）
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -Run 'https://github.com/lcxxjmsg-cyber/SMBProxy/blob/main/client/setup-client-win10-11.ps1'"

# 2) 跑任意网站上的脚本
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -Run 'https://example.com/tool.ps1'"

# 3) 跑本机的脚本（自动提权，省去手动开管理员窗口 + 切目录）
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -Run 'C:\tools\install.bat'"

# 4) 给目标脚本传参数
powershell "& ([scriptblock]::Create((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/lcxxjmsg-cyber/GitHub-Script-Entrance/main/launch.ps1'))) -Run 'https://example.com/tool.ps1' -ScriptArgs '-Port','1445'"
```

> 💡 **命令由两部分组成**：
> - 前半段 `irm 'https://gh-proxy.com/.../launch.ps1'` 是**拉取引导壳本身**，地址固定、不用改。
> - 后半段 `-Run '...'` 才是**你要运行的目标**，这里随便换。

---

## 参数说明

| 参数 | 必填 | 说明 |
|------|:---:|------|
| `-Run` | ✅ | 要运行的目标：URL / 仓库相对路径 / 本地文件路径 |
| `-Repo` | | 仓库相对路径的归属仓库，默认 `lcxxjmsg-cyber/GitHub-Script-Entrance` |
| `-Branch` | | 分支，默认 `main` |
| `-ScriptArgs` | | 转发给目标脚本的参数（数组），如 `-ScriptArgs '-a','1'` |
| `-NoElevate` | | 跳过自动提权（已是管理员或无需管理员时用） |

---

## 目标地址的四种写法

`-Run` 会自动识别下列四种形态：

| 写法 | 示例 | 处理方式 |
|------|------|---------|
| **GitHub 网页地址** | `https://github.com/user/repo/blob/main/x.ps1` | 自动转成 raw，走镜像加速 |
| **raw / 任意 URL** | `https://raw.githubusercontent.com/...`<br>`https://example.com/x.ps1` | GitHub 走镜像；其他站直连 |
| **仓库相对路径** | `client/setup.ps1` | 按 `-Repo`/`-Branch` 拼成 raw，走镜像 |
| **本地文件路径** | `C:\a\x.ps1`、`.\x.bat` | 不下载，直接运行 |

---

## 支持的文件类型

| 类型 | 运行方式 |
|------|---------|
| `.ps1` | 在当前（管理员）进程内执行，交互输入（`Read-Host`）正常 |
| `.bat` / `.cmd` | 下载到临时目录后用 `cmd.exe /c` 运行 |
| `.exe` | 直接运行 |
| `.msi` | 通过 `msiexec /i` 安装 |

> 远程文件会下载到系统临时目录，运行结束后**自动清理**。所有目标都继承引导壳的**管理员权限**。

---

## 工作原理

```
一行命令
   │
   ▼
irm 拉取 launch.ps1 (引导壳, 走 gh 镜像)
   │
   ▼
scriptblock 传参执行 launch.ps1 -Run <目标>
   │
   ├─ 非管理员? → UAC 提权, 原样带参重新拉起 (自身也走镜像)
   │
   ├─ 识别 -Run:  GitHub网页→raw | raw/URL | 仓库相对 | 本地
   │
   ├─ 远程? → 多镜像回退下载到临时目录 (github 类自动加速)
   │
   ├─ 按扩展名运行: ps1 / bat / cmd / exe / msi
   │
   └─ finally: 清理临时文件
```

---

## 镜像与 ISP 封锁

针对 GitHub 域名（`github.com` / `raw.githubusercontent.com`），引导壳会**按顺序尝试多个镜像**，任一成功即用，全部失败才报错：

1. `gh-proxy.com`（实时转发，永远最新）
2. `ghproxy.net`
3. `ghfast.top`
4. `cdn.jsdelivr.net`（CDN，小文件回退）
5. `fastly.jsdelivr.net`
6. `raw.githubusercontent.com`（原始源，最后兜底）

> **只有 GitHub 系地址会走镜像**（这些镜像是 GitHub 专用反代）。指向其他平台（GitLab、你自己的服务器等）的 URL 会**直连下载**，不经过镜像。如果那些站点本身被墙，本工具无法代理。

---

## 常见问题

**Q：为什么前半段拉壳必须用 raw 地址，不能用 github 网页地址？**

A：前半段是 PowerShell 的 `irm` 直接下载，没有任何智能转换；`gh-proxy.com/` 后面必须跟真实的 `raw.githubusercontent.com` 地址。而「github 网页地址自动转 raw」是**引导壳内部**的功能，只对后半段 `-Run` 的目标生效（那时壳已加载）。

**Q：能运行 GitLab / Bitbucket / 其他被墙平台的脚本吗？**

A：能下载能运行，但**不走 GitHub 镜像加速**（那些镜像只服务 GitHub）。若目标平台本身被 ISP 封锁，需要你自备通用代理。

**Q：会不会把脚本留在磁盘上？**

A：不会。远程脚本下载到系统临时目录，`finally` 中运行结束即删除。本地脚本则原地运行、不复制。

**Q：`.ps1` 之外，`.bat` 也是管理员权限吗？**

A：是。引导壳启动即提权为管理员，之后它启动的 `cmd`/`exe`/`msi` 全部继承管理员权限（Windows 子进程继承父进程令牌）。

**Q：目标脚本需要交互输入怎么办？**

A：`.ps1` 在当前进程内执行，`Read-Host` 等交互完全正常。

**Q：如何拉取被墙的其他 GitHub 仓库？**

A：直接把它的地址放进 `-Run` 即可，例如 `-Run 'https://github.com/别人/仓库/blob/main/x.ps1'`，会自动转 raw 并走镜像。

---

## License

MIT
