# skills

通用 agent skills — 一份内容,三个 CLI(Claude Code / Codex / Gemini)共享。

## Install

```bash
git clone git@github.com:cossin/skills.git ~/repositories/skills
cd ~/repositories/skills
./install.sh
```

脚本幂等,重复运行会同步新增/移除的 skill,不会破坏无关链接。

## 工作原理

三个 CLI 都识别同一份 `SKILL.md`(frontmatter + body 格式一致)。`install.sh` 把每个 skill 符号链接到:

- `~/.claude/skills/<name>` — Claude Code(CLI 与 Desktop 共用)
- `~/.agents/skills/<name>` — 跨 agent 通用路径,当前版本的 Codex 与 Gemini CLI 都原生读取
- `~/.codex/skills/<name>` — 旧版 Codex 的兼容路径
- `~/skills/<name>` — CLI 无关路径,方便其他工具引用

**旧版 Gemini**(无原生 skill 支持)走兼容方案:`install.sh` 在 `~/.gemini/GEMINI.md` 里维护一个受管理 block(用 `<!-- managed-skills:begin -->` / `<!-- managed-skills:end -->` 标记),列出所有 skill 并指向 `~/skills/<name>/SKILL.md`。block 之外的内容不会被改动;标记不成对(只剩其一)、重复、顺序错误或被空白/CRLF 污染时脚本直接报错退出,不改写文件。

## 目录结构

每个顶层目录就是一个 skill,目录内必须有带 frontmatter 的 `SKILL.md`:

```
<skill-name>/
  SKILL.md         # 必需,含 name + description frontmatter
  [其他资源]       # 可选:脚本、模板、参考文档等
```

## 现有 skill

- **admin-management-design** — 后台管理系统设计/实现规范:默认 Lark 海外版登录、侧栏 + 面包屑布局,创建和修改数据默认使用 modal。
- **code-review** — 代码 review 清单:空实现与占位 mock、外部 API 对接一致性、分页完整性、单测覆盖、硬编码、官方文档依据、可选参数兼容。
- **deployment-planning** — 部署/上线/发布计划:无损升级、滚动发布、灰度发布、数据库迁移、旧数据兼容、存量数据处理和回滚方案。
- **root-cause-analysis** — 问题分析/根因分析:基于事实、日志、代码和时间线定位根因。
- **system-architecture-design** — 系统/架构/方案设计:技术方案、RFC/ADR、迁移方案、架构评审;默认 PostgreSQL,Web 前端默认 Cloudflare Worker + GitHub push 自动部署。

## 新增一个 skill

1. 在 repo 根创建目录 `<name>/`,放入 `SKILL.md`
2. frontmatter 必须有 `name` 和 `description`(description 会被写入 GEMINI.md,且必须写在单行上)
3. `./install.sh` 生效

## 测试

```bash
tests/install_test.sh
```

沙箱运行,不触碰真实 `$HOME`。

## 卸载

从 repo 里删除对应的 `<name>/` 目录,重新运行 `./install.sh`:相关链接会作为 stale 被清理,GEMINI.md 的 block 同步更新(删光全部 skill 再运行同样生效)。手动也可:

```bash
rm ~/.claude/skills/<name> ~/.agents/skills/<name> ~/.codex/skills/<name> ~/skills/<name>
# 手动删除 ~/.gemini/GEMINI.md 里 managed-skills block 中的对应条目
```
