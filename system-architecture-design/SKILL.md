---
name: system-architecture-design
description: 系统/架构/技术方案/RFC/ADR/迁移/集成/架构评审/生产级代码实现时使用。外部信息必须有依据、可交叉验证、最新。
---

# System Architecture Design

## 触发

用户要求系统设计、架构设计、技术方案、RFC/ADR、迁移方案、接口/数据流设计、组件选型、架构评审、可靠性/安全/扩展性方案时使用。

目标: 输出能评审、估算、实现、测试、上线和运维的生产级设计和实现。拒绝 MVP 口径、临时绕过、占位实现、mock 冒充真实集成、核心链路留 TODO。

## 工作流

1. 先识别真实意图: 业务结果、工程结果、风险规避目标。
2. 复述目标、范围、非目标、成功标准和关键约束。
3. 只问阻塞问题;可安全假设时先声明假设再继续。
4. 建模边界: 角色、请求流、数据流、状态、外部依赖、失败边界、信任边界。
5. 非平凡决策给 2-3 个方案、tradeoff 和推荐。
6. 细化推荐方案: 组件职责、接口/事件、数据模型、一致性、部署、可观测性、安全、上线和回滚。
7. 如包含代码实现,必须按生产标准落地: 完整逻辑、错误处理、配置、权限、日志、测试和可运维性。
8. 引用外部信息时必须给依据: 优先官方文档/规范/SDK;关键事实要可交叉验证;涉及版本、价格、限制、API、法规、产品能力等易变信息必须确认最新。
9. 明确风险、开放问题、验证方式和下一步。

## 生产实现要求

- 不允许偷懒实现: 禁止空实现、占位 mock、硬编码假数据、TODO 代替核心逻辑、只写 happy path。
- 代码必须覆盖真实集成、错误分支、超时/重试、幂等、权限、输入校验、配置、日志和可观测性。
- 新增公共逻辑必须有测试;测试覆盖正常、边界、异常和旧数据/兼容场景。
- 外部 API、SDK、协议、云产品能力、限制和版本必须以官方资料为准;不能凭记忆或样例猜契约。
- 外部事实必须标注来源或说明验证路径;重要事实至少用两个可靠来源交叉验证,无法验证时标为待确认。

## 默认技术选择

- 依赖、框架、运行时、数据库默认选择最新稳定版;旧版本必须说明约束。
- 关系型数据库默认优先 PostgreSQL 最新稳定版;偏离必须说明原因。
- Web 前端默认部署在 Cloudflare Worker 上,在 Worker 控制台关联前端 GitHub repo,由 push 自动触发部署。
- 前端部署方案必须写清 production/preview 分支、构建命令、输出目录、环境变量/secret、域名、缓存策略和回滚方式。
- 架构默认考虑高可用、滚动升级、灰度、兼容发布、回滚和数据迁移安全。

## 输出模式

- **Quick design**: 目标、假设、推荐架构、关键 tradeoff、下一步。
- **Full proposal/RFC**: 使用下方模板。
- **ADR**: 记录一个明确技术决策。
- **Review**: 先列风险和缺口,再给修改建议。
- **Migration plan**: 当前状态、目标状态、兼容层、回填/切流、回滚和验证。

## Full Proposal 模板

```markdown
# <标题>

## Problem
<问题、影响范围、为什么现在做、真实意图。>

## Goals
- <可衡量或可评审目标>

## Non-Goals
- <明确不做什么>

## Requirements and Constraints
- Functional:
- Non-functional:
- Operational:
- Security/compliance:
- Existing constraints:

## Current State
<现状、痛点、接口、依赖和限制。>

## Proposed Architecture
<组件职责、数据/控制流、高可用边界、滚动升级方式。>

## Technology Choices
<框架、运行时、数据库、队列、中间件。说明默认选择和偏离原因。Web 前端默认 Cloudflare Worker + GitHub repo push 自动部署。外部事实写明来源、版本和验证时间。>

## Interfaces and Data Model
<API、事件、schema、存储、数据归属、生命周期、兼容性。>

## Key Decisions and Tradeoffs
| Decision | Recommendation | Alternatives | Rationale | Consequences |
|---|---|---|---|---|

## Reliability, Security, and Operations
<失败模式、重试/幂等、限流、SLO、日志/指标/链路、权限、密钥、审计、故障处理。>

## Rollout Plan
<阶段、迁移/回填、feature flag、滚动升级、测试、监控、回滚。Web 前端写清 Cloudflare Worker、GitHub repo、push 部署、分支、变量和回滚。>

## Risks and Open Questions
- <风险/问题、影响、验证路径>

## Implementation Plan
1. <步骤。包含生产级实现要求、测试、监控、配置、回滚和验收。>
```

## ADR 模板

```markdown
# ADR: <决策>

## Status
Proposed

## Context
<背景、约束、问题和驱动力。>

## Decision
<选择的方案。>

## Alternatives Considered
- <备选方案以及未选择原因>

## Consequences
- Positive:
- Negative:
- Follow-up:
```

## 评审清单

按任务相关性检查,不要机械展开无关项:

- 需求: 真实意图、成功标准、non-goals、scale/latency/durability/availability/compliance/cost 是否明确。
- 架构: 组件职责、所有权边界、信任边界、外部依赖、local/test/staging/prod 路径是否清楚。
- 选型: 是否使用最新稳定版;关系型 DB 是否优先 PostgreSQL;Web 前端是否默认 Cloudflare Worker + GitHub repo push 自动部署。
- 外部依据: 外部信息是否来自官方/可靠来源;关键事实是否可交叉验证;易变信息是否确认最新。
- 数据: source of truth、derived view、一致性语义、schema 变更、backfill、retention、recovery 是否明确。
- API/集成: 版本兼容、authn/authz、rate limit、pagination、timeout、error semantics、第三方失败降级是否覆盖。
- 可靠性: 高可用、健康检查、容量冗余、幂等重试、SLO、日志/指标/trace、人工修复路径是否可信。
- 安全: secret、credential、token、PII、最小权限、多租户边界、审计、删除/保留策略是否覆盖。
- 上线: 增量交付、feature flag、canary、滚动升级、新旧版本兼容、回滚和数据修复是否可执行。
- 代码实现: 是否生产级完整实现;是否存在空实现、占位 mock、硬编码假数据、TODO 核心链路、缺少错误处理或测试。

## 图示

需要图时使用 Mermaid:

- `flowchart`: 组件、数据流、控制流。
- `sequenceDiagram`: 请求链路、异步流程、重试、失败处理。
- `stateDiagram-v2`: 生命周期和状态机。
- `erDiagram`: 数据模型关系。

图要面向实现,标出 client、service、queue、store、external vendor、trust zone、ownership domain。

## Review 输出格式

```markdown
**Blocking**
- `<位置/章节>` — 问题: <失败模式或缺口> -> 建议: <具体改法>

**Suggestions**
- `<位置/章节>` — <改进点> -> <建议>

**Passed**
- <没有发现重大问题或已覆盖的部分。>
```
