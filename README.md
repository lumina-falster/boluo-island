# 🍍 菠萝岛果实助手

逆水寒手游「菠萝岛」果实成熟倒计时工具：手机网页查看每块地的成熟状态和剩余时间，快成熟前自动推送到微信。

- **零服务器**：静态网页托管在 GitHub Pages，定时任务用 GitHub Actions，全部免费
- **手动录入**：照着游戏内显示的剩余时间点几下即可，无需读内存、无封号风险
- **数据自主**：所有数据存在你自己仓库的 `data.json` 里

```
手机浏览器（GitHub Pages 网页）
   │ ① 种下果实时，照游戏显示录入「剩余时间」+ 肥料
   │ ② 网页通过 GitHub API 写入 data.json（倒计时本地实时计算）
   ▼
GitHub 仓库（data.json）
   │ ③ Actions 定时任务每 5 分钟检查一次
   ▼
Server酱 / 企业微信机器人 / PushPlus → 微信收到提醒
```

> 注：Actions 定时任务高峰期可能有几分钟延迟，建议「提前提醒」设置 ≥15 分钟。

---

## 一、部署（约 10 分钟）

### 方式 A：自动部署（推荐，本机装有 Python 即可）

```bash
python deploy.py --token <你的GitHub令牌> --serverchan-key <Server酱SendKey>
```

一条命令完成建仓库、传文件、开 Pages、配密钥、发测试通知。令牌需勾选 `repo` + `workflow` 权限。之后拿到企业微信 Webhook 等再重跑一次即可补配。

### 方式 B：手动部署

#### 1. 创建 GitHub 仓库并上传文件

注册/登录 [github.com](https://github.com) → 右上角 **+** → **New repository** → 名称如 `boluo-island`，选 **Public**（免费额度必需，数据只有果实信息，无隐私）→ Create。

把 4 个核心文件上传到仓库**根目录**（网页上传：仓库页 **Add file → Upload files**，把 `index.html`、`data.json`、`scripts` 文件夹、`.github` 文件夹一起拖进去；或用 git；`deploy.py` 只是本机部署辅助脚本，无需上传）：

```
boluo-island/
├── index.html                  ← 网页
├── data.json                   ← 数据
├── scripts/notify.py           ← 提醒脚本
└── .github/workflows/notify.yml ← 定时任务
```

git 方式：

```bash
cd boluo-island
git init && git add . && git commit -m "init"
git branch -M main
git remote add origin https://github.com/<你的用户名>/boluo-island.git
git push -u origin main
```

### 2. 开启 GitHub Pages

仓库 **Settings → Pages** → Source 选 **Deploy from a branch** → 分支 `main`、目录 `/(root)` → Save。
1 分钟后访问 `https://<你的用户名>.github.io/boluo-island/`。

### 3. 创建访问令牌（PAT）

GitHub → 头像 → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**：

- Repository access：**Only select repositories** → 选中 `boluo-island`
- Permissions：**Contents → Read and write**，**Actions → Read and write**
- 有效期建议 90 天以上（过期后网页会提示，重新生成并在网页设置里更新即可）

复制生成的令牌（`github_pat_` 开头），后面填进网页。令牌只存在你手机浏览器本地，不会上传到任何地方。

### 4. 配置通知渠道（至少配一个）

在仓库 **Settings → Secrets and variables → Actions → New repository secret** 逐个添加：

| Secret 名 | 获取方式 |
|---|---|
| `SERVERCHAN_SENDKEY` | [sct.ftqq.com](https://sct.ftqq.com) 微信扫码登录 → 复制 SendKey（免费版每天 5 条） |
| `WECOM_WEBHOOK` | 手机装「企业微信」→ 免费创建企业 → 建个群 → 群设置 → 群机器人 → 添加 → 复制 Webhook 地址 |
| `PUSHPLUS_TOKEN` | [pushplus.plus](https://www.pushplus.plus) 微信扫码 → 复制 token（Server酱 条数不够时的备选） |

### 5. 网页里完成配置

手机打开第 2 步的网页地址（建议「添加到主屏幕」当 App 用）：

1. 点右上角 **⚙️ 设置** → 填 GitHub 用户名、仓库名、PAT → **测试并保存连接**
2. 设置提前提醒分钟数（默认 15）、通知渠道开关 → **保存设置**
3. 点 **发送测试通知**，微信收到消息即部署成功 ✅

---

## 二、日常使用

界面是和游戏农场对应的 **8×8 = 64 块地网格**，每格显示位置（行-列）、果实和倒计时，颜色区分状态（绿=生长中 / 橙=即将成熟 / 红=已成熟）。

**批量种植（推荐）**：

1. 点「批量种植」进入批量模式
2. 手指**拖动滑过**要种的地块即选中（滑过已选地块可取消）
3. 点底部「种植」→ 选果实、肥料，填剩余时间 → 保存，一次种完一整片

**单块操作**：普通模式下点地块——空地直接录入；已种植的显示详情（倒计时、肥料、备注），可「编辑 / 重新录入」或「已收获，清空地块」。

- 照游戏里显示的剩余时间填（有 30分钟/1/2/4/8/12/24小时 快捷键），成熟时刻自动计算
- 游戏里被**催熟舞/好友松土/促熟化肥**加速后，进详情点「编辑 / 重新录入」更新剩余时间
- 批量模式下点「清空」可一次收获多块地
- 也可以用「按种植时间推算」模式：填种植时间和预计成熟时长，适合补录之前种下的
- 地块名可以改成游戏里的实际位置叫法（单块编辑时改）

## 三、常见问题

- **提醒没来 / 迟到**：GitHub Actions 高峰期会延迟几分钟，属正常；去仓库 **Actions** 标签页看「菠萝岛成熟提醒」的运行记录排查。也可在网页设置里点「立即检查提醒」手动触发。
- **Server酱 每天只有 5 条免费额度**：多块地同时成熟会合并成一条推送；不够用时改用企业微信机器人或 PushPlus。
- **GitHub 会自动禁用 60 天无活动的定时任务**：日常使用网页保存数据就会产生提交，保持活跃即可；若被禁用，去 Actions 页面手动 Enable。
- **PAT 过期**：网页会提示 401，重新生成令牌并在设置里更新。
- **误操作想恢复数据**：`data.json` 每次修改都有 commit 记录，仓库里可查看历史版本还原。
- **为什么是 8×8**：对应菠萝岛农场的 64 块地布局。如果以后游戏改了地块数，改 `index.html` 里的 `ROWS/COLS` 常量和 `data.json` 即可。

## 四、说明

- 本工具与网易/逆水寒官方无关，纯手动录入，不读取游戏数据，无封号风险。
- 倒计时基于录入时刻推算，若游戏内加速/打断，请及时重新录入。
