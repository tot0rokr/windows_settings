-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

local home = wezterm.home_dir
local sep  = package.config:sub(1,1)  -- 윈도우 '\' / 유닉스 '/'

-- ================================================================
-- SSH 서버 레지스트리
-- 서버를 추가/변경할 때는 이 테이블만 수정하세요. 아래 launch menu
-- 항목은 이 레지스트리로부터 자동 생성됩니다.
--   name : 런처(Ctrl+Shift+Alt+L)에 표시될 라벨
--   host : IP 주소, 호스트명, 또는 ~/.ssh/config 별칭
--   user : (선택) SSH 사용자명. 호스트 별칭에 이미 user가 있으면 생략 가능
--   key  : (선택) 개인키 파일명. $HOME 아래에서 탐색
--   cwd  : (선택, Windows 전용) cmd.exe의 작업 디렉터리
--
-- 새 서버 항목 추가 시 일회성 SSH 키 등록 절차:
--
--   1. Ed25519 키 쌍 생성 (편한 쪽에서 만들면 됨. 최종적으로 개인키는
--      클라이언트에, 공개키는 서버에 있어야 합니다):
--        ssh-keygen -t ed25519 -f <key>.pem -C "<label>"
--      <key>.pem(개인키)과 <key>.pem.pub(공개키)이 생성됩니다.
--
--   2. 공개키를 서버 사용자의 authorized_keys에 등록:
--        ssh-copy-id -i <key>.pem.pub <user>@<host>
--      또는 서버에서 수동으로:
--        mkdir -p ~/.ssh && chmod 700 ~/.ssh
--        cat <key>.pem.pub >> ~/.ssh/authorized_keys
--        chmod 600 ~/.ssh/authorized_keys
--
--   3. 개인키를 Windows 클라이언트의 <cwd>\<key> 경로에 배치.
--      예: C:\Users\MB-PC-24-041\junhovm.pem
--      scp 등 안전한 채널로 전송하세요. 이메일/메신저로는 절대 보내지 말 것.
--
--   4. Windows에서 개인키 ACL을 잠가야 OpenSSH가 거부하지 않습니다
--      (PowerShell):
--        icacls $HOME\<key> /inheritance:r
--        icacls $HOME\<key> /grant:r "$($env:USERNAME):(R)"
--      Unix 동등: chmod 600 <key>
--
--   5. 클라이언트에서 비밀번호 없이 로그인되는지 확인:
--        ssh -i $HOME\<key> <user>@<host>
--      성공하면 아래에서 자동 생성되는 "SSH <name>" / "BTOP on <name>"
--      런처 항목도 그대로 동작합니다.
-- ================================================================
local servers = {
  {
    name = "Junho-VM",
    host = "172.30.100.10",
    user = "junho",
    key  = "junhovm.pem",
    cwd  = [[C:\Users\MB-PC-24-041]],
  },
  {
    name = "gen5-1",
    host = "10.1.1.91",
    user = "junho.lee",
    cwd  = [[C:\Users\MB-PC-24-041]],
  },
  -- Examples:
  -- { name = "Dev",     host = "192.168.0.42", user = "junho" },
  -- { name = "Aliased", host = "my-host-alias-from-ssh-config" },
}

-- Build an `ssh` argv for the given server.
--   key_prefix : path prefix prepended to `server.key` (e.g. ".\\" on Windows,
--                "$HOME/" on Unix). Ignored when the server has no key.
--   remote_cmd : optional command to run on the remote (e.g. "btop").
--                When set, `-t` is added so the remote command gets a TTY.
local function build_ssh_argv(server, key_prefix, remote_cmd)
  local argv = { "ssh" }
  if server.key then
    table.insert(argv, "-i")
    table.insert(argv, (key_prefix or "") .. server.key)
  end
  table.insert(argv, remote_cmd and "-t" or "-Y")
  local target = server.host
  if server.user and server.user ~= "" then
    target = server.user .. "@" .. server.host
  end
  table.insert(argv, target)
  if remote_cmd then
    table.insert(argv, remote_cmd)
  end
  return argv
end

