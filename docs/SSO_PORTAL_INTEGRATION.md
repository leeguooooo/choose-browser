# Choose Browser 接入 app.misonote.com / SSO 说明

## 目标
- 在 `app.misonote.com/choose-browser` 中统一展示与启动 Choose Browser。
- 使用 Cloudflare SSO 的统一会员权益判断：
  - 主权益键：`membership.all_apps`
  - 预留权益键：`app.choose-browser.access`

## 当前约定
- 统一租户：`tenant-misonote`
- 统一客户端：`misonote-choose-browser-web`
- 门户入口页：`https://app.misonote.com/choose-browser`
- 产品落地域名：`https://choose-browser.misonote.com`

## 阶段建议
1. Phase 1（已对齐）
- 保持现有产品域名，门户只做目录页 + 跳转。
2. Phase 2
- Web 入口接入 OIDC PKCE（client_id=`misonote-choose-browser-web`）。
- API/服务端接口按 `membership.all_apps` 判定可用性。
3. Phase 3
- 下线旧鉴权路径（如有），统一收口至 SSO。
