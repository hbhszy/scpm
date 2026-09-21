# scpm (Script Profile Manager)

<p align="center">
  <b>极简、轻量、零依赖的 PowerShell 脚本与云同步管理器</b><br>
  <sub>告别臃肿杂乱的 <code>$PROFILE</code>，一套脚本库多设备自动同步，即开即用、按需注入。</sub>
</p>

---

## ✨ 核心特性

- ⚡ **启动零延迟 (0ms)**：通过静态编译的 Loader 机制，每次打开终端只加载启用的脚本纯文本引用，**零 JSON 解析、零复杂开销**。
- ☁️ **坚果云 / 云同步原生联动**：初始化自动探测坚果云（Nutstore）目录，将个人脚本库放入云端，多电脑自动同步。
- 🔌 **按需启停与即时加载**：
  - `sm enable <脚本>`：加入自启并**即时注入当前终端**，无需重启窗口。
  - `sm disable <脚本>`：一键关闭自启，保持终端干净整洁。
- 🛠️ **全生命周期管理**：
  - `sm new`：快速生成带注释模板的标准脚本并自动打开编辑器。
  - `sm add`：导入本地脚本，自动提取脚本内描述。
  - `sm edit`：直接用 VS Code / 记事本编辑脚本。
  - `sm sync`：一键同步扫描云盘中新增或删减的脚本。
  - `sm doctor`：配置、存储路径、云盘连接与 Profile 挂载健康检查。
- 🔄 **内置一键自更新**：运行 `sm update` 即可从 GitHub 自动检测并拉取最新版本，现有配置与脚本 100% 安全保留。
- 🛡️ **双环境与中文编码兼容**：采用 UTF-8 with BOM 规范与 `$HOME` 相对路径，完美兼容 **PowerShell 7** 与 **Windows PowerShell 5.1**，避免多字节中文解析报错。

---

## 🚀 快速安装

### 方式一：远程一键安装（推荐）

在 PowerShell 终端（以管理员或普通用户均可）中执行：

```powershell
irm https://raw.githubusercontent.com/hbhszy/scpm/main/install.ps1 | iex
```

> **提示**：安装完成后会自动引导执行初始化 `scpm init`，智能识别坚果云路径并挂载到 `$PROFILE`。

---

### 方式二：本地克隆安装

```powershell
git clone https://github.com/hbhszy/scpm.git
cd scpm
.\install.ps1
```

---

## 📖 常用命令速查

命令名支持完整格式 `scpm`，也支持极简别名 **`sm`**：

| 命令 | 别名 | 功能描述 |
| :--- | :--- | :--- |
| `sm init` | - | **初始化向导**：自动探测坚果云路径，选择存储目录并注入 Profile 钩子 |
| `sm list` | `sm ls` | **查看脚本清单**：显示所有受管理脚本、启停状态 `[✓]/[✗]`、描述及路径 |
| `sm enable <名称>` | `sm on` | **启用脚本注入**：加入引导并在**当前会话立即生效**（支持通配符 `sm on *`） |
| `sm disable <名称>` | `sm off`| **禁用脚本注入**：关闭自启，新终端将不再加载该脚本 |
| `sm add <文件路径>` | - | **收录脚本**：将现有脚本安全复制到存储库，自动提取简介并注册 |
| `sm new <名称>` | - | **新建脚本**：生成标准脚手架模板并自动调用默认编辑器打开 |
| `sm edit <名称>` | - | **快速编辑**：自动使用 VS Code 或记事本打开脚本文件 |
| `sm rm <名称>` | `sm remove`| **注销脚本**：从管理清单中剔除（追加 `-DeleteFile` 可连同删除磁盘文件） |
| `sm sync` | `sm refresh`| **刷新同步**：扫描存储库目录（如坚果云中新同步的文件），自动注册增量 |
| `sm doctor` | `sm status` | **健康体检**：检查配置文件、存储库可达性、Profile 挂载与文件完整度 |
| `sm update` | `sm upgrade`| **一键升级**：连接 GitHub 检查并自动更新 scpm 到最新版 |
| `sm help` | `-h` | 显示帮助说明菜单 |

---

## 💡 典型使用场景示例

### 1. 跨电脑同步 Antigravity CLI 切换脚本
在电脑 A 上：
```powershell
# 初始化并选择坚果云路径 (推荐)
sm init

# 查看已有坚果云脚本，确认 agy-toggle 已就绪
sm ls
```

在电脑 B 上：
安装坚果云并完成文件同步后，直接运行：
```powershell
irm https://raw.githubusercontent.com/hbhszy/scpm/main/install.ps1 | iex
```
安装程序会自动定位到同一个坚果云同步目录，所有脚本和自启设置秒级同步就绪！

### 2. 新建一个小工具脚本
```powershell
sm new pxy -Desc "快速设置与取消终端 HTTP 代理"
```
自动创建并打开编辑器，编辑保存后即刻在终端全局可用。

### 3. 升级 scpm
```powershell
sm update
```
自动拉取 GitHub 仓库最新代码，刷新 Loader 并热重载到当前会话。

---

## 🗑️ 卸载

如需卸载 `scpm`，可运行仓库自带的卸载脚本：

```powershell
.\uninstall.ps1
```

- 会自动从 `$PROFILE` 中清除 `# >>> scpm loader start >>>` 引导块。
- 会删除已安装的模块文件。
- **默认完整保留你的坚果云及所有个人脚本源文件**。

---

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 协议。
