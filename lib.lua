--[[
╔══════════════════════════════════════════════════════════╗
║           ImGuiLib — Dear ImGui Accurate Port            ║
║           Faithful to Dear ImGui's dense, flat UI        ║
╚══════════════════════════════════════════════════════════╝

QUICK START:
    local ImGui = loadstring(game:HttpGet("..."))()

    local Window = ImGui.CreateWindow("Dear ImGui Demo")

    local Tab = Window:AddTab("Examples")

    Tab:AddText("Hello, world!")
    Tab:AddButton("Button")
    Tab:AddCheckbox("checkbox", false, function(v) print(v) end)

    local mySlider = Tab:AddSliderInt("slider int", 0, 100, 0, function(v) end)
    local myFloat  = Tab:AddSliderFloat("slider float", 0, 1, 0.5, function(v) end)

    Tab:AddInputText("input text", "", function(v) end)
    Tab:AddInputInt("input int", 0, function(v) end)

    Tab:AddCombo("combo", {"AAAA","BBBB","CCCC"}, "AAAA", function(v) end)

    Tab:AddColorEdit("color 1", Color3.fromRGB(255,0,0), function(v) end)

    Tab:AddSeparator()
    local tree = Tab:AddCollapsingHeader("Open me")
    tree:AddText("  Inside a tree")
    tree:AddButton("  Nested Button")

    Tab:AddListbox("listbox", {"Apple","Banana","Cherry"}, "Apple", function(v) end)

    Tab:AddRadioGroup({"radio a","radio b","radio c"}, "radio a", function(v) end)

THEME FUNCTIONS:
    Window:SetTheme({ ... })
    Window:SetToggleKey(Enum.KeyCode.RightShift)
]]

local ImGuiLib   = {}
ImGuiLib.__index = ImGuiLib

-- ─── Services ────────────────────────────────────────────
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local LocalPlayer      = Players.LocalPlayer

-- ─── Config System ───────────────────────────────────────
-- Uses exploit filesystem (writefile / readfile / isfolder / makefolder)
-- Configs are saved as JSON to: workspace/../ImGuiLib/<configName>.json
-- (Executors expose writefile/readfile as globals, not in a service)

local CONFIG_DIR = "ImGuiLib"

local function cfgPath(name)
    return CONFIG_DIR .. "/" .. name .. ".json"
end

local function cfgEnsureDir()
    local ok = pcall(function()
        if not isfolder(CONFIG_DIR) then
            makefolder(CONFIG_DIR)
        end
    end)
    return ok
end

local function cfgEncode(data)
    -- Serialise to JSON using HttpService so we never have escape issues.
    -- Color3 values are converted to a plain table first so JSONEncode can handle them.
    local proxy = {}
    for k, v in pairs(data) do
        if typeof(v) == "Color3" then
            proxy[k] = {__type="Color3", r=v.R, g=v.G, b=v.B}
        else
            proxy[k] = v
        end
    end
    local ok, result = pcall(function()
        return HttpService:JSONEncode(proxy)
    end)
    return ok and result or "{}"
end

local function cfgDecode(json)
    -- Decode JSON produced by cfgEncode back to a Lua table
    local ok, result = pcall(function()
        return HttpService:JSONDecode(json)
    end)
    if not ok then return nil end
    -- Re-hydrate Color3 objects
    for k, v in pairs(result) do
        if type(v) == "table" and v["__type"] == "Color3" then
            result[k] = Color3.new(v.r or 0, v.g or 0, v.b or 0)
        end
    end
    return result
end

local function cfgWrite(name, data)
    if not cfgEnsureDir() then return false end
    local ok = pcall(writefile, cfgPath(name), cfgEncode(data))
    return ok
end

local function cfgRead(name)
    local ok, raw = pcall(readfile, cfgPath(name))
    if not ok or not raw then return nil end
    return cfgDecode(raw)
end

local function cfgExists(name)
    local ok, result = pcall(isfile, cfgPath(name))
    return ok and result
end

-- ─── Dear ImGui Dark Theme Colours ───────────────────────
local DEFAULT_THEME = {
    WindowBg        = Color3.fromRGB(15,  15,  15),
    ChildBg         = Color3.fromRGB(20,  20,  20),
    TitleBgActive   = Color3.fromRGB(41,  74,  122),
    MenuBarBg       = Color3.fromRGB(36,  36,  36),
    FrameBg         = Color3.fromRGB(41,  41,  41),
    FrameBgHover    = Color3.fromRGB(66,  66,  66),
    FrameBgActive   = Color3.fromRGB(30,  30,  30),
    Button          = Color3.fromRGB(66,  66,  66),
    ButtonHover     = Color3.fromRGB(100, 100, 100),
    ButtonActive    = Color3.fromRGB(41,  74,  122),
    Header          = Color3.fromRGB(41,  74,  122),
    HeaderHover     = Color3.fromRGB(66,  66,  66),
    SliderGrab      = Color3.fromRGB(100, 149, 237),
    CheckMark       = Color3.fromRGB(100, 149, 237),
    TabActive       = Color3.fromRGB(51,  51,  51),
    Separator       = Color3.fromRGB(110, 110, 128),
    Text            = Color3.fromRGB(255, 255, 255),
    TextDisabled    = Color3.fromRGB(128, 128, 128),
    Border          = Color3.fromRGB(110, 110, 128),
    ScrollbarGrab   = Color3.fromRGB(79,  79,  79),
    PopupBg         = Color3.fromRGB(20,  20,  20),
}

-- ─── Layout metrics ───────────────────────────────────────
local M = {
    RowHeight    = 20,
    Padding      = 8,
    ItemSpacing  = 2,
    FontSize     = 13,
    Font         = Enum.Font.Code,
    CheckboxSize = 13,
    IndentW      = 12,
    TitleHeight  = 20,
    MenuBarH     = 22,
    ScrollbarW   = 10,
    ArrowW       = 18,
    LabelW       = 140,
    CornerR      = 2,
}

-- ─── Utilities ───────────────────────────────────────────
local function deepCopy(t) local c={} for k,v in pairs(t) do c[k]=v end return c end
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function round(v) return math.floor(v+0.5) end

local function mk(cls, props, parent)
    local i = Instance.new(cls)
    for k,v in pairs(props) do pcall(function() i[k]=v end) end
    if parent then i.Parent = parent end
    return i
end

