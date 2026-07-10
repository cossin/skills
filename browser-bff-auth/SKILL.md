---
name: browser-bff-auth
description: 浏览器应用(SPA)接入 OAuth/OIDC 登录时使用。BFF(BCP 最佳实践):token 只在服务端、浏览器只拿 HttpOnly cookie,消除 XSS 窃取 token 与多标签刷新竞争。含 Cloudflare Worker + Durable Object 落地方案与实现清单。
---

# Browser BFF Auth

## 触发

给浏览器里的 SPA / dashboard 接入 OAuth2 / OIDC 登录(Keycloak / Auth0 / Google 等),需要:安全存放 token、会话续期、登出、多标签/多设备一致,或要评审现有"token 存 localStorage"的前端鉴权方案时使用。

目标:按 IETF《OAuth 2.0 for Browser-Based Apps》(BCP)落地生产级鉴权——**浏览器不持有任何 token**,杜绝 XSS 窃取长期凭据和多标签刷新竞争。拒绝"access/refresh token 存 localStorage/sessionStorage + 前端自刷"这类方案。

## 核心原则(BCP)

**只要应用有后端(哪怕是个薄 Worker),就用 BFF,不要把 token 交给浏览器 JS。**

1. token(access + refresh)只存**服务端**;OAuth code 交换、刷新、登出全在服务端做。
2. 浏览器只拿一个**不透明会话 cookie**:`HttpOnly` + `Secure` + `SameSite=Lax` + `Path=/`。JS 读不到 → XSS 偷不到 token。
3. 前端调**同源** `/api/*`(cookie 自动带),BFF 服务端按会话取 token、附 `Authorization: Bearer` 代理到上游。前端零 token、零 CORS(同源)。
4. 登录态由 `/auth/me` 返回(用户名/角色,**不含 token**)。

## 架构(BFF)

```
浏览器(仅 HttpOnly sid cookie)
   │  整页跳转 /auth/login、/auth/logout;同源 fetch /auth/me、/api/*
   ▼
BFF(后端:Worker / Node / 边缘函数)
   ├─ /auth/login    起 PKCE、下发 sid cookie、302 跳 IdP
   ├─ /auth/callback  服务端用 code+verifier 换 token、建会话、302 回 /
   ├─ /auth/me        从会话返回 { authenticated, username, roles }
   ├─ /auth/logout    清会话 + 清 cookie + 跳 IdP end_session
   └─ /api/*          按 sid 取(必要时刷新)access token,附 Bearer 代理到上游
   ▼
会话存储(服务端):sid → { access, refresh, id_token, expires_at, profile }
```

## 存储选型

| 方案 | 一致性 | 单飞刷新 | 说明 |
|---|---|---|---|
| **Durable Object**(每会话一个,推荐) | 强一致 | **免费**(单实例串行) | 一个 sid 映射唯一 DO 实例,同会话所有标签进同一实例→刷新天然串行。用 SQLite 存储(migration 写 `new_sqlite_classes`)则 **CF 免费档也能用**;`get/put/delete` API 不变。 |
| **KV / Redis**(sid→加密 blob,带 TTL) | 最终一致(KV)/强(Redis) | 需显式加锁 | 简单;KV 多 PoP 并发刷+轮换开启时有小概率双刷,要锁或容忍。 |
| 无状态加密 cookie(token AEAD 塞进 cookie) | — | 难 | ❌ 轮换要每请求改 cookie、4KB 上限塞不下离线 token、刷新无法跨请求协调。避免。 |

**默认 Durable Object / 单实例 KV**:把"同会话刷新串行"这个正确性交给存储原语,别在应用层手写分布式锁。

## 刷新触发

**惰性、按需——不用后台定时器**(前端更不刷):

- 每个被代理的 `/api/*` 请求进来 → 查会话里 access token 到期时刻 → 过期或临近(<30–60s)→ **先刷再转发**上游。
- 上游 401 兜底:时钟偏差/提前失效 → 刷一次 + 重试一次。
- **单飞**:同会话并发请求共享同一个在飞刷新 promise(DO 实例内存里一个 promise;`if(!refreshing) refreshing=doRefresh()` 的 check-and-set 同步执行,JS 单线程即原子)。刷新失败(refresh 过期/被撤)→ 删会话 → 前端下次 `/auth/me` 得 `authenticated:false` → 回登录。

## 会话 · 多标签 · 多设备

- **同浏览器多标签**:共用同一 sid cookie → 同一服务端会话(同一 DO)→ 刷新共享 + 串行 → **零竞争、不互踢**。（对比:token 放前端时,多标签各自定时刷、轮换开启会 reuse detection 互踢。）
- **多设备 / 多浏览器(手机 + PC)**:各自独立登录 → 各自 sid cookie → 各自独立会话与 refresh token 链 → **天然互不影响、永不互踢**。
- 不要试图"隔离"多标签的 storage:只有 sessionStorage/内存是每标签隔离的,但那会牺牲"登一次全标签通用"。BFF 用**共享会话 + 服务端串行**解决,而非隔离。

## 安全要点

