# SSO 迁移计划 — Postiz iframe 嵌入方案

> 目标：将 Postiz 以 iframe 方式嵌入到父应用中，实现 SSO 单点登录。
> 约束：**不修改父页面**，仅修改 Postiz 项目本身。

---

## 一、允许 Postiz 被跨域 iframe 嵌入

### 1.1 NestJS 安全头现状（无需修改）

> **重要：** 本项目 `apps/backend/src/main.ts` **未使用 helmet**，NestJS 层不会主动设置 `X-Frame-Options` 或 CSP `frame-ancestors`。因此 NestJS 侧无需修改任何安全头配置。

iframe 嵌入受阻的来源通常是**反向代理（Nginx）**，见 1.5。

---

### 1.2 更新 `main.ts` CORS `exposedHeaders`（必须修改）

**文件：`apps/backend/src/main.ts`**

当前 `exposedHeaders` 中，`auth`、`showorg`、`impersonate`、`logout` 只在 `NOT_SECURED` 时才暴露给前端：

```ts
// 当前
exposedHeaders: [
  'reload', 'onboarding', 'activate',
  ...(process.env.NOT_SECURED ? ['auth', 'showorg', 'impersonate'] : []),
],
```

SSO 方案要求前端在**生产（secured）模式**下也能读取 `auth` 和 `logout` header，否则 SSO 登录成功后前端拿不到 JWT。

**修改方案：**

```ts
// 修改后：始终暴露必要 header
exposedHeaders: [
  'reload',
  'onboarding',
  'activate',
  'auth',
  'showorg',
  'impersonate',
  'logout',
  'x-copilotkit-runtime-client-gql-version',
],
```

> **注意：** 同时确认 `allowedHeaders` 中包含 `auth`、`showorg`、`impersonate`（当前已包含，无需修改）。

---

### 1.3 Cookie `SameSite` 属性

跨域 iframe 中，浏览器默认不发送第三方 Cookie。如果 Postiz 依赖 Cookie（如认证 Session），必须调整：

```ts
// NestJS 中 session/cookie 配置
app.use(session({
  cookie: {
    sameSite: 'none',    // 允许跨站发送
    secure: true,        // SameSite=None 必须配合 Secure
    // ...
  },
}));

// 如果使用 passport
app.use(cookieParser());
```

> **关键约束：** `SameSite=None` 必须同时设置 `Secure=true`，即必须运行在 HTTPS 上。

---

### 1.4 前端（Angular）移除 iframe 跳出逻辑

如果前端有检测并强制跳出 iframe 的代码，需要移除：

```ts
// 搜索并移除类似代码
if (window.top !== window.self) {
  window.top.location = window.self.location;  // 强制跳出 iframe — 移除
}
```

---

### 1.5 反向代理层（Nginx）

如果使用 Nginx 等反向代理，也要检查并修改：

```nginx
# 移除或修改这些行
add_header X-Frame-Options "SAMEORIGIN";
add_header Content-Security-Policy "frame-ancestors 'self';";

# 修改为：
add_header Content-Security-Policy "frame-ancestors 'self' https://parent-domain.com;";
# 不再添加 X-Frame-Options
```

---

### 1.6 OAuth / 第三方登录的 iframe 兼容

大多数 OAuth 提供商（Google、GitHub 等）**禁止在 iframe 中加载其授权页面**（设置 `X-Frame-Options: DENY`）。

**解决方案：**

- OAuth 登录按钮改为 `target="_blank"` 在新窗口打开
- 使用 `postMessage` 在父页面完成 OAuth 后回传 token
- 或改用后端 OAuth flow（授权码模式），在 iframe 内通过 API 完成 token 交换

---

## 二、Cookie 改 SessionStorage 存储方案

> **核心问题：** 跨域 iframe 中，浏览器默认阻止第三方 Cookie（SameSite=Lax 是默认行为）。即使设置了 `SameSite=None; Secure`，Safari 等浏览器仍可能通过 ITP 等机制拦截第三方 Cookie。
>
> **解决方案：** 将前端认证 token 从 Cookie 存储改为 `sessionStorage`，彻底绕过 Cookie 的跨域限制。

### 2.1 当前认证流程分析

Postiz 当前使用 **JWT Cookie** 认证，分两种模式：

**Secured 模式（生产环境）：**
```
前端发送登录请求 → 后端 res.cookie('auth', jwt, { httpOnly, secure, sameSite: 'none' }) → 浏览器自动携带 cookie
```

**Non-secured 模式（开发环境）：**
```
前端发送登录请求 → 后端 res.header('auth', jwt) → layout.context.tsx 的 afterRequest 回调捕获 header → setCookie('auth', jwt, 365) → 写入 document.cookie → custom.fetch.func.ts 读取 cookie 作为 header 发送
```

**关键文件：**

| 文件 | 当前行为 |
|------|----------|
| `apps/backend/src/api/routes/auth.controller.ts` | 登录/注册后 `res.cookie('auth', jwt, ...)` |
| `apps/frontend/src/components/layout/layout.context.tsx` | afterRequest 回调中 `setCookie('auth', headerAuth, 365)` |
| `libraries/helpers/src/utils/custom.fetch.func.ts` | 读取 `document.cookie` 中的 auth，作为 header 发送 |
| `apps/backend/src/services/auth/auth.middleware.ts` | 从 `req.cookies.auth` 或 `req.headers.auth` 验证 JWT |

