# 社交平台评论 API 支持情况

> 生成时间: 2026-04-13
> 项目: Postiz App

---

## 功能概述

系统定义了评论管理接口 `ISocialMediaIntegration`：

```typescript
// 拉取评论
fetchComments?(
  integrationId: string,
  accessToken: string,
  platformPostId: string,
  options?: { maxResults?: number; pageToken?: string }
): Promise<FetchCommentsResult>;

// 回复评论
replyToComment?(
  integrationId: string,
  accessToken: string,
  platformPostId: string,
  commentId: string,
  content: string
): Promise<ReplyResult>;
```

---

## 当前实现情况

| 平台 | 标识符 | 拉取评论 | 回复评论 | 实现状态 |
|------|--------|:-------:|:-------:|:-------:|
| YouTube | `youtube` | ✅ | ✅ | 已实现 |
| X (Twitter) | `x` | ❌ | ❌ | 未实现 |
| Facebook | `facebook` | ❌ | ❌ | 未实现 |
| Instagram | `instagram` | ❌ | ❌ | 未实现 |
| Threads | `threads` | ❌ | ❌ | 未实现 |
| LinkedIn | `linkedin` | ❌ | ❌ | 未实现 |
| TikTok | `tiktok` | ❌ | ❌ | 未实现 |
| Reddit | `reddit` | ❌ | ❌ | 未实现 |
| Bluesky | `bluesky` | ❌ | ❌ | 未实现 |
| Mastodon | `mastodon` | ❌ | ❌ | 未实现 |
| Telegram | `telegram` | ❌ | ❌ | 未实现 |
| Discord | `discord` | ❌ | ❌ | 未实现 |
| Pinterest | `pinterest` | ❌ | ❌ | 未实现 |
| VK | `vk` | ❌ | ❌ | 未实现 |
| Faroaster | `faroaster` | ❌ | ❌ | 未实现 |
| Nostr | `nostr` | ❌ | ❌ | 未实现 |
| Medium | `medium` | ❌ | ❌ | 未实现 |
| Dev.to | `dev.to` | ❌ | ❌ | 未实现 |

---

## API 支持情况详情

### YouTube ✅

**官方文档**: https://developers.google.com/youtube/v3/docs/commentThreads/list

**当前 Scopes**:
- `https://www.googleapis.com/auth/youtube.force-ssl`
- `https://www.googleapis.com/auth/youtube.readonly`

**评论 API**:
- 拉取: `commentThreads.list` - 获取视频评论线程
- 回复: `comments.insert` - 创建回复评论

**实现位置**: `libraries/nestjs-libraries/src/integrations/social/youtube.provider.ts`

---

### X (Twitter)

**官方文档**: https://developer.x.com/en/docs

**当前 Scopes**: OAuth 1.0a (无明确 scope)

**评论 API 限制**:
- ✅ 回复推文: `POST /2/tweets` + `reply` 参数
- ⚠️ **重要限制 (2026年3月起)**: 必须被提及或与作者有互动才能回复
- ❌ 拉取评论: 官方 API 不提供直接获取推文评论的端点

**需要添加**: 读取他人推文评论需要第三方 API

---

### Facebook

**官方文档**: https://developers.facebook.com/docs/graph-api/reference/post/comments/

**当前 Scopes**:
- `pages_show_list`
- `pages_manage_engagement`
- `pages_read_engagement`
- `read_insights`

**评论 API**:
- 拉取: `GET /{post-id}/comments`
- 回复: `POST /{post-id}/comments`

**要求**: 需要 Page access token + `MODERATE` 权限

---

### Instagram

**官方文档**: https://developers.facebook.com/docs/instagram-api/reference/ig-media/comments

**当前 Scopes**:
- `instagram_basic`
- `instagram_manage_comments`
- `instagram_content_publish`

**评论 API**:
- 拉取: `GET /{ig-media-id}/comments`
- 回复: `POST /{ig-media-id}/comments`

**重要提醒**:
- ⚠️ Basic Display API 已于 **2024年12月废弃**
- 必须使用 **Instagram Graph API**
- 仅支持 Business/Creator 账号
- 需要关联 Facebook Page

---

### Threads

**官方文档**: https://developers.facebook.com/docs/threads/retrieve-and-manage-replies/

**当前 Scopes**:
- `threads_basic`
- `threads_content_publish`
- `threads_manage_replies`
- `threads_manage_insights`

**评论 API**:
- 拉取: `GET /{threads-user-id}/replies` - 获取用户的所有回复
- 获取帖子评论: `GET /{media-id}/comments` (需确认)
- 回复: `POST /{threads-user-id}/threads` + `reply_to_id`

**权限要求**:
- 回复根帖子: 必须是帖子所有者
- 回复其他回复: 需要 `threads_keyword_search` 或 `threads_manage_mentions`

---

### LinkedIn

**官方文档**: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/comments-api

**当前 Scopes**:
- `openid`, `profile`
- `w_member_social`
- `r_basicprofile`
- `rw_organization_admin`
- `w_organization_social`
- `r_organization_social`

**评论 API**:
- 拉取: `GET /socialActions/{shareUrn}/comments`
- 获取评论回复: `GET /socialActions/{commentUrn}/comments`
- 回复: `POST /socialActions/{shareUrn}/comments`

**注意**: 部分 API 权限将于 2023年6月迁移到新权限名

---

### TikTok

