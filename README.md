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

**外部 skill 源**:[external-skills.txt](external-skills.txt) 里列出的外部 git 仓库会在安装时自动 clone/更新到 `.external/`(已 gitignore),其中的 skill 与本地 skill 一起链接到上述路径。每行格式 `<别名> <git地址> [子目录] [只装哪些顶层分类...]`,子目录可写 `.` 占位(skill 在仓库根但需要分类过滤时)。重名优先级:**本地 skill > 清单中靠前的源**,被跳过的会告警。当前未配置外部来源;需要时可显式添加,删除来源后重新安装会清理其安装链接。URL 改了会自动重建 checkout,上游 force-push/改分支名也能跟上,离线时沿用已有 checkout 并告警。

> 信任提示:外部 skill 的正文会被 agent 当作指令执行,且每次运行 install.sh 都会拉取上游最新内容——相当于持续信任该仓库的维护者。想锁定内容,fork 一份换成自己的地址。

**旧版 Gemini**(无原生 skill 支持)走兼容方案:`install.sh` 在 `~/.gemini/GEMINI.md` 里维护一个受管理 block(用 `<!-- managed-skills:begin -->` / `<!-- managed-skills:end -->` 标记),列出所有 skill 并指向 `~/skills/<name>/SKILL.md`。block 之外的内容不会被改动;标记不成对(只剩其一)、重复、顺序错误或被空白/CRLF 污染时脚本直接报错退出,不改写文件。

## 目录结构

每个顶层目录就是一个 skill,目录内必须有带 frontmatter 的 `SKILL.md`:

```
<skill-name>/
  SKILL.md         # 必需,含 name + description frontmatter
  [其他资源]       # 可选:脚本、模板、参考文档等
```

## 现有 skill

- **design-and-implementation** — 设计与实现原则:以业务目标和风险为依据,复用现有系统,明确业务不变量、一致性边界、失败恢复和实际验证,控制复杂度与总成本。
- **browser-bff-auth** — 浏览器 SPA 的 OAuth/OIDC 鉴权 BFF(BCP)方案:token 只在服务端、浏览器只拿 HttpOnly cookie,消除 XSS 窃 token 与多标签刷新竞争;Cloudflare Worker + Durable Object 落地与实现清单。
- **render-api-data-safely** — 前端异步数据展示规范:等待真实接口响应，显式区分 loading/error/empty/success，禁止默认业务值、假数据和初始空值抢先渲染。

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

本地 skill:从 repo 里删除对应的 `<name>/` 目录,重新运行 `./install.sh`,相关链接会作为 stale 被清理,GEMINI.md 的 block 同步更新(删光全部 skill 再运行同样生效)。外部 skill:编辑 `external-skills.txt` 删掉分类或整行后重跑即可;残留的 `.external/<别名>/` checkout 可手动删除。手动也可:

```bash
rm ~/.claude/skills/<name> ~/.agents/skills/<name> ~/.codex/skills/<name> ~/skills/<name>
# 手动删除 ~/.gemini/GEMINI.md 里 managed-skills block 中的对应条目
```
