local hook = hook
local bit = bit
local math = math

local Color = Color
local ipairs = ipairs
local RealFrameTime = RealFrameTime

local color_white = color_white
local color_black = color_black

local sui = sui

local isfunction = sui.isfunction
local isstring = sui.isstring

local floor = math.floor
local Material = Material

function sui.scale(v)
	return ScrH() * (v / 900)
end

function sui.hex_rgb(hex)
	hex = tonumber(hex:gsub("^([%w])([%w])([%w])$", "%1%1%2%2%3%3", 1), 16)

	return Color(
		bit.band(bit.rshift(hex, 16), 0xFF),
		bit.band(bit.rshift(hex, 8), 0xFF),
		bit.band(hex, 0xFF)
	)
end

function sui.rgb_hex(c)
	return bit.tohex((c.r * 0x10000) + (c.g * 0x100) + c.b, 6)
end

local rgb_hex = sui.rgb_hex

function sui.lerp_color(from, to)
	local frac = RealFrameTime() * 10
	from.r = Lerp(frac, from.r, to.r)
	from.g = Lerp(frac, from.g, to.g)
	from.b = Lerp(frac, from.b, to.b)
	from.a = Lerp(frac, from.a, to.a)
end

do
	local colors = {
		["41b9ff"] = Color(44, 62, 80),
		["00c853"] = Color(44, 62, 80),
		["181818"] = Color(242, 241, 239),
		["212121"] = Color(242, 241, 239),
	}

	function sui.contrast_color(color)
		local c = colors[rgb_hex(color)]
		if c then return c end

		local luminance = (0.299 * color.r + 0.587 * color.g + 0.114 * color.b) / 255
		return luminance > 0.5 and color_black or color_white
	end
end

do
	local SetDrawColor = surface.SetDrawColor
	local SetMaterial = surface.SetMaterial
	local DrawTexturedRectRotated = surface.DrawTexturedRectRotated
	function sui.draw_material(mat, x, y, size, col, rot)
		SetDrawColor(col)

		if x == -1 then
			x = size / 2
		end

		if y == -1 then
			y = size / 2
		end

		if mat then
			SetMaterial(mat)
		end

		DrawTexturedRectRotated(x, y, size, size, rot or 0)
	end
end

do
	local hsv_t = {
		[0] = function(v, p, q, t)
			return v, t, p
		end,
		[1] = function(v, p, q, t)
			return q, v, p
		end,
		[2] = function(v, p, q, t)
			return p, v, t
		end,
		[3] = function(v, p, q, t)
			return p, q, v
		end,
		[4] = function(v, p, q, t)
			return t, p, v
		end,
		[5] = function(v, p, q, t)
			return v, p, q
		end
	}

	function sui.hsv_to_rgb(h, s, v)
		local i = floor(h * 6)
		local f = h * 6 - i

		return hsv_t[i % 6](
			v * 255,             -- v
			(v * (1 - s)) * 255, -- p
			(v * (1 - f * s)) * 255, -- q
			(v * (1 - (1 - f) * s)) * 255 -- t
		)
	end
end

local Panel = FindMetaTable("Panel")
local SetSize = Panel.SetSize
local GetWide = Panel.GetWide
local GetTall = Panel.GetTall
function sui.scaling_functions(panel)
	local scale_changed
	local SUI = CURRENT_SUI

	local dock_top = function(s, h)
		if not h then return end

		if not scale_changed then
			s.real_h = h
		end

		if not s.no_scale then
			h = SUI.Scale(h)
		end

		if GetTall(s) == h then return end

		SetSize(s, GetWide(s), h)
	end

	local dock_right = function(s, w)
		if not w then return end

		if not scale_changed then
			s.real_w = w
		end

		if not s.no_scale then
			w = SUI.Scale(w)
		end

		if GetWide(s) == w then return end

		SetSize(s, w, GetTall(s))
	end

	local size_changed = function(s, w, h)
		if s.using_scale then return end

		s.using_scale = true

		local dock = s:GetDock()

		if dock ~= FILL then
			if dock == NODOCK then
				dock_top(s, h)
				dock_right(s, w)
			elseif dock == TOP or dock == BOTTOM then
				dock_top(s, h)
			else
				dock_right(s, w)
			end
		end

		s.using_scale = nil
	end

	local wide_changed = function(s, w)
		size_changed(s, w)
	end

	local tall_changed = function(s, h)
		size_changed(s, nil, h)
	end

	function panel:ScaleChanged()
		scale_changed = true
		size_changed(self, self.real_w, self.real_h)
		scale_changed = nil
		if self.OnScaleChange then
			self:OnScaleChange()
		end
	end

	local on_remove = function(s)
		SUI.RemoveScaleHook(s)
	end

	function panel:ScaleInit()
		self.SetSize = size_changed
		self.SetWide = wide_changed
		self.SetTall = tall_changed
		SUI.OnScaleChanged(self, self.ScaleChanged)
		self:On("OnRemove", on_remove)
	end