### 2.2 修改方案

#### 2.2.1 前端：Cookie → SessionStorage

**文件：`apps/frontend/src/components/layout/layout.context.tsx`**

当前代码有**三处**需要修改（注意：logout 处理分布在两个独立 if 块中，均需更新）：

```tsx
// ① 写入：setCookie → sessionStorage.setItem（约 L45-53）
if (headerAuth) {
  // 原：setCookie('auth', headerAuth, 365);
  if (typeof window !== 'undefined') {
    window.sessionStorage.setItem('auth', headerAuth);
  }
}
if (showOrg) {
  // 原：setCookie('showorg', showOrg, 365);
  if (typeof window !== 'undefined') {
    window.sessionStorage.setItem('showorg', showOrg);
  }
}
if (impersonate) {
  // 原：setCookie('impersonate', impersonate, 365);
  if (typeof window !== 'undefined') {
    window.sessionStorage.setItem('impersonate', impersonate);
  }
}

// ② 第一处清除：logout header 触发（约 L54-60）
if (logout && !isSecured) {
  // 原：setCookie('auth', '', -10); setCookie('showorg', '', -10); setCookie('impersonate', '', -10);
  if (typeof window !== 'undefined') {
    window.sessionStorage.removeItem('auth');
    window.sessionStorage.removeItem('showorg');
    window.sessionStorage.removeItem('impersonate');
  }
  window.location.href = '/';
  return true;
}

// ③ 第二处清除：401 状态码触发（约 L83-90）
if (response.status === 401 || response?.headers?.get('logout')) {
  if (!isSecured) {
    // 原：setCookie('auth', '', -10); setCookie('showorg', '', -10); setCookie('impersonate', '', -10);
    if (typeof window !== 'undefined') {
      window.sessionStorage.removeItem('auth');
      window.sessionStorage.removeItem('showorg');
      window.sessionStorage.removeItem('impersonate');
    }
  }
  window.location.href = '/';
}
```

---

**文件：`libraries/helpers/src/utils/custom.fetch.func.ts`**

当前代码从 cookie 读取 `auth`、`showorg`、`impersonate` **三个值**（L23-44），均需迁移到 sessionStorage：

```ts
// 当前（需修改）：三处 document.cookie 读取
const authNonSecuredCookie = document.cookie.split(';').find(...);     // L23-28
const authNonSecuredOrg = document.cookie.split(';').find(...);        // L31-36
const authNonSecuredImpersonate = document.cookie.split(';').find(...); // L40-44

// 修改后：统一从 sessionStorage 读取
const authNonSecuredCookie =
  typeof window === 'undefined' ? null : window.sessionStorage.getItem('auth');

const authNonSecuredOrg =
  typeof window === 'undefined' ? null : window.sessionStorage.getItem('showorg');

const authNonSecuredImpersonate =
  typeof window === 'undefined' ? null : window.sessionStorage.getItem('impersonate');
```

其余 header 构建逻辑（L50-68）使用这三个变量，**无需修改**。

---

**文件：`apps/frontend/src/components/layout/logout.component.tsx`**

当前非 secured 模式只清除 `auth` cookie（L24-25），修改为清除全部 sessionStorage 键：

```tsx
if (!isSecured) {
  // 原：setCookie('auth', '', -10);
  if (typeof window !== 'undefined') {
    window.sessionStorage.removeItem('auth');
    window.sessionStorage.removeItem('showorg');
    window.sessionStorage.removeItem('impersonate');
  }
}
```

#### 2.2.2 后端：移除 Cookie 设置，改用 Header

**文件：`apps/backend/src/api/routes/auth.controller.ts`**

当前代码（以 login 为例）：
```ts
// 当前：设置 cookie
response.cookie('auth', jwt, {
  domain: getCookieUrlFromDomain(process.env.FRONTEND_URL!),
  ...(!process.env.NOT_SECURED
    ? { secure: true, httpOnly: true, sameSite: 'none' }
    : {}),
  expires: new Date(Date.now() + 1000 * 60 * 60 * 24 * 365),
});

if (process.env.NOT_SECURED) {
  response.header('auth', jwt);
}
```

修改后：
```ts
// 修改后：始终通过 header 传递 token
response.header('auth', jwt);
response.header('showorg', user.organizations?.[0]?.id?.toString() ?? '');

// 移除 response.cookie() 调用
```

**文件：`apps/backend/src/api/routes/users.controller.ts`**

`/user/logout` 端点（L239-282）：
```ts
// 当前：已设置 response.header('logout', 'true')，同时也 clearCookie
// 只需移除三个 response.cookie(...) 清除调用，保留 response.header('logout', 'true')
response.header('logout', 'true');
// 删除：response.cookie('auth', ...) response.cookie('showorg', ...) response.cookie('impersonate', ...)
response.status(200).send();
```

`/user/impersonate` 端点（L113-138）：
```ts
// 当前：secured 模式只设 cookie；NOT_SECURED 模式同时设 cookie + header
// 修改为：始终设置 header，移除 response.cookie()
response.header('impersonate', id);
// 删除：response.cookie('impersonate', id, { ... })
```

