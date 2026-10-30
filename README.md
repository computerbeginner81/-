# 下班倒计时 · 朋友留言

一个**单文件网页** + **Supabase 免费云数据库**，给站长自己用，也给朋友看：

- 不需要 Python
- 不需要公网 IP、不需要自己买服务器
- 倒计时、作息、日薪：**所有人可读，只有站长可写**
- 朋友留言：不用注册、不用密码，输入 ID 就能互相留句话
- 来访人数按 ID 统计，访客也能看见
- 这不是长期公开的社区，只给朋友之间留言

前端只有 `index.html` 一个文件，可以直接双击打开，也可以上传到 Netlify Drop / GitHub Pages / Cloudflare Pages 得到公开网址。

---

## 一次性设置（约 10 分钟）

### 1. 创建 Supabase 免费项目

打开 [supabase.com](https://supabase.com)，注册并创建一个免费项目，区域选离你近的。

### 2. 建表

1. 在 Supabase 项目中打开 **SQL Editor**。
2. 打开本目录的 `supabase-schema.sql`；站长邮箱已经预填好。
   - 站长公开 ID 固定是「站长」，不需要改。
3. 把整段 SQL 粘贴进 SQL Editor 执行。已经执行过旧版的话，再整段执行一次即可；脚本可以重复跑。这次会补上作息云同步和按 ID 的来访统计。给留言盖章不依赖新表，没执行也能用。

### 3. 创建站长账号

1. 打开 **Authentication → Users → Add user**。
2. 邮箱填 SQL 中预填的站长邮箱，设置一个密码。
3. 勾选 **Auto Confirm User**。
4. 可选：在 Authentication 设置里关闭公开注册（Allow new users to sign up），减少垃圾账号。

普通访客不需要在这里创建账号。

### 4. 填写前端配置

用记事本打开 `index.html`，找到最上面的：

```js
window.OFFWORK_CLOUD = {
  SUPABASE_URL: "",
  SUPABASE_ANON_KEY: ""
};
```

在 Supabase 项目里点右上角的 **Connect**（或 **Settings → API Keys**）：

- `Project URL` → `SUPABASE_URL`
- **Publishable key**（`sb_publishable_...`）→ `SUPABASE_ANON_KEY`
  - 旧项目如果只显示 legacy `anon` key，也可以直接用它。

**不要填 secret key / service_role key。** Publishable / anon key 本来就是公开的，安全由数据库 RLS 规则保证。

站长邮箱只写在 SQL 里，不会出现在网页源码中。

### 5. 打开或发布

- 直接双击 `index.html`：需要联网，Supabase 允许跨域时可以直接用。
- 推荐 [Cloudflare Drop](https://www.cloudflare.com/drop/)：**不用注册**，把 `index.html` 拖进去就能得到一个临时网址（60 分钟）。觉得好用再点 **Claim**，用免费 Cloudflare 账号保留下来。
- 也可以用 [Netlify Drop](https://app.netlify.com/drop)、GitHub Pages 或 Cloudflare Pages。

> **只上传 `index.html` 就够了。** 整个文件夹里还有 SQL 和说明文件，不需要发布到静态网站。

### 6. 站长登录

打开页面 → 页脚「站长入口」→ 输入站长 Supabase 邮箱和密码。

邮箱不会写死在网页里，只有站长验证成功且数据库确认是站长邮箱后，才会显示管理面板。

---

## 使用规则

这个页面服务于站长本人：作息和倒计时由站长设定，打开网页的人都能看到同一套时间。留言只是朋友之间互相留句话，不做成长期公开社区。

### 普通访客

- 不用登录就能看到倒计时、今日薪资和发薪日。不能改作息，也不能换歌。
- 站长放了歌之后，点页面右上角的音符可以播放或暂停。浏览器需要这一次点击才会出声。
- 进入留言区后输入 2–16 位 ID，不需要密码、邮箱或手机号。
- 下次打开页面会记住这个 ID，并按 ID 记一次来访。
- 页面上会显示一共多少个 ID 来过、今天多少人、今天多少条留言。
- 可以发留言，也可以给别人的留言盖章：👍 😂 ☕ 🔥 🎉。没发过言也可以盖章。
- 同一 ID 每次发言至少间隔 5 秒。
- 到下班时间、以及发薪日当天，页面会撒一次彩纸。每人每天各一次。

### 站长

- 修改全站上下班时间、午休、日薪、发薪日和工作日
- 换全站背景音乐：在 Supabase Storage 建一个 Public 桶，上传 mp3，把 Public URL 填进设置
- 删除任意留言
- 置顶 / 取消置顶
- 禁言 / 解除禁言 ID
- 发布 / 清空全站公告
- 站长 ID 被保留，普通访客不能使用

管理权限由 Supabase Auth + RLS 在数据库层执行，不是前端假装隐藏。

---

## 必须知道的限制

1. **只凭 ID 进入，任何人知道你的 ID 都可以用这个 ID 发言。**  
   这是“不需要密码”的代价。站长身份是例外：站长使用 Supabase 邮箱密码，普通访客无法冒充。
2. **普通用户不能删除自己的留言**，只有站长能删。  
   因为 ID 没有密码，无法在数据库层安全地证明“这条留言确实是你发的”。
3. **封禁只能封 ID，不能封设备。**  
   被禁言的人换一个 ID 仍然可以继续发言；这是匿名 ID 模式的边界。
4. **页面只加载最近 100 条留言。**
5. **Supabase 免费项目长时间不使用可能会暂停。**  
   数据一般会保留，重新激活项目即可；如果长期公开使用，建议升级到付费计划或定期访问。
6. 站长邮箱写在 `supabase-schema.sql` 的 `owner_email()` 里，不会出现在网页源码中。建议用一个专门的邮箱。

---

## 安全说明

- Publishable key / anon key 是公开的；secret key / service_role key 绝对不能放进网页。
- 所有写权限由 Postgres RLS 控制：
  - 所有人可读留言、作息和按 ID 汇总的人数
  - 朋友可以发留言、盖章；只有站长可改作息、删除、置顶、禁言、发公告
  - 站长 ID 不能被普通访客使用
- 5 秒发言冷却由数据库触发器执行，换浏览器也不能绕过同一个 ID 的冷却。
- 用户 ID、留言、公告全部按纯文本渲染，避免 XSS。
- 站长密码只存在 Supabase Auth，不写在 HTML 或 SQL 里。

---

## 找不到 Project URL / Publishable key？

Supabase 改版后，**不再叫 `Project Settings → API`**。按下面找：

1. 先在 Dashboard 里点开你的项目（不是组织首页）。
2. 看项目页面右上角，找 **Connect** 按钮。
3. 点开后，弹窗里能看到 **Project URL** 和 **Publishable key**，右侧有复制按钮。
4. 如果找不到 Connect：看左侧栏最下面的 **Settings**（齿轮）→ **API Keys**。
5. 如果你的界面仍显示 **Settings → API**，点它也可以。

要复制的是：

- **Project URL**：`https://xxxx.supabase.co`
- **Publishable key**：`sb_publishable_...`
  - 旧项目只有 **anon** key 时，用 anon 也可以

不要复制 **Secret key** 或 **service_role**。

## 文件

- `index.html`：**唯一需要发布的前端文件**，云配置在文件顶部。
- `supabase-schema.sql`：Supabase 建表 / RLS / 触发器 SQL，只在设置时用一次。
- `README.md`：本说明。