end

do
	local utf8 = {}

	do
		---@format disable
    local string=string;local a=string.sub;local b=string.char;local c=string.byte;local d,e,f,g,h=bit.bor,bit.band,bit.lshift,bit.rshift,bit.bnot;local i=table.concat;utf8={}local j=0x80;local k=0xFFFD;local l=0x80;local m=0xBF;local n=0x3F;local o=0x1F;local p=0x0F;local q=0x07;local r=0xF1;local s=0xF0;local t=0x02;local u=0x13;local v=0x03;local w=0x23;local x=0x34;local y=0x04;local z=0x44;local A={s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,s,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,r,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,t,u,v,v,v,v,v,v,v,v,v,v,v,v,w,v,v,x,y,y,y,z,r,r,r,r,r,r,r,r,r,r,r}local B={{l,m},{0xA0,m},{l,0x9F},{0x90,m},{l,0x8F}}function utf8.decode(C,D)D=D or 1;local E=#C;if D<1 or D>E then return k,0 end;if E-D+1<1 then return k,0 end;local F,G,H,I=c(C,D,D+3)local J=A[F+1]if J>=s then local K=g(f(J,31),31)return d(e(F,h(K)),e(0xFFFD,K)),1 end;local L=e(J,7)local M=B[g(J,4)+1]if E-D+1<L then return k,1 end;if G<M[1]or M[2]<G then return k,1 end;if L<=2 then return d(f(e(F,o),6),e(G,n)),2 end;if H<l or m<H then return k,1 end;if L<=3 then return d(d(f(e(F,p),12),f(e(G,n),6)),e(H,n)),3 end;if I<l or m<I then return k,1 end;return d(d(d(f(e(F,q),18),f(e(G,n),12)),f(e(H,n),6)),e(I,n)),4 end;local N=utf8.decode;function utf8.width(C,D)local E=#C;if D<1 or D>E then return 0 end;if E-D+1<1 then return 0 end;local F,G,H,I=c(C,D,D+3)local J=A[F+1]if J>=s then return 1 end;local L=e(J,7)local M=B[g(J,4)+1]if E-D+1<L then return 1 end;if G<M[1]or M[2]<G then return 1 end;if L<=2 then return 2 end;if H<l or m<H then return 1 end;if L<=3 then return 3 end;if I<l or m<I then return 1 end;return 4 end;local O=utf8.width;local function P(Q)if Q<=0x7F then return b(Q)elseif Q<=0x7FF then return b(d(0xC0,g(Q,6)),d(0x80,e(Q,n)))elseif Q<=0xFFFF then return b(d(0xE0,g(Q,12)),d(0x80,e(g(Q,6),n)),d(0x80,e(Q,n)))elseif Q<=0x10FFFF then return b(d(0xF0,g(Q,18)),d(0x80,e(g(Q,12),n)),d(0x80,e(g(Q,6),n)),d(0x80,e(Q,n)))end;return P(k)end;function utf8.sub(C,R,S)local T=#C;S=S or-1;local U=0;local V=0;if R<0 or S<0 then local W=0;local D=1;while true do local X=O(C,D)if X==0 then break end;D=D+X;W=W+1 end;if R<0 then U=W+R+1 else U=R end;if S<0 then V=W+S+1 else V=S end else U,V=R,S end;if U>V or U<1 then return""end;local Y=0;local D=1;local Z=-1;local _=T;while true do Y=Y+1;local X=O(C,D)if X==0 then break end;if Y==U then Z=D end;if Y==V then _=D+X-1;break end;D=D+X end;if Z==-1 then return""end;return a(C,Z,_)end;function utf8.len(C)local a0,D=0,1;while true do local X=O(C,D)if X==0 then return a0 end;D=D+X;a0=a0+1 end end;local a1,a2={},0;local function a3(C)a2=0;local D=1;while true do local a4,a5=N(C,D)if a5==0 then return end;local a6=P(a4)a2=a2+1;a1[a2]=a6;D=D+a5 end end;function utf8.force(C)a3(C)local a7=i(a1,"",1,a2)return a7,a2 end;function utf8.to_table(C)a1={}a3(C)local a7=a1;a1={}return a7,a2 end
	end

	sui.utf8 = utf8
