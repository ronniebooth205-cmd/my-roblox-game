--!strict
-- StarterPlayer > StarterPlayerScripts > UI > Theme (ModuleScript)
-- Visual tokens for every screen: dark charcoal surfaces, white text, electric-green accent,
-- rounded corners. Matches the Figma file "Surron Life UI" (see docs/UI.md). Change a token
-- here and every component picks it up.

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(10, 11, 13),
	Surface = Color3.fromRGB(20, 22, 25),
	SurfaceRaised = Color3.fromRGB(30, 33, 38),
	SurfaceHover = Color3.fromRGB(40, 44, 50),
	Stroke = Color3.fromRGB(52, 56, 64),
	Text = Color3.fromRGB(245, 247, 250),
	TextMuted = Color3.fromRGB(150, 156, 166),
	TextDim = Color3.fromRGB(96, 102, 112),
	Accent = Color3.fromRGB(57, 255, 136), -- electric green
	AccentDark = Color3.fromRGB(22, 150, 78),
	AccentText = Color3.fromRGB(8, 20, 12),
	Warning = Color3.fromRGB(255, 196, 64),
	Danger = Color3.fromRGB(255, 72, 88),
	Info = Color3.fromRGB(80, 170, 255),
	Gold = Color3.fromRGB(255, 208, 92),
}

Theme.Fonts = {
	Display = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Mono = Enum.Font.RobotoMono,
}

Theme.Radius = {
	Small = UDim.new(0, 8),
	Medium = UDim.new(0, 12),
	Large = UDim.new(0, 18),
	Pill = UDim.new(1, 0),
}

Theme.Spacing = { XS = 4, S = 8, M = 12, L = 16, XL = 24 }

Theme.TextSize = { Caption = 13, Body = 16, Label = 18, Title = 24, Hero = 44 }

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

return Theme