**官方文档**: https://developers.tiktok.com/doc/research-api-specs-query-video-comments

**当前 Scopes**:
- `video.list`
- `user.info.basic`
- `video.publish`
- `video.upload`
- `user.info.profile`
- `user.info.stats`

**评论 API**:
- ⚠️ **仅限 Research API**: `POST /v2/research/video/comment/list/`
- 需要 `research.data.basic` scope
- 仅支持学术研究用途，不适合商业应用

**限制**: 官方 Comments API 仅供研究，商业用途受限

---

### Reddit

**官方文档**: https://www.reddit.com/dev/api/#section_comments

**当前 Scopes**: `read`, `identity`, `submit`, `flair`

**评论 API**:
- 拉取帖子评论: `GET /r/{subreddit}/comments/{article}`
- 回复评论: `POST /api/comment`
- 获取用户评论: `GET /user/{username}/comments`

**需要添加**: `read` scope (已具备)

---

### Bluesky (AT Protocol)

**官方文档**: https://docs.atproto.api/guides/data-plane/

**评论 API**:
- 获取帖子线程: `app.bsky.feed.getPostThread`
- 创建回复: `app.bsky.feed.post` (作为回复)

**AT Protocol 端点**:
- 仓库操作: `com.atproto.repo.createRecord`
- 帖子类型: `app.bsky.feed.post`

---

### Mastodon

**官方文档**: https://docs.joinmastodon.org/api/

**当前 Scopes**: `write:statuses`, `profile`, `write:media`

**评论 API**:
- 获取 statuses 下的回复: `GET /api/v1/statuses/{id}/context`
- 创建回复: `POST /api/v1/statuses` + `in_reply_to_id`

**注意**: 需要添加 `read:statuses` scope 来读取评论

---

### Telegram

**官方文档**: https://core.telegram.org/bots/api#getupdates

**评论 API**:
- 获取更新: `getUpdates` - 获取消息/评论
- 回复: `sendMessage` - 发送回复消息

**限制**: 需要知道 chat_id 和 message_id

---

### Discord

**官方文档**: https://discord.com/developers/docs/resources/channel#list-message-reactions

**评论 API**:
- 获取消息: `GET /channels/{channel_id}/messages`
- 获取消息评论: `GET /channels/{channel_id}/messages/{message_id}/threads`
- 回复线程: `POST /channels/{channel_id}/messages`

**注意**: 频道消息评论使用线程机制

---

### Pinterest

**官方文档**: https://developers.pinterest.com/docs/api/v5/#operation/comments/list

**评论 API**:
- 拉取评论: `GET /v5/pins/{pin_id}/comments`
- 回复: `POST /v5/pins/{pin_id}/comments`

---

### VK (VKontakte)

**官方文档**: https://dev.vk.com/method/wall.getComments

**评论 API**:
- 获取评论: `wall.getComments`
- 添加评论: `wall.createComment`
- 获取回复: `wall.getComments` + `thread`

---

### 其他平台

| 平台 | 文档链接 |
|------|---------|
| Faroaster | https://docs.farcaster.xyz/ |
| Nostr | https://github.com/nostr-protocol/nips |
| Medium | https://github.com/Medium/medium-api-docs |
| Dev.to | https://developers.forem.com/api/v1#tag/comments |

---

## 官方 API 文档首页

| 平台 | 文档地址 |
|------|---------|
| YouTube | https://developers.google.com/youtube |
| X/Twitter | https://developer.x.com/en/docs |
| Facebook | https://developers.facebook.com/docs/graph-api |
| Instagram | https://developers.facebook.com/docs/instagram-api |
| Threads | https://developers.facebook.com/docs/threads |
| LinkedIn | https://learn.microsoft.com/en-us/linkedin/ |
| TikTok | https://developers.tiktok.com/ |
| Reddit | https://www.reddit.com/dev/api/ |
| Bluesky | https://docs.atproto.api/ |
| Mastodon | https://docs.joinmastodon.org/api/ |
| Telegram | https://core.telegram.org/bots/api |
| Discord | https://discord.com/developers/docs |
| Pinterest | https://developers.pinterest.com/docs/api/ |
| VK | https://dev.vk.com/ |
| Faroaster | https://docs.farcaster.xyz/ |
| Nostr | https://nostr.com/developers |

---

## 实现优先级建议

### 高优先级 (API 支持良好，易实现)

1. **Reddit** - API 支持完善，只需添加 `read:statuses` scope
2. **Mastodon** - ActivityPub 协议支持，API 清晰
3. **Facebook** - API 支持完整，需 Page 权限
4. **LinkedIn** - API 支持完整，需组织权限

### 中优先级 (有实现难度)

5. **Instagram** - 需确认 Business 账号 + Graph API 迁移
6. **Threads** - API 较新，功能完善
7. **Bluesky** - AT Protocol 实现

### 低优先级 (有平台限制)

8. **X/Twitter** - 回复受限，需被提及
9. **TikTok** - 仅 Research API 可用
10. **Discord** - 需要 Bot 权限配置

---

## 相关文件

- 接口定义: `libraries/nestjs-libraries/src/integrations/social/social.integrations.interface.ts`
- 后端 API: `apps/backend/src/api/routes/social-comments.controller.ts`
- 评论服务: `libraries/nestjs-libraries/src/database/prisma/comments/comments.service.ts`
- YouTube 实现: `libraries/nestjs-libraries/src/integrations/social/youtube.provider.ts`