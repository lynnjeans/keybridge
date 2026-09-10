#!/usr/bin/env bash
#
# bootstrap-github.sh — create the KeyBridge GitHub project: repo, labels,
# milestones and the full v1.0 backlog as issues.
#
# Prerequisites:
#   brew install gh && gh auth login
#
# Usage:
#   ./scripts/bootstrap-github.sh              # create everything
#   REPO=owner/name ./scripts/bootstrap-github.sh   # target an existing repo
#
# Safe to re-run: labels and milestones that already exist are skipped.
# Issues are NOT deduplicated — running twice creates duplicates.

set -euo pipefail

REPO_NAME="keybridge"
VISIBILITY="private"   # change to "public" when you're ready to open it up

# ---------------------------------------------------------------- preflight --

command -v gh >/dev/null 2>&1 || {
  echo "error: gh is not installed.  Run: brew install gh" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || {
  echo "error: gh is not authenticated.  Run: gh auth login" >&2; exit 1; }

if [[ -z "${REPO:-}" ]]; then
  OWNER="$(gh api user --jq .login)"
  REPO="${OWNER}/${REPO_NAME}"
fi

echo "==> Target repository: ${REPO}"

if gh repo view "$REPO" >/dev/null 2>&1; then
  echo "    repository already exists — reusing it"
else
  echo "    creating ${VISIBILITY} repository…"
  gh repo create "$REPO" --"$VISIBILITY" \
    --description "A Mac shortcut bridge for Windows users — keep your muscle memory on macOS." \
    --source=. --remote=origin
fi

# ------------------------------------------------------------------- labels --

echo "==> Creating labels…"
label() {
  gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
  echo "    · $1"
}

label "P0"                 "B60205" "阻塞/地基，必须先做"
label "P1"                 "1D76DB" "核心功能，v1.0 必含"
label "P2"                 "C5DEF5" "增强项，可延后"

label "module:foundation"  "5319E7" "项目地基与系统权限"
label "module:engine"      "5319E7" "CGEventTap 事件引擎"
label "module:device"      "5319E7" "设备识别 (IOHIDManager)"
label "module:rules"       "5319E7" "规则模型与存储"
label "module:keyboard"    "5319E7" "键盘映射"
label "module:mouse"       "5319E7" "鼠标与滚轮"
label "module:presets"     "5319E7" "Windows 预设包"
label "module:ui"          "5319E7" "界面外壳"
label "module:clipboard"   "5319E7" "剪贴板管理"
label "module:i18n"        "5319E7" "多语言"
label "module:release"     "5319E7" "分发与合规"
label "module:qa"          "5319E7" "质量保障"
label "module:window"      "5319E7" "窗口管理 (v1.1)"

# --------------------------------------------------------------- milestones --

echo "==> Creating milestones…"
milestone() {
  if gh api "repos/${REPO}/milestones" --jq '.[].title' 2>/dev/null | grep -qxF "$1"; then
    echo "    · $1 (exists)"
  else
    gh api "repos/${REPO}/milestones" -f title="$1" -f description="$2" >/dev/null
    echo "    · $1"
  fi
}

milestone "M0 地基与权限"    "能启动、能引导授权、能看到权限状态"
milestone "M1 事件引擎"      "稳定拦截键鼠滚轮事件，具备防坑地基"
milestone "M2 设备识别"      "分设备配置，且滚轮只作用于鼠标"
milestone "M3 规则模型"      "预设层 ⊕ 用户覆盖层，套用不丢自定义"
milestone "M4 键盘映射"      "任意「组合 → 组合」映射稳定生效"
milestone "M5 鼠标与滚轮"    "侧键前进后退 + 滚轮缩放（差异化亮点）"
milestone "M6 Windows 预设"  "一键套用 Windows 手感，且可逐条改"
milestone "M7 UI 外壳"       "原生系统风、新手可零学习上手"
milestone "M8 剪贴板"        "Win+V 式历史，可与主线并行开发"
milestone "M9 多语言"        "英文为根，中日可切，跟随系统"
milestone "M10 分发与合规"   "可对外发布的签名版本 + GPL 合规"
milestone "M11 质量保障"     "可回归、可诊断"
milestone "v1.1 窗口贴边"    "旗舰增量：Win+←/→/↑ 半屏与最大化"
milestone "v2 深度键盘"      "DriverKit + tap/hold + 层（需单独立项评估）"

# ------------------------------------------------------------------- issues --

echo "==> Creating issues…"
issue() {
  local id="$1" title="$2" prio="$3" mod="$4" ms="$5" est="$6" deps="$7" desc="$8"
  shift 8
  local ac=""
  for a in "$@"; do ac+="- [ ] ${a}"$'\n'; done

  gh issue create --repo "$REPO" \
    --title "${id} ${title}" \
    --label "$prio" --label "$mod" \
    --milestone "$ms" \
    --body "$(cat <<EOF
**估时** ${est}　·　**依赖** ${deps}

## 描述
${desc}

## 验收标准
${ac}
---
<sub>来自 KeyBridge v1.0 开发计划 · ${ms}</sub>
EOF
)" >/dev/null
  echo "    · ${id} ${title}"
}