`/user/change-org` 端点（L215-237）：
```ts
// 当前：secured 模式只设 cookie；NOT_SECURED 模式同时设 cookie + header
// 修改为：始终设置 header，移除 response.cookie()
response.header('showorg', id);
// 删除：response.cookie('showorg', id, { ... })
response.status(200).send();
```

#### 2.2.3 后端 Middleware 兼容

**文件：`apps/backend/src/services/auth/auth.middleware.ts`**

当前中间件已经从两个来源读取 token：
- `req.cookies.auth`（Cookie 模式）
- `req.headers.auth`（Header 模式）

**无需修改**，因为前端会将 token 放在 `auth` header 中发送，中间件已经支持。

### 2.3 SSO Token 传递方案

当 Postiz 作为 iframe 嵌入时，父应用需要将认证 token 传递给 Postiz。有两种方案：

#### 方案 A：URL 参数传递（推荐）

父应用将 SSO token 作为 URL 参数传递给 iframe：

```html
<iframe src="https://postiz.example.com/auth/sso?token=SSO_TOKEN_FROM_PARENT"></iframe>
```

前端 `/auth/sso` 页面接收 token，调用后端验证并转换为内部 JWT：

```tsx
// apps/frontend/src/app/(app)/auth/sso/page.tsx
'use client';

import { useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useFetch } from '@gitroom/helpers/utils/custom.fetch';

export default function SsoLoginPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const fetch = useFetch(); // ✅ Hook 必须在组件顶层调用
  const [error, setError] = useState<string>('');

  useEffect(() => {
    const token = searchParams.get('token');
    if (!token) {
      setError('Missing SSO token');
      return;
    }
    handleSsoLogin(token);
  }, []);

  const handleSsoLogin = async (ssoToken: string) => {
    try {
      // fetch 来自组件顶层的 useFetch()，不在此处调用 hook
      const res = await fetch('/auth/sso', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: ssoToken }),
      });

      if (!res.ok) {
        const msg = await res.text();
        setError(msg || 'SSO login failed');
        return;
      }

      // 后端返回内部 JWT，通过 header 传递
      // layout.context.tsx 的 afterRequest 会自动将其存入 sessionStorage
      // 后端同时返回 reload header 触发页面刷新
      window.location.href = '/';
    } catch (e: any) {
      setError(e.message || 'SSO login error');
    }
  };

  if (error) {
    return (
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="text-center">
          <p className="text-red-500 mb-4">{error}</p>
          <button onClick={() => router.push('/auth/login')} className="underline">
            Go to login page
          </button>
        </div>
      </div>
    );
  }

  return <div className="flex items-center justify-center min-h-[50vh]">
    <p>Authenticating via SSO...</p>
  </div>;
}
```

#### 方案 B：postMessage 传递

父应用通过 postMessage 发送 SSO token：

```html
<!-- 父页面 -->
<iframe id="postiz" src="https://postiz.example.com/auth/sso"></iframe>
<script>
  const iframe = document.getElementById('postiz');
  iframe.onload = () => {
    iframe.contentWindow.postMessage(
      { type: 'SSO_TOKEN', token: 'SSO_TOKEN_FROM_PARENT' },
      'https://postiz.example.com'
    );
  };

  // 监听来自 Postiz 的消息
  window.addEventListener('message', (event) => {
    if (event.origin !== 'https://postiz.example.com') return;

    if (event.data?.type === 'SSO_NEEDS_ACCOUNT_CREATION') {
      // 用户不存在，需要创建账号
      const { email, name, providerId } = event.data;

      // 调用父应用自己的用户创建接口
      createUserInParentApp(email, name, providerId).then((created) => {
        if (created) {
          // 父应用创建用户后，重新发送 token 给 iframe
          iframe.contentWindow.postMessage(
            { type: 'SSO_TOKEN', token: 'SSO_TOKEN_FROM_PARENT' },
            'https://postiz.example.com'
          );
        }
      });
    }
  });
</script>
```

Postiz 前端监听并存储：

