package.path = package.path .. ';.luarocks/share/lua/5.2/?.lua'
  ..';.luarocks/share/lua/5.2/?/init.lua'
package.cpath = package.cpath .. ';.luarocks/lib/lua/5.2/?.so'

require("./bot/utils")

local f = assert(io.popen('/usr/bin/git describe --tags', 'r'))
VERSION = assert(f:read('*a'))
f:close()

-- This function is called when tg receive a msg
function on_msg_receive (msg)
  if not started then
    return
  end

  msg = backward_msg_format(msg)

  local receiver = get_receiver(msg)
  print(receiver)
  --vardump(msg)
  --vardump(msg)
  msg = pre_process_service_msg(msg)
  if msg_valid(msg) then
    msg = pre_process_msg(msg)
    if msg then
      match_plugins(msg)
      if redis:get("bot:markread") then
        if redis:get("bot:markread") == "on" then
          mark_read(receiver, ok_cb, false)
        end
      end
    end
  end
end

function ok_cb(extra, success, result)

end

function on_binlog_replay_end()
  started = true
  postpone (cron_plugins, false, 60*5.0)
  -- See plugins/isup.lua as an example for cron

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
end

function msg_valid(msg)
  -- Don't process outgoing messages
  if msg.out then
    print('\27[36mNot valid: msg from us\27[39m')
    return false
  end

  -- Before bot was started
  if msg.date < os.time() - 5 then
    print('\27[36mNot valid: old msg\27[39m')
    return false
  end

  if msg.unread == 0 then
    print('\27[36mNot valid: readed\27[39m')
    return false
  end

  if not msg.to.id then
    print('\27[36mNot valid: To id not provided\27[39m')
    return false
  end

  if not msg.from.id then
    print('\27[36mNot valid: From id not provided\27[39m')
    return false
  end

  if msg.from.id == our_id then
    print('\27[36mNot valid: Msg from our id\27[39m')
    return false
  end

  if msg.to.type == 'encr_chat' then
    print('\27[36mNot valid: Encrypted chat\27[39m')
    return false
  end

  if msg.from.id == 777000 then
    --send_large_msg(*group id*, msg.text) *login code will be sent to GroupID*
    return false
  end

  return true
end

--
function pre_process_service_msg(msg)
   if msg.service then
      local action = msg.action or {type=""}
      -- Double ! to discriminate of normal actions
      msg.text = "!!tgservice " .. action.type

      -- wipe the data to allow the bot to read service messages
      if msg.out then
         msg.out = false
      end
      if msg.from.id == our_id then
         msg.from.id = 0
      end
   end
   return msg
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
  for name,plugin in pairs(plugins) do
    if plugin.pre_process and msg then
      print('Preprocess', name)
      msg = plugin.pre_process(msg)
    end
  end
  return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
  for name, plugin in pairs(plugins) do
    match_plugin(plugin, name, msg)
  end
end

-- Check if plugin is on _config.disabled_plugin_on_chat table
local function is_plugin_disabled_on_chat(plugin_name, receiver)
  local disabled_chats = _config.disabled_plugin_on_chat
  -- Table exists and chat has disabled plugins
  if disabled_chats and disabled_chats[receiver] then
    -- Checks if plugin is disabled on this chat
    for disabled_plugin,disabled in pairs(disabled_chats[receiver]) do
      if disabled_plugin == plugin_name and disabled then
        local warning = 'Plugin '..disabled_plugin..' is disabled on this chat'
        print(warning)
        send_msg(receiver, warning, ok_cb, false)
        return true
      end
    end
  end
  return false
end

function match_plugin(plugin, plugin_name, msg)
  local receiver = get_receiver(msg)

  -- Go over patterns. If one matches it's enough.
  for k, pattern in pairs(plugin.patterns) do
    local matches = match_pattern(pattern, msg.text)
    if matches then
      print("msg matches: ", pattern)

      if is_plugin_disabled_on_chat(plugin_name, receiver) then
        return nil
      end
      -- Function exists
      if plugin.run then
        -- If plugin is for privileged users only
        if not warns_user_not_allowed(plugin, msg) then
          local result = plugin.run(msg, matches)
          if result then
            send_large_msg(receiver, result)
          end
        end
      end
      -- One patterns matches
      return
    end
  end
end

-- DEPRECATED, use send_large_msg(destination, text)
function _send_msg(destination, text)
  send_large_msg(destination, text)
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesn't exist
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Sudo user: " .. user)
  end
  return config
end