-- Append per-server menu entries (SSH + BTOP) to `menu`.
local function append_server_entries(menu, platform)
  for _, s in ipairs(servers) do
    if platform == "windows" then
      local key_prefix = home .. sep
      local ssh_line  = table.concat(build_ssh_argv(s, key_prefix), " ")
      local btop_line = table.concat(build_ssh_argv(s, key_prefix, "btop"), " ")
      table.insert(menu, {
        label = "SSH " .. s.name,
        args  = { "cmd.exe", "/k", ssh_line },
        cwd   = s.cwd or home,
      })
      table.insert(menu, {
        label = "BTOP on " .. s.name,
        args  = { "cmd.exe", "/k", btop_line },
        cwd   = s.cwd or home,
      })
    else
      local key_prefix = home .. sep
      table.insert(menu, {
        label = "SSH " .. s.name,
        args  = build_ssh_argv(s, key_prefix),
      })
      table.insert(menu, {
        label = "BTOP on " .. s.name,
        args  = build_ssh_argv(s, key_prefix, "btop"),
      })
    end
  end
end

-- This is where you actually apply your config choices.
-- config.default_prog = { "/bin/bash" }
if wezterm.target_triple:find("windows") then
  config.default_prog = { "powershell.exe", "-NoLogo"  }
  config.launch_menu = {
    { label = "PowerShell", args = { "powershell.exe" } },
    { label = "PowerShell 7", args = { "pwsh.exe" } },
    { label = "CMD", args = { "cmd.exe" } },
    -- UAC 프롬프트 → 관리자 cmd.exe가 별도 OS 윈도우로 뜸 (wezterm 탭 안에선 권한 격상 불가)
    { label = "Admin CMD", args = { "powershell.exe", "-NoProfile", "-Command", "Start-Process -Verb RunAs cmd.exe" } },
    { label = "Admin PowerShell", args = { "powershell.exe", "-NoProfile", "-Command", "Start-Process -Verb RunAs powershell.exe" } },
  }
  append_server_entries(config.launch_menu, "windows")

elseif wezterm.target_triple:find("darwin") then
  -- macOS
  config.default_prog = { "/bin/zsh", "-l" }
  config.launch_menu = {
    { label = "zsh (login)", args = { "/bin/zsh", "-l" } },
  }
  append_server_entries(config.launch_menu, "darwin")

elseif wezterm.target_triple:find("linux") then
  -- Linux
  config.default_prog = { "/bin/bash", "-l" }
  config.launch_menu = {
    { label = "bash (login)", args = { "/bin/bash", "-l" } },
  }
  append_server_entries(config.launch_menu, "linux")
end

config.canonicalize_pasted_newlines = "LineFeed"


-- config.ssh_domains = {
--  {
--    name = "dev-server",
--    remote_address = "192.168.0.42",
--    username = "user",
--  },
--}

-- config.audible_bell = "SystemBeep"
-- config.enable_tab_bar = true
-- config.hide_tab_bar_if_only_one_tab = true
-- config.use_fancy_tab_bar = true

config.window_decorations = "RESIZE"
config.scrollback_lines = 10000
config.force_reverse_video_cursor = true


-- 단축키
config.disable_default_key_bindings = true
config.keys = {
    -- 복사: Ctrl+Shift+C
    {
      key = 'C',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.CopyTo 'Clipboard',
    },
    -- 붙여넣기: Ctrl+Shift+V
    {
      key = 'V',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.PasteFrom 'Clipboard',
    },
-- 새 탭: Ctrl+Shift+T
{
  key = 'T',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.SpawnTab 'CurrentPaneDomain',
},

-- 탭 전환 (다음/이전): Ctrl+Tab / Ctrl+Shift+Tab
{
  key = 'Tab',
  mods = 'CTRL',
  action = wezterm.action.ActivateTabRelative(1),
},
{
  key = 'Tab',
  mods = 'CTRL|SHIFT',
  action = wezterm.action.ActivateTabRelative(-1),
},

-- 탭 닫기
{
  key = 'W',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.CloseCurrentTab { confirm = true },
},
-- 전체화면
{
  key = 'Enter',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.ToggleFullScreen,
},
-- 새창
{
  key = 'N',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.SpawnWindow,
},
-- 탭 이동
-- {
--   key = '1',
--   mods = 'CTRL|SHIFT',
--   action = wezterm.action.ActivateTab(0),
-- },
-- {
--   key = '2',
--   mods = 'CTRL|SHIFT',
--   action = wezterm.action.ActivateTab(1),
-- },
-- {
--   key = '3',
--   mods = 'CTRL|SHIFT',
--   action = wezterm.action.ActivateTab(2),
-- },
-- {
--   key = '4',
--   mods = 'CTRL|SHIFT',
--   action = wezterm.action.ActivateTab(3),
-- },
-- Search
{
  key = 'F',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.Search 'CurrentSelectionOrEmptyString',
},
-- 커맨드 선택
{
  key = 'P',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.ActivateCommandPalette,
},
-- 테마 토글
{
  key = 'M',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.EmitEvent 'toggle-theme',
},
-- 배경 화면 토글
    {
      key = 'B',
      mods = 'CTRL|SHIFT|ALT',
      action = wezterm.action.EmitEvent 'toggle-bg',
    },
-- Launch menu
  {
    key = "L",
    mods = "CTRL|SHIFT|ALT",
    action = wezterm.action.ShowLauncher,
  },
-- Font size: Ctrl + (+/-/0)
-- (+)는 키보드 레이아웃에 따라 '=' + SHIFT로 들어가는 경우가 많아서 둘 다 넣어둠
{
  key = '=',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.IncreaseFontSize,
},
{
  key = '-',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.DecreaseFontSize,
},
{
  key = '+',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.IncreaseFontSize,
},
{
  key = '_',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.DecreaseFontSize,
},
{
  key = '0',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.ResetFontSize,
},
{
  key = ')',
  mods = 'CTRL|SHIFT|ALT',
  action = wezterm.action.ResetFontSize,
},
}