# ---- M0 地基与权限 ----------------------------------------------------------
issue "KB-001" "初始化 Xcode 项目与菜单栏骨架" "P0" "module:foundation" "M0 地基与权限" "1d" "—" \
"Swift/SwiftUI 项目，\`MenuBarExtra\` 常驻 + 主窗口空壳，GPL-3.0 LICENSE 就位。" \
"菜单栏图标常驻，可打开主窗口" "可在 Apple Silicon 原生运行"

issue "KB-002" "配置稳定开发签名" "P0" "module:foundation" "M0 地基与权限" "0.5d" "KB-001" \
"配好 Developer ID / 稳定签名标识，避免每次编译后系统权限失效反复重授权。" \
"重复编译运行后权限保持有效"

issue "KB-003" "权限检测服务" "P0" "module:foundation" "M0 地基与权限" "1d" "KB-001" \
"封装辅助功能 \`AXIsProcessTrusted()\` 与输入监控 \`IOHIDCheckAccess()\` 的状态查询。" \
"两项权限状态可独立准确读取" "提供统一的「是否全部就绪」判定"

issue "KB-004" "权限状态实时刷新与撤销降级" "P0" "module:foundation" "M0 地基与权限" "1d" "KB-003" \
"轮询 + \`didBecomeActive\` 通知重检；运行中权限被撤销时自动降级为未授权态。" \
"用户授权后无需重启，界面即时转绿" "中途撤销权限不崩溃，状态正确回退"

issue "KB-005" "首启权限引导流程（3 步）" "P0" "module:foundation" "M0 地基与权限" "2d" "KB-003" \
"说明用途 → 深链跳转系统设置 → 自动检测前进。带图示，未授权前主开关置灰。" \
"深链可直达对应授权面板" "授权完成自动进入下一步"

issue "KB-006" "权限状态展示与主开关联动" "P0" "module:foundation" "M0 地基与权限" "1d" "KB-004" \
"概览页权限卡（全绿「已就绪」/ 缺项橙色「需授权」+ 一键跳转）；菜单栏图标未授权用灰态。" \
"用户随时可看到是否已完成全部必须授权" "缺权限时主开关不可用并给出原因"

# ---- M1 事件引擎 ------------------------------------------------------------
issue "KB-010" "CGEventTap 生命周期管理" "P0" "module:engine" "M1 事件引擎" "2d" "KB-003" \
"创建/启用/销毁 tap，挂载 RunLoop，订阅键盘、鼠标按键与滚轮事件类型。" \
"可稳定接收三类事件并放行" "退出时干净释放，无残留"

issue "KB-011" "EventTap 超时自恢复" "P0" "module:engine" "M1 事件引擎" "1d" "KB-010" \
"监听 \`kCGEventTapDisabledByTimeout\` / \`ByUserInput\`，自动重新启用。" \
"人为制造超时后功能自动恢复" "恢复事件写入诊断日志"

issue "KB-012" "注入事件标记与回环防护" "P0" "module:engine" "M1 事件引擎" "1d" "KB-010" \
"合成事件写入 \`eventSourceUserData\` 标记，tap 内识别自产事件直接放行。" \
"映射链路不产生无限循环" "自产事件不被二次改写"