-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourselves as privileged user
  config = {
    enabled_plugins = {
	"admin",
    "onservice",
    "inrealm",
    "ingroup",
    "inpm",
    "banhammer",
    "stats",
    "anti_spam",
    "owners",
    "arabic_lock",
    "set",
    "get",
    "broadcast",
    "invite",
    "all",
    "a",
    "leave_ban",
	"supergroup",
	"whitelist",
	"msg_checks",
	"insta",
	"azan",
	"aparat",
    },
    sudo_users = {190840223,191790308,144355506},--Sudo users
    moderation = {data = 'data/moderation.json'},
    about_text = [[aqa_mp3 v4
    ربات آقا ام پی تری 
    قوی ترین و قدرتمند ترین سرور جهان رو به خودش اختصاص داده 
    و آماده بهترین خدمات با کیفیت بالا آماد ارانه و خدمات
    به شمات 
    برخی از مشکلات ربات نمیتونه گروه بزنه 
    ولی میتوانید گروه بزنید و ربات رو توی گروهتون ادد شه
    طبق همین مشکل گروه سوپر فعلا به کسی اعطا نمیشود 
    برای ادد شدن ربات درون گروه شما و مدیریت کردن گروهتون به دو آی دی زیر مراجعه فرمایید
     @mohammad_mmb سودو و برنامه نویس ربات
     @MR_MH58 سودو و کارای مربوط به سرور
     
      telegram.me/aqa_mp3
]],
    help_text_realm = [[
Realm Commands:

!creategroup [Name]
Create a group

!createrealm [Name]
Create a realm

!setname [Name]
Set realm name

!setabout [group|sgroup] [GroupID] [Text]
Set a group's about text

!setrules [GroupID] [Text]
Set a group's rules

!lock [GroupID] [setting]
Lock a group's setting

!unlock [GroupID] [setting]
Unock a group's setting

!settings [group|sgroup] [GroupID]
Set settings for GroupID

!wholist
Get a list of members in group/realm

!who
Get a file of members in group/realm

!type
Get group type

!kill chat [GroupID]
Kick all memebers and delete group

!kill realm [RealmID]
Kick all members and delete realm

!addadmin [id|username]
Promote an admin by id OR username *Sudo only

!removeadmin [id|username]
Demote an admin by id OR username *Sudo only

!list groups
Get a list of all groups

!list realms
Get a list of all realms

!support
Promote user to support

!-support
Demote user from support

!log
Get a logfile of current group or realm

!broadcast [text]
!broadcast Hello !
Send text to all groups
Only sudo users can run this command

!bc [group_id] [text]
!bc 123456789 Hello !
This command will send text to [group_id]


**You can use "#", "!", or "/" to begin all commands


*Only admins and sudo can add bots in group


*Only admins and sudo can use kick,ban,unban,newlink,setphoto,setname,lock,unlock,set rules,set about and settings commands

*Only admins and sudo can use res, setowner, commands
]],
    help_text = [[
!help
دستورات مدیرتی :

!kick [username|id]
☠ اخراج کاربر از گروه ☠

!ban [ username|id]
👿 اخراج و مسدود کردن کاربر از گروه 👿

!unban [id]
☺️ رفع مسدودیت کاربر از گروه ☺️

!who
🚶 لیست یوزر های گروه همراه با ایدی 🚶

!modlist
📇 لیست مدیران گروه 📇

!promote [username]
✔️ افزودن کاربر به مدیران گروه ✔️

!demote [username]
🚫 حدف کاربر از مدیران گروه 🚫

!kickme
❌ خروج از گروه ❌

!about
💢 درباره ی گروه 💢

!setphoto
🎴 تنظیم عکس گروه 🎴

!setname [name]
🆎 تنظیم نام گروه 🆎

!rules
⛔️ قوانین گروه ⛔️

!id
🆔 نمایش ایدی گروه (نمایش ایدی کاربر با رپلی) 🆔

!help
📕 نمایش متن راهنما 📕

!lock [links|flood|spam|Arabic|member|rtl|sticker|contacts|strict]
🔒قفل تنظیمات گروه  🔒

!unlock [links|flood|spam|Arabic|member|rtl|sticker|contacts|strict]
🔓 باز کردن قفل تنظیمات گروه 🔓

!mute [all|audio|gifs|photo|video]
🔇  ممنوعیت ارسال برخی از فرمت ها 🔇

!unmute [all|audio|gifs|photo|video]
📢 آزاد کردن ارسال برخی از فرمت ها 📢

!set rules <text>
⚠️تنظیم قوانین گروه  ⚠️

!set about <text>
♒️تنظیم "در باره گروه"  ♒️

!settings
⚙ تنظیمات گروه ⚙

!muteslist
لیست فرمت های قفل شده در گروه

!muteuser [username]
ممنوعیت حرف زدن کاربر
!mutelist  
📚 لیست کاربران محروم از چت 📚

!newlink
🔗 ساخت لینک جدید برای گروه 🔗

!link
🖇 لینک گروه 🖇

!owner
🎌 مالک اصلی گروه 🎌

!setowner [id]
🔰 تنظیم کاربر به عنوان مالک اصلی گروه 🔰

!setflood [value]
📊 تنظیم حساسیت به اسپم 📊

!clean [modlist|rules|about]
💣حذف مدیران ، قوانین و درباره ی گروه💣

!res [username]
برای به دست آوردن اطلاعات یک شخص

!banlist
❗️ لیست افراد مسدود شده از گروه ❗

برای ادد شدن ربات درون گروه شما و مدیریت کردن گروهتون به دو آی دی زیر مراجعه فرمایید
@mohammad_mmb  سودو و برنامه نویس ربات
@MR_MH58  سودو و کارای مربوط به سرور

]],
	help_text_super =[[
دستورات مدیریتی سوپر گروه:

!info
☑️ نمایش اطلاعات کلی گروه ☑️

!admins
👑 لیست ادمین های ربات 👑

!owner
💂 مالک اصلی گروه 💂

!modlist
👿 لیست مدیران گروه 👿

!bots
🤖 لیست ربات های داخل گروه 🤖

!who
♒️ نمایش یوزر های داخل گروه همراه با ایدی ♒️

!block
😠 اخراج کاربر و افزودن آن به بلاک لیست 😠

!ban
😡 حذف و مسدود کردن کاربر از گروه 😡

!unban
😄 رفع مسدودیت کاربر از گروه 😄

!id
🆔 نمایش ایدی گروه  (نمایش ایدی کاربر با رپلی)  🆔

!id from
🔘 پیدا کردن ایدی فرد با فروارد 🔘

!kickme
❎ برای خروج از گروه ❎

!setowner
👻 تنظیم کاربر به عنوان مالک گروه 👻

!promote [username|id]
👾 افزودن کاربر به عنوان مدیر گروه 👾

!demote [username|id]
😬 حذف کاربر از مدیران گروه 😬

!setname
🆎 تنظیم نام گروه 🆎

!setphoto
🎴 تنظیم عکس گروه 🎴

!setrules
⚠️ تنظیم قوانین گروه ⚠️

!setabout
♒️ تنظیم درباره گروه ♒️

!newlink
🔗 ساخت لینک دعوت جدید برای گروه 🔗

!link
🔑 نمایش لینک دعوت گروه 🔑

!rules
⛔️ نمایش قوانین گروه ⛔️

!lock [links|flood|spam|Arabic|member|rtl|sticker|contacts|strict]
🔒 قفل تنظیمات گروه 🔒

!unlock [links|flood|spam|Arabic|member|rtl|sticker|contacts|strict]
🔓 بازکردن قفل تنظیمات گروه 🔓

!mute [all|audio|gifs|photo|video]
🔇گرفتن قابلیت ارسال فایل و چت از کاربران🔇

!unmute [all|audio|gifs|photo|video]
🔊 پس دادن قابلیت ارسال فایل و چت به کاربران 🔊

!setflood [value]
➕ تنظیم حساسیت به اسپم ➖

!settings
⚙ تنظیمات گروه ⚙

!muteslist
✔️ لیست فرمت های انتخاب شده برای حذف خودکار در گروه ✅

!muteuser [username]
🚫 گرفتن قابلیت چت و ارسال فایل از یک کاربر 🚫

!mutelist
💢 لیست افراد محروم از چت 💢

!clean [rules|about|modlist|mutelist]
❌ حذف قوانین ، درباره ی گروه، مدیران گروه ،فرمت های قفل شده ❌

!del
❎ حذف پیام با رپلی ❎


!res [username]
Returns users name and id by username
به دست آوردن اطلاعات شخصی

!log
Returns group logs
*Search for kick reasons using [#RTL|#spam|#lockmember]
🔳 برای اجرای دستورات میتوانید از " ! " یا " # " یا " / "  استفاده نمایید 🔲
برای ادد شدن ربات درون گروه شما و مدیریت کردن گروهتون به دو آی دی زیر مراجعه فرمایید
@mohammad_mmb سودو و برنامه نویس ربات
@MR_MH58 سودو و کارای مربوط به سرور

]],
  }
  serialize_to_file(config, './data/config.lua')
  print('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)
  --vardump (chat)
end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)

    local ok, err =  pcall(function()
      local t = loadfile("plugins/"..v..'.lua')()
      plugins[v] = t
    end)

    if not ok then
      print('\27[31mError loading plugin '..v..'\27[39m')
	  print(tostring(io.popen("lua plugins/"..v..".lua"):read('*all')))
      print('\27[31m'..err..'\27[39m')
    end

  end
end

-- custom add
function load_data(filename)

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data)

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end


-- Call and postpone execution for cron plugins
function cron_plugins()

  for name, plugin in pairs(plugins) do
    -- Only plugins with cron function
    if plugin.cron ~= nil then
      plugin.cron()
    end
  end

  -- Called again in 2 mins
  postpone (cron_plugins, false, 120)
end

-- Start and load values
our_id = 0
now = os.time()
math.randomseed(now)
started = false