local function corner(p,r) mk("UICorner",{CornerRadius=UDim.new(0,r or M.CornerR)},p) end
local function pad(p,t,b,l,r) mk("UIPadding",{PaddingTop=UDim.new(0,t or 0),PaddingBottom=UDim.new(0,b or 0),PaddingLeft=UDim.new(0,l or 0),PaddingRight=UDim.new(0,r or 0)},p) end
local function vlist(p,sp) mk("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,FillDirection=Enum.FillDirection.Vertical,HorizontalAlignment=Enum.HorizontalAlignment.Left,Padding=UDim.new(0,sp or M.ItemSpacing)},p) end
local function hlist(p,sp) mk("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,sp or 0)},p) end
local function tw(obj,props,t) TweenService:Create(obj,TweenInfo.new(t or 0.07,Enum.EasingStyle.Linear),props):Play() end

-- ──────────────────────────────────────────────────────────
--  Section — the thing that owns widgets
-- ──────────────────────────────────────────────────────────
local Section = {}
Section.__index = Section

function Section.new(frame, theme, indent, winFrame, registry)
    -- registry is a shared table owned by Window; all keyed widgets register here
    return setmetatable({ContentFrame=frame, Theme=theme, Indent=indent or 0, RowOrder=0, WinFrame=winFrame, _registry=registry or {}}, Section)
end

function Section:_n() self.RowOrder=self.RowOrder+1; return self.RowOrder end

-- shared: right-side label
local function rightLabel(parent, text, theme)
    mk("TextLabel",{
        Size=UDim2.new(0,M.LabelW,1,0), Position=UDim2.new(1,-M.LabelW,0,0),
        BackgroundTransparency=1, Text=text, TextColor3=theme.Text,
        Font=M.Font, TextSize=M.FontSize, TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
    }, parent)
end

-- ── AddText ───────────────────────────────────────────────
function Section:AddText(text, disabled)
    local T=self.Theme; local o=self:_n()
    local row=mk("Frame",{Name="Txt_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local lbl=mk("TextLabel",{Size=UDim2.new(1,-M.Padding*2,1,0),Position=UDim2.new(0,M.Padding+self.Indent,0,0),BackgroundTransparency=1,Text=text,TextColor3=disabled and T.TextDisabled or T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},row)
    return {SetText=function(_,t)lbl.Text=t end}
end

-- ── AddSeparator ──────────────────────────────────────────
function Section:AddSeparator()
    local T=self.Theme; local o=self:_n()
    local row=mk("Frame",{Name="Sep_"..o,Size=UDim2.new(1,0,0,9),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    mk("Frame",{Size=UDim2.new(1,-M.Padding*2,0,1),Position=UDim2.new(0,M.Padding,0.5,0),BackgroundColor3=T.Separator,BackgroundTransparency=0.4,BorderSizePixel=0},row)
end

-- ── AddButton ─────────────────────────────────────────────
function Section:AddButton(text, callback)
    callback=callback or function()end
    local T=self.Theme; local o=self:_n()
    local row=mk("Frame",{Name="Btn_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local btn=mk("TextButton",{AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.new(0,0,0,M.RowHeight-4),Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.Button,Text="  "..text.."  ",TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,BorderSizePixel=0},row)
    corner(btn)
    btn.MouseEnter:Connect(function() btn.BackgroundColor3=T.ButtonHover end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3=T.Button end)
    btn.MouseButton1Down:Connect(function() btn.BackgroundColor3=T.ButtonActive end)
    btn.MouseButton1Up:Connect(function() btn.BackgroundColor3=T.ButtonHover; callback() end)
    return {SetText=function(_,t) btn.Text="  "..t.."  " end, SetCallback=function(_,cb)callback=cb end}
end

-- ── AddCheckbox ───────────────────────────────────────────
function Section:AddCheckbox(text, default, callback, key)
    callback=callback or function()end
    local T=self.Theme; local state=default or false; local o=self:_n()
    local reg=self._registry
    local row=mk("Frame",{Name="Chk_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local box=mk("Frame",{Size=UDim2.new(0,M.CheckboxSize,0,M.CheckboxSize),Position=UDim2.new(0,M.Padding+self.Indent,0.5,-M.CheckboxSize/2),BackgroundColor3=T.FrameBg,BorderSizePixel=0},row)
    corner(box)
    local chk=mk("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=state and "v" or "",TextColor3=T.CheckMark,Font=Enum.Font.GothamBold,TextSize=M.FontSize-1},box)
    mk("TextLabel",{Size=UDim2.new(1,-(M.CheckboxSize+M.Padding*2+self.Indent),1,0),Position=UDim2.new(0,M.CheckboxSize+M.Padding+4+self.Indent,0,0),BackgroundTransparency=1,Text=text,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},row)
    local winAutoSave=reg and reg.__window
    local function set(v,silent)
        state=v; chk.Text=state and "v" or ""; box.BackgroundColor3=state and T.FrameBgActive or T.FrameBg
        if not silent then callback(state) end
        if winAutoSave and winAutoSave._autoSaveName then winAutoSave:SaveConfig(winAutoSave._autoSaveName) end
    end
    local cb=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""},row)
    cb.MouseEnter:Connect(function() tw(box,{BackgroundColor3=T.FrameBgHover},0.05) end)
    cb.MouseLeave:Connect(function() tw(box,{BackgroundColor3=state and T.FrameBgActive or T.FrameBg},0.05) end)
    cb.MouseButton1Click:Connect(function() set(not state) end)
    if key and reg then reg[key]={get=function()return state end, set=function(v)set(v,true);callback(state)end} end
    return {GetValue=function(_)return state end, SetValue=function(_,v)set(v)end, SetCallback=function(_,cb2)callback=cb2 end}
end

-- ── AddSliderInt / AddSliderFloat ─────────────────────────
local function makeSlider(self, text, minVal, maxVal, default, callback, isFloat, key)
    callback=callback or function()end
    local T=self.Theme
    local fmt=isFloat and "%.3f" or "%d"
    local value=clamp(default or minVal, minVal, maxVal)
    local o=self:_n()
    local reg=self._registry

    -- Row holds everything — no ClipsDescendants so editBox can overlay freely
    local row=mk("Frame",{Name="Sld_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o,ClipsDescendants=false},self.ContentFrame)

    local sw=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,M.RowHeight-4)

    -- Slider track — no ClipsDescendants, just visual
    local sf=mk("Frame",{Size=sw,Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0,ClipsDescendants=false},row)
    corner(sf)

    local fill=mk("Frame",{Size=UDim2.new(0,0,1,0),BackgroundColor3=T.SliderGrab,BorderSizePixel=0,ZIndex=1},sf)
    corner(fill)

    -- Value label — shown during normal drag mode
    local vl=mk("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=string.format(fmt,value),TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Center,ZIndex=2},sf)

    -- Invisible drag button — sits on top of everything during drag mode
    local dragBtn=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",ZIndex=3},sf)

    -- Edit box — sibling of sf, covers same area, only shown during edit mode
    -- Parented to row (not sf) so ClipsDescendants on sf doesn't matter
    local editBg=mk("Frame",{Size=sw,Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBgHover,BorderSizePixel=0,Visible=false,ZIndex=10,ClipsDescendants=true},row)
    corner(editBg)
    mk("UIStroke",{Color=T.SliderGrab,Thickness=1},editBg)
    local editBox=mk("TextBox",{Size=UDim2.new(1,-8,1,0),Position=UDim2.new(0,4,0,0),BackgroundTransparency=1,Text="",TextColor3=T.Text,PlaceholderColor3=T.TextDisabled,PlaceholderText="type value...",Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Center,ZIndex=11,ClearTextOnFocus=false},editBg)

    rightLabel(row, text, T)

    local winAutoSave=reg and reg.__window
    local editing=false

    local function upd(pct, silent)
        pct=clamp(pct,0,1)
        value=isFloat and (minVal+(maxVal-minVal)*pct) or round(minVal+(maxVal-minVal)*pct)
        fill.Size=UDim2.new(pct,0,1,0)
        vl.Text=string.format(fmt,value)
        if not silent then callback(value) end
        if winAutoSave and winAutoSave._autoSaveName then winAutoSave:SaveConfig(winAutoSave._autoSaveName) end
    end

    local function enterEditMode()
        editing=true
        dragBtn.Visible=false  -- hide drag button so editBox gets input
        editBox.Text=string.format(fmt,value)
        editBg.Visible=true
        editBox:CaptureFocus()
    end

    local function leaveEditMode()
        editing=false
        editBg.Visible=false
        dragBtn.Visible=true
        tw(sf,{BackgroundColor3=T.FrameBg},0.05)
        local n=tonumber(editBox.Text)
        if n then
            upd((clamp(n,minVal,maxVal)-minVal)/(maxVal-minVal))
        end
    end

    editBox.FocusLost:Connect(function() if editing then leaveEditMode() end end)

    -- Confirm with Enter key while editing
    editBox:GetPropertyChangedSignal("Text"):Connect(function()
        -- allow only numbers, minus, and decimal point
    end)
    UserInputService.InputBegan:Connect(function(inp, gpe)
        if editing and not gpe and inp.KeyCode==Enum.KeyCode.Return then
            leaveEditMode()
        end
        -- click outside while editing closes it
        if editing and inp.UserInputType==Enum.UserInputType.MouseButton1 then
            local mp=inp.Position
            local ap=editBg.AbsolutePosition; local as=editBg.AbsoluteSize
            local inside=mp.X>=ap.X and mp.X<=ap.X+as.X and mp.Y>=ap.Y and mp.Y<=ap.Y+as.Y
            if not inside then leaveEditMode() end
        end
    end)

    upd((value-minVal)/(maxVal-minVal), true)
    callback(value)

    local dragging=false
    local lastClickTime=0

    dragBtn.MouseButton1Down:Connect(function(x)
        local now=tick()
        if now-lastClickTime < 0.35 then
            enterEditMode()
            lastClickTime=0
            return
        end
        lastClickTime=now
        dragging=true
        upd((x-sf.AbsolutePosition.X)/sf.AbsoluteSize.X)
    end)
    dragBtn.MouseEnter:Connect(function() tw(sf,{BackgroundColor3=T.FrameBgHover},0.05) end)
    dragBtn.MouseLeave:Connect(function() tw(sf,{BackgroundColor3=T.FrameBg},0.05) end)

    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType==Enum.UserInputType.MouseMovement then
            upd((inp.Position.X-sf.AbsolutePosition.X)/sf.AbsoluteSize.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then
            if dragging then
                dragging=false
                tw(sf,{BackgroundColor3=T.FrameBg},0.05)
            end
        end
    end)

    if key and reg then
        reg[key]={
            get=function() return value end,
            set=function(v)
                local p=(clamp(v,minVal,maxVal)-minVal)/(maxVal-minVal)
                upd(p,true); callback(value)
            end
        }
    end

    return {
        GetValue    = function(_) return value end,
        SetValue    = function(_,v) local p=(clamp(v,minVal,maxVal)-minVal)/(maxVal-minVal); upd(p) end,
        SetMin      = function(_,v) minVal=v; upd((clamp(value,minVal,maxVal)-minVal)/(maxVal-minVal),true) end,
        SetMax      = function(_,v) maxVal=v; upd((clamp(value,minVal,maxVal)-minVal)/(maxVal-minVal),true) end,
        SetRange    = function(_,lo,hi) minVal=lo; maxVal=hi; upd((clamp(value,minVal,maxVal)-minVal)/(maxVal-minVal),true) end,
        SetCallback = function(_,cb2) callback=cb2 end,
    }
end

function Section:AddSliderInt(text,min,max,default,callback,key) return makeSlider(self,text,min,max,default,callback,false,key) end
function Section:AddSliderFloat(text,min,max,default,callback,key) return makeSlider(self,text,min,max,default,callback,true,key) end

-- ── AddInputText ──────────────────────────────────────────
function Section:AddInputText(text, default, callback, key)
    callback=callback or function()end
    local T=self.Theme; local o=self:_n()
    local reg=self._registry
    local row=mk("Frame",{Name="ITxt_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local ibg=mk("Frame",{Size=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,M.RowHeight-4),Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0,ClipsDescendants=true},row)
    corner(ibg)
    local box=mk("TextBox",{Size=UDim2.new(1,-6,1,0),Position=UDim2.new(0,4,0,0),BackgroundTransparency=1,Text=default or "",TextColor3=T.Text,PlaceholderColor3=T.TextDisabled,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false},ibg)
    rightLabel(row, text, T)
    local winAutoSave=reg and reg.__window
    box.Focused:Connect(function() tw(ibg,{BackgroundColor3=T.FrameBgHover},0.05) end)
    box.FocusLost:Connect(function(enter)
        tw(ibg,{BackgroundColor3=T.FrameBg},0.05); callback(box.Text,enter)
        if winAutoSave and winAutoSave._autoSaveName then winAutoSave:SaveConfig(winAutoSave._autoSaveName) end
    end)
    if key and reg then reg[key]={get=function()return box.Text end, set=function(v)box.Text=tostring(v);callback(box.Text,false)end} end
    return {GetText=function(_)return box.Text end, SetText=function(_,t)box.Text=t end, SetCallback=function(_,cb)callback=cb end}
end

-- ── AddInputInt / AddInputFloat (with +/- steppers) ───────
local function makeInputNum(self, text, default, callback, isFloat, step, key)
    callback=callback or function()end; step=step or 1
    local T=self.Theme; local value=default or 0
    local fmt=isFloat and "%.6g" or "%d"; local o=self:_n()
    local reg=self._registry
    local row=mk("Frame",{Name="INum_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local cont=mk("Frame",{Size=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,M.RowHeight-4),Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0,ClipsDescendants=true},row)
    corner(cont)
    local AW=M.ArrowW
    local minus=mk("TextButton",{Size=UDim2.new(0,AW,1,0),BackgroundTransparency=1,Text="-",TextColor3=T.TextDisabled,Font=M.Font,TextSize=M.FontSize,BorderSizePixel=0},cont)
    mk("Frame",{Size=UDim2.new(0,1,1,0),Position=UDim2.new(0,AW,0,0),BackgroundColor3=T.Border,BackgroundTransparency=0.5,BorderSizePixel=0},cont)
    local box=mk("TextBox",{Size=UDim2.new(1,-AW*2-2,1,0),Position=UDim2.new(0,AW+1,0,0),BackgroundTransparency=1,Text=string.format(fmt,value),TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Center,ClearTextOnFocus=false},cont)
    mk("Frame",{Size=UDim2.new(0,1,1,0),Position=UDim2.new(1,-AW-1,0,0),BackgroundColor3=T.Border,BackgroundTransparency=0.5,BorderSizePixel=0},cont)
    local plus=mk("TextButton",{Size=UDim2.new(0,AW,1,0),Position=UDim2.new(1,-AW,0,0),BackgroundTransparency=1,Text="+",TextColor3=T.TextDisabled,Font=M.Font,TextSize=M.FontSize,BorderSizePixel=0},cont)
    rightLabel(row,text,T)
    local winAutoSave=reg and reg.__window
    local function set(v, silent)
        value=isFloat and v or round(v); box.Text=string.format(fmt,value)
        if not silent then callback(value) end
        if winAutoSave and winAutoSave._autoSaveName then winAutoSave:SaveConfig(winAutoSave._autoSaveName) end
    end
    minus.MouseButton1Click:Connect(function() set(value-step) end)
    plus.MouseButton1Click:Connect(function() set(value+step) end)
    box.FocusLost:Connect(function() local n=tonumber(box.Text); if n then set(n) else box.Text=string.format(fmt,value) end end)
    for _,b in ipairs({minus,plus}) do
        b.MouseEnter:Connect(function() b.TextColor3=T.Text end)
        b.MouseLeave:Connect(function() b.TextColor3=T.TextDisabled end)
    end
    if key and reg then reg[key]={get=function()return value end, set=function(v)set(v,true);callback(value)end} end
    return {GetValue=function(_)return value end, SetValue=function(_,v)set(v)end, SetCallback=function(_,cb)callback=cb end}
end

function Section:AddInputInt(text,default,callback,step,key) return makeInputNum(self,text,default,callback,false,step or 1,key) end
function Section:AddInputFloat(text,default,callback,step,key) return makeInputNum(self,text,default,callback,true,step or 0.1,key) end

-- ── AddCombo ──────────────────────────────────────────────
function Section:AddCombo(text, options, default, callback, key)
    callback=callback or function()end; options=options or {}
    local T=self.Theme; local selected=default or options[1] or ""; local open=false; local o=self:_n()
    local reg=self._registry
    local winAutoSave=reg and reg.__window
    local row=mk("Frame",{Name="Cbo_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local AW=18
    local comboBg=mk("Frame",{Size=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,M.RowHeight-4),Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0},row)
    corner(comboBg)
    local selLbl=mk("TextLabel",{Size=UDim2.new(1,-AW-4,1,0),Position=UDim2.new(0,4,0,0),BackgroundTransparency=1,Text=selected,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left},comboBg)
    local arrowBox=mk("Frame",{Size=UDim2.new(0,AW,1,2),Position=UDim2.new(1,-AW,0,-1),BackgroundColor3=T.Button,BorderSizePixel=0},comboBg)
    corner(arrowBox)
    mk("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="v",TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize},arrowBox)
    rightLabel(row,text,T)

    -- Popup parented to WinFrame so it is never clipped by the scroll frame
    local itemH=M.RowHeight-4
    local popupH=#options*itemH+4
    local winRef=self.WinFrame
    local popup=mk("Frame",{
        Size=UDim2.new(0,0,0,popupH),  -- width set dynamically when opened
        BackgroundColor3=T.PopupBg,
        BorderSizePixel=0,
        Visible=false,
        ZIndex=200,
        ClipsDescendants=true,
    }, winRef or row)
    corner(popup); mk("UIStroke",{Color=T.Border,Thickness=1},popup); pad(popup,2,2,2,2); vlist(popup,0)

    for i,opt in ipairs(options) do
        local isSel=opt==selected
        local itm=mk("TextButton",{Size=UDim2.new(1,0,0,itemH),BackgroundColor3=isSel and T.Header or T.PopupBg,BackgroundTransparency=isSel and 0 or 1,Text=(isSel and "  " or "    ")..opt,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0,LayoutOrder=i,ZIndex=201},popup)
        itm.MouseEnter:Connect(function() if opt~=selected then itm.BackgroundTransparency=0;itm.BackgroundColor3=T.HeaderHover end end)
        itm.MouseLeave:Connect(function() if opt~=selected then itm.BackgroundTransparency=1 end end)
        itm.MouseButton1Click:Connect(function()
            selected=opt; selLbl.Text=opt
            for _,c in ipairs(popup:GetChildren()) do
                if c:IsA("TextButton") then
                    local copt=c.Text:gsub("^%s+","")
                    if copt==selected then c.BackgroundTransparency=0;c.BackgroundColor3=T.Header;c.Text="  "..copt
                    else c.BackgroundTransparency=1;c.Text="    "..copt end
                end
            end
            open=false; popup.Visible=false; callback(selected)
            if winAutoSave and winAutoSave._autoSaveName then winAutoSave:SaveConfig(winAutoSave._autoSaveName) end
        end)
    end

    local function openPopup()
        if not winRef then popup.Visible=true; return end
        -- Position popup below comboBg in WinFrame-local space
        local winAbsPos  = winRef.AbsolutePosition
        local cbAbsPos   = comboBg.AbsolutePosition
        local cbAbsSize  = comboBg.AbsoluteSize
        local relX = cbAbsPos.X - winAbsPos.X
        local relY = cbAbsPos.Y - winAbsPos.Y + cbAbsSize.Y + 1
        popup.Position = UDim2.new(0, relX, 0, relY)
        popup.Size     = UDim2.new(0, cbAbsSize.X, 0, popupH)
        popup.Visible  = true
    end

    local cb=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""},comboBg)
    cb.MouseEnter:Connect(function() tw(comboBg,{BackgroundColor3=T.FrameBgHover},0.05) end)
    cb.MouseLeave:Connect(function() tw(comboBg,{BackgroundColor3=T.FrameBg},0.05) end)
    cb.MouseButton1Click:Connect(function()
        open=not open
        if open then openPopup() else popup.Visible=false end
    end)

    if key and reg then reg[key]={get=function()return selected end, set=function(v)
        selected=v; selLbl.Text=v
        for _,c in ipairs(popup:GetChildren()) do
            if c:IsA("TextButton") then
                local copt=c.Text:gsub("^%s+","")
                if copt==selected then c.BackgroundTransparency=0;c.BackgroundColor3=T.Header;c.Text="  "..copt
                else c.BackgroundTransparency=1;c.Text="    "..copt end
            end
        end
        callback(selected)
    end} end
    return {GetSelected=function(_)return selected end, SetCallback=function(_,cb2)callback=cb2 end}
end

-- ── AddColorEdit ──────────────────────────────────────────
function Section:AddColorEdit(text, default, callback, key)
    callback=callback or function()end
    local T=self.Theme; local color=default or Color3.fromRGB(255,0,0); local o=self:_n()
    local reg=self._registry
    local row=mk("Frame",{Name="Col_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local swH=M.RowHeight-4
    local sw=mk("TextButton",{Size=UDim2.new(0,swH,0,swH),Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=color,Text="",BorderSizePixel=0},row)
    corner(sw); mk("UIStroke",{Color=T.Border,Thickness=1},sw)
    local rgbW=UDim2.new(1,-(M.LabelW+swH+M.Padding*2+4+self.Indent),0,swH)
    local rgbBg=mk("Frame",{Size=rgbW,Position=UDim2.new(0,M.Padding+self.Indent+swH+4,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0},row)
    corner(rgbBg)
    local function fmtC(c) return string.format("%.3f, %.3f, %.3f, 1.000",c.R,c.G,c.B) end
    local lbl=mk("TextLabel",{Size=UDim2.new(1,-4,1,0),Position=UDim2.new(0,4,0,0),BackgroundTransparency=1,Text=fmtC(color),TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left},rgbBg)
    rightLabel(row,text,T)
    if key and reg then reg[key]={get=function()return color end, set=function(c)color=c;sw.BackgroundColor3=c;lbl.Text=fmtC(c);callback(c)end} end
    return {
        GetColor=function(_)return color end,
        SetColor=function(_,c) color=c; sw.BackgroundColor3=c; lbl.Text=fmtC(c); callback(c) end,
        SetCallback=function(_,cb)callback=cb end,
    }
end

-- ── AddListbox ────────────────────────────────────────────
function Section:AddListbox(text, items, default, callback, visibleRows)
    callback=callback or function()end; visibleRows=visibleRows or 4; items=items or {}
    local T=self.Theme; local selected=default or items[1]; local o=self:_n()
    local itemH=M.RowHeight-4; local boxH=visibleRows*itemH+4
    local totalH=boxH+M.RowHeight+2
    local row=mk("Frame",{Name="Lb_"..o,Size=UDim2.new(1,0,0,totalH),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    mk("TextLabel",{Size=UDim2.new(1,-M.Padding*2,0,M.RowHeight),Position=UDim2.new(0,M.Padding,0,0),BackgroundTransparency=1,Text=text,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},row)
    local lb=mk("ScrollingFrame",{Size=UDim2.new(1,-M.Padding*2,0,boxH),Position=UDim2.new(0,M.Padding,0,M.RowHeight+2),BackgroundColor3=T.FrameBg,BorderSizePixel=0,ScrollBarThickness=M.ScrollbarW,ScrollBarImageColor3=T.ScrollbarGrab,CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y},row)
    corner(lb); mk("UIStroke",{Color=T.Border,Thickness=1},lb); pad(lb,2,2,2,2); vlist(lb,0)
    for i,item in ipairs(items) do
        local isSel=item==selected
        local btn=mk("TextButton",{Size=UDim2.new(1,0,0,itemH),BackgroundColor3=T.Header,BackgroundTransparency=isSel and 0 or 1,Text="  "..item,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0,LayoutOrder=i},lb)
        btn.MouseEnter:Connect(function() if item~=selected then btn.BackgroundTransparency=0;btn.BackgroundColor3=T.HeaderHover end end)
        btn.MouseLeave:Connect(function() if item~=selected then btn.BackgroundTransparency=1 end end)
        btn.MouseButton1Click:Connect(function()
            for _,c in ipairs(lb:GetChildren()) do if c:IsA("TextButton") then c.BackgroundTransparency=1 end end
            selected=item; btn.BackgroundTransparency=0; btn.BackgroundColor3=T.Header; callback(selected)
        end)
    end
    return {GetSelected=function(_)return selected end, SetCallback=function(_,cb)callback=cb end}
end

-- ── AddCollapsingHeader ───────────────────────────────────
function Section:AddCollapsingHeader(text, defaultOpen)
    local T=self.Theme; local isOpen=defaultOpen==nil and false or defaultOpen; local o=self:_n()
    local hrow=mk("Frame",{Name="Hdr_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundColor3=T.Header,BackgroundTransparency=0.55,BorderSizePixel=0,LayoutOrder=o},self.ContentFrame)
    local arr=mk("TextLabel",{Size=UDim2.new(0,14,1,0),Position=UDim2.new(0,M.Padding,0,0),BackgroundTransparency=1,Text=isOpen and "v" or ">",TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextYAlignment=Enum.TextYAlignment.Center},hrow)
    mk("TextLabel",{Size=UDim2.new(1,-30,1,0),Position=UDim2.new(0,M.Padding+14,0,0),BackgroundTransparency=1,Text=text,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},hrow)
    local co=self:_n()
    local child=mk("Frame",{Name="HC_"..o,Size=UDim2.new(1,0,0,0),BackgroundColor3=T.ChildBg,BackgroundTransparency=0.5,BorderSizePixel=0,LayoutOrder=co,ClipsDescendants=true},self.ContentFrame)
    vlist(child,M.ItemSpacing); pad(child,2,2,0,0)
    local childSection=Section.new(child,T,M.IndentW,self.WinFrame,self._registry)
    local ly=child:FindFirstChildWhichIsA("UIListLayout")
    local function resize() child.Size=UDim2.new(1,0,0,isOpen and (ly.AbsoluteContentSize.Y+4) or 0) end
    ly:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() if isOpen then resize() end end)
    local cb=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""},hrow)
    cb.MouseEnter:Connect(function() hrow.BackgroundTransparency=0.35 end)
    cb.MouseLeave:Connect(function() hrow.BackgroundTransparency=0.55 end)
    cb.MouseButton1Click:Connect(function() isOpen=not isOpen; arr.Text=isOpen and "v" or ">"; resize() end)
    resize()
    return childSection
end

-- ── AddRadioGroup ─────────────────────────────────────────
function Section:AddRadioGroup(items, default, callback, key)
    callback=callback or function()end; items=items or {}
    local T=self.Theme; local selected=default or items[1]; local btns={}
    local reg=self._registry
    for _,item in ipairs(items) do
        local o=self:_n()
        local row=mk("Frame",{Name="Rad_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
        local circ=mk("Frame",{Size=UDim2.new(0,11,0,11),Position=UDim2.new(0,M.Padding+self.Indent,0.5,-5),BackgroundColor3=T.FrameBg,BorderSizePixel=0},row)
        corner(circ,6)
        local dot=mk("Frame",{Size=UDim2.new(0,5,0,5),Position=UDim2.new(0.5,-2,0.5,-2),BackgroundColor3=T.CheckMark,BackgroundTransparency=item==selected and 0 or 1,BorderSizePixel=0},circ)
        corner(dot,3)
        mk("TextLabel",{Size=UDim2.new(1,-(20+M.Padding+self.Indent),1,0),Position=UDim2.new(0,20+M.Padding+self.Indent,0,0),BackgroundTransparency=1,Text=item,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},row)
        table.insert(btns,{item=item,dot=dot,circ=circ})
        local cb=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""},row)
        cb.MouseEnter:Connect(function() tw(circ,{BackgroundColor3=T.FrameBgHover},0.05) end)
        cb.MouseLeave:Connect(function() tw(circ,{BackgroundColor3=T.FrameBg},0.05) end)
        cb.MouseButton1Click:Connect(function()
            selected=item
            for _,b in ipairs(btns) do b.dot.BackgroundTransparency=b.item==selected and 0 or 1 end
            callback(selected)
        end)
    end
    if key and reg then reg[key]={get=function()return selected end, set=function(v)
        selected=v
        for _,b in ipairs(btns) do b.dot.BackgroundTransparency=b.item==selected and 0 or 1 end
        callback(selected)
    end} end
    return {GetSelected=function(_)return selected end, SetCallback=function(_,cb)callback=cb end}
end

-- ──────────────────────────────────────────────────────────
--  Tab
-- ──────────────────────────────────────────────────────────
local Tab={}; Tab.__index=Tab

function Tab.new(name, scrollFrame, theme, winFrame, registry)
    local t=setmetatable({},Tab)
    t.Name=name; t.ScrollFrame=scrollFrame; t.Theme=theme
    local inner=mk("Frame",{Name="Inner",Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,AutomaticSize=Enum.AutomaticSize.Y},scrollFrame)
    vlist(inner,M.ItemSpacing)
    t.Section=Section.new(inner,theme,0,winFrame,registry)
    return t
end

local proxyMethods={"AddText","AddSeparator","AddButton","AddCheckbox","AddSliderInt","AddSliderFloat","AddInputText","AddInputInt","AddInputFloat","AddCombo","AddColorEdit","AddListbox","AddCollapsingHeader","AddRadioGroup"}
for _,m in ipairs(proxyMethods) do Tab[m]=function(self,...) return self.Section[m](self.Section,...) end end

-- ──────────────────────────────────────────────────────────
--  Window
-- ──────────────────────────────────────────────────────────
local Window={}; Window.__index=Window

function Window.new(title, options)
    local self=setmetatable({},Window)
    options=options or {}
    self.Title=title; self.Theme=deepCopy(DEFAULT_THEME)
    self.Tabs={}; self.TabMap={}; self.ActiveTab=nil
    self.Visible=true; self.ToggleKey=options.ToggleKey or Enum.KeyCode.RightShift
    self._registry={}          -- keyed widget registry: key → {get, set}
    self._registry.__window=self -- back-reference so widgets can trigger auto-save
    self._autoSaveName=nil     -- set to a string to enable auto-save
    local W=options.Width or 430; local H=options.Height or 480

    -- Cleanup: destroy ALL existing ImGuiLib GUIs (any title) before creating a new one.
    -- This ensures re-executing a script never leaves ghost windows behind.
    local guiName = "ImGui_"..title
    local coreGui = game:GetService("CoreGui")
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    for _, parent in ipairs({coreGui, playerGui}) do
        if parent then
            -- Remove any child whose name starts with "ImGui_"
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name:sub(1,6) == "ImGui_" then
                    child:Destroy()
                end
            end
        end
    end

    -- Create new ScreenGui and parent it
    local sg = Instance.new("ScreenGui")
    sg.Name             = guiName
    sg.ResetOnSpawn     = false
    sg.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder     = 999
    sg.IgnoreGuiInset   = true

    local parentedToCoreGui = false
    pcall(function()
        sg.Parent = coreGui
        parentedToCoreGui = true
    end)
    if not parentedToCoreGui then
        if playerGui then
            sg.Parent = playerGui
        else
            sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
    end
    self.ScreenGui = sg

    local win=mk("Frame",{Name="Win",Size=UDim2.new(0,W,0,H),Position=options.Position or UDim2.new(0.5,-W/2,0.5,-H/2),BackgroundColor3=self.Theme.WindowBg,BorderSizePixel=0,ClipsDescendants=false},sg)
    corner(win,3); mk("UIStroke",{Color=self.Theme.Border,Thickness=1},win)
    self.WinFrame=win

    -- Title bar
    local tb=mk("Frame",{Name="TitleBar",Size=UDim2.new(1,0,0,M.TitleHeight),BackgroundColor3=self.Theme.TitleBgActive,BorderSizePixel=0},win)
    corner(tb,3)
    mk("Frame",{Size=UDim2.new(1,0,0.5,0),Position=UDim2.new(0,0,0.5,0),BackgroundColor3=self.Theme.TitleBgActive,BorderSizePixel=0},tb)
    mk("TextLabel",{Size=UDim2.new(1,-M.Padding*2,1,0),Position=UDim2.new(0,M.Padding,0,0),BackgroundTransparency=1,Text=title,TextColor3=self.Theme.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},tb)
    self._titleBar=tb

    -- Drag
    local drag,dStart,dPos=false,nil,nil
    local dragBtn=mk("TextButton",{Size=UDim2.new(1,-20,1,0),BackgroundTransparency=1,Text=""},tb)
    dragBtn.InputBegan:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 then drag=true;dStart=inp.Position;dPos=win.Position end end)
    UserInputService.InputChanged:Connect(function(inp) if drag and inp.UserInputType==Enum.UserInputType.MouseMovement then local d=inp.Position-dStart; win.Position=UDim2.new(dPos.X.Scale,dPos.X.Offset+d.X,dPos.Y.Scale,dPos.Y.Offset+d.Y) end end)
    UserInputService.InputEnded:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)

    -- Menu bar — outer ScrollingFrame clips overflow, inner Frame holds tab buttons
    local mbScroll=mk("ScrollingFrame",{
        Name="MenuBarScroll",
        Size=UDim2.new(1,0,0,M.MenuBarH),
        Position=UDim2.new(0,0,0,M.TitleHeight),
        BackgroundColor3=self.Theme.MenuBarBg,
        BorderSizePixel=0,
        ScrollBarThickness=0,
        ScrollingDirection=Enum.ScrollingDirection.X,
        CanvasSize=UDim2.new(0,0,1,0),
        AutomaticCanvasSize=Enum.AutomaticSize.X,
        ClipsDescendants=true,
    },win)
    mk("Frame",{Size=UDim2.new(1,0,0,1),Position=UDim2.new(0,0,1,-1),BackgroundColor3=self.Theme.Border,BackgroundTransparency=0.5,BorderSizePixel=0},mbScroll)
    local mb=mk("Frame",{
        Name="MenuBar",
        Size=UDim2.new(0,0,1,0),
        AutomaticSize=Enum.AutomaticSize.X,
        BackgroundTransparency=1,
        BorderSizePixel=0,
    },mbScroll)
    hlist(mb,0); pad(mb,2,2,4,4)
    self._menuBar=mb
    self._menuBarScroll=mbScroll

    -- Content
    local contentY=M.TitleHeight+M.MenuBarH
    local ca=mk("Frame",{Name="Content",Size=UDim2.new(1,0,1,-contentY),Position=UDim2.new(0,0,0,contentY),BackgroundColor3=self.Theme.ChildBg,BorderSizePixel=0,ClipsDescendants=true},win)
    self._contentArea=ca

    -- Keybind
    UserInputService.InputBegan:Connect(function(inp,gpe) if not gpe and inp.KeyCode==self.ToggleKey then self:Toggle() end end)

    return self
end

function Window:AddTab(name)
    local T=self.Theme
    local tabBtn=mk("TextButton",{Name=name,AutomaticSize=Enum.AutomaticSize.X,Size=UDim2.new(0,0,1,0),BackgroundColor3=T.TabActive,BackgroundTransparency=1,Text=" "..name.." ",TextColor3=T.TextDisabled,Font=M.Font,TextSize=M.FontSize,BorderSizePixel=0,LayoutOrder=#self.Tabs+1},self._menuBar)
    local scroll=mk("ScrollingFrame",{Name=name.."_S",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=M.ScrollbarW,ScrollBarImageColor3=T.ScrollbarGrab,CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,Visible=false},self._contentArea)
    pad(scroll,3,3,0,0)
    local tab=Tab.new(name,scroll,T,self.WinFrame,self._registry)
    table.insert(self.Tabs,tab); self.TabMap[name]=tab
    tabBtn.MouseButton1Click:Connect(function() self:SelectTab(name) end)
    if #self.Tabs==1 then self:SelectTab(name) end
    return tab
end

function Window:SelectTab(name)
    local T=self.Theme
    for _,tab in ipairs(self.Tabs) do
        local isA=tab.Name==name; tab.ScrollFrame.Visible=isA
        local btn=self._menuBar:FindFirstChild(tab.Name)
        if btn then btn.TextColor3=isA and T.Text or T.TextDisabled; btn.BackgroundTransparency=isA and 0 or 1; btn.BackgroundColor3=T.TabActive end
    end
    self.ActiveTab=self.TabMap[name]
end

function Window:Toggle() self.Visible=not self.Visible; self.WinFrame.Visible=self.Visible end
function Window:SetVisible(v) self.Visible=v; self.WinFrame.Visible=v end
function Window:SetToggleKey(k) self.ToggleKey=k end

function Window:SetTheme(overrides)
    for k,v in pairs(overrides) do self.Theme[k]=v end
    self.WinFrame.BackgroundColor3=self.Theme.WindowBg
    self._titleBar.BackgroundColor3=self.Theme.TitleBgActive
    for _,c in ipairs(self._titleBar:GetChildren()) do if c:IsA("Frame") then c.BackgroundColor3=self.Theme.TitleBgActive end end
    self._menuBarScroll.BackgroundColor3=self.Theme.MenuBarBg
    self._contentArea.BackgroundColor3=self.Theme.ChildBg
    if self.ActiveTab then self:SelectTab(self.ActiveTab.Name) end
end

-- ── Config: collect current state of all registered widgets ──
function Window:_collectConfig()
    local data = {}
    for key, entry in pairs(self._registry) do
        local ok, val = pcall(entry.get)
        if ok and val ~= nil then
            data[key] = val
        end
    end
    return data
end

-- ── Config: apply a loaded data table to all registered widgets ──
function Window:_applyConfig(data)
    for key, val in pairs(data) do
        local entry = self._registry[key]
        if entry then
            pcall(entry.set, val)
        end
    end
end

-- Window:SaveConfig(name)
-- Saves current widget values to ImGuiLib/<name>.json
-- Returns true on success, false on failure
function Window:SaveConfig(name)
    name = name or "default"
    local data = self:_collectConfig()
    local ok = cfgWrite(name, data)
    return ok
end

-- Window:LoadConfig(name)
-- Loads widget values from ImGuiLib/<name>.json and applies them
-- Returns true on success, false if file missing or error
function Window:LoadConfig(name)
    name = name or "default"
    if not cfgExists(name) then return false end
    local data = cfgRead(name)
    if not data then return false end
    self:_applyConfig(data)
    return true
end

-- Window:EnableAutoSave(name)
-- Every time any registered widget changes it saves automatically
-- Call this AFTER adding all your widgets
function Window:EnableAutoSave(name)
    name = name or "default"
    self._autoSaveName = name
end

-- Window:DisableAutoSave()
function Window:DisableAutoSave()
    self._autoSaveName = nil
end

-- Window:DeleteConfig(name)
-- Deletes the saved config file
function Window:DeleteConfig(name)
    name = name or "default"
    local ok = pcall(delfile, cfgPath(name))
    return ok
end

-- Window:ListConfigs()
-- Returns a table of saved config names (without .json extension)
function Window:ListConfigs()
    local names = {}
    local ok, files = pcall(listfiles, CONFIG_DIR)
    if not ok then return names end
    for _, path in ipairs(files) do
        local name = path:match("[/\]([^/\]+)%.json$")
        if name then table.insert(names, name) end
    end
    return names
end

function Window:Destroy() self.ScreenGui:Destroy() end

-- ─── Built-in Themes ────────────────────────────────────
local BUILTIN_THEMES = {

    Default = {
        WindowBg      = Color3.fromRGB(15,  15,  15),
        ChildBg       = Color3.fromRGB(20,  20,  20),
        TitleBgActive = Color3.fromRGB(41,  74, 122),
        MenuBarBg     = Color3.fromRGB(36,  36,  36),
        FrameBg       = Color3.fromRGB(41,  41,  41),
        FrameBgHover  = Color3.fromRGB(66,  66,  66),
        FrameBgActive = Color3.fromRGB(30,  30,  30),
        Button        = Color3.fromRGB(66,  66,  66),
        ButtonHover   = Color3.fromRGB(100,100, 100),
        ButtonActive  = Color3.fromRGB(41,  74, 122),
        Header        = Color3.fromRGB(41,  74, 122),
        HeaderHover   = Color3.fromRGB(66,  66,  66),
        SliderGrab    = Color3.fromRGB(100,149, 237),
        CheckMark     = Color3.fromRGB(100,149, 237),
        TabActive     = Color3.fromRGB(51,  51,  51),
        Separator     = Color3.fromRGB(110,110, 128),
        Text          = Color3.fromRGB(255,255, 255),
        TextDisabled  = Color3.fromRGB(128,128, 128),
        Border        = Color3.fromRGB(110,110, 128),
        ScrollbarGrab = Color3.fromRGB(79,  79,  79),
        PopupBg       = Color3.fromRGB(20,  20,  20),
    },

    Hyacinth = {
        TitleBgActive = Color3.fromRGB(80,  30, 140),
        MenuBarBg     = Color3.fromRGB(30,  10,  60),
        WindowBg      = Color3.fromRGB(15,   5,  30),
        ChildBg       = Color3.fromRGB(22,   8,  44),
        FrameBg       = Color3.fromRGB(50,  20,  90),
        FrameBgHover  = Color3.fromRGB(80,  40, 130),
        FrameBgActive = Color3.fromRGB(35,  10,  70),
        Button        = Color3.fromRGB(80,  30, 140),
        ButtonHover   = Color3.fromRGB(110, 50, 180),
        ButtonActive  = Color3.fromRGB(60,  15, 110),
        Header        = Color3.fromRGB(100, 40, 180),
        HeaderHover   = Color3.fromRGB(80,  30, 140),
        SliderGrab    = Color3.fromRGB(138, 43, 226),
        CheckMark     = Color3.fromRGB(180,100, 255),
        Border        = Color3.fromRGB(100, 50, 180),
        Text          = Color3.fromRGB(220,200, 255),
        TextDisabled  = Color3.fromRGB(120, 90, 160),
        PopupBg       = Color3.fromRGB(22,   8,  44),
        Separator     = Color3.fromRGB(100, 50, 180),
        ScrollbarGrab = Color3.fromRGB(80,  30, 140),
        TabActive     = Color3.fromRGB(40,  15,  80),
    },

    Blackout = {
        TitleBgActive = Color3.fromRGB(40,  40,  40),
        MenuBarBg     = Color3.fromRGB(18,  18,  18),
        WindowBg      = Color3.fromRGB(0,    0,   0),
        ChildBg       = Color3.fromRGB(8,    8,   8),
        FrameBg       = Color3.fromRGB(28,  28,  28),
        FrameBgHover  = Color3.fromRGB(48,  48,  48),
        FrameBgActive = Color3.fromRGB(18,  18,  18),
        Button        = Color3.fromRGB(45,  45,  45),
        ButtonHover   = Color3.fromRGB(70,  70,  70),
        ButtonActive  = Color3.fromRGB(25,  25,  25),
        Header        = Color3.fromRGB(55,  55,  55),
        HeaderHover   = Color3.fromRGB(70,  70,  70),
        SliderGrab    = Color3.fromRGB(200,200, 200),
        CheckMark     = Color3.fromRGB(255,255, 255),
        Border        = Color3.fromRGB(80,  80,  80),
        Text          = Color3.fromRGB(255,255, 255),
        TextDisabled  = Color3.fromRGB(120,120, 120),
        PopupBg       = Color3.fromRGB(8,    8,   8),
        Separator     = Color3.fromRGB(80,  80,  80),
        ScrollbarGrab = Color3.fromRGB(90,  90,  90),
        TabActive     = Color3.fromRGB(38,  38,  38),
    },

    Crimson = {
        TitleBgActive = Color3.fromRGB(120, 10,  10),
        MenuBarBg     = Color3.fromRGB(40,   5,   5),
        WindowBg      = Color3.fromRGB(15,   3,   3),
        ChildBg       = Color3.fromRGB(22,   6,   6),
        FrameBg       = Color3.fromRGB(55,  15,  15),
        FrameBgHover  = Color3.fromRGB(90,  25,  25),
        FrameBgActive = Color3.fromRGB(40,   8,   8),
        Button        = Color3.fromRGB(110, 15,  15),
        ButtonHover   = Color3.fromRGB(160, 30,  30),
        ButtonActive  = Color3.fromRGB(80,  10,  10),
        Header        = Color3.fromRGB(140, 20,  20),
        HeaderHover   = Color3.fromRGB(110, 15,  15),
        SliderGrab    = Color3.fromRGB(210, 50,  50),
        CheckMark     = Color3.fromRGB(255,120,  80),
        Border        = Color3.fromRGB(150, 40,  40),
        Text          = Color3.fromRGB(255,220, 210),
        TextDisabled  = Color3.fromRGB(150, 90,  80),
        PopupBg       = Color3.fromRGB(22,   6,   6),
        Separator     = Color3.fromRGB(140, 40,  40),
        ScrollbarGrab = Color3.fromRGB(110, 20,  20),
        TabActive     = Color3.fromRGB(60,  12,  12),
    },

    Ocean = {
        TitleBgActive = Color3.fromRGB(10,  60,  80),
        MenuBarBg     = Color3.fromRGB(5,   25,  38),
        WindowBg      = Color3.fromRGB(3,   12,  18),
        ChildBg       = Color3.fromRGB(6,   20,  30),
        FrameBg       = Color3.fromRGB(10,  45,  60),
        FrameBgHover  = Color3.fromRGB(15,  70,  95),
        FrameBgActive = Color3.fromRGB(8,   35,  48),
        Button        = Color3.fromRGB(10,  65,  88),
        ButtonHover   = Color3.fromRGB(0,  110, 140),
        ButtonActive  = Color3.fromRGB(5,   50,  68),
        Header        = Color3.fromRGB(0,   80, 110),
        HeaderHover   = Color3.fromRGB(10,  65,  88),
        SliderGrab    = Color3.fromRGB(0,  180, 200),
        CheckMark     = Color3.fromRGB(0,  220, 180),
        Border        = Color3.fromRGB(0,   90, 120),
        Text          = Color3.fromRGB(200,245, 255),
        TextDisabled  = Color3.fromRGB(90, 160, 180),
        PopupBg       = Color3.fromRGB(6,   20,  30),
        Separator     = Color3.fromRGB(0,   90, 120),
        ScrollbarGrab = Color3.fromRGB(0,   80, 110),
        TabActive     = Color3.fromRGB(8,   40,  55),
    },

    Toxic = {
        TitleBgActive = Color3.fromRGB(0,   60,   0),
        MenuBarBg     = Color3.fromRGB(0,   20,   0),
        WindowBg      = Color3.fromRGB(0,    5,   0),
        ChildBg       = Color3.fromRGB(0,   10,   0),
        FrameBg       = Color3.fromRGB(0,   40,   0),
        FrameBgHover  = Color3.fromRGB(0,   65,   5),
        FrameBgActive = Color3.fromRGB(0,   28,   0),
        Button        = Color3.fromRGB(0,   55,   0),
        ButtonHover   = Color3.fromRGB(0,   90,  10),
        ButtonActive  = Color3.fromRGB(0,   38,   0),
        Header        = Color3.fromRGB(0,   75,   0),
        HeaderHover   = Color3.fromRGB(0,   55,   0),
        SliderGrab    = Color3.fromRGB(0,  220,  80),
        CheckMark     = Color3.fromRGB(100,255, 100),
        Border        = Color3.fromRGB(0,  100,  20),
        Text          = Color3.fromRGB(180,255, 180),
        TextDisabled  = Color3.fromRGB(60, 130,  60),
        PopupBg       = Color3.fromRGB(0,   10,   0),
        Separator     = Color3.fromRGB(0,  100,  20),
        ScrollbarGrab = Color3.fromRGB(0,   70,  10),
        TabActive     = Color3.fromRGB(0,   30,   0),
    },
}

function Window:ApplyTheme(name)
    local t = BUILTIN_THEMES[name]
    if not t then
        -- case-insensitive fallback
        local lower = name:lower()
        for k, v in pairs(BUILTIN_THEMES) do
            if k:lower() == lower then t = v; break end
        end
    end
    assert(t, "Distort: unknown theme '" .. tostring(name) .. "'. Available: Default, Hyacinth, Blackout, Crimson, Ocean, Toxic")
    self:SetTheme(t)
end

-- ─── Public API ──────────────────────────────────────────
function ImGuiLib.CreateWindow(title, options) return Window.new(title,options) end
ImGuiLib.DefaultTheme  = deepCopy(DEFAULT_THEME)
ImGuiLib.Themes        = BUILTIN_THEMES
return ImGuiLib