- Cookie:`HttpOnly`(挡 XSS 读取)、`Secure`(仅 HTTPS)、`SameSite=Lax`(**必须 Lax**,否则从 IdP 302 回 `/auth/callback` 时 cookie 不带、拿不到中转态)、`Path=/`。
- sid 用 CSPRNG 随机(≥128 bit),映射服务端会话;别把任何 token 放进 cookie。
- PKCE 在服务端做:verifier 存"登录中转态"(pre-auth,换到 token 后删),挡授权码注入。public client(无 secret)即可;或用 confidential client、secret 只在 BFF。
- `state` 参数存中转态并校验,挡 CSRF/串话。
- CSRF:`SameSite=Lax` + 同源 `fetch`(自定义头、非表单)基本足够;高危写操作可再加 CSRF token 或校验 `Origin`。
- 登出:清服务端会话 + 过期 cookie(`Max-Age=0`)+ 跳 IdP `end_session`(带 `id_token_hint` + `post_logout_redirect_uri`)结束 SSO。
- 会话时长由 IdP 的 **SSO Session Idle/Max** 控(app 会话 = SSO 会话,BFF 惰性刷新即滑动)。**BFF 一般不用 `offline_access`**——那是给独立于浏览器的后台/移动端的,还会留"登出后 token 仍存活"的尾巴,且常触发 IdP 的 offline 限制;要超长会话直接把 SSO Session Idle/Max 调大。

## 请求流

```mermaid
sequenceDiagram
  participant B as 浏览器(sid cookie)
  participant F as BFF
  participant S as 会话存储(DO/KV)
  participant I as IdP(Keycloak)
  participant U as 上游 API
  B->>F: GET /auth/login
  F->>S: 存 {verifier,state}
  F-->>B: 302→IdP + Set-Cookie sid(HttpOnly)
  B->>I: 授权(PKCE)
  I-->>B: 302 /auth/callback?code&state
  B->>F: GET /auth/callback (带 sid)
  F->>I: code+verifier 换 token(服务端)
  F->>S: 存 {access,refresh,exp,profile}
  F-->>B: 302 /
  B->>F: GET /api/compass/prices (带 sid)
  F->>S: 取会话;过期?→单飞刷新
  F->>U: 附 Bearer 代理
  U-->>F: 数据
  F-->>B: 数据(token 不下发)
```

## 实现清单(生产级,别留 TODO)

后端(BFF):
- [ ] `/auth/login`:CSPRNG sid → 存中转态(verifier/state)→ Set-Cookie(HttpOnly/Secure/SameSite=Lax)→ 302 IdP。
- [ ] `/auth/callback`:校验 state → 服务端换 token → 建会话 → 删中转态 → 302 `/`;失败带 `?login_error=` 回 `/`。
- [ ] `/auth/me`:返回 `{authenticated, username, roles}`,`Cache-Control: no-store`。
- [ ] `/auth/logout`:清会话 + 过期 cookie + 跳 IdP end_session。
- [ ] `/api/*`:取 token(惰性刷新+单飞)→ 附 Bearer 代理到上游;401 时清 cookie。
- [ ] 存储:DO 绑定/KV + 迁移;刷新失败删会话;`refresh_token` 不回传时沿用旧值。
- [ ] 错误分支:IdP 不可达、code 交换失败、refresh 被撤、cookie 缺失、未知 `/api` 前缀,全部显式处理。

前端:
- [ ] **零 token**:login/logout = 到 BFF 的整页跳转;登录态查 `/auth/me`;业务走同源 `/api/*`(`credentials:"include"`)。
- [ ] 删掉一切 token/refresh/PKCE/localStorage 逻辑。

平台配置:
- [ ] IdP client 登记回调 `https://<域名>/auth/callback`;BFF 有后端后无需给浏览器开 CORS/Web Origins(token 交换在服务端)。
- [ ] 上游 API 若原来为浏览器开了 CORS,BFF 化后可收(改为仅同源经 BFF)。

## 反模式(评审时打回)

- ❌ access/refresh token 存 localStorage / sessionStorage / 非 HttpOnly cookie(XSS 可窃)。
- ❌ 前端定时器自刷 + 多标签各刷(轮换开启会 reuse detection 互踢)。
- ❌ 用 sessionStorage"隔离多标签"来回避竞争(牺牲共享登录,且不解决持久性)。
- ❌ 隐藏 iframe `prompt=none` 静默刷新(被现代浏览器第三方 cookie 限制打穿)。
- ❌ 无状态加密 cookie 存 token 却又开 refresh 轮换(每请求改 cookie、大小超限)。

## 默认技术选择

- 前端默认 Cloudflare Worker 托管 + GitHub push 自动部署;BFF 即把这个 Worker 从"薄壳"升为有状态代理。
- 会话存储默认 **Durable Object**(强一致 + 免费单飞;CF 上用 SQLite-backed DO,migration 写 `new_sqlite_classes`,**免费档即可**);其它平台用单实例 KV/Redis + 锁并说明取舍。
- IdP 默认复用现有(如 Keycloak);client 用 public + PKCE(BFF 服务端做),避免额外 secret 管理。

## 落地参考

参考实现:`~/repositories/quant-console`(Cloudflare Worker BFF + Session Durable Object)——`worker/index.js`(路由/代理)、`worker/session.js`(DO:token 保管 + 惰性单飞刷新)、前端 `src/lib/{auth,api}.ts` + `src/hooks/useAuth.ts`(零 token)。