```tsx
// apps/frontend/src/app/(app)/auth/sso/page.tsx
'use client';

import { useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useFetch } from '@gitroom/helpers/utils/custom.fetch';

export default function SsoLoginPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const fetch = useFetch(); // ✅ Hook 必须在组件顶层调用
  const [error, setError] = useState<string>('');
  const [needsCreation, setNeedsCreation] = useState(false);

  useEffect(() => {
    // 1. 优先从 URL 参数获取 token
    const urlToken = searchParams.get('token');
    if (urlToken) {
      handleSsoLogin(urlToken);
      return;
    }

    // 2. 监听 postMessage 获取 token
    const handler = (event: MessageEvent) => {
      const allowedOrigins = (process.env.NEXT_PUBLIC_SSO_PARENT_ORIGINS || '')
        .split(',').filter(Boolean);
      if (!allowedOrigins.includes(event.origin)) return;

      if (event.data?.type === 'SSO_TOKEN' && event.data?.token) {
        handleSsoLogin(event.data.token);
      }
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, []);

  const handleSsoLogin = async (ssoToken: string) => {
    try {
      // fetch 来自组件顶层的 useFetch()，不在此处调用 hook
      const res = await fetch('/auth/sso', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: ssoToken }),
      });

      if (res.ok) {
        // 登录成功，刷新页面
        window.location.href = '/';
        return;
      }

      const data = await res.json();

      // 用户不存在，需要创建账号
      if (res.status === 403 && data.needsAccountCreation) {
        setNeedsCreation(true);
        notifyParentNeedsAccountCreation(data);
        return;
      }

      const msg = await res.text();
      setError(msg || 'SSO login failed');
    } catch (e: any) {
      setError(e.message || 'SSO login error');
    }
  };

  // 通知父页面需要创建账号
  const notifyParentNeedsAccountCreation = (data: {
    email: string;
    name?: string;
    providerId?: string;
  }) => {
    if (typeof window === 'undefined' || !window.parent || window.parent === window) {
      // 非 iframe 环境，显示错误
      setError('User account does not exist. Please contact administrator.');
      return;
    }

    // 通过 postMessage 通知父页面
    window.parent.postMessage(
      {
        type: 'SSO_NEEDS_ACCOUNT_CREATION',
        email: data.email,
        name: data.name,
        providerId: data.providerId,
      },
      '*' // 生产环境应限制为目标域
    );
  };

  if (needsCreation) {
    return (
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="text-center">
          <p className="text-yellow-500 mb-4">
            Your account does not exist in Postiz. Please complete registration in the parent application.
          </p>
          <p className="text-gray-400 text-sm">
            If you are the administrator, please ensure the user has been created in the parent application first.
          </p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="text-center">
          <p className="text-red-500 mb-4">{error}</p>
          <button onClick={() => router.push('/auth/login')} className="underline">
            Go to login page
          </button>
        </div>
      </div>
    );
  }

  return <div className="flex items-center justify-center min-h-[50vh]">
    <p>Authenticating via SSO...</p>
  </div>;
}
```

---

## 三、对外接口契约

> 本章定义 Postiz 向父应用暴露的两个接口，父应用按此契约对接，无需关心内部实现细节。

---

### 接口一：前端 SSO 登录入口（iframe src）

**形式：** 前端页面 URL，父应用直接设置为 iframe 的 `src`

```
GET https://<postiz-domain>/auth/sso?token=<SSO_TOKEN>
```

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `token` | string | 是 | 父应用签发的 SSO token，包含 `merchantId` 和 `merchantName` |

**行为：**
1. 页面加载后自动取出 `token`，调用后端 `POST /auth/sso`
2. 成功 → 存储 JWT，跳转到 Postiz 主页
3. 失败（用户不存在）→ 通过 `postMessage` 通知父页面，父应用调用**接口二**创建用户后重试

**示例：**
```html
<iframe src="https://postiz.example.com/auth/sso?token=eyJhbGciOiJIUzI1NiJ9..."></iframe>
```

---

### 接口二：用户注册接口（开放接口，免登录）

**形式：** HTTP API，供父应用在用户首次登录（收到 403）时调用

```
POST /auth/sso/create-account
Content-Type: application/json
```

**请求体：**

```json
{
  "token": "<SSO_TOKEN>"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `token` | string | 是 | 与接口一相同的 SSO token |

**Token 验证（后端调用认证服务器）：**

后端收到 token 后，向 `SSO_SERVER_URL/api/sso/verify` 发起请求由认证服务器验证并返回用户信息，Postiz 不自行解码 token。

认证服务器返回字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `merchantId` | string | 商户唯一标识，作为 Postiz 用户的 `providerId` |
| `merchantName` | string | 商户名称，作为组织名 |

**响应：**

| 情况 | 状态码 | 说明 |
|------|--------|------|
| 创建成功 | `200 OK` | Response Header 包含 `auth: <JWT>`、`showorg: <orgId>`、`reload: true` |
| token 无效 | `400 Bad Request` | body 为错误信息 |
| 用户已存在 | `409 Conflict` | 用户已存在，无需重复创建，请直接调用登录流程 |

**成功响应 Headers：**

```
auth: eyJhbGciOiJIUzI1NiJ9...
showorg: clxxxxxxxxxxxxx
reload: true
```

**父应用调用时序（完整 SSO 流程）：**

```
1. 设置 iframe src → /auth/sso?token=TOKEN
2. iframe 自动调用 POST /auth/sso
   ├─ 200 → 登录成功，iframe 正常使用
   └─ 403 (needsAccountCreation)
        └─ 父应用收到 postMessage: SSO_NEEDS_ACCOUNT_CREATION
             └─ 父应用调用 POST /auth/sso/create-account { token }
                  ├─ 200 → 父应用重新触发 iframe 加载（重发 SSO_TOKEN postMessage）
                  └─ 400/409 → 处理错误
```

---

## 四、SSO 集成 — 后端实现

> **流程：** 父应用传入 SSO token → 后端验证 token 获取用户信息（merchantId / merchantName）→ 查找用户是否存在 → 不存在则返回 403 + needsAccountCreation → 父应用调用注册接口创建用户后重新发起登录 → 签发内部 JWT

### 3.1 后端新增端点 `POST /auth/sso`

**文件：`apps/backend/src/api/routes/auth.controller.ts`**

在 AuthController 中新增 `ssoLogin` 方法：

```ts
import { SsoLoginDto } from '@gitroom/nestjs-libraries/dtos/auth/sso.login.dto';