config.exit_behavior = "Hold"

config.set_environment_variables = {
  EDITOR = "nvim",
  LANG = "ko_KR.UTF-8",
}



-- For example, changing the initial geometry for new windows:
config.initial_cols = 120
config.initial_rows = 28



config.font = wezterm.font { family = 'D2CodingLigature Nerd Font' }
-- or, changing the font size and color scheme.
config.font_size = 12
-- config.color_scheme = 'BirdsOfParadise'
config.color_scheme = 'BlulocoDark'
-- config.color_scheme = 'Flatland'

-- 테마 토글
wezterm.on('toggle-theme', function(window, pane)
  local overrides = window:get_config_overrides() or {}
  if not overrides.color_scheme then
    overrides.color_scheme = 'Flatland'
  else
    overrides.color_scheme = nil
  end
  window:set_config_overrides(overrides)
end)


config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.8,
}




-- Background
config.window_background_opacity = 0.95
config.text_background_opacity = 0.9

config.enable_scroll_bar = true
-- config.min_scroll_bar_height = '2cell'
config.colors = {
  scrollbar_thumb = 'black',
}

local bg_path = table.concat({ home, "terminal_background.jpg" }, sep)

local background = {
  -- This is the deepest/back-most layer. It will be rendered first
  {
    source = { File = bg_path, },
    -- The texture tiles vertically but not horizontally.
    -- When we repeat it, mirror it so that it appears "more seamless".
    -- An alternative to this is to set `width = "100%"` and have
    -- it stretch across the display
    repeat_x = 'Mirror',
    hsb = {
      brightness = 0.05,
      hue = 1.0,
      saturation = 1.0,
    },
    -- When the viewport scrolls, move this layer 10% of the number of
    -- pixels moved by the main viewport. This makes it appear to be
    -- further behind the text.
    attachment = { Parallax = 0.3 },
  },
  -- Subsequent layers are rendered over the top of each other
  {
    source = {
      File = '/Alien_Ship_bg_vert_images/Overlays/overlay_1_spines.png',
    },
    width = '100%',
    repeat_x = 'NoRepeat',

    -- position the spins starting at the bottom, and repeating every
    -- two screens.
    vertical_align = 'Bottom',
    repeat_y_size = '200%',
    hsb = dimmer,

    -- The parallax factor is higher than the background layer, so this
    -- one will appear to be closer when we scroll
    attachment = { Parallax = 0.2 },
  },
  {
    source = {
      File = '/Alien_Ship_bg_vert_images/Overlays/overlay_2_alienball.png',
    },
    width = '100%',
    repeat_x = 'NoRepeat',

    -- start at 10% of the screen and repeat every 2 screens
    vertical_offset = '10%',
    repeat_y_size = '200%',
    hsb = dimmer,
    attachment = { Parallax = 0.3 },
  },
}

wezterm.on('toggle-bg', function(window, pane)
  local overrides = window:get_config_overrides() or {}

  if overrides.background then
    print("🔄 배경화면 끔")
    overrides.background = nil
  else
    print("🖼️ 배경화면 켬")
    overrides.background = background
  end

  window:set_config_overrides(overrides)
end)

-------------

-- Finally, return the configuration to wezterm:
return config