end

--
-- thanks falco!
-- https://github.com/FPtje/DarkRP/blob/4fd2c3c315427e79bb7624702cfaefe9ad26ac7e/gamemode/modules/base/cl_util.lua#L42
--
do
	local surface = surface

	function sui.wrap_text(text, font, max_width, last_width, max_lines)
		local utf8_text = sui.utf8.to_table(text)
		local original_max_width = max_width
		max_width = last_width or max_width
		max_lines = max_lines or math.huge

		surface.SetFont(font)
		local _, newline_height = surface.GetTextSize("W")

		local output = ""
		local current_line_width = 0
		local total_height = newline_height

		for i = 1, #utf8_text do
			local char = utf8_text[i]
			local char_width = surface.GetTextSize(char)

			-- Check if we need to wrap or add newline
			local should_wrap = char == "\n" or current_line_width + char_width > max_width

			if should_wrap then
				-- Check if we exceeded max lines
				if total_height + newline_height > max_lines * newline_height then
					local ellipsis_width = surface.GetTextSize("...")

					-- Trim characters until we can fit the ellipsis
					while current_line_width + ellipsis_width > max_width do
						output = output:sub(1, -2)
						current_line_width = current_line_width - char_width
					end

					output = output .. "..."
					break
				end

				output = output .. "\n"
				current_line_width = char_width
				max_width = original_max_width
				total_height = total_height + newline_height

				-- Skip adding the character if it's a newline
				if char == "\n" then
					goto _continue_
				end
			else
				current_line_width = current_line_width + char_width
			end

			output = output .. char
			::_continue_::
		end

		return output, total_height
	end
end

function sui.register(classname, panel_table, parent_class)
	sui.TDLib.Install(panel_table)

	if not panel_table.Add then
		function panel_table:Add(pnl)
			return vgui.Create(pnl, self)
		end
	end

	if not panel_table.NoOverrideClear and not panel_table.Clear then
		function panel_table:Clear()
			local children = self:GetChildren()
			for i = 1, #children do
				children[i]:Remove()
			end
		end
	end

	local SUI = CURRENT_SUI

	for k, v in pairs(SUI.panels_funcs) do
		panel_table[k] = v
	end

	panel_table.SUI_GetColor = function(name)
		return SUI.GetColor(name)
	end

	SUI.panels[classname] = panel_table

	return vgui.Register(SUI.name .. "." .. classname, panel_table, parent_class)
end

local function prepare_theme(theme)
	for k, v in pairs(theme) do
		if IsColor(v) then continue end

		if istable(v) then
			prepare_theme(v)
		elseif isstring(v) and v:sub(1, 1) == "#" then
			theme[k] = sui.hex_rgb(v:sub(2))
		end
	end
end