// 在 AuthController 类中新增：
@Post('/sso')
async ssoLogin(
  @Body() body: SsoLoginDto,
  @Res({ passthrough: false }) response: Response,
  @RealIP() ip: string,
  @UserAgent() userAgent: string
) {
  try {
    const result = await this._authService.ssoLogin(body.token);

    // 用户存在且已激活 → 签发 JWT
    if (result.exists && result.activated) {
      const jwt = await this._authService.signJwt(result.user); // ✅ 调用 AuthService 的公开方法

      response.header('auth', jwt);
      if (result.orgId) {
        response.header('showorg', result.orgId);
      }
      response.header('reload', 'true');
      response.status(200).json({ login: true });
      return;
    }

    // 用户不存在 或 未激活 → 返回需要授权状态
    response.status(403).json({
      needsAccountCreation: true,
      merchantId: result.merchantId,
      merchantName: result.merchantName,
      message: 'User account does not exist, please create account first',
    });
  } catch (e: any) {
    response.status(400).send(e.message);
  }
}
```

### 3.2 新增 DTO

**文件：`libraries/nestjs-libraries/src/dtos/auth/sso.login.dto.ts`**

```ts
import { IsNotEmpty, IsString } from 'class-validator';

export class SsoLoginDto {
  @IsNotEmpty()
  @IsString()
  token: string;
}
```

### 3.3 后端新增账号创建端点 `POST /auth/sso/create-account`

遵循 Controller → Service → Repository 三层架构，**所有业务逻辑放在 AuthService**，Controller 只做调用和响应。

**文件：`apps/backend/src/api/routes/auth.controller.ts`**（Controller 层，轻薄）

```ts
@Post('/sso/create-account')
async ssoCreateAccount(
  @Body() body: SsoCreateAccountDto,
  @Res({ passthrough: false }) response: Response,
) {
  try {
    const result = await this._authService.ssoCreateAccount(body.token);
    response.header('auth', result.jwt);
    if (result.orgId) {
      response.header('showorg', result.orgId);
    }
    response.header('reload', 'true');
    response.status(200).json({ login: true });
  } catch (e: any) {
    if (e.message === 'USER_ALREADY_EXISTS') {
      response.status(409).send('User already exists');
      return;
    }
    response.status(400).send(e.message);
  }
}
```

**文件：`apps/backend/src/services/auth/auth.service.ts`**（Service 层，新增方法）

```ts
async ssoCreateAccount(token: string) {
  const { merchantId, merchantName } = await this._ssoService.verifyToken(token);

  // 幂等检查：用户已存在则直接返回，不报错
  const existing = await this._userService.getUserByProvider(merchantId, Provider.GENERIC);
  if (existing) {
    throw new Error('USER_ALREADY_EXISTS'); // Controller 捕获后返回 409
  }

  // email 由 merchantId 合成，保证唯一且无需父应用提供
  const syntheticEmail = `${merchantId}@sso.merchant`;

  const create = await this._organizationService.createOrgAndUser(
    {
      company: merchantName,
      email: syntheticEmail,
      password: '',
      provider: Provider.GENERIC,
      providerId: merchantId,
      datafast_visitor_id: undefined,
    },
    'sso-auto',
    'sso-client'
  );

  const newUser = create.users[0].user;
  const jwt = await this.signJwt(newUser);
  return { jwt, orgId: create.id ?? null };
}
```

**DTO：**

**文件：`libraries/nestjs-libraries/src/dtos/auth/sso.create-account.dto.ts`**

```ts
import { IsNotEmpty, IsString } from 'class-validator';

export class SsoCreateAccountDto {
  @IsNotEmpty()
  @IsString()
  token: string;
  // merchantId 和 merchantName 从 token 中解码，无需请求体单独传入
}
```

### 3.4 AuthService 中新增 `ssoLogin` 方法

**文件：`apps/backend/src/services/auth/auth.service.ts`**

在 AuthService 类中新增：

```ts
async ssoLogin(ssoToken: string) {
  // 1. 调用外部认证服务器验证 token，获取 merchantId / merchantName
  const { merchantId, merchantName } = await this._ssoService.verifyToken(ssoToken);

  // 2. 按 providerId（merchantId）查找用户是否存在
  const user = await this._userService.getUserByProvider(merchantId, Provider.GENERIC);

  if (user) {
    // 用户存在 → 返回用户信息
    return {
      exists: true,
      activated: user.activated,
      user,
      merchantId,
      merchantName,
      orgId: user.organizations?.[0]?.id ?? null,
    };
  }

  // 3. 用户不存在 → 返回需要创建账号状态（不主动注册，由父应用调用创建接口）
  return {
    exists: false,
    activated: false,
    user: null,
    merchantId,
    merchantName,
    orgId: null,
  };
}
```

### 3.4 SSO 服务实现

**文件：`apps/backend/src/services/auth/sso.service.ts`**（新建）

```ts
import { Injectable } from '@nestjs/common';

export interface SsoUserInfo {
  merchantId: string;   // 商户唯一标识，用作 providerId
  merchantName: string; // 商户名称，用作组织名
}

