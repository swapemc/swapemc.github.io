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
local LocalPlayer      = Players.LocalPlayer

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

function Section.new(frame, theme, indent)
    return setmetatable({ContentFrame=frame, Theme=theme, Indent=indent or 0, RowOrder=0}, Section)
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
function Section:AddCheckbox(text, default, callback)
    callback=callback or function()end
    local T=self.Theme; local state=default or false; local o=self:_n()
    local row=mk("Frame",{Name="Chk_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local box=mk("Frame",{Size=UDim2.new(0,M.CheckboxSize,0,M.CheckboxSize),Position=UDim2.new(0,M.Padding+self.Indent,0.5,-M.CheckboxSize/2),BackgroundColor3=T.FrameBg,BorderSizePixel=0},row)
    corner(box)
    local chk=mk("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=state and "v" or "",TextColor3=T.CheckMark,Font=Enum.Font.GothamBold,TextSize=M.FontSize-1},box)
    mk("TextLabel",{Size=UDim2.new(1,-(M.CheckboxSize+M.Padding*2+self.Indent),1,0),Position=UDim2.new(0,M.CheckboxSize+M.Padding+4+self.Indent,0,0),BackgroundTransparency=1,Text=text,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},row)
    local function set(v) state=v; chk.Text=state and "v" or ""; box.BackgroundColor3=state and T.FrameBgActive or T.FrameBg; callback(state) end
    local cb=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=""},row)
    cb.MouseEnter:Connect(function() tw(box,{BackgroundColor3=T.FrameBgHover},0.05) end)
    cb.MouseLeave:Connect(function() tw(box,{BackgroundColor3=state and T.FrameBgActive or T.FrameBg},0.05) end)
    cb.MouseButton1Click:Connect(function() set(not state) end)
    return {GetValue=function(_)return state end, SetValue=function(_,v)set(v)end, SetCallback=function(_,cb2)callback=cb2 end}
end

-- ── AddSliderInt / AddSliderFloat ─────────────────────────
local function makeSlider(self, text, min, max, default, callback, isFloat)
    callback=callback or function()end
    local T=self.Theme
    local fmt=isFloat and "%.3f" or "%d"
    local value=clamp(default or min, min, max)
    local o=self:_n()
    local row=mk("Frame",{Name="Sld_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local sw=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,M.RowHeight-4)
    local sf=mk("Frame",{Size=sw,Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0,ClipsDescendants=true},row)
    corner(sf)
    local fill=mk("Frame",{Size=UDim2.new(0,0,1,0),BackgroundColor3=T.SliderGrab,BorderSizePixel=0},sf)
    local vl=mk("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text=string.format(fmt,value),TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Center,ZIndex=3},sf)
    rightLabel(row, text, T)
    local function upd(pct)
        pct=clamp(pct,0,1)
        value=isFloat and (min+(max-min)*pct) or round(min+(max-min)*pct)
        fill.Size=UDim2.new(pct,0,1,0); vl.Text=string.format(fmt,value); callback(value)
    end
    upd((value-min)/(max-min))
    local dragging=false
    local cb=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",ZIndex=5},sf)
    cb.MouseButton1Down:Connect(function(x)
        dragging=true
        upd((x-sf.AbsolutePosition.X)/sf.AbsoluteSize.X)
    end)
    cb.MouseEnter:Connect(function() tw(sf,{BackgroundColor3=T.FrameBgHover},0.05) end)
    cb.MouseLeave:Connect(function() tw(sf,{BackgroundColor3=T.FrameBg},0.05) end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType==Enum.UserInputType.MouseMovement then
            upd((inp.Position.X-sf.AbsolutePosition.X)/sf.AbsoluteSize.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false; tw(sf,{BackgroundColor3=T.FrameBg},0.05) end
    end)
    return {GetValue=function(_)return value end, SetValue=function(_,v) value=clamp(v,min,max); upd((value-min)/(max-min)) end, SetCallback=function(_,cb2)callback=cb2 end}
end

function Section:AddSliderInt(text,min,max,default,callback) return makeSlider(self,text,min,max,default,callback,false) end
function Section:AddSliderFloat(text,min,max,default,callback) return makeSlider(self,text,min,max,default,callback,true) end

-- ── AddInputText ──────────────────────────────────────────
function Section:AddInputText(text, default, callback)
    callback=callback or function()end
    local T=self.Theme; local o=self:_n()
    local row=mk("Frame",{Name="ITxt_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o},self.ContentFrame)
    local ibg=mk("Frame",{Size=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,M.RowHeight-4),Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0,ClipsDescendants=true},row)
    corner(ibg)
    local box=mk("TextBox",{Size=UDim2.new(1,-6,1,0),Position=UDim2.new(0,4,0,0),BackgroundTransparency=1,Text=default or "",TextColor3=T.Text,PlaceholderColor3=T.TextDisabled,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,ClearTextOnFocus=false},ibg)
    rightLabel(row, text, T)
    box.Focused:Connect(function() tw(ibg,{BackgroundColor3=T.FrameBgHover},0.05) end)
    box.FocusLost:Connect(function(enter) tw(ibg,{BackgroundColor3=T.FrameBg},0.05); callback(box.Text,enter) end)
    return {GetText=function(_)return box.Text end, SetText=function(_,t)box.Text=t end, SetCallback=function(_,cb)callback=cb end}
end

-- ── AddInputInt / AddInputFloat (with +/- steppers) ───────
local function makeInputNum(self, text, default, callback, isFloat, step)
    callback=callback or function()end; step=step or 1
    local T=self.Theme; local value=default or 0
    local fmt=isFloat and "%.6g" or "%d"; local o=self:_n()
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
    local function set(v) value=isFloat and v or round(v); box.Text=string.format(fmt,value); callback(value) end
    minus.MouseButton1Click:Connect(function() set(value-step) end)
    plus.MouseButton1Click:Connect(function() set(value+step) end)
    box.FocusLost:Connect(function() local n=tonumber(box.Text); if n then set(n) else box.Text=string.format(fmt,value) end end)
    for _,b in ipairs({minus,plus}) do
        b.MouseEnter:Connect(function() b.TextColor3=T.Text end)
        b.MouseLeave:Connect(function() b.TextColor3=T.TextDisabled end)
    end
    return {GetValue=function(_)return value end, SetValue=function(_,v)set(v)end, SetCallback=function(_,cb)callback=cb end}
end

function Section:AddInputInt(text,default,callback,step) return makeInputNum(self,text,default,callback,false,step or 1) end
function Section:AddInputFloat(text,default,callback,step) return makeInputNum(self,text,default,callback,true,step or 0.1) end

-- ── AddCombo ──────────────────────────────────────────────
function Section:AddCombo(text, options, default, callback)
    callback=callback or function()end; options=options or {}
    local T=self.Theme; local selected=default or options[1] or ""; local open=false; local o=self:_n()
    local row=mk("Frame",{Name="Cbo_"..o,Size=UDim2.new(1,0,0,M.RowHeight),BackgroundTransparency=1,LayoutOrder=o,ClipsDescendants=false,ZIndex=10},self.ContentFrame)
    local AW=18
    local comboBg=mk("Frame",{Size=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,M.RowHeight-4),Position=UDim2.new(0,M.Padding+self.Indent,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=T.FrameBg,BorderSizePixel=0,ZIndex=10},row)
    corner(comboBg)
    local selLbl=mk("TextLabel",{Size=UDim2.new(1,-AW-4,1,0),Position=UDim2.new(0,4,0,0),BackgroundTransparency=1,Text=selected,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=11},comboBg)
    local arrowBox=mk("Frame",{Size=UDim2.new(0,AW,1,2),Position=UDim2.new(1,-AW,0,-1),BackgroundColor3=T.Button,BorderSizePixel=0,ZIndex=11},comboBg)
    corner(arrowBox)
    mk("TextLabel",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="v",TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,ZIndex=12},arrowBox)
    rightLabel(row,text,T)
    local itemH=M.RowHeight-4
    local popupH=#options*itemH+4
    local popup=mk("Frame",{Size=UDim2.new(1,-(M.LabelW+M.Padding+self.Indent),0,popupH),Position=UDim2.new(0,M.Padding+self.Indent,1,1),BackgroundColor3=T.PopupBg,BorderSizePixel=0,Visible=false,ZIndex=50,ClipsDescendants=true},row)
    corner(popup); mk("UIStroke",{Color=T.Border,Thickness=1},popup); pad(popup,2,2,2,2); vlist(popup,0)
    for i,opt in ipairs(options) do
        local isSel=opt==selected
        local itm=mk("TextButton",{Size=UDim2.new(1,0,0,itemH),BackgroundColor3=isSel and T.Header or T.PopupBg,BackgroundTransparency=isSel and 0 or 1,Text=(isSel and "  " or "    ")..opt,TextColor3=T.Text,Font=M.Font,TextSize=M.FontSize,TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0,LayoutOrder=i,ZIndex=51},popup)
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
        end)
    end
    local cb=mk("TextButton",{Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,Text="",ZIndex=15},comboBg)
    cb.MouseEnter:Connect(function() tw(comboBg,{BackgroundColor3=T.FrameBgHover},0.05) end)
    cb.MouseLeave:Connect(function() tw(comboBg,{BackgroundColor3=T.FrameBg},0.05) end)
    cb.MouseButton1Click:Connect(function() open=not open; popup.Visible=open end)
    return {GetSelected=function(_)return selected end, SetCallback=function(_,cb2)callback=cb2 end}
end

-- ── AddColorEdit ──────────────────────────────────────────
function Section:AddColorEdit(text, default, callback)
    callback=callback or function()end
    local T=self.Theme; local color=default or Color3.fromRGB(255,0,0); local o=self:_n()
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
    local childSection=Section.new(child,T,M.IndentW)
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
function Section:AddRadioGroup(items, default, callback)
    callback=callback or function()end; items=items or {}
    local T=self.Theme; local selected=default or items[1]; local btns={}
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
    return {GetSelected=function(_)return selected end, SetCallback=function(_,cb)callback=cb end}
end

-- ──────────────────────────────────────────────────────────
--  Tab
-- ──────────────────────────────────────────────────────────
local Tab={}; Tab.__index=Tab

function Tab.new(name, scrollFrame, theme)
    local t=setmetatable({},Tab)
    t.Name=name; t.ScrollFrame=scrollFrame; t.Theme=theme
    local inner=mk("Frame",{Name="Inner",Size=UDim2.new(1,0,0,0),BackgroundTransparency=1,AutomaticSize=Enum.AutomaticSize.Y},scrollFrame)
    vlist(inner,M.ItemSpacing)
    t.Section=Section.new(inner,theme,0)
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
    local W=options.Width or 430; local H=options.Height or 480

    local sg=mk("ScreenGui",{Name="ImGui_"..title,ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=999})
    local ok=pcall(function() sg.Parent=game:GetService("CoreGui") end)
    if not ok then sg.Parent=LocalPlayer:WaitForChild("PlayerGui") end
    self.ScreenGui=sg

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

    -- Menu bar (tabs go here)
    local mb=mk("Frame",{Name="MenuBar",Size=UDim2.new(1,0,0,M.MenuBarH),Position=UDim2.new(0,0,0,M.TitleHeight),BackgroundColor3=self.Theme.MenuBarBg,BorderSizePixel=0},win)
    hlist(mb,0); pad(mb,2,2,4,4)
    mk("Frame",{Size=UDim2.new(1,0,0,1),Position=UDim2.new(0,0,1,-1),BackgroundColor3=self.Theme.Border,BackgroundTransparency=0.5,BorderSizePixel=0},mb)
    self._menuBar=mb

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
    local tab=Tab.new(name,scroll,T)
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
    self._menuBar.BackgroundColor3=self.Theme.MenuBarBg
    self._contentArea.BackgroundColor3=self.Theme.ChildBg
    if self.ActiveTab then self:SelectTab(self.ActiveTab.Name) end
end

function Window:Destroy() self.ScreenGui:Destroy() end

-- ─── Public API ──────────────────────────────────────────
function ImGuiLib.CreateWindow(title, options) return Window.new(title,options) end
ImGuiLib.DefaultTheme=deepCopy(DEFAULT_THEME)
return ImGuiLib
