// Builds the "Screens" page in the Surron Life UI Figma file (desktop riding HUD + main menu)
// from the tokens, text styles and components already on the Foundations page.
// Run through the Figma MCP use_figma tool with fileKey vITYOoThSbA8PpHN4vE7sR.
// Component node ids (from the Foundations page): Button set 2:43, QuickButton 2:44,
// StatRow 2:46, Toast 2:51. If they've changed, look them up by name first.
const page = figma.createPage(); page.name = "Screens";
await figma.setCurrentPageAsync(page);
const vars = await figma.variables.getLocalVariablesAsync();
const V = Object.fromEntries(vars.map(v => [v.name, v]));
const styles = await figma.getLocalTextStylesAsync();
const TS = Object.fromEntries(styles.map(s => [s.name, s]));
await Promise.all(["Black","Bold","Medium","SemiBold"].map(s => figma.loadFontAsync({ family: "Montserrat", style: s })));
const [btnSet, qb, toastC] = await Promise.all(["2:43","2:44","2:51"].map(id => figma.getNodeByIdAsync(id)));
const paint = (name, opacity) => { const p = figma.variables.setBoundVariableForPaint({ type: "SOLID", color: { r: 0, g: 0, b: 0 } }, "color", V[name]); return opacity === undefined ? p : { ...p, opacity }; };
const radius = (node, n) => { for (const k of ["topLeftRadius","topRightRadius","bottomLeftRadius","bottomRightRadius"]) node.setBoundVariable(k, V[n]); };
const text = (chars, style, color, parent) => { const t = figma.createText(); t.textStyleId = TS[style].id; t.characters = chars; t.fills = [paint(color)]; if (parent) parent.appendChild(t); return t; };
const variant = (name) => btnSet.children.find(c => c.name === "Style=" + name);
const button = (label, style, parent, w, h) => { const i = variant(style).createInstance(); i.setProperties({ [Object.keys(i.componentProperties).find(k => k.startsWith("Label"))]: label }); if (w) i.resize(w, h || 48); if (parent) parent.appendChild(i); return i; };
const glass = (name, layout) => { const f = figma.createAutoLayout(layout || "VERTICAL", { name }); f.fills = [paint("color/background", 0.75)]; f.strokes = [paint("color/stroke", 0.5)]; f.strokeWeight = 1; radius(f, "radius/large"); return f; };
const scene = (name, x, w, h, top, bottom) => {
  const f = figma.createFrame(); f.name = name; f.resize(w, h); f.x = x; f.y = 0; f.clipsContent = true;
  f.fills = [{ type: "GRADIENT_LINEAR", gradientTransform: [[0, 1, 0], [-1, 0, 1]], gradientStops: [{ position: 0, color: { ...top, a: 1 } }, { position: 1, color: { ...bottom, a: 1 } }] }];
  return f;
};
const created = [];

// Desktop HUD
const hud = scene("HUD — Desktop riding (1920x1080)", 0, 1920, 1080, { r: 0.42, g: 0.55, b: 0.68 }, { r: 0.2, g: 0.21, b: 0.23 });
created.push(hud.id);
const top = glass("TopBar", "HORIZONTAL"); top.itemSpacing = 12; top.paddingLeft = top.paddingRight = 10; top.paddingTop = top.paddingBottom = 9; top.counterAxisAlignItems = "CENTER";
hud.appendChild(top); top.x = 16; top.y = 16;
const badge = figma.createAutoLayout("HORIZONTAL", { name: "LevelBadge" }); badge.resize(48, 48); badge.primaryAxisSizingMode = "FIXED"; badge.counterAxisSizingMode = "FIXED"; badge.primaryAxisAlignItems = "CENTER"; badge.counterAxisAlignItems = "CENTER"; badge.fills = [paint("color/accent")]; radius(badge, "radius/pill");
text("12", "Display/Title", "color/accent-text", badge); top.appendChild(badge);
const tcol = figma.createAutoLayout("VERTICAL", { name: "CashXp", itemSpacing: 6 }); tcol.fills = [];
text("£24,860", "Display/Title", "color/text", tcol);
text("1,820 / 3,660 XP", "Caption/Caption", "color/text-muted", tcol); top.appendChild(tcol);
const qrow = figma.createAutoLayout("HORIZONTAL", { name: "QuickButtons", itemSpacing: 8 }); qrow.fills = [];
for (const icon of ["👥", "★", "🗺", "🔧", "☰"]) { const i = qb.createInstance(); i.setProperties({ [Object.keys(i.componentProperties)[0]]: icon }); qrow.appendChild(i); }
hud.appendChild(qrow); qrow.x = 1920 - 16 - qrow.width; qrow.y = 16;
const wp = glass("WheeliePanel"); wp.counterAxisAlignItems = "CENTER"; wp.paddingTop = 10; wp.paddingBottom = 12; wp.paddingLeft = wp.paddingRight = 20; wp.itemSpacing = 2;
text("86 m", "Display/Hero", "color/text", wp); text("4,215 PTS", "Heading/Label", "color/accent", wp); text("x1.75   ·   BEST 142 m", "Caption/Caption", "color/gold", wp);
hud.appendChild(wp); wp.x = (1920 - wp.width) / 2; wp.y = 92;
const bi = glass("BikeInfo"); bi.paddingLeft = bi.paddingRight = 14; bi.paddingTop = bi.paddingBottom = 12; bi.itemSpacing = 8;
text("LIGHT BEE STYLE 72V", "Heading/Body", "color/text", bi); text("BATTERY 78%", "Caption/Caption", "color/accent", bi);
hud.appendChild(bi); bi.x = 20; bi.y = 1080 - 20 - bi.height;
const sp = glass("Speedometer"); sp.counterAxisAlignItems = "CENTER"; sp.paddingTop = sp.paddingBottom = 24; sp.paddingLeft = sp.paddingRight = 60;
text("28", "Display/Hero", "color/text", sp); text("MPH", "Caption/Caption", "color/text-muted", sp);
hud.appendChild(sp); sp.x = 1920 - 20 - sp.width; sp.y = 1080 - 20 - sp.height;
const ti = toastC.createInstance(); hud.appendChild(ti); ti.x = (1920 - ti.width) / 2; ti.y = 16;

// Main menu
const menu = scene("Main Menu (1920x1080)", 2020, 1920, 1080, { r: 0.12, g: 0.13, b: 0.15 }, { r: 0.05, g: 0.05, b: 0.06 });
created.push(menu.id);
const colm = figma.createAutoLayout("VERTICAL", { name: "MenuColumn", itemSpacing: 10 }); colm.fills = []; colm.resize(400, 100); colm.counterAxisSizingMode = "FIXED";
text("SURRON LIFE", "Display/Hero", "color/text", colm);
text("WHEELIE CITY", "Display/Title", "color/accent", colm);
button("PLAY", "Primary", colm, 400, 64).layoutSizingHorizontal = "FILL";
for (const l of ["GARAGE", "BIKES", "SHOP", "SETTINGS"]) button(l, "Secondary", colm, 400, 52).layoutSizingHorizontal = "FILL";
button("CODES", "Ghost", colm, 400, 52).layoutSizingHorizontal = "FILL";
menu.appendChild(colm); colm.x = 48; colm.y = (1080 - colm.height) / 2;

return { createdNodeIds: created };