@Injectable()
export class SsoService {
  async verifyToken(token: string): Promise<SsoUserInfo> {
    const ssoServerUrl = process.env.SSO_SERVER_URL;

    if (!ssoServerUrl) {
      throw new Error('SSO not configured: SSO_SERVER_URL is missing');
    }

    // 内部网络调用认证服务器，无需鉴权 header
    const res = await fetch(`${ssoServerUrl}/api/sso/verify`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ token }),
    });

    if (!res.ok) {
      throw new Error('Invalid or expired SSO token');
    }

    const data = await res.json();

    if (!data.merchantId || !data.merchantName) {
      throw new Error('SSO server returned incomplete user info');
    }

    return {
      merchantId: data.merchantId,
      merchantName: data.merchantName,
    };
  }
}
```

在 `api.module.ts` 中注册 SsoService（**注意：项目中不存在 `auth.module.ts`，模块文件是 `apps/backend/src/api/api.module.ts`**）：

```ts
// apps/backend/src/api/api.module.ts
import { SsoService } from '@gitroom/backend/services/auth/sso.service';

@Module({
  providers: [
    AuthService,
    SsoService, // ← 新增
    // ...其余 providers 保持不变
  ],
})
export class ApiModule implements NestModule { ... }
```

在 AuthService 中注入 SsoService，同时将 `jwt` 方法改为 **public**（Controller 调用 `signJwt` 需要）：

```ts
// auth.service.ts

constructor(
  private _userService: UsersService,
  private _organizationService: OrganizationService,
  private _notificationService: NotificationService,
  private _emailService: EmailService,
  private _providerManager: AuthProviderManager,
  private _ssoService: SsoService, // ← 新增注入
) {}

// 将原来的 private jwt() 改为 public，并重命名为 signJwt 以避免歧义
public async signJwt(user: User) {
  if (user.password) {
    delete user.password;
  }
  return AuthChecker.signJWT(user);
}
```

> **注意：** 将 `jwt` 改名为 `signJwt` 后，需将文件内部原有的 `this.jwt(...)` 调用（`routeAuth`、`activate`、`resendActivationEmail`、`checkExists` 中）一并替换为 `this.signJwt(...)`。

### 3.5 环境变量配置

在 `.env` 中新增：

```env
# SSO 集成配置
SSO_SERVER_URL=http://sso-service:8080   # 内部服务地址，无需鉴权
SSO_PARENT_ORIGINS=https://parent-domain.com,https://another-parent.com
```

### 3.6 SSO 集成流程图

#### 场景 A：用户已存在（直接登录）

```
父应用                        Postiz iframe                        Postiz Backend
   │                              │                                     │
   │  ┌─ URL: /auth/sso?token=XX ─┤                                     │
   │─────────────────────────────>│                                     │
   │                              │  POST /auth/sso { token: XX }       │
   │                              │────────────────────────────────────>│
   │                              │                    验证 SSO token   │
   │                              │                    ───────────────>外部认证服务
   │                              │                                     │
   │                              │       返回用户信息 {email, name...}  │
   │                              │<────────────────────────────────────│
   │                              │              查找用户 by email      │
   │                              │                    ───────────────>数据库
   │                              │                    ───────────────>用户存在 ✅
   │                              │              签发内部 JWT           │
   │                              │<────────────────────────────────────│
   │                              │                                     │
   │  header: auth=JWT            │                                     │
   │  header: reload=true         │                                     │
   │<─────────────────────────────│                                     │
   │                              │                                     │
   │  sessionStorage.setItem('auth', JWT)                              │
   │  window.location.href = '/'  │                                     │
   │                              │                                     │
   │  已登录状态，正常使用        │                                     │
   │                              │                                     │
```

#### 场景 B：用户不存在（需要创建账号）

```
父应用                        Postiz iframe                        Postiz Backend
   │                              │                                     │
   │  ┌─ URL: /auth/sso?token=XX ─┤                                     │
   │─────────────────────────────>│                                     │
   │                              │  POST /auth/sso { token: XX }       │
   │                              │────────────────────────────────────>│
   │                              │                    验证 SSO token   │
   │                              │                    ───────────────>外部认证服务
   │                              │                                     │
   │                              │       返回用户信息 {email, name...}  │
   │                              │<────────────────────────────────────│
   │                              │              查找用户 by email      │
   │                              │                    ───────────────>数据库
   │                              │                    ───────────────>用户不存在 ❌
   │                              │                                     │
   │  403: needsAccountCreation   │                                     │
   │  {email, name, providerId}    │                                     │
   │<─────────────────────────────│                                     │
   │                              │                                     │
   │  postMessage:                │                                     │
   │  SSO_NEEDS_ACCOUNT_CREATION  │                                     │
   │  {email, name, providerId}    │                                     │
   │◀─────────────────────────────│                                     │
   │                              │                                     │
   │  ┌─ 在父应用中创建用户 ────┐ │                                     │
   │  └─────────────────────────┘ │                                     │
   │                              │                                     │
   │  postMessage: SSO_TOKEN       │                                     │
   │─────────────────────────────>│                                     │
   │                              │  重新 POST /auth/sso                 │
   │                              │────────────────────────────────────>│
   │                              │                    验证 token        │
   │                              │                    查找用户          │
   │                              │                    用户已存在 ✅     │
   │                              │              签发内部 JWT           │
   │                              │<────────────────────────────────────│
   │                              │                                     │
   │  header: auth=JWT            │                                     │
   │  header: reload=true         │                                     │
   │<─────────────────────────────│                                     │
   │                              │                                     │
   │  登录成功                     │                                     │