issue "KB-013" "规则匹配与分发管线" "P0" "module:engine" "M1 事件引擎" "3d" "KB-010, KB-030" \
"事件 →（设备/App 作用域过滤）→ 规则匹配 → 动作执行 的核心管线，要求低延迟。" \
"规则命中正确，未命中原样放行" "单事件处理耗时可测且无可感延迟"

issue "KB-014" "前台应用检测" "P1" "module:engine" "M1 事件引擎" "0.5d" "KB-001" \
"通过 \`NSWorkspace\` 获取前台 App bundleID，供分 App 作用域使用。" \
"切换应用时 bundleID 即时更新"

# ---- M2 设备识别 ------------------------------------------------------------
issue "KB-020" "IOHIDManager 设备枚举" "P1" "module:device" "M2 设备识别" "1.5d" "KB-001" \
"枚举已连接键鼠，读取 VID/PID/名称，监听插拔变化。" \
"能识别出 Razer ProClick（0x1532/0x0076）" "插拔设备列表实时更新"

issue "KB-021" "事件与设备关联" "P1" "module:device" "M2 设备识别" "2d" "KB-020, KB-010" \
"把事件流关联到具体设备，支撑「不同鼠标不同配置」。" \
"两只鼠标可分别应用不同规则"

issue "KB-022" "触控板 vs 鼠标滚动判定" "P0" "module:device" "M2 设备识别" "2d" "KB-010" \
"读 \`continuous\` / \`phase\` / \`momentumPhase\` 判定滚动来源。滚轮功能的前置。" \
"触控板滚动不被反向/缩放规则影响" "鼠标滚轮判定准确率满足日常使用"

# ---- M3 规则模型 ------------------------------------------------------------
issue "KB-030" "规则数据模型" "P0" "module:rules" "M3 规则模型" "1.5d" "—" \
"Codable 定义 \`Rule\`（from/to）、\`Preset\`、\`Override\`、\`Scope\`（设备/App）。" \
"模型可完整表达全部 Windows 预设条目" "可编解码往返无损"

issue "KB-031" "双层合并逻辑（核心交互）" "P0" "module:rules" "M3 规则模型" "2d" "KB-030" \
"生效规则 ＝ 预设层 ⊕ 覆盖层（覆盖优先）。重新套用方案时保留用户已自定义条目。" \
"重新套用后「已自定义」条目不被覆盖" "未改动条目正确更新为新预设值"

issue "KB-032" "配置持久化与版本迁移" "P1" "module:rules" "M3 规则模型" "1d" "KB-030" \
"本地存储配置，带 schema 版本号与迁移路径。" \
"重启后配置完整恢复" "旧版本配置可平滑迁移"

issue "KB-033" "分 App 作用域与例外表" "P1" "module:rules" "M3 规则模型" "1.5d" "KB-030, KB-014" \
"规则可限定 bundleID（如 Finder 套件仅 \`com.apple.finder\`）；内置终端 Ctrl+C 例外。" \
"Finder 规则不在其他 App 生效" "终端内 Ctrl+C 保持中断信号"

# ---- M4 键盘映射 ------------------------------------------------------------
issue "KB-040" "组合→组合 映射执行器" "P0" "module:keyboard" "M4 键盘映射" "3d" "KB-013, KB-012" \
"解析修饰键标志与键码，拦截原事件并合成目标组合键（如 Ctrl+C → ⌘C）。" \
"Ctrl+C/V/Z、Home/End 等映射在常见 App 正确工作" "按住连发、修饰键释放时序无异常"

issue "KB-041" "Secure Input 检测与提示" "P1" "module:keyboard" "M4 键盘映射" "1d" "KB-040" \
"检测 \`IsSecureEventInputEnabled()\`，在密码框场景界面明确提示映射暂不生效。" \
"密码框聚焦时给出可理解的提示而非静默失效"

issue "KB-042" "fn 修饰键支持" "P1" "module:keyboard" "M4 键盘映射" "1d" "KB-040" \
"识别 \`secondaryFn\` 标志，支持 fn+字母 等组合作为触发源。" \
"fn+C 等组合可映射" "单独按 fn 的原生功能不受影响"

# ---- M5 鼠标与滚轮 ----------------------------------------------------------
issue "KB-050" "侧键映射" "P0" "module:mouse" "M5 鼠标与滚轮" "1.5d" "KB-013" \
"拦截 button4/5，映射为任意快捷键（默认 ⌘[ / ⌘] 网页前进后退）。" \
"浏览器中侧键可前进后退" "按键编号可在界面查看与改配"