function sui.new(addon_name, default_scaling, panels_funcs)
	local SUI = {
		name = addon_name,
		panels = {},
		panels_funcs = panels_funcs or {}
	}

	CURRENT_SUI = SUI

	do
		local themes = table.Copy(sui.themes)
		local current_theme_table

		function SUI.GetColor(color_name)
			return current_theme_table[color_name]
		end

		function SUI.SetTheme(theme_name)
			SUI.current_theme = theme_name
			current_theme_table = themes[theme_name]
			hook.Call(addon_name .. ".ThemeChanged")
		end

		function SUI.GetThemes()
			return themes
		end

		function SUI.AddToTheme(theme_name, tbl)
			local theme = themes[theme_name]
			for k, v in pairs(tbl) do
				theme[k] = v
			end
			prepare_theme(theme)
		end

		function SUI.RemoveTheme(theme_name)
			themes[theme_name] = nil
			if theme_name == SUI.current_theme then
				SUI.SetTheme(next(themes))
			end
		end

		function SUI.AddTheme(theme_name, tbl)
			prepare_theme(tbl)
			themes[theme_name] = tbl
		end

		SUI.themes = themes
	end

	local Scale
	do
		local scale = 1

		if default_scaling then
			SUI.Scale = sui.scale
		else
			function SUI.Scale(v)
				return floor((v * scale) + 0.5)
			end
		end
		Scale = SUI.Scale

		function SUI.ScaleEven(v)
			v = Scale(v)
			if v % 2 ~= 0 then
				v = v + 1
			end
			return v
		end

		function SUI.SetScale(_scale)
			if _scale == scale then return end

			scale = _scale
			SUI.scale = _scale

			for k, v in pairs(SUI.fonts) do
				SUI.CreateFont(k:sub(#addon_name + 1), v.font, v.size, v.weight)
			end

			SUI.CallScaleChanged()
		end

		local n = 0
		local keys = {}
		local hooks = {}
		_G[addon_name .. "_HOOKS"] = keys
		_G[addon_name .. "_KEYS"] = hooks
		_G[addon_name .. "_N"] = function()
			return n
		end
		function SUI.OnScaleChanged(name, func)
			if not isfunction(func) then
				error("Invalid function?")
			end

			if not name then
				error("Invalid name?")
			end

			if not isstring(name) then
				local _func = func
				func = function()
					local isvalid = name.IsValid
					if isvalid and isvalid(name) then
						_func(name)
					else
						SUI.RemoveScaleHook(name, true)
					end
				end
			end

			local pos = keys[name]
			if pos then
				hooks[pos + 1] = func
			else
				hooks[n + 1] = name
				hooks[n + 2] = func
				keys[name] = n + 1
				n = n + 2
			end
		end

		function SUI.RemoveScaleHook(name, in_hook)
			local pos = keys[name]
			if not pos then return end

			if in_hook then
				hooks[pos] = nil
				hooks[pos + 1] = nil
			else
				local new_name = hooks[n - 1]
				if new_name then
					hooks[pos], hooks[pos + 1] = new_name, hooks[n]
					hooks[n - 1], hooks[n] = nil, nil
					keys[new_name] = pos
				end
				n = n - 2
			end
			keys[name] = nil
		end

		function SUI.CallScaleChanged()
			if n == 0 then return end

			local i, c_n = 2, n
			::loop::
			local func = hooks[i]
			if func then
				func()
				i = i + 2
			else
				local _n, _i = c_n, i
				if n ~= c_n then
					_n = n
					i = i + 2
				else
					c_n = c_n - 2
				end

				local new_name = hooks[_n - 1]
				if new_name then
					hooks[_i - 1], hooks[_i] = new_name, hooks[_n]
					hooks[_n - 1], hooks[_n] = nil, nil
					keys[new_name] = _i - 1
				end

				n = n - 2
			end

			if i <= c_n then
				goto loop
			end
		end

		function SUI.GetScale()
			return scale
		end

		SUI.scale = 1
	end

	do
		local fonts = {}

		function SUI.CreateFont(font_name, font, size, weight)
			font_name = addon_name .. font_name

			fonts[font_name] = fonts[font_name] or {
				font = font,
				size = size,
				weight = weight
			}

			surface.CreateFont(font_name, {
				font = font,
				size = Scale(size),
				weight = weight,
				extended = true
			})

			return font_name
		end

		function SUI.GetFont(font_name)
			return addon_name .. font_name
		end

		function SUI.GetFontHeight(font_name)
			local font = fonts[addon_name .. font_name] or fonts[font_name]
			if not font then return 0 end

			return floor(Scale(font.size or 0))
		end

		SUI.fonts = fonts
	end

	do
		local materials = {}

		local delay = 0.008
		local next_run = UnPredictedCurTime()

		function SUI.Material(mat, allow_delay, opts)
			local _mat = materials[mat]
			if _mat then return _mat end

			if allow_delay then
				if UnPredictedCurTime() < next_run then return end
				next_run = UnPredictedCurTime() + delay
			end

			materials[mat] = Material(mat, opts or "mips smooth")

			return materials[mat]
		end

		SUI.materials = materials
	end

	SUI.SetTheme("Dark")

	for _, f in ipairs(file.Find("sui/vgui/sui_*.lua", "LUA")) do
		include("sui/vgui/" .. f)
	end

	for _, f in ipairs(file.Find(string.format("sui/vgui/%s_*.lua", addon_name:lower()), "LUA")) do
		include("sui/vgui/" .. f)
	end

	return SUI
end

sui.themes = sui.themes or {}
function sui.add_theme(name, tbl)
	prepare_theme(tbl)
	sui.themes[name] = tbl
end

function sui.valid_options()
	local objs = {}
	objs.IsValid = function()
		local valid = true
		for i = 1, #objs do
			local obj = objs[i]
			if obj:IsValid() and obj.valid == false then
				valid = false
				break
			end
		end
		return valid
	end
	objs.Add = function(obj)
		table.insert(objs, obj)
	end
	return objs
end

do
	local surface_SetFont = surface.SetFont
	local surface_GetTextSize = surface.GetTextSize
	function sui.get_text_size(text, font)
		surface_SetFont(font)
		return surface_GetTextSize(text)
	end
end

do
	local SURFACE = Color(31, 31, 31)
	local PRIMARY = Color(65, 185, 255)

	local ON_SURFACE = Color(255, 255, 255)
	local ON_SURFACE_HIGH_EMPHASIS = ColorAlpha(ON_SURFACE, 221)
	local ON_SURFACE_MEDIUM_EMPHASIS = ColorAlpha(ON_SURFACE, 122)
	local ON_SURFACE_DISABLED = ColorAlpha(ON_SURFACE, 97)

	local ON_PRIMARY = Color(60, 60, 60)

	sui.add_theme("Dark", {
		frame = Color(18, 18, 18),
		frame_blur = false,

		title = ON_SURFACE,
		header = SURFACE,

		close = ON_SURFACE_MEDIUM_EMPHASIS,
		close_hover = Color(255, 60, 60),
		close_press = Color(255, 255, 255, 30),

		button = PRIMARY,
		button_text = "#050709",
		button_hover = ColorAlpha(ON_PRIMARY, 100),
		button_click = ColorAlpha(ON_PRIMARY, 240),
		button_disabled = Color(100, 100, 100),
		button_disabled_text = "#bdbdbd",

		button2_hover = ColorAlpha(PRIMARY, 5),
		button2_selected = ColorAlpha(PRIMARY, 15),

		scroll = ColorAlpha(PRIMARY, 97),
		scroll_grip = PRIMARY,

		scroll_panel = Color(29, 29, 29),
		scroll_panel_outline = false,

		text_entry_bg = Color(34, 34, 34),
		text_entry_bar_color = Color(0, 0, 0, 0),
		text_entry = ON_SURFACE_HIGH_EMPHASIS,
		text_entry_2 = ON_SURFACE_MEDIUM_EMPHASIS,
		text_entry_3 = PRIMARY,

		property_sheet_bg = Color(39, 39, 39),
		property_sheet_tab = Color(150, 150, 150),
		property_sheet_tab_click = Color(255, 255, 255, 30),
		property_sheet_tab_active = PRIMARY,

		toggle_button = ON_SURFACE_DISABLED,
		toggle_button_switch = ON_SURFACE_HIGH_EMPHASIS,

		toggle_button_active = ColorAlpha(PRIMARY, 65),
		toggle_button_switch_active = PRIMARY,

		slider_knob = PRIMARY,
		slider_track = ColorAlpha(PRIMARY, 65),
		slider_hover = ColorAlpha(PRIMARY, 5),
		slider_pressed = ColorAlpha(PRIMARY, 30),

		on_sheet = Color(43, 43, 43, 200),
		on_sheet_hover = Color(200, 200, 200, 20),

		--=--
		query_box_bg = "#181818",
		query_box_cancel = Color(244, 67, 54, 30),
		query_box_cancel_text = "#f44336",
		--=--

		--=--
		menu = "#212121",

		menu_option = "#212121",
		menu_option_text = "#bdbdbd",
		menu_option_hover = "#3b3b3b",
		menu_option_hover_text = "#fefefe",

		menu_spacer = "#303030",
		--=--

		line = "#303030",

		--=--
		column_sheet = "#263238",
		column_sheet_bar = "#202020",

		column_sheet_tab = "#202020",
		column_sheet_tab_hover = "#2e2e2e",
		column_sheet_tab_active = "#383838",

		column_sheet_tab_icon = "#909090",
		column_sheet_tab_icon_hover = "#f0f0f0",
		column_sheet_tab_icon_active = "#34a1e0",
		--=--

		--=--
		collapse_category_header = "#272727",
		collapse_category_header_hover = "#2a2a2a",
		collapse_category_header_active = "#2e2e2e",

		collapse_category_header_text = "#aaaaaa",
		collapse_category_header_text_hover = "#dcdcdc",
		collapse_category_header_text_active = "#34A1E0",

		collapse_category_item = "#343434",
		collapse_category_item_hover = "#464646",
		collapse_category_item_active = "#535353",

		collapse_category_item_text = "#aaaaaa",
		collapse_category_item_text_hover = "#dcdcdc",
		collapse_category_item_text_active = "#ffffff",
		--=--
	})
end

do
	local PRIMARY = Color(65, 185, 255)

	local ON_PRIMARY = Color(220, 220, 220)

	sui.add_theme("Blur", {
		frame = Color(30, 30, 30, 220),
		frame_blur = true,

		title = Color(255, 255, 255),
		header = Color(60, 60, 60, 200),

		close = Color(200, 200, 200),
		close_hover = Color(255, 60, 60),
		close_press = Color(255, 255, 255, 30),

		button = ColorAlpha(PRIMARY, 130),
		button_text = ON_PRIMARY,
		button_hover = Color(0, 0, 0, 30),
		button_click = PRIMARY,
		button_disabled = Color(100, 100, 100),
		button_disabled_text = "#bdbdbd",

		button2_hover = ColorAlpha(PRIMARY, 5),
		button2_selected = ColorAlpha(PRIMARY, 15),

		scroll = Color(0, 0, 0, 100),
		scroll_grip = PRIMARY,

		scroll_panel = Color(255, 255, 255, 10),
		scroll_panel_outline = false,

		text_entry_bg = Color(0, 0, 0, 0),
		text_entry_bar_color = Color(200, 200, 200, 153),
		text_entry = Color(240, 240, 240, 221),
		text_entry_2 = Color(200, 200, 200, 153),
		text_entry_3 = PRIMARY,

		property_sheet_bg = Color(60, 60, 60, 200),
		property_sheet_tab = Color(150, 150, 150),
		property_sheet_tab_click = Color(255, 255, 255, 40),
		property_sheet_tab_active = PRIMARY,

		toggle_button = Color(244, 67, 54),
		toggle_button_switch = Color(230, 230, 230),

		toggle_button_active = PRIMARY,
		toggle_button_switch_active = Color(230, 230, 230),

		slider_knob = PRIMARY,
		slider_track = ColorAlpha(PRIMARY, 100),
		slider_hover = ColorAlpha(PRIMARY, 40),
		slider_pressed = ColorAlpha(PRIMARY, 70),

		on_sheet = Color(60, 60, 60, 180),
		on_sheet_hover = Color(30, 30, 30, 70),

		--=--
		query_box_bg = Color(0, 0, 0, 100),
		query_box_cancel = Color(244, 67, 54, 30),
		query_box_cancel_text = "#f44336",
		--=--
	})
end
