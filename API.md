# 接口文档

本文档描述本应用实际调用、以及可接入但尚未调用的 FxTwitter / 备用接口。字段以 [OpenAPI 3.0](https://api.fxtwitter.com/2/openapi.json) 和 2026-08-17 实测返回为准。官方说明：[FxEmbed API](https://docs.fxembed.com/api/introduction/) · [接口一览](https://docs.fxembed.com/api/twitter/)。

应用不登录、不使用官方开发者密钥。国内访问需 Clash / VPN。

---

## 1. 概述

| 项 | 值 |
|----|----|
| 基址 | `https://api.fxtwitter.com` |
| 版本 | v2（路径前缀 `/2/`）。旧版 v1 仍可用，但不含 v2 全部能力 |
| 协议 | HTTPS，请求方式全部为 **GET**，响应 `Content-Type: application/json` |
| 鉴权 | 无 Token、无 Cookie |
| 限流 | 约每 IP **1000 次 / 分钟** |
| 代理示例 | `curl -x http://127.0.0.1:7897`（端口以应用设置为准） |

当前路径 `/{handle}` 是 v1 资料接口，应用仅在 `/2/profile/{handle}` 失败时回退。下载仍走 v1 `GET /status/{id}`，尚未升到 `GET /2/status/{id}`。

---

## 2. 通用约定

### 2.1 请求头

```
Accept: application/json
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36
```

下载视频文件时额外加：

```
Referer: https://x.com/
```

### 2.2 路径参数 `{handle}`

用户名不带 `@`，大小写不敏感。也可用数字 ID：`id:11348282`。

### 2.3 真值查询参数

`about_account`、`with_replies`、`groupthreads` 等「真值」参数，下列任一即视为开启：`1`、`true`、`yes`、`on`、空字符串。别名 `aboutAccount` 与 `about_account` 等价。

`count` 一般范围 **1–100**。未特别说明时，列表默认 20，搜索默认 30，热点最大 50。

### 2.4 分页

列表接口返回：

```json
{
  "code": 200,
  "results": [],
  "cursor": { "top": "...", "bottom": "..." }
}
```

下一页把上一页的 `cursor.bottom` 原样作为查询参数 `cursor` 传入。不要把 `since` 和 `cursor` 一起用。

### 2.5 响应与错误

每个 JSON 都有 `code`，数值与 HTTP 状态码一致。判断成败以 `code` 为准（有时 HTTP 仍是 200，body 里 `code` 已是错误）。

| HTTP / code | 含义 |
|-------------|------|
| 200 | 成功 |
| 204 | 仅时间线：传了 `since` 且未传 `cursor`，且本页没有更新的帖。无 JSON body |
| 400 | 参数非法（空 `q`、非法 ID 等） |
| 401 | 单帖 / 主题 / 评论：上游要求登录或不允许匿名读 |
| 404 | 用户 / 帖子不存在；**搜索、引用在无结果时也会 404**，body 仍是 `{ "code": 404, "results": [], "cursor": { "top": null, "bottom": null } }` |
| 500 | 上游失败 |

错误 body 常见形态：

```json
{ "code": 404, "message": "User not found" }
```

### 2.6 本文档写法

每个接口固定包含：**功能说明、接入状态、请求方式、请求地址、路径参数、查询参数、响应状态、成功返回、请求实例、返回实例**。帖子、用户的完整字段只在第 3 节定义一次，各接口用「见 3.x」引用，避免漏字段或复制一份残缺表。

返回实例来自真实请求，数组只保留 1 条，长字符串已截断。`cursor` 每次都会变，不能照抄翻页。

---

## 3. 公共数据结构

### 3.1 用户 User（`type: profile`）

资料、关注/粉丝、转发列表、帖子 `author` 都是这套字段。发帖数在 v2 是 `statuses`；应用入库时若没有 `statuses` 会再读 `tweets`。

| 字段 | 类型 | 说明 |
|------|------|------|
| type | string | 固定 `profile` |
| id | string | 数字用户 ID |
| screen_name | string | 用户名（不带 `@`） |
| name | string | 显示名 |
| description | string | 简介 |
| raw_description.text | string | 简介原文 |
| raw_description.facets | array | 简介里的 mention / url / hashtag |
| avatar_url | string / null | 头像 |
| banner_url | string / null | 头图 |
| url | string | 主页 `https://x.com/{screen_name}` |
| location | string | 位置 |
| website.url | string / null | 外链 |
| website.display_url | string | 外链展示文案 |
| followers | number | 粉丝数 |
| following | number | 关注数 |
| statuses | number | 发帖数 |
| media_count | number | 媒体数 |
| likes | number | 喜欢数 |
| protected | boolean | 是否锁帖 |
| joined | string | 注册时间，Twitter 日期格式 |
| birthday | object / null | `day` / `month` / `year` |
| verification.verified | boolean | 是否认证 |
| verification.type | string / null | `government` / `organization` / `individual` |
| verification.verified_at | string / null | 认证时间 |
| about_account | object | 仅请求带了 `about_account=1` 时出现，见 3.4 |
| profile_embed | boolean | 是否允许嵌入 |

```json
{
  "type": "profile",
  "id": "11348282",
  "screen_name": "NASA",
  "name": "NASA",
  "description": "Making the seemingly impossible, possible. ✨",
  "raw_description": { "text": "Making the seemingly impossible, possible. ✨", "facets": [] },
  "avatar_url": "https://pbs.twimg.com/profile_images/1321163587679784960/0ZxKlEKB_normal.jpg",
  "banner_url": "https://pbs.twimg.com/profile_banners/11348282/1775567134",
  "url": "https://x.com/NASA",
  "location": "Pale Blue Dot",
  "website": { "url": "http://www.nasa.gov/", "display_url": "nasa.gov" },
  "followers": 92316091,
  "following": 119,
  "statuses": 74339,
  "media_count": 28078,
  "likes": 16934,
  "protected": false,
  "joined": "Wed Dec 19 20:20:32 +0000 2007",
  "verification": { "verified": true, "verified_at": null, "type": "government" }
}
```

### 3.2 帖子 Status（`type: status`）

时间线、媒体、搜索、评论、引用、单帖 v2、主题帖里的帖都是这套字段。不可用的引用/主题坑位可能是 `type: tombstone`（`reason`: `deleted` / `suspended` / `private` / `blocked` / `unavailable`）。

| 字段 | 类型 | 说明 |
|------|------|------|
| type | string | `status` |
| id | string | 帖子 snowflake ID |
| url | string | 帖子链接 |
| text | string | 展示正文 |
| raw_text.text | string | 原文（含 t.co） |
| raw_text.display_text_range | number[] | 展示区间 |
| raw_text.facets | array | `mention` / `hashtag` / `url` / `media` |
| created_at | string | 发布时间（Twitter 日期格式） |
| created_timestamp | number | Unix **秒** |
| likes | number | 喜欢 |
| reposts | number | 转发（v1 字段名是 `retweets`） |
| quotes | number | 引用数 |
| replies | number | 回复数 |
| bookmarks | number / null | 书签 |
| views | number / null | 播放/阅读 |
| lang | string / null | 语言，如 `en` |
| source | string / null | 客户端，如 `Twitter for iPhone` |
| provider | string | 固定 `twitter` |
| embed_card | string | `tweet` / `summary` / `summary_large_image` / `player` |
| possibly_sensitive | boolean | 敏感标记 |
| is_note_tweet | boolean | 是否长帖 |
| community_note | object / null | 社区附注 |
| replying_to | object / null | 回复目标：`screen_name`、`status`、`url` |
| reposted_by | object / null | 转发者摘要 |
| author | object | 作者，结构同 User |
| media | object | 见 3.3 |
| quote | object / tombstone | 被引用的帖 |
| poll | object | 投票：`choices` / `total_votes` / `ends_at` |
| card | object | 链接卡片 |
| translation | object | 传 `lang` 且有翻译时出现 |
| article | object | Articles 长文正文 |
| community | object | 社群信息 |

### 3.3 媒体 media

| 字段 | 类型 | 说明 |
|------|------|------|
| photos[] | array | 图 / GIF。`type`: `photo` / `gif`；有 `url`、`width`、`height`、`altText` |
| videos[] | array | 视频 / GIF。`type`: `video` / `gif` |
| videos[].url | string | 当前选中的直链（通常最高清 mp4） |
| videos[].thumbnail_url | string | 封面 |
| videos[].duration | number | 时长（秒） |
| videos[].width / height | number | 分辨率 |
| videos[].format | string | 如 `video/mp4` |
| videos[].formats[] | array | 多码率。`container`: `mp4` / `webm` / `m3u8`；`codec`: `h264` / `hevc` / `vp9` / `av1`；`bitrate`；`url` |
| all[] | array | `photos` + `videos` 合并 |
| mosaic | object | 多图拼图 |
| external | object | 外链视频 |
| broadcast | object | 直播 |

```json
{
  "videos": [
    {
      "id": "2088354592220164096",
      "type": "video",
      "format": "video/mp4",
      "url": "https://video.twimg.com/amplify_video/2088354592220164096/vid/avc1/1280x720/JNNAMOLs2QTSjlN8.mp4?tag=29",
      "thumbnail_url": "https://pbs.twimg.com/media/HPtTb-BXwAA954N.jpg",
      "duration": 76.676,
      "width": 1280,
      "height": 720,
      "formats": [
        { "container": "m3u8", "url": "https://video.twimg.com/amplify_video/.../pl/PTiHE6OKkyr8tCH3.m3u8?tag=29" },
        { "container": "mp4", "codec": "h264", "bitrate": 256000, "url": "https://video.twimg.com/amplify_video/.../480x270/3Tiv6Nkxw4Kmvxga.mp4?tag=29" }
      ]
    }
  ],
  "all": ["与 videos[0] 相同"]
}
```

### 3.4 About Account

| 字段 | 类型 | 说明 |
|------|------|------|
| location_accurate | boolean | 位置是否可靠 |
| based_in | string / null | 所在地 |
| created_country_accurate | boolean / null | 注册国家是否可靠 |
| source | string / null | 来源 |
| username_changes.count | number | 改名次数 |
| username_changes.last_changed_at | string / null | 最近改名时间 |

---

## 4. 接口一览

| 编号 | 接口名称 | 方法 | 请求地址 | 功能 | 接入 |
|------|----------|------|----------|------|------|
| 5.1 | 用户资料 | GET | `/2/profile/{handle}` | 正规资料；可替换旧 `/{handle}` | 已接入，失败回退 v1 |
| 5.2 | 用户时间线 | GET | `/2/profile/{handle}/statuses` | 帖子列表；`with_replies` 带回复；`since` 增量 | 已接入。动态页传 `since`；未传 `with_replies` |
| 5.3 | 用户媒体 | GET | `/2/profile/{handle}/media` | 只含图/视频的帖 | 已接入 |
| 5.4 | 关注列表 | GET | `/2/profile/{handle}/following` | 他关注了谁 | 已接入 |
| 5.5 | 粉丝列表 | GET | `/2/profile/{handle}/followers` | 谁关注了他 | 已接入 |
| 5.6 | 长文 Articles | GET | `/2/profile/{handle}/articles` | 用户 Articles | 未接入 |
| 5.7 | About Account | GET | `/2/profile/{handle}/about` | 账号「关于」统计 | 未接入 |
| 6.1 | 单帖 v2 | GET | `/2/status/{id}` | 正规单帖，可替换下载用的 v1 | 未接入 |
| 6.2 | 主题帖 | GET | `/2/thread/{id}` | 把长帖按顺序串起来 | 未接入 |
| 6.3 | 评论 | GET | `/2/conversation/{id}` | 帖子 + 主题 + 别人的回复 | 已接入 |
| 6.4 | 引用列表 | GET | `/2/status/{id}/quotes` | 引用这条帖的帖 | 未接入 |
| 6.5 | 转发列表 | GET | `/2/status/{id}/reposts` | 转发这条帖的用户 | 未接入 |
| 6.6 | 单帖 v1 | GET | `/status/{id}` | 旧版单帖，下载在用 | 已接入 |
| 7.1 | 搜索帖子 | GET | `/2/search` | 搜帖；热点点进去应用内搜 | 已接入 |
| 7.2 | 输入补全 | GET | `/2/typeahead` | 输入时补全用户 / 话题 | 未接入 |
| 7.3 | 官方热点 | GET | `/2/trends` | 替代 trends24 全球页 | 已接入（仅全球） |
| 8.1 | vxTwitter | GET | `https://api.vxtwitter.com/i/status/{id}` | 单帖备用 | 已接入 |
| 8.2 | Nitter RSS | GET | `https://nitter.net/{handle}/rss` | 时间线备用 | 已接入 |
| 8.3 | trends24 | GET | `https://trends24.in/{region}/` | 地区热点 HTML | 已接入 |

---

## 5. 用户

### 5.1 获取用户资料

**功能说明：** 按用户名或 `id:{数字}` 取资料。正规入口是本接口；旧版 `GET /{handle}` 仅作失败回退。

**接入状态：** 已接入 · `XFollowingService.fetchAccount` · 添加关注、同步资料、打开主页。未传 `about_account`。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/profile/{handle}`

失败回退：`https://api.fxtwitter.com/{handle}`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| handle | string | 是 | 见 2.2，例如 `NASA` 或 `id:11348282` |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| about_account | string | 否 | — | 真值时 `user` 上带 `about_account` |
| aboutAccount | string | 否 | — | 上一参数的别名 |

**响应状态：** `200` / `400` / `404`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| message | string | 如 `OK` |
| user | object | 见 3.1 |

**请求实例**

```http
GET /2/profile/NASA HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA'

# 附带 About Account
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA?about_account=1'
```

**返回实例**

```json
{
  "code": 200,
  "message": "OK",
  "user": {
    "type": "profile",
    "id": "11348282",
    "screen_name": "NASA",
    "name": "NASA",
    "description": "Making the seemingly impossible, possible. ✨",
    "raw_description": { "text": "Making the seemingly impossible, possible. ✨", "facets": [] },
    "avatar_url": "https://pbs.twimg.com/profile_images/1321163587679784960/0ZxKlEKB_normal.jpg",
    "banner_url": "https://pbs.twimg.com/profile_banners/11348282/1775567134",
    "url": "https://x.com/NASA",
    "location": "Pale Blue Dot",
    "website": { "url": "http://www.nasa.gov/", "display_url": "nasa.gov" },
    "followers": 92316091,
    "following": 119,
    "statuses": 74339,
    "media_count": 28078,
    "likes": 16934,
    "protected": false,
    "joined": "Wed Dec 19 20:20:32 +0000 2007",
    "verification": { "verified": true, "verified_at": null, "type": "government" }
  }
}
```

`?about_account=1` 时 `user` 多一段：

```json
"about_account": {
  "location_accurate": true,
  "username_changes": { "count": 0, "last_changed_at": null }
}
```

---

### 5.2 获取用户时间线

**功能说明：** 用户发帖列表。默认不含回复。`with_replies=1` 把回复也算进时间线。`since` 只拉某时刻之后的新帖，适合增量刷新；此时不要带 `cursor`，若没有更新的帖则 **HTTP 204**。

**接入状态：** 已接入 · `XFollowingService.fetchPostsPage` · C 关注主页、关注动态。主页传 `count`、`lang=zh-cn`。动态页第一页传 `since=当天 0 点`（Unix 秒），无新帖按 204 结束；当天帖超过一页时再带 `cursor` 翻页（此时不再带 `since`）。未传 `with_replies` / `groupthreads`。无 `since` 的第一页失败回退 Nitter RSS。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/profile/{handle}/statuses`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| handle | string | 是 | 见 2.2 |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| count | number | 否 | 20 | 每页条数，1–100。应用传 30 |
| cursor | string | 否 | — | 上一页 `cursor.bottom` |
| since | number | 否 | — | Unix 秒；≥ `1e12` 按毫秒。无 `cursor` 时，没有更新的帖返回 204 |
| with_replies | string | 否 | — | 真值则包含回复 |
| groupthreads | string | 否 | — | 真值则 `results` 可能混有 `type: thread` |
| lang | string | 否 | — | 翻译语言，如 `zh-cn` |

**响应状态：** `200` / `204` / `400` / `404` / `500`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| results | array | 帖子列表，元素见 3.2 |
| cursor.top | string | 向上翻页 |
| cursor.bottom | string | 向下翻页 |

**请求实例**

```http
GET /2/profile/NASA/statuses?count=30 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/statuses?count=30'

# 翻页
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/statuses?count=30&cursor=CURSOR_BOTTOM'

# 带回复
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/statuses?count=30&with_replies=1'

# 增量（since 为 Unix 秒）
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/statuses?count=30&since=1710000000'
```

**返回实例**（`results[0]` 完整字段见 3.2，此处只列常用字段）

```json
{
  "code": 200,
  "results": [
    {
      "type": "status",
      "id": "2088354741810016725",
      "url": "https://x.com/NASAAdmin/status/2088354741810016725",
      "text": "We’re going big for America’s 250th. 🇺🇸",
      "created_at": "Fri Aug 14 19:59:04 +0000 2026",
      "created_timestamp": 1786737544,
      "likes": 3067,
      "reposts": 394,
      "quotes": 41,
      "replies": 102,
      "views": 369070,
      "lang": "en",
      "author": { "type": "profile", "screen_name": "NASAAdmin", "name": "NASA Administrator Jared Isaacman" },
      "media": {
        "videos": [
          {
            "type": "video",
            "url": "https://video.twimg.com/amplify_video/2088354592220164096/vid/avc1/1280x720/JNNAMOLs2QTSjlN8.mp4?tag=29",
            "thumbnail_url": "https://pbs.twimg.com/media/HPtTb-BXwAA954N.jpg",
            "duration": 76.676,
            "width": 1280,
            "height": 720
          }
        ]
      }
    }
  ],
  "cursor": { "top": "DAAHCgAB...", "bottom": "DAAHCgAB..." }
}
```

---

### 5.3 获取用户媒体时间线

**功能说明：** 只返回带图片或视频的帖，结构与时间线相同。

**接入状态：** 已接入 · `XFollowingService._fetchMediaPosts` · C 视频（只要视频）、关注图片（只要图）。应用 `count=50`、`lang=zh-cn`。失败时回退 `statuses` 再本地过滤。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/profile/{handle}/media`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| handle | string | 是 | 见 2.2 |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| count | number | 否 | 20 | 1–100。应用传 50 |
| cursor | string | 否 | — | 翻页 |
| lang | string | 否 | — | 翻译语言 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回：** 同 5.2，`results[]` 为 Status。

**请求实例**

```http
GET /2/profile/NASA/media?count=50 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/media?count=50'
```

**返回实例：** 同 5.2。实测一条 NASA 媒体帖 ID `2088355206723477740`。

---

### 5.4 获取关注列表

**功能说明：** 该用户关注了谁。

**接入状态：** 已接入 · `XFollowingService.fetchFollowing` · 主页「关注了 N 个人」。应用 `count=100`，最多连拉 10 页。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/profile/{handle}/following`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| handle | string | 是 | 见 2.2 |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| count | number | 否 | 20 | 1–100。应用传 100 |
| cursor | string | 否 | — | 翻页 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| results | array | 用户列表，元素见 3.1 |
| cursor | object | 翻页 |

**请求实例**

```http
GET /2/profile/NASA/following?count=100 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/following?count=100'
```

**返回实例**

```json
{
  "code": 200,
  "results": [
    {
      "type": "profile",
      "id": "14091091",
      "screen_name": "NASAHubble",
      "name": "Hubble",
      "description": "The official X account for the NASA Hubble Space Telescope…",
      "avatar_url": "https://pbs.twimg.com/profile_images/3468011581/efb985f24af0a814a722457a768f3cc5_normal.jpeg",
      "url": "https://x.com/NASAHubble",
      "followers": 8906708,
      "following": 44,
      "statuses": 8427,
      "protected": false,
      "verification": { "verified": true, "type": "government" }
    }
  ],
  "cursor": {
    "top": "-1|2089189797401722881",
    "bottom": "1597662557210910184|2089189797401722811"
  }
}
```

---

### 5.5 获取粉丝列表

**功能说明：** 谁关注了该用户。请求、参数、返回与 5.4 相同，只改路径。

**接入状态：** 已接入 · `XFollowingService.fetchFollowers` · 主页点「N 关注者」。应用 `count=100`，最多 10 页。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/profile/{handle}/followers`

**路径参数 / 查询参数 / 成功返回：** 同 5.4。

**响应状态：** `200` / `400` / `404` / `500`

**请求实例**

```http
GET /2/profile/NASA/followers?count=100 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/followers?count=100'
```

**返回实例：** `results[]` 为 User，形态同 5.4。

---

### 5.6 获取长文 Articles

**功能说明：** 列出用户发布的 Articles。没有长文时 `results` 为空数组，仍是 `code: 200`。

**接入状态：** 未接入。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/profile/{handle}/articles`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| handle | string | 是 | 见 2.2 |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| count | number | 否 | 20 | 1–100 |
| cursor | string | 否 | — | 翻页 |
| lang | string | 否 | — | 翻译语言 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回：** `{ "code": 200, "results": [ Status ], "cursor": { ... } }`。有内容时帖子上带 `article` 对象（见 3.2）。

**请求实例**

```http
GET /2/profile/NASA/articles?count=20 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/articles?count=20'
```

**返回实例**（NASA 当前无 Articles）

```json
{
  "code": 200,
  "results": [],
  "cursor": { "top": "DAAJAAA", "bottom": "DAABCgABHP5LF4G___4KAAIAAAAAAAAAAAgAAwAAAAIAAA" }
}
```

---

### 5.7 获取 About Account

**功能说明：** 只要账号「关于」统计，不拉完整资料。与 `GET /2/profile/{handle}?about_account=1` 里的 `user.about_account` 是同一份数据。

**接入状态：** 未接入。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/profile/{handle}/about`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| handle | string | 是 | 见 2.2 |

**查询参数：** 无

**响应状态：** `200` / `400` / `404`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| message | string | `OK` |
| about_account | object | 见 3.4 |

**请求实例**

```http
GET /2/profile/NASA/about HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/profile/NASA/about'
```

**返回实例**

```json
{
  "code": 200,
  "message": "OK",
  "about_account": {
    "location_accurate": true,
    "username_changes": { "count": 0, "last_changed_at": null }
  }
}
```

---

## 6. 帖子

路径里的 `{id}` 均为帖子 snowflake，正则 `^\d{2,20}$`。

### 6.1 获取单帖（v2）

**功能说明：** 按 ID 取一条帖。这是正规单帖接口。下载目前仍用 6.6 的 v1（根字段是 `tweet`，转发叫 `retweets`）；升上来应改用本接口（根字段是 `status`，转发叫 `reposts`）。

**接入状态：** 未接入。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/status/{id}`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 帖子数字 ID |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| about_account | string | 否 | — | 真值时作者带 About Account |
| aboutAccount | string | 否 | — | 别名 |
| lang | string | 否 | — | 翻译语言，如 `zh-cn` |

**响应状态：** `200` / `400` / `401` / `404` / `500`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| status | object | 当前帖，见 3.2 |
| author | object | 作者，见 3.1（与 `status.author` 重复一份） |
| thread | array / null | 若属于主题帖，可能带上下文；单帖常为 `null` |

**请求实例**

```http
GET /2/status/2088354741810016725 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/status/2088354741810016725'
```

**返回实例**

```json
{
  "code": 200,
  "status": {
    "type": "status",
    "id": "2088354741810016725",
    "url": "https://x.com/NASAAdmin/status/2088354741810016725",
    "text": "We’re going big for America’s 250th. 🇺🇸\n\nMAX POWER is coming to Florida Nov. 7-8. @NASA …",
    "created_at": "Fri Aug 14 19:59:04 +0000 2026",
    "created_timestamp": 1786737544,
    "likes": 3067,
    "reposts": 394,
    "quotes": 41,
    "replies": 102,
    "bookmarks": 182,
    "views": 369070,
    "lang": "en",
    "source": "Twitter for iPhone",
    "provider": "twitter",
    "embed_card": "player",
    "possibly_sensitive": false,
    "is_note_tweet": true,
    "community_note": null,
    "replying_to": null,
    "reposted_by": null,
    "author": { "type": "profile", "id": "2000593641480605696", "screen_name": "NASAAdmin" },
    "media": {
      "videos": [
        {
          "id": "2088354592220164096",
          "type": "video",
          "url": "https://video.twimg.com/amplify_video/2088354592220164096/vid/avc1/1280x720/JNNAMOLs2QTSjlN8.mp4?tag=29",
          "thumbnail_url": "https://pbs.twimg.com/media/HPtTb-BXwAA954N.jpg",
          "duration": 76.676,
          "width": 1280,
          "height": 720
        }
      ]
    }
  },
  "thread": null,
  "author": { "type": "profile", "id": "2000593641480605696", "screen_name": "NASAAdmin" }
}
```

---

### 6.2 获取主题帖

**功能说明：** 与 6.1 相同，但把同一条长帖 / 主题按顺序放进 `thread`。

**接入状态：** 未接入。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/thread/{id}`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 主题中任意一条帖子 ID |

**查询参数：** 同 6.1（`about_account` / `aboutAccount` / `lang`）。

**响应状态：** `200` / `400` / `401` / `404` / `500`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| status | object | 当前这条，见 3.2 |
| thread | array | 主题里其它帖，元素见 3.2 |
| author | object | 作者，见 3.1 |

**请求实例**

```http
GET /2/thread/2088354741810016725 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/thread/2088354741810016725'
```

**返回实例**

```json
{
  "code": 200,
  "status": { "type": "status", "id": "2088354741810016725", "text": "…" },
  "thread": [
    { "type": "status", "id": "2088354741810016726", "text": "主题下一楼" }
  ],
  "author": { "type": "profile", "screen_name": "NASAAdmin" }
}
```

---

### 6.3 获取帖子评论

**功能说明：** 返回当前帖、完整主题链（会走到根帖），以及别人的回复。回复排序由 `ranking_mode` 决定。

**接入状态：** 已接入 · `XFollowingService.fetchReplies` · 点帖子打开评论。应用传 `ranking_mode=recency`、`lang=zh-cn`。未传 `about_account`。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/conversation/{id}`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 帖子数字 ID |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| ranking_mode | string | 否 | `likes` | `likes` 按赞；`recency` 按时间。应用传 `recency` |
| cursor | string | 否 | — | 回复翻页 |
| about_account | string | 否 | — | 真值时作者带 About Account |
| aboutAccount | string | 否 | — | 别名 |
| lang | string | 否 | — | 翻译语言 |

**响应状态：** `200` / `400` / `401` / `404` / `500`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| status | object | 当前帖，见 3.2 |
| thread | array | 主题链 |
| replies | array | 评论，元素见 3.2 |
| author | object | 作者，见 3.1 |
| cursor.bottom | string | 下一页评论 |

**请求实例**

```http
GET /2/conversation/2088354741810016725?ranking_mode=recency HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/conversation/2088354741810016725?ranking_mode=recency'
```

**返回实例**

```json
{
  "code": 200,
  "status": { "type": "status", "id": "2088354741810016725" },
  "thread": [],
  "replies": [
    {
      "type": "status",
      "id": "2088974796923043995",
      "text": "@NASAAdmin @NASA So proud of NASA…",
      "created_timestamp": 1786800000,
      "author": { "type": "profile", "screen_name": "someone" }
    }
  ],
  "author": { "type": "profile", "screen_name": "NASAAdmin" },
  "cursor": { "bottom": "DAAKCgAB..." }
}
```

---

### 6.4 获取引用列表

**功能说明：** 列出引用该帖的帖（上游搜索算子 `quoted_tweet_id`，走 Latest）。无引用时常见 **404 + 空 `results`**，不是帖子不存在。

**接入状态：** 未接入。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/status/{id}/quotes`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 被引用的帖子 ID |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| count | number | 否 | 20 | 1–100 |
| cursor | string | 否 | — | 翻页 |
| lang | string | 否 | — | 翻译语言 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回：** `{ "code": 200, "results": [ Status ], "cursor": { ... } }`

**请求实例**

```http
GET /2/status/2088354741810016725/quotes?count=20 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/status/2088354741810016725/quotes?count=20'
```

**返回实例（无引用）**

```json
{
  "code": 404,
  "results": [],
  "cursor": { "top": null, "bottom": null }
}
```

**返回实例（有引用时 `results[0]` 形态）**

```json
{
  "code": 200,
  "results": [
    {
      "type": "status",
      "id": "2088899161169006836",
      "text": "https://x.com/NASAAdmin/status/2088354741810016725",
      "author": { "type": "profile", "screen_name": "someone" }
    }
  ],
  "cursor": { "top": "...", "bottom": "..." }
}
```

---

### 6.5 获取转发列表

**功能说明：** 列出转发该帖的用户（不是帖，是 User）。

**接入状态：** 未接入。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/status/{id}/reposts`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 帖子数字 ID |

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| count | number | 否 | 20 | 1–100 |
| cursor | string | 否 | — | 翻页 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回：** `{ "code": 200, "results": [ User ], "cursor": { ... } }`

**请求实例**

```http
GET /2/status/2088354741810016725/reposts?count=20 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/status/2088354741810016725/reposts?count=20'
```

**返回实例**

```json
{
  "code": 200,
  "results": [
    {
      "type": "profile",
      "id": "11348282",
      "screen_name": "NASA",
      "name": "NASA",
      "avatar_url": "https://pbs.twimg.com/profile_images/1321163587679784960/0ZxKlEKB_normal.jpg",
      "followers": 92316095,
      "following": 119,
      "statuses": 74339
    }
  ],
  "cursor": {
    "top": null,
    "bottom": "eyJpZCI6IjIwODgzNTQ3NDE4MTAwMTY3MjUiLCJmbG9ja0N1cnNvciI6IjI1NTQxMDk1NDAiLCJvcmlnaW5hbERpcmVjdGlvbiI6IkRlc2NlbmRpbmcifQ==-999899"
  }
}
```

---

### 6.6 解析单帖（v1，下载在用）

**功能说明：** 旧版单帖。根对象是 `tweet` 不是 `status`；转发字段是 `retweets` 不是 `reposts`。失败再走 8.1 vxTwitter。

**接入状态：** 已接入 · `XVideoService._resolve` · 贴链接下载、C 视频下载。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/status/{id}`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 帖子数字 ID |

**查询参数：** 无

**响应状态：** `200` / `404` 等（v1 未完整写入 OpenAPI）

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| message | string | `OK` |
| tweet | object | 帖子。媒体结构与 3.3 相近 |
| tweet.id | string | 帖子 ID |
| tweet.text | string | 正文 |
| tweet.retweets | number | 转发（v2 叫 `reposts`） |
| tweet.media.videos[].url | string | 视频直链 |
| tweet.media.videos[].formats | array | 多码率 |

**请求实例**

```http
GET /status/2088354741810016725 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/status/2088354741810016725'
```

**返回实例**

```json
{
  "code": 200,
  "message": "OK",
  "tweet": {
    "id": "2088354741810016725",
    "url": "https://x.com/NASAAdmin/status/2088354741810016725",
    "text": "We’re going big for America’s 250th. 🇺🇸",
    "retweets": 394,
    "likes": 3067,
    "created_timestamp": 1786737544,
    "media": {
      "videos": [
        {
          "type": "video",
          "url": "https://video.twimg.com/amplify_video/2088354592220164096/vid/avc1/1280x720/JNNAMOLs2QTSjlN8.mp4?tag=29",
          "thumbnail_url": "https://pbs.twimg.com/media/HPtTb-BXwAA954N.jpg",
          "duration": 76.676,
          "width": 1280,
          "height": 720
        }
      ]
    }
  }
}
```

下载视频文件：

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Referer: https://x.com/' \
  -o video.mp4 \
  'VIDEO_DIRECT_URL'
```

---

## 7. 发现

### 7.1 搜索帖子

**功能说明：** 按关键词、`#话题` 或用户名搜帖。`feed` 对应 Latest / Top / Media。无结果时常见 **404 + 空 `results`**。

**接入状态：** 已接入 · `XFollowingService.searchPosts` · C 热点点击、C 关注 / C 热点顶部「搜索」。应用 `count=30`、`lang=zh-cn`。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/search`

**路径参数：** 无

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| q | string | 是 | — | 非空查询。必须 URL 编码，例如 `#NASA` → `%23NASA` |
| feed | string | 否 | `latest` | `latest` 最新 / `top` 热门 / `media` 媒体 |
| count | number | 否 | 30 | 1–100 |
| cursor | string | 否 | — | 翻页 |
| lang | string | 否 | — | 翻译语言 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回：** 同 5.2，`results[]` 为 Status。

**请求实例**

```http
GET /2/search?q=puppies&feed=latest&count=30 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -G 'https://api.fxtwitter.com/2/search' \
  --data-urlencode 'q=puppies' \
  --data-urlencode 'feed=latest' \
  --data-urlencode 'count=30'

curl -x http://127.0.0.1:7897 \
  -G 'https://api.fxtwitter.com/2/search' \
  --data-urlencode 'q=#NASA' \
  --data-urlencode 'feed=top' \
  --data-urlencode 'count=30'

curl -x http://127.0.0.1:7897 \
  -G 'https://api.fxtwitter.com/2/search' \
  --data-urlencode 'q=NASA' \
  --data-urlencode 'feed=media' \
  --data-urlencode 'count=30'
```

**返回实例**

```json
{
  "code": 200,
  "results": [
    {
      "type": "status",
      "id": "2089189920128774441",
      "url": "https://x.com/WolfprwX/status/2089189920128774441",
      "text": "A woman in Florida who was selling rare and expensive puppies…",
      "created_timestamp": 1786936666,
      "author": { "type": "profile", "screen_name": "WolfprwX", "name": "Wolf" }
    }
  ],
  "cursor": { "top": "DAADDAAB…", "bottom": "DAADDAAB…" }
}
```

---

### 7.2 输入补全

**功能说明：** 按前缀补全用户、话题、事件。适合输入 `@` 时联想用户名。补全里的 User 计数经常是 `0`，不能当正式资料用，点选后再调 5.1。

**接入状态：** 未接入。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/typeahead`

**路径参数：** 无

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| q | string | 是 | — | 前缀，例如 `nas` |
| result_type | string | 否 | `events,users,topics` | 逗号分隔，只要部分就传 `users` 或 `users,topics` |
| src | string | 否 | `search_box` | 上游来源提示 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| query | string | 原查询 |
| num_results | number | 条数 |
| users | array | 用户，结构同 3.1（计数常为 0） |
| topics | array | `{ "topic": "nasa" }` |
| events | array | 事件，可能为空 |

**请求实例**

```http
GET /2/typeahead?q=nas&result_type=users,topics HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -G 'https://api.fxtwitter.com/2/typeahead' \
  --data-urlencode 'q=nas' \
  --data-urlencode 'result_type=users,topics'
```

**返回实例**

```json
{
  "code": 200,
  "query": "nas",
  "num_results": 13,
  "users": [
    {
      "type": "profile",
      "id": "96829836",
      "name": "Nasir Jones",
      "screen_name": "Nas",
      "avatar_url": "https://pbs.twimg.com/profile_images/1296572343527956480/uEnYM6yq_normal.jpg",
      "url": "https://x.com/Nas",
      "followers": 0,
      "following": 0,
      "statuses": 0,
      "verification": { "verified": true, "verified_at": null, "type": "individual" }
    }
  ],
  "topics": [{ "topic": "nasa" }, { "topic": "nasdas" }],
  "events": []
}
```

---

### 7.3 获取全球热点

**功能说明：** 官方 Explore 热点。可替代 trends24 的全球页；其他地区应用仍抓 trends24 HTML。

**接入状态：** 已接入（仅「全球」）· `XTrendsService._fetchFx`。应用 `type=trending`、`count=50`。失败回退 trends24 全球页。

**请求方式：** `GET`

**请求地址：** `https://api.fxtwitter.com/2/trends`

**路径参数：** 无

**查询参数**

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| type | string | 否 | `trending` | 目前只支持 `trending` |
| count | number | 否 | 20 | 最大 50。应用传 50 |

**响应状态：** `200` / `400` / `404` / `500`

**成功返回**

| 字段 | 类型 | 说明 |
|------|------|------|
| code | number | `200` |
| timeline_type | string | 如 `trending` |
| trends | array | 热点 |
| trends[].name | string | 名称或 `#话题` |
| trends[].rank | string / null | 排名，常为 `null` |
| trends[].context | string | 如 `Politics · Trending` |
| cursor | object | 翻页（应用未用） |

**请求实例**

```http
GET /2/trends?type=trending&count=50 HTTP/1.1
Host: api.fxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.fxtwitter.com/2/trends?type=trending&count=50'
```

**返回实例**

```json
{
  "code": 200,
  "timeline_type": "trending",
  "trends": [
    { "name": "Hayden Panettiere", "rank": null, "context": "Entertainment · Trending" },
    { "name": "#Lanterns", "rank": null, "context": "Trending in United States" },
    { "name": "Parallax", "rank": null, "context": "Trending in United States" }
  ],
  "cursor": { "top": "DAAJAAA", "bottom": "DAADCgABHP5LEHs___YPAAIKAAAAAAAA" }
}
```

---

## 8. 备用接口

### 8.1 vxTwitter 单帖

**功能说明：** FxTwitter v1 单帖失败时兜底。

**接入状态：** 已接入 · `XVideoService._resolve`

**请求方式：** `GET`

**请求地址：** `https://api.vxtwitter.com/i/status/{id}`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| id | string | 是 | 帖子数字 ID |

**查询参数：** 无

**请求实例**

```http
GET /i/status/2088354741810016725 HTTP/1.1
Host: api.vxtwitter.com
Accept: application/json
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/json' \
  'https://api.vxtwitter.com/i/status/2088354741810016725'
```

---

### 8.2 Nitter RSS

**功能说明：** `statuses` 第一页失败时拉文字帖。返回 RSS XML，不是 JSON。翻页不再走 RSS。

**接入状态：** 已接入 · `XFollowingService._fetchPostsFromRss`

**请求方式：** `GET`

**请求地址：** `https://nitter.net/{handle}/rss`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| handle | string | 是 | 用户名 |

**查询参数：** 无

**成功返回：** RSS XML，解析 `<item>`。

**请求实例**

```http
GET /NASA/rss HTTP/1.1
Host: nitter.net
Accept: application/rss+xml, text/xml, */*
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: application/rss+xml, text/xml, */*' \
  'https://nitter.net/NASA/rss'
```

---

### 8.3 地区热点 trends24

**功能说明：** 抓 HTML。非「全球」地区用这个；全球接口失败时也用全球页。

**接入状态：** 已接入 · `XTrendsService._fetchTrends24`

**请求方式：** `GET`

**请求地址：** `https://trends24.in/{region}/`

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| region | string | 否 | 空为全球 |

| 地区 | 请求地址 |
|------|----------|
| 全球 | `https://trends24.in/` |
| 美国 | `https://trends24.in/united-states/` |
| 日本 | `https://trends24.in/japan/` |
| 韩国 | `https://trends24.in/south-korea/` |
| 英国 | `https://trends24.in/united-kingdom/` |
| 台湾 | `https://trends24.in/taiwan/` |
| 香港 | `https://trends24.in/hong-kong/` |

**查询参数：** 无

**成功返回：** HTML。应用解析 `.trend-card__list` 里的 `.trend-link`。

**请求实例**

```http
GET /japan/ HTTP/1.1
Host: trends24.in
Accept: text/html,application/xhtml+xml
```

```bash
curl -x http://127.0.0.1:7897 \
  -H 'Accept: text/html,application/xhtml+xml' \
  'https://trends24.in/japan/'
```

---

## 9. 页面与接口对应

| 页面 / 操作 | 请求方式 | 请求地址 | 文档 |
|-------------|----------|----------|------|
| 添加关注、同步资料 | GET | `/2/profile/{handle}` | 5.1 |
| C 关注主页帖子 | GET | `/2/profile/{handle}/statuses` | 5.2 |
| 关注动态 | GET | 对关注名单批量 `statuses?since=当天0点` | 5.2 |
| 关注图片 / C 视频 | GET | `/2/profile/{handle}/media` | 5.3 |
| 关注了谁 | GET | `/2/profile/{handle}/following` | 5.4 |
| 谁关注了他 | GET | `/2/profile/{handle}/followers` | 5.5 |
| 评论 | GET | `/2/conversation/{id}` | 6.3 |
| 搜索 / 点热点 | GET | `/2/search` | 7.1 |
| C 热点 · 全球 | GET | `/2/trends` | 7.3 |
| C 热点 · 其他地区 | GET | `https://trends24.in/{region}/` | 8.3 |
| 贴链接下载 | GET | `/status/{id}`，失败走 vxTwitter | 6.6 / 8.1 |