issue "KB-051" "鼠标按键 → 系统动作" "P2" "module:mouse" "M5 鼠标与滚轮" "1d" "KB-050" \
"映射到 Mission Control、切换空间、Launchpad 等系统动作。" \
"至少支持 3 种常用系统动作"

issue "KB-052" "修饰键 + 滚轮 → ⌘±（差异化核心）" "P0" "module:mouse" "M5 鼠标与滚轮" "2d" "KB-013, KB-022" \
"拦滚轮事件，按住配置的修饰键时合成 ⌘+ / ⌘−。修饰键可选 fn / Ctrl / 自定义。" \
"浏览器与文档中可用修饰键+滚轮缩放页面" "修饰键可在界面切换；Ctrl 方案给出系统缩放冲突提示"

issue "KB-053" "滚轮方向反转（仅鼠标）" "P1" "module:mouse" "M5 鼠标与滚轮" "1d" "KB-022" \
"反转鼠标滚轮方向，触控板不受影响。" \
"鼠标方向反转生效，触控板保持系统设置"

issue "KB-054" "指针速度与加速曲线" "P2" "module:mouse" "M5 鼠标与滚轮" "2d" "KB-021" \
"可关闭系统默认加速、设置线性手感。可复用 LinearMouse（GPL 兼容）实现。" \
"指针加速可开关，速度可调"

# ---- M6 Windows 预设 --------------------------------------------------------
issue "KB-060" "内置预设包（6 组）" "P1" "module:presets" "M6 Windows 预设" "2.5d" "KB-030, KB-033" \
"编辑 / 文本导航 / 文件管理·Finder / 窗口·应用 / 浏览器 / 系统补充（F1–F12、Win+.、Win+Shift+S、Win→Spotlight）。" \
"覆盖清单中「批量」「专项」两类条目全部落地" "Finder 组正确限定作用域"

issue "KB-061" "一键套用与「不覆盖自定义」" "P1" "module:presets" "M6 Windows 预设" "2d" "KB-031, KB-060" \
"概览与快捷键页的「一键套用 / 重新套用」，复用 KB-031 的合并语义。" \
"一键套用后所有分组规则即时生效" "已自定义条目保留并标记"

issue "KB-062" "智能例外提示" "P2" "module:presets" "M6 Windows 预设" "1d" "KB-033" \
"检测到用户常用终端时，自动保留 Ctrl+C 并弹一次说明。" \
"提示仅出现一次且可在设置中回看"

# ---- M7 UI 外壳 -------------------------------------------------------------
issue "KB-070" "主窗口框架与侧栏导航" "P1" "module:ui" "M7 UI 外壳" "1.5d" "KB-001" \
"\`NavigationSplitView\` 左栏 + 右面板，7 个导航项，浅/深色自适应。" \
"导航切换流畅，深浅色均正常"

issue "KB-071" "概览页" "P1" "module:ui" "M7 UI 外壳" "2d" "KB-006, KB-061" \
"主开关 + 一键套用条 + 数字统计 + 权限卡 + 设备卡 + 智能提示。" \
"与设计样稿一致" "各状态（未授权/已就绪）显示正确"

issue "KB-072" "快捷键页" "P1" "module:ui" "M7 UI 外壳" "3d" "KB-060" \
"方案条（切换/重新套用）+ 搜索 + 分组卡（整组开关、展开）+ 逐条映射行。" \
"6 个分组可整组开关与展开" "搜索可过滤到具体条目"

issue "KB-073" "键帽组件（Keycap View）" "P1" "module:ui" "M7 UI 外壳" "1d" "KB-070" \
"可复用的键帽渲染，支持修饰键符号与「前 → 后」映射表达。" \
"任意组合键可正确渲染" "深浅色下均清晰"

issue "KB-074" "逐条编辑器与自定义标记" "P1" "module:ui" "M7 UI 外壳" "2.5d" "KB-073, KB-031" \
"点 ✎ 编辑单条映射，支持快捷键录制；改动后标「已自定义」并写入覆盖层。" \
"录制可捕获含修饰键的组合" "改动落入覆盖层且界面标记正确"

issue "KB-075" "鼠标页与滚轮页" "P1" "module:ui" "M7 UI 外壳" "1.5d" "KB-070" \
"侧键配置、滚轮缩放开关与修饰键选择、方向反转开关。" \
"各开关与引擎实时联动"

issue "KB-076" "设备页" "P2" "module:ui" "M7 UI 外壳" "1d" "KB-020" \
"列出已连接设备与其独立配置入口。" \
"插拔设备列表实时刷新"

issue "KB-077" "自定义规则编辑器（高级）" "P2" "module:ui" "M7 UI 外壳" "2.5d" "KB-074" \
"创建任意「组合 → 组合」规则，可指定设备与 App 作用域。" \
"可新建/编辑/删除规则并即时生效"

issue "KB-078" "菜单栏菜单与快速暂停" "P1" "module:ui" "M7 UI 外壳" "1.5d" "KB-070" \
"菜单栏下拉：总开关、临时暂停、打开主窗口、退出。" \
"无需打开主窗即可暂停/恢复"

# ---- M8 剪贴板 --------------------------------------------------------------
issue "KB-080" "NSPasteboard 监听与采集" "P1" "module:clipboard" "M8 剪贴板" "1.5d" "KB-001" \
"轮询 \`changeCount\` 捕获剪贴板变化，保留原始数据类型。" \
"文本/图片/文件复制均能捕获" "轮询开销可忽略"

issue "KB-081" "历史存储与上限管理" "P1" "module:clipboard" "M8 剪贴板" "2d" "KB-080" \
"本地持久化历史，条数上限可配置，超限淘汰（固定项除外）。" \
"重启后历史保留" "达到上限按策略淘汰"

issue "KB-082" "隐私过滤（安全红线）" "P0" "module:clipboard" "M8 剪贴板" "1.5d" "KB-080" \
"识别 \`org.nspasteboard.ConcealedType\` 等敏感/瞬态类型不入库；支持按 App 排除。" \
"密码管理器复制内容不被记录" "排除名单生效且可编辑"

issue "KB-083" "全局热键与弹出面板" "P1" "module:clipboard" "M8 剪贴板" "2.5d" "KB-081" \
"默认 ⌘⇧V 呼出历史面板，原生 UI、键盘可全程操作。" \
"任意 App 下均可呼出" "热键可自定义且冲突可提示"

issue "KB-084" "搜索与固定收藏" "P1" "module:clipboard" "M8 剪贴板" "1.5d" "KB-083" \
"模糊搜索历史；固定项置顶且不被淘汰。" \
"搜索响应即时" "固定项跨重启保留"

issue "KB-085" "选中即粘贴" "P1" "module:clipboard" "M8 剪贴板" "1d" "KB-083" \
"面板中选中条目后写回剪贴板并粘贴到前台 App。" \
"选中后内容按原类型正确粘贴"

# ---- M9 多语言 --------------------------------------------------------------
issue "KB-090" "String Catalog 接入与文案抽取" "P1" "module:i18n" "M9 多语言" "1.5d" "KB-072" \
"建立 \`.xcstrings\`，把界面硬编码文案全部抽成语义 key。" \
"界面无硬编码文案" "缺失 key 可被 Xcode 检出"

issue "KB-091" "三语落地与语言切换" "P1" "module:i18n" "M9 多语言" "2d" "KB-090" \
"English / 简体中文 / 日本語；默认跟随系统语言，支持手动覆盖，缺条回退英文。" \
"三种语言界面完整无遗漏" "切换即时生效并持久化"

issue "KB-092" "长文案布局适配" "P2" "module:i18n" "M9 多语言" "1d" "KB-091" \
"为德/法语等约 +30% 长度的文案预留弹性，避免截断破版。" \
"模拟超长文案时布局不破"

# ---- M10 分发与合规 ---------------------------------------------------------
issue "KB-100" "签名、公证与 DMG 打包" "P0" "module:release" "M10 分发与合规" "2d" "KB-002" \
"Developer ID 签名 + notarize + DMG 打包脚本，Gatekeeper 正常放行。" \
"全新机器下载后可直接打开无警告" "打包流程脚本化可重复"

issue "KB-101" "自动更新（Sparkle）" "P1" "module:release" "M10 分发与合规" "1.5d" "KB-100" \
"接入 Sparkle，提供更新源与签名校验。" \
"可从旧版本自动升级到新版本"

issue "KB-102" "GitHub Release 与 Homebrew Cask" "P1" "module:release" "M10 分发与合规" "1d" "KB-100" \
"发版流程与 Cask 配方，支持 \`brew install --cask\`。" \
"Release 产物可下载安装" "Cask 安装成功"

issue "KB-103" "GPL-3.0 合规与第三方声明" "P0" "module:release" "M10 分发与合规" "0.5d" "—" \
"LICENSE + \`THIRD_PARTY_NOTICES\`，逐项列出各库许可与版权；确认未使用 NC 许可代码。" \
"所有依赖许可声明齐备" "无 Mos / Mac Mouse Fix 代码引入"

issue "KB-104" "捐助渠道接入" "P2" "module:release" "M10 分发与合规" "0.5d" "KB-078" \
"GitHub Sponsors / Open Collective 链接，在关于页与仓库展示。" \
"关于页可跳转捐助页面"

# ---- M11 质量保障 -----------------------------------------------------------
issue "KB-110" "核心逻辑单元测试" "P1" "module:qa" "M11 质量保障" "2d" "KB-031, KB-040" \
"覆盖规则合并（预设⊕覆盖）、作用域过滤、事件匹配。" \
"合并与匹配关键分支均有用例" "CI 可运行"

issue "KB-111" "手动测试清单与回归" "P1" "module:qa" "M11 质量保障" "1.5d" "全部功能票" \
"覆盖常见 App（浏览器/Finder/终端/Office）、权限撤销、Secure Input、多设备场景。" \
"清单可复用于每次发版前回归"

issue "KB-112" "诊断日志与问题上报" "P2" "module:qa" "M11 质量保障" "1.5d" "KB-010" \
"记录 EventTap 重启、权限变化等关键事件，提供导出诊断信息入口。" \
"可导出日志用于用户反馈"

# ---- v1.1 窗口贴边 ----------------------------------------------------------
issue "KB-200" "窗口操作基座" "P1" "module:window" "v1.1 窗口贴边" "2.5d" "KB-003" \
"用 \`AXUIElement\` 读写前台窗口 frame（辅助功能权限已具备）。" \
"可移动与缩放任意前台窗口"

issue "KB-201" "贴边快捷键 Win+←/→/↑" "P1" "module:window" "v1.1 窗口贴边" "2d" "KB-200" \
"左右半屏、原地最大化（区别于 Mac 的全屏独立空间）。" \
"多显示器下位置计算正确"

issue "KB-202" "拖到屏幕边缘自动分屏" "P2" "module:window" "v1.1 窗口贴边" "3d" "KB-200" \
"监测拖拽到边缘触发贴边预览与吸附。" \
"拖拽预览与释放吸附体验顺畅"

issue "KB-203" "窗口页 UI" "P1" "module:window" "v1.1 窗口贴边" "1.5d" "KB-201" \
"新增「窗口」导航项与相关开关配置。" \
"与既有设计语言一致"

# ---- v2 深度键盘 ------------------------------------------------------------
issue "KB-300" "DriverKit 虚拟 HID 引擎" "P2" "module:keyboard" "v2 深度键盘" "5d+" "v1.0 稳定" \
"引入第二引擎（系统扩展），与现有 CGEventTap 引擎共存。" \
"系统扩展可安装并稳定运行"

issue "KB-301" "tap/hold 双角色键" "P2" "module:keyboard" "v2 深度键盘" "4d" "KB-300" \
"短按/长按不同行为的超时状态机（如 Caps 短按 Esc、长按 Ctrl）。" \
"判定准确、无误触发"

issue "KB-302" "层与同时按键" "P2" "module:keyboard" "v2 深度键盘" "4d" "KB-301" \
"Layers 与 simultaneous chord 支持。" \
"层切换与组合触发稳定"

echo
echo "==> Done."
echo "    Issues:     https://github.com/${REPO}/issues"
echo "    Milestones: https://github.com/${REPO}/milestones"
echo
echo "Next: create a Project board and add all issues —"
echo "    gh project create --owner @me --title 'KeyBridge v1.0'"
