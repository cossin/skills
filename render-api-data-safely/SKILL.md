---
name: render-api-data-safely
description: 前端实现、修改或审查异步接口数据展示时使用，包括 React/Vue/Svelte 组件、页面、header、用户信息、列表、详情、统计和鉴权 hook。要求等待当前请求成功后才渲染真实业务数据，显式区分 loading/error/empty/success，禁止用硬编码默认值、假数据、mock 或初始空值掩盖尚未返回的数据。
---

# Render API Data Safely

## 核心原则

把“尚未返回”视为独立状态，不要当成“字段缺失”或“空数据”。只有请求成功后，才展示响应中的业务数据。

- 禁止在等待接口时展示硬编码业务值，例如 `user?.name ?? "Admin"`、`count || 0`、默认头像、示例列表或 mock 统计。
- 禁止用 `[]`、`{}`、`0` 等初始值让未完成的请求看起来已经成功；初始 loading 和成功后的 empty 必须可区分。
- loading 可显示 spinner、进度、不会冒充真实值的 skeleton，或暂时隐藏该区域。不要把成功态布局配上假内容提前渲染。
- error 必须有明确分支；不要吞掉错误后继续渲染默认值。
- empty 只能在请求成功且响应按接口契约确实为空后展示。
- `0`、`false` 等可能是合法响应值；不要用 truthy 判断把它们替换掉。

## 实现流程

1. 找到真实数据来源和请求生命周期。优先复用 query、store 或 hook 已提供的 `status`、`loading`、`error`、`data`；不要只看 `data` 是否为空。
2. 如果数据层只暴露 `data | null`，扩展它以暴露明确状态。不要猜测 `null` 到底表示未请求、请求中、未登录、成功但为空，还是失败。
3. 建模 `idle/loading/error/success`；在 `success` 内再根据接口契约判断有数据或 empty。
4. 按状态先后渲染，确保 success 之前不会执行依赖真实数据的展示逻辑。
5. 对路由参数、筛选条件或资源 ID 的变化使用正确的 request/cache key。不要把上一请求的数据冒充当前资源；防止较慢的旧响应覆盖新响应。
6. 运行或补充状态测试，确认首次渲染和请求等待期间不会闪现默认业务值。

## 推荐状态模型

优先使用判别联合或等价的框架状态，避免多个布尔值产生矛盾组合：

```ts
type RemoteData<T> =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "error"; error: Error }
  | { status: "success"; data: T };
```

渲染顺序保持明确：

```tsx
if (result.status === "idle" || result.status === "loading") {
  return <LoadingState />;
}

if (result.status === "error") {
  return <ErrorState error={result.error} />;
}

if (isEmptyResponse(result.data)) {
  return <EmptyState />;
}

return <Content data={result.data} />;
```

`isEmptyResponse` 必须依据接口契约定义。不要用一个通用 truthy 判断代替契约。

## 常见问题与修正

错误：在鉴权请求返回前显示一个虚构身份。

```tsx
const { user } = useAuth();
return <span>{user?.name ?? "Admin"}</span>;
```

修正：使用 hook 已暴露的状态；未登录和加载中是不同状态。

```tsx
const { user, status, error } = useAuth();

if (status === "loading") return <HeaderLoading />;
if (status === "error") return <HeaderError error={error} />;
if (status === "unauthenticated") return <SignedOutHeader />;

return <span>{user.name}</span>;
```

错误：把请求中的列表初始化为空数组，导致先闪现“暂无数据”。

```tsx
const [items, setItems] = useState<Item[]>([]);
return items.length === 0 ? <EmptyState /> : <List items={items} />;
```

修正：独立记录请求状态，只有成功后才判断空数组。

对于请求成功后仍缺失的可选字段，按产品语义隐藏该字段或明确显示“未提供/未设置”。不要编造一个看似真实的替代值。表单输入的产品默认值、测试 fixture 和用户明确要求的演示数据不属于本规则，但必须与接口返回数据分开建模和命名。

## 缓存与重新请求

- 首次加载必须等待真实数据。
- 同一资源已有成功缓存时，可按项目既有策略在后台刷新；缓存必须确实来自该资源的真实响应。
- 请求参数或资源身份变化时，默认先进入 loading，不要把旧资源数据贴到新资源标题下。
- 如果产品明确采用 stale-while-revalidate，保留旧数据必须是有意设计，并提供刷新中状态；不要通过默认值隐式实现。

## 验证清单

- 延迟 promise：resolve 前不存在姓名、数量、列表项等业务数据，也不存在硬编码替代值。
- 成功有数据：只展示响应中的值。
- 成功为空：只在成功后展示 empty state。
- 失败：展示 error state，不展示默认业务值。
- 合法 falsy：`0`、`false` 按真实含义展示。
- 鉴权：loading、authenticated、unauthenticated、error 互不混淆。
- 快速切换参数：旧响应不会覆盖或冒充新请求的数据。

修改代码时，顺手扫描同一数据流的调用方，清理会造成默认值闪现的同类写法；不要把范围扩大到无关的静态文案或表单默认值。
