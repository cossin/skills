# skills

通用 agent skills — 一份内容,三个 CLI(Claude Code / Codex / Gemini)共享。

## Install

```bash
git clone git@github.com-cossin:cossin/skills.git ~/repositories/skills
cd ~/repositories/skills
./install.sh
```

脚本幂等,重复运行会同步新增/移除的 skill,不会破坏无关链接。

## 工作原理

- **Claude Code / Codex** 都识别 `SKILL.md`(frontmatter + body 格式一致)。`install.sh` 把每个 skill 符号链接到:
  - `~/.claude/skills/<name>`
  - `~/.codex/skills/<name>`
  - `~/skills/<name>`(CLI 无关路径,方便其他工具引用)
- **Gemini** 无原生 skill 系统。`install.sh` 在 `~/.gemini/GEMINI.md` 里维护一个受管理 block(用 `<!-- managed-skills:begin -->` / `<!-- managed-skills:end -->` 标记),列出所有 skill 并指向 `~/skills/<name>/SKILL.md`。block 之外的内容不会被动。

## 目录结构

每个顶层目录就是一个 skill,目录内必须有带 frontmatter 的 `SKILL.md`:

```
<skill-name>/
  SKILL.md         # 必需,含 name + description frontmatter
  [其他资源]       # 可选:脚本、模板、参考文档等
```

## 现有 skill

- **code-review** — 代码 review 清单:空实现与占位 mock、外部 API 对接一致性、分页完整性、单测覆盖、硬编码。

## 新增一个 skill

1. 在 repo 根创建目录 `<name>/`,放入 `SKILL.md`
2. frontmatter 必须有 `name` 和 `description`(description 会被写入 GEMINI.md)
3. `./install.sh` 生效

## 卸载

删除 repo 目录并重新运行 `install.sh` 会把相关链接作为 stale 清理掉。手动也可:

```bash
rm ~/.claude/skills/<name> ~/.codex/skills/<name> ~/skills/<name>
# 手动删除 ~/.gemini/GEMINI.md 里 managed-skills block 中的对应条目
```