```

### 3.7 SSO 集成检查清单

| # | 修改项 | 文件 | 操作 | 状态 |
|---|--------|------|------|------|
| 1 | SSO 验证端点 | `auth.controller.ts` | 新增 `POST /auth/sso`（用户存在则返回 JWT，不存在则返回 403 + needsAccountCreation） | ✅ |
| 2 | SSO 登录 DTO | `dtos/auth/sso.login.dto.ts` | 新建 DTO | ✅ |
| 3 | SSO 创建账号端点 | `auth.controller.ts` | 新增 `POST /auth/sso/create-account`（验证 token 后创建用户+组织，签发 JWT） | ✅ |
| 4 | SSO 创建账号 DTO | `dtos/auth/sso.create-account.dto.ts` | 新建 DTO（token + optional company） | ✅ |
| 5 | SSO 业务逻辑 | `auth.service.ts` | 新增 `ssoLogin()` 方法（查找用户，存在则返回信息，不存在则返回 needsCreation 状态） | ✅ |
| 6 | SSO 服务 | `sso.service.ts` | 新建，调用外部认证服务验证 token | ✅ |
| 7 | 模块注册 | `api.module.ts` | 在 `apps/backend/src/api/api.module.ts` 中注册 SsoService | ✅ |
| 8 | 前端 SSO 页面 | `app/(app)/auth/sso/page.tsx` | 新建，接收 token、调用后端、处理 needsAccountCreation、postMessage 通知父页面 | ✅ |
| 9 | 环境变量 | `.env` | `SSO_SERVER_URL`, `SSO_PARENT_ORIGINS` | ✅ |

---

## 四、完整检查清单

### 4.1 Cookie → SessionStorage 迁移

| # | 修改项 | 文件 | 操作 | 状态 |
|---|--------|------|------|------|
| 1 | 前端 token 存储 | `layout.context.tsx` | `setCookie` → `sessionStorage.setItem` | ✅ |
| 2 | 前端 token 读取 | `custom.fetch.func.ts` | `document.cookie` → `sessionStorage.getItem` | ✅ |
| 3 | 前端清除 token | `layout.context.tsx` + `logout.component.tsx` | `setCookie(..., '', -10)` → `sessionStorage.removeItem` | ✅ |
| 4 | 后端移除 cookie | `auth.controller.ts` | 移除 `res.cookie()`，保留 `res.header()` | ✅ |
| 5 | 后端 logout | `users.controller.ts` | 移除 `res.clearCookie()`，设置 `logout` header | ✅ |
| 6 | 后端 org/impersonate | `users.controller.ts` | `res.cookie()` → `res.header()` | ✅ |
| 7 | 创建 /auth/sso 路由 | `app/(app)/auth/sso/page.tsx` | 新建页面，接收 token 并调用后端 | ✅ |
| 8 | 移除 iframe 跳出代码 | 全局搜索 | 项目中不存在 `window.top.location` 跳出代码 | ✅（无需修改） |

### 4.2 SSO 集成

| # | 修改项 | 文件 | 操作 | 状态 |
|---|--------|------|------|------|
| 1 | SSO 验证端点 | `auth.controller.ts` | 新增 `POST /auth/sso`（用户存在则返回 JWT，不存在则返回 403 + needsAccountCreation） | ✅ |
| 2 | SSO 创建账号端点 | `auth.controller.ts` | 新增 `POST /auth/sso/create-account`（父应用创建用户后调用） | ✅ |
| 3 | SSO 登录 DTO | `dtos/auth/sso.login.dto.ts` | 新建 DTO | ✅ |
| 4 | SSO 创建账号 DTO | `dtos/auth/sso.create-account.dto.ts` | 新建 DTO（token + optional company） | ✅ |
| 5 | SSO 业务逻辑 | `auth.service.ts` | 新增 `ssoLogin()` 方法（查找用户，存在则返回信息，不存在则返回 needsCreation 状态） | ✅ |
| 6 | SSO 服务 | `sso.service.ts` | 新建，调用外部认证服务验证 token | ✅ |
| 7 | 模块注册 | `api.module.ts` | 在 `apps/backend/src/api/api.module.ts` 中注册 SsoService（不是 auth.module.ts） | ✅ |
| 8 | 前端 SSO 页面 | `app/(app)/auth/sso/page.tsx` | 新建，useFetch() 在组件顶层调用；接收 token、调用后端、处理 needsAccountCreation、postMessage 通知父页面 | ✅ |
| 9 | 环境变量 | `.env` | `SSO_SERVER_URL`, `SSO_PARENT_ORIGINS` | ✅ |

### 4.3 iframe 嵌入相关

| # | 修改项 | 位置 | 操作 | 状态 |
|---|--------|------|------|------|
| 1 | CORS `exposedHeaders` | `apps/backend/src/main.ts` | 将 `auth`/`showorg`/`impersonate`/`logout` 从 `NOT_SECURED` 条件中移出，始终暴露 | ✅ |
| 2 | `X-Frame-Options` / `frame-ancestors` | NestJS 层无 helmet，**无需修改** | — | ✅ |
| 3 | Nginx 安全头 | `var/docker/nginx.conf` | 添加 `frame-ancestors 'self';` CSP header（需替换为实际父域名） | ✅ |
| 4 | OAuth 跳转 | `google.provider.tsx`, `github.provider.tsx`, `oauth.provider.tsx` | `window.location.href` → `window.open(..., '_blank')` | ✅ |

---

## 五、实施步骤

### Phase 1：基础 iframe 可嵌入

1. **更新 `main.ts` CORS `exposedHeaders`**（1.2）
   - 将 `auth`、`showorg`、`impersonate`、`logout` 从 `NOT_SECURED` 条件中移出，始终暴露
   - 这是后续所有 header 认证方案的前提

2. **检查 Nginx 配置，移除冲突的安全头**（1.5）
   - 搜索并移除 `add_header X-Frame-Options`
   - 将 `frame-ancestors` 改为允许父域名
   - NestJS 层无 helmet，**无需改动 NestJS 代码**

3. 验证 iframe 可以加载 Postiz 页面

### Phase 2：Cookie → SessionStorage 迁移

4. **修改 `layout.context.tsx`**（2.2.1）
   - `setCookie` → `sessionStorage.setItem`（写入处）
   - **注意：logout 清除逻辑有两处**（L54 和 L83），均需改为 `sessionStorage.removeItem`

5. **修改 `custom.fetch.func.ts`**（2.2.1）
   - `auth`、`showorg`、`impersonate` **三个** cookie 读取全部迁移到 `sessionStorage.getItem`

6. **修改 `logout.component.tsx`**（2.2.1）
   - 非 secured 模式下清除 `auth`、`showorg`、`impersonate` 三个 sessionStorage 键

7. **修改 `auth.controller.ts`**（2.2.2）
   - `register`、`login`、`activate`、`oauthExists` 端点：移除 `response.cookie()`，始终使用 `response.header('auth', jwt)`

8. **修改 `users.controller.ts`**（2.2.2）
   - `logout`：移除三个 `response.cookie()` 清除调用，保留 `response.header('logout', 'true')`
   - `impersonate`：移除 `response.cookie('impersonate', ...)`，始终使用 `response.header('impersonate', id)`
   - `change-org`：移除 `response.cookie('showorg', ...)`，始终使用 `response.header('showorg', id)`

9. 验证认证流程正常工作（登录、登出、切换组织）

### Phase 3：SSO 集成

10. **在 `auth.service.ts` 中准备基础**
    - 将 `private jwt()` 改名并改为 `public signJwt()`
    - 更新文件内所有 `this.jwt(...)` 为 `this.signJwt(...)`
    - 新增 `ssoLogin()` 和 `ssoCreateAccount()` 方法
    - 注入 `SsoService`

11. **新建 `sso.service.ts`**（3.4 节）
    - 实现 `verifyToken()` 调用外部认证服务

12. **在 `api.module.ts` 中注册 `SsoService`**（3.4 节）
    - 文件路径：`apps/backend/src/api/api.module.ts`（**不是** auth.module.ts）

13. **在 `auth.controller.ts` 中新增两个端点**（3.1 + 3.3 节）
    - `POST /auth/sso`：调用 `authService.ssoLogin()`
    - `POST /auth/sso/create-account`：调用 `authService.ssoCreateAccount()`

14. **新建两个 DTO 文件**（3.2 节）
    - `sso.login.dto.ts`
    - `sso.create-account.dto.ts`

15. **新建前端 SSO 页面** `apps/frontend/src/app/(app)/auth/sso/page.tsx`（2.3 节）
    - `useFetch()` 必须在组件顶层调用，不能在 `handleSsoLogin` 异步函数内部调用

16. **配置环境变量**（3.5 节）
    - `SSO_SERVER_URL`、`SSO_PARENT_ORIGINS`
    - 前端：`NEXT_PUBLIC_SSO_PARENT_ORIGINS`

17. 端到端测试 SSO 登录流程（用户已存在 / 用户不存在两个场景）

---

## 六、注意事项

- **HTTPS 是硬性要求**：`SameSite=None` + `Secure` 需要 HTTPS 环境
- **浏览器兼容性**：部分旧版浏览器不支持 `ALLOW-FROM`，统一使用 CSP `frame-ancestors`
- **安全风险**：允许 iframe 嵌入会增加 Clickjacking 风险，生产环境务必使用 `frame-ancestors` 白名单而非 `*`
- **Safari 限制**：Safari 对第三方 Cookie 限制最严格，使用 sessionStorage 方案可规避
- **SSO Token 安全**：SSO token 应有时效限制（建议 5 分钟），防止重放攻击
- **用户不自动创建**：用户不存在时返回 `needsAccountCreation` 状态，通过 `postMessage` 通知父页面创建账号后再重新发起登录
- **postMessage 来源验证**：生产环境务必验证 `event.origin` 在白名单内，防止跨域攻击
