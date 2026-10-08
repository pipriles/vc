package vc

import "core:fmt"
import "core:strings"

// The Options box (0x40ed40): a window over the middle of the tank that
// grows open, with a picture on the left, a title bar, and pages: the menu,
// Settings, Help, Stats, Credits, Utilities and Version Info. Switching page
// wipes the title bar and slides the picture. Buttons have three frames
// (normal, hover, pressed) and act when released over.

BOX_W :: 472 // 0x1d8
BOX_H :: 167 // 0xa7
BOX_X :: (VIEW_W - BOX_W) / 2 // 84
BOX_Y :: 170 // 0xaa
PIC_W :: 200 // the left picture (vcg_2000's width, 0x454b90)
BOX_CX :: BOX_X + PIC_W // page contents (0x437574)
BOX_TEXT_R :: BOX_X + 0x1d6 // right edge of help and credits text
BOX_CLIP :: BOX_Y + 0x85 // help and credits lines are clipped here
SAVER_X :: BOX_CX + 182 // port: screensaver idle buttons on the Utilities page
BAR_Y :: 0x94
ARROW_Y :: 0x134
CLOSE_Y :: 0x91

HELP_LINES :: 161 // 0x42dd68
CREDIT_LINES :: 43 // 0x42d2e8 (32), plus the port's own

Box_Page :: enum {
	Menu,
	Stats,
	Credits,
	Settings,
	Help,
	Utilities,
	Version,
}

Box_State :: enum {
	Closed,
	Opening,
	Open,
	Closing,
}

Box :: struct {
	state:          Box_State,
	w, h:           int, // current size while growing or shrinking
	page, next:     Box_Page,
	switching:      bool, // page wipe running (0x437b18)
	wipe, wipe_v:   int, // title bar wipe (0x437984, 0x43759c)
	pic, pic_v:     int, // picture slide (0x437978, 0x4375e8)
	top, sub:       int, // help / credits: first line and pixel offset (0x437618, 0x437670)
	speed, speed_n: int, // arrow scrolling, speeding up while held (0x43123c, 0x437b30)
	held:           int, // control pressed: index from box_hit, -1 none
	mx, my:         int, // pointer in view coordinates
	down, inside:   bool,
	mood, variant:  int, // stats picture frame and prognosis variant (0x44ddea, 0x44ddec)
	// smooth drawing: values at the start of the last step
	from_w, from_h, from_wipe, from_pic, from_scroll: int,
}

// What the pointer is over.
Box_Hit :: enum {
	None,
	Item, // menu / utilities buttons, toggles, Back: item index in hit_i
	Minus, // frame rate
	Plus,
	Saver_Minus, // screensaver idle time (port)
	Saver_Plus,
	Up, // help and credits scrolling
	Down,
	Close,
}

Line :: struct {
	text:        string,
	style:       int, // 1 heading, 2 highlighted
	center:      bool,
	icon:        int, // 0 none, 1 button (index, frame), 2 gauge bitmap (index, frame)
	index, frame: int,
}

// Help lines (0x42dd68): text, style, icon. Gauge icons index ui.gauges
// (0 mood, 1 health, 2 water, 3 food).
HELP := [HELP_LINES]Line {
	{"TOP SCREEN ICONS", 1, false, 0, 0, 0}, {}, {},
	{"FOOD INDICATOR", 2, false, 2, 3, 5},
	{"This icon tells you just how hungry your spider", 0, false, 0, 0, 0},
	{"is - full or simply ravenous!", 0, false, 0, 0, 0}, {}, {},
	{"WATER INDICATOR", 2, false, 2, 2, 5},
	{"This icon tells you when your spider is ready for", 0, false, 0, 0, 0},
	{"a drink - fully refreshed or gasping with thirst.", 0, false, 0, 0, 0}, {}, {},
	{"HEALTH INDICATOR", 2, false, 2, 1, 5},
	{"The heart icon reveals your spider's fitness", 0, false, 0, 0, 0},
	{"levels - brimming with health or seriously ill.", 0, false, 0, 0, 0}, {}, {}, {},
	{"MOOD INDICATOR", 2, false, 2, 0, 4}, {},
	{"Check your spider's mood with this guage - is", 0, false, 0, 0, 0},
	{"it happy or hassled? Content or annoyed?", 0, false, 0, 0, 0}, {}, {},
	{"BOTTOM SCREEN BUTTONS", 1, false, 0, 0, 0}, {},
	{"HAND", 2, false, 0, 0, 0},
	{"Cycle through the handling options with this", 0, false, 0, 0, 0},
	{"icon - from pick up and prod to tap and touch.", 0, false, 0, 0, 0}, {},
	{"HINT : Use the Right mouse button to quickly", 0, false, 0, 0, 0},
	{"cycle through each handling option. Hold down", 0, false, 0, 0, 0},
	{"the Left mouse button to perform the action.", 0, false, 0, 0, 0}, {}, {},
	{"KNOCK", 2, false, 1, 0, 0},
	{"Use this mode to tap on the glass to attract", 0, false, 0, 0, 0},
	{"attention - but beware, persistent rapping will", 0, false, 0, 0, 0},
	{"annoy your spider.", 0, false, 0, 0, 0}, {}, {},
	{"PICK UP", 2, false, 1, 0, 1},
	{"Use this mode to pick up and move either your spider,", 0, false, 0, 0, 0},
	{"live bait or tank toys. Caution - excessive pet", 0, false, 0, 0, 0},
	{"handling should be avoided.", 0, false, 0, 0, 0}, {}, {},
	{"PROD", 2, false, 1, 0, 2},
	{"Use this mode to gently prod your pet and attract", 0, false, 0, 0, 0},
	{"attention. Warning - overuse will seriously annoy", 0, false, 0, 0, 0},
	{"your pet!", 0, false, 0, 0, 0}, {}, {},
	{"STROKE", 2, false, 1, 0, 3},
	{"Use this tool to stroke your pet. However, she can be", 0, false, 0, 0, 0},
	{"temperamental and too much petting will make", 0, false, 0, 0, 0},
	{"her mad!", 0, false, 0, 0, 0}, {}, {},
	{"CHASE", 2, false, 1, 0, 4},
	{"The playtime button. As you move the cursor the", 0, false, 0, 0, 0},
	{"spider follows it around the tank - unless of", 0, false, 0, 0, 0},
	{"course she's busy eating or in a mood!", 0, false, 0, 0, 0}, {}, {},
	{"FOOD", 2, false, 1, 1, 0},
	{"The spider's favorite icon! This takes you directly", 0, false, 0, 0, 0},
	{"to the cricket basket to pick up live bait. Collect a", 0, false, 0, 0, 0},
	{"cricket and transfer it to the tank to feed", 0, false, 0, 0, 0},
	{"your spider.", 0, false, 0, 0, 0}, {}, {},
	{"WATER TAP", 2, false, 1, 2, 0},
	{"Fill your spider's waterbowl by using this icon.", 0, false, 0, 0, 0}, {}, {},
	{"SCAN MODE / FOLLOW MODE", 2, false, 0, 0, 0},
	{"A multi-functional switch to click you through the", 0, false, 0, 0, 0},
	{"scan and follow options.", 0, false, 0, 0, 0}, {}, {},
	{"FOLLOW MODE", 2, false, 1, 3, 1},
	{"In this mode, your spider remains in the centre of", 0, false, 0, 0, 0},
	{"the screen as the viewfinder follows its every", 0, false, 0, 0, 0},
	{"movement around the tank.", 0, false, 0, 0, 0}, {}, {},
	{"SCAN MODE", 2, false, 1, 3, 0},
	{"In this mode, the viewfinder stays fixed in a position", 0, false, 0, 0, 0},
	{"allowing the spider to crawl in and out of view.", 0, false, 0, 0, 0}, {}, {},
	{"ZOOM IN", 2, false, 1, 4, 0},
	{"Use this function to take a close up view of your", 0, false, 0, 0, 0},
	{"spider as it feeds, crawls or cleans.", 0, false, 0, 0, 0}, {}, {},
	{"ZOOM OUT", 2, false, 1, 5, 0},
	{"Use this function to view the entire tank. You may", 0, false, 0, 0, 0},
	{"also access the tank furniture store from this", 0, false, 0, 0, 0},
	{"view, choosing various plants and toys to put into", 0, false, 0, 0, 0},
	{"your spider's tank.", 0, false, 0, 0, 0}, {}, {},
	{"BROOM", 2, false, 1, 6, 0},
	{"This icon allows you to tidy the tank and to sweep", 0, false, 0, 0, 0},
	{"up debris left after feeding.", 0, false, 0, 0, 0}, {}, {},
	{"OPTIONS", 2, false, 1, 7, 0},
	{"This icon is used to access the various option pages.", 0, false, 0, 0, 0}, {}, {},
	{"VC WEB-SITE", 2, false, 1, 8, 0},
	{"A direct link to the hatching website for Virtual", 0, false, 0, 0, 0},
	{"Creatures. Visit here for the latest news on", 0, false, 0, 0, 0},
	{"Virtual Creatures.", 0, false, 0, 0, 0}, {}, {},
	{"FLOATING PANEL", 2, false, 1, 9, 0},
	{"Miniaturize your spider tank using this mode and", 0, false, 0, 0, 0},
	{"keep watch on your spider while doing other", 0, false, 0, 0, 0},
	{"work on screen.", 0, false, 0, 0, 0}, {}, {}, {},
	{"SETTINGS OPTIONS", 1, false, 0, 0, 0}, {},
	{"FRAME RATE", 2, false, 0, 0, 0},
	{"Choose between 10, 14 and 18 frames per second", 0, false, 0, 0, 0},
	{"screen update to suit the capability of your PC.", 0, false, 0, 0, 0}, {},
	{"SOUND", 2, false, 0, 0, 0},
	{"Turn the sound on or off with this button (depends", 0, false, 0, 0, 0},
	{"if you're too squeamish to listen to the crunching and", 0, false, 0, 0, 0},
	{"slurping as your spider devours its prey!)", 0, false, 0, 0, 0}, {},
	{"FULL SCREEN", 2, false, 0, 0, 0},
	{"This button will allow you to switch between running", 0, false, 0, 0, 0},
	{"the application in Full Screen mode or as a", 0, false, 0, 0, 0},
	{"standard window.", 0, false, 0, 0, 0}, {},
	{"HELP TEXT", 2, false, 0, 0, 0},
	{"Turn the flyover Help Text on or off with this button.", 0, false, 0, 0, 0}, {},
	// (Freeze Simulation isn't ported: its lines stay so the line numbers
	// the buttons jump to match the original)
	{"", 0, false, 0, 0, 0}, {"", 0, false, 0, 0, 0}, {"", 0, false, 0, 0, 0},
	{"", 0, false, 0, 0, 0}, {}, {},
	{"ADDITIONAL HELP", 1, false, 0, 0, 0}, {},
	{"Additional help can be found in the README.DOC", 0, false, 0, 0, 0},
	{"that shipped with the installation. Alternatively,", 0, false, 0, 0, 0},
	{"for up to the minute hints and tips, visit the", 0, false, 0, 0, 0},
	{"Help/FAQ pages on the VC Website found at :", 0, false, 0, 0, 0}, {},
	{"http://www.virtualcreatures.com/vc", 0, false, 1, 8, 0}, {},
}

CREDITS := [CREDIT_LINES]Line {
	{"VIRTUAL CREATURES", 1, true, 0, 0, 0},
	{"CREDITS", 1, true, 0, 0, 0}, {},
	{"Virtual Creatures have emerged directly from the", 0, false, 0, 0, 0},
	{"hatching rooms of leading multi-media agency Global", 0, false, 0, 0, 0},
	{"Beach. Described as 'pets with attitude', the", 0, false, 0, 0, 0},
	{"painstaking task of building these virtual beings", 0, false, 0, 0, 0},
	{"with full artificial intelligence was entirely the", 0, false, 0, 0, 0},
	{"work of the group's expert team of digital DNA", 0, false, 0, 0, 0},
	{"engineers.", 0, false, 0, 0, 0}, {}, {},
	{"Original Concept", 2, true, 0, 0, 0}, {"Clive Jackson", 0, true, 0, 0, 0}, {},
	{"Lead Programmer", 2, true, 0, 0, 0}, {"Phil Higgs", 0, true, 0, 0, 0}, {},
	{"Digital Design", 2, true, 0, 0, 0}, {"Jinx", 0, true, 0, 0, 0}, {},
	{"Additional Programming", 2, true, 0, 0, 0}, {"Iain Lewis", 0, true, 0, 0, 0}, {},
	{"Sound FX", 2, true, 0, 0, 0}, {"Chris Ford", 0, true, 0, 0, 0}, {},
	{"Additional Graphics", 2, true, 0, 0, 0}, {"Dan Northover", 0, true, 0, 0, 0},
	{"Gary Ellis", 0, true, 0, 0, 0}, {"Stephen Rose", 0, true, 0, 0, 0}, {},
	// the browser port
	{"Browser Port", 2, true, 0, 0, 0}, {"Oswald Capriles", 0, true, 0, 0, 0}, {},
	{"Rescued from the original Windows release: the", 0, false, 0, 0, 0},
	{"program and its data were reverse engineered", 0, false, 0, 0, 0},
	{"from the old binaries and rebuilt in Odin for", 0, false, 0, 0, 0},
	{"WebAssembly, so the spiders can live on in a", 0, false, 0, 0, 0},
	{"web browser, behaving just as they always did.", 0, false, 0, 0, 0}, {}, {}, {},
}

// Stats prognosis (0x42cde8): four ways of saying each of five states.
PROGNOSIS := [20]string {
	"Ecstatically happy! Keep it up.",
	"Perfect pet owner - your spider couldn't be happier.",
	"Peak condition - keep up the good work.",
	"Perfect - supremely happy, couldn't be better.",
	"She's in a good mood - but she can still improve.",
	"Almost perfect - she's happy and content.",
	"Contented - relaxed and quite happy.",
	"Doing well - almost perfect!",
	"She's in a good, but not great, mood.",
	"More attention will pay dividends!",
	"A bit moody - could be better.",
	"A little fractious - may be temperamental.",
	"Unhappy - give your pet some serious attention.",
	"Neglected - in need of attention.",
	"Lonely and depressed - tend to her now.",
	"Sad and lonely - urgent attention required.",
	"Dead - your pet has died, neglected and unloved.",
	"Dead - neglect has killed your pet.",
	"Sorry, but your pet has died!",
	"Dead - too late, your pet has gone to cyberspace heaven!",
}

MENU_ITEMS := [5]string{"Settings", "Help", "Stats", "Credits", "Utilities"}
SETTING_ITEMS := [5]string{"Frame Rate", "Sound", "Full Screen", "Help Text", "Smooth Motion"} // (port: smooth in the Freeze Simulation slot)
SAVER_IDLE := [5]int{0, 2, 5, 10, 30} // screensaver after these idle minutes, 0 never
UTILITY_ITEMS := [4]string{"Download Crickets", "Resurrect Creature", "Version Info", "Screensaver"}

// Fonts (0x40e... CreateFontA): Arial bold 18, bold 12, bold italic 16.
FONT_BIG :: 1
FONT_SMALL :: 2
FONT_ITALIC :: 3
WHITE :: 0xffffff
ORANGE :: 0xefbb3f // 0x3fbbef BGR
TEAL :: 0x008080
LIGHT_YELLOW :: 0xffff80
RED :: 0xff0000

// Bitmaps (vcg_2000..2022).
Box_Art :: struct {
	frame, bar:             Bitmap, // 2015 window, 2016 title bar
	logo, stats, beach:     Bitmap, // pictures 2000, 2012 (5 frames), 2013
	button, back:           Bitmap, // 2002 >>, 2010 <<
	toggle:                 Bitmap, // 2003: off / on, 3 frames each
	minus, plus:            Bitmap, // 2004, 2005
	up, down:               Bitmap, // 2006, 2007
	fps:                    Bitmap, // 2001
	close:                  Bitmap, // 2014
	titles:                 [6]Bitmap, // 2017 STATS 2018 CREDITS 2019 OPTIONS 2020 SETTINGS 2021 HELP 2022 UTILITIES
}

box_art_load :: proc(a: ^Box_Art) {
	ld :: proc(id: int) -> Bitmap {
		b, _ := bmp_load(load_file(fmt.tprintf("bitmaps/vcg_%d.bmp", id)))
		return b
	}
	a.frame, a.bar = ld(2015), ld(2016)
	a.logo, a.stats, a.beach = ld(2000), ld(2012), ld(2013)
	a.button, a.back, a.toggle = ld(2002), ld(2010), ld(2003)
	a.minus, a.plus, a.up, a.down = ld(2004), ld(2005), ld(2006), ld(2007)
	a.fps, a.close = ld(2001), ld(2014)
	for i in 0 ..< 6 do a.titles[i] = ld(2017 + i)
}

// --- opening, closing, switching pages ------------------------------------------

// The Options button (0x41c4b0 command 6).
box_toggle :: proc() {
	b := &game.ui.box
	switch b.state {
	case .Closed, .Closing:
		if b.state == .Closed do b.w, b.h = 0, 0
		b.state = .Opening
		b.page, b.switching, b.held = .Menu, false, -1
	case .Opening, .Open:
		b.state = .Closing
		b.held = -1
	}
}

// Right-click help: the help page at a line, opening the box if needed
// (wnd_proc 0x205 -> 0x4514ba).
open_help :: proc(line: int) {
	b := &game.ui.box
	if b.state == .Open {
		box_switch(.Help)
	} else {
		if b.state == .Closed do b.w, b.h = 0, 0
		b.state = .Opening
		b.page, b.switching, b.held = .Help, false, -1
	}
	b.top, b.sub = line, 0
	b.speed, b.speed_n = 5, 0
	b.from_scroll = scroll_pos(b.top, b.sub)
}

// Help / credits scroll as one number: line y = BOX_Y + 20 * line - pos.
scroll_pos :: proc(top, sub: int) -> int {return top * 20 - sub}

// The values to draw with: between the last two steps when smooth.
box_remember :: proc() {
	b := &game.ui.box
	b.from_w, b.from_h, b.from_wipe, b.from_pic = b.w, b.h, b.wipe, b.pic
	b.from_scroll = scroll_pos(b.top, b.sub)
}

box_switch :: proc(to: Box_Page) {
	b := &game.ui.box
	speed := settings.frame_rate == 2 ? 40 : settings.frame_rate == 1 ? 60 : 80
	b.next = to
	b.switching = true
	b.wipe, b.wipe_v = 0, speed
	b.pic, b.pic_v = 0, speed / 2
	b.from_wipe, b.from_pic = 0, 0
	b.held = -1
	host_sound(418)
}

// Once a frame.
box_tick :: proc() {
	b := &game.ui.box
	switch b.state {
	case .Closed:
		return
	case .Opening:
		// InflateRect by 40 x 18 a frame
		b.w = min(b.w + 80, BOX_W)
		b.h = min(b.h + 36, BOX_H)
		if b.w == BOX_W && b.h == BOX_H do b.state = .Open
		return
	case .Closing:
		b.w = max(b.w - 80, 0)
		b.h = max(b.h - 36, 0)
		if b.w == 0 && b.h == 0 do b.state = .Closed
		return
	case .Open:
	}
	if b.switching {
		bar := &assets.options_box.bar
		b.wipe += b.wipe_v
		if b.wipe >= bar.w {
			b.wipe -= b.wipe_v
			b.wipe_v, b.pic_v = -b.wipe_v, -b.pic_v
			host_sound(417)
		}
		b.pic += b.pic_v
		if b.pic >= bar.w - 1 do b.pic = PIC_W - 1
		if b.pic < 1 do b.pic = 0
		if b.wipe < 1 {
			b.switching = false
			b.page = b.next
			if b.page == .Help || b.page == .Credits {
				if b.sub == 0 && b.top == 0 do b.sub = 20
			}
		}
		return
	}
	// holding a scroll arrow: faster and faster (0x40f... arrows)
	hit, _ := box_hit(b.mx, b.my)
	if b.down && b.held >= 0 && Box_Hit(b.held >> 8) == hit && (hit == .Up || hit == .Down) {
		lines := b.page == .Help ? HELP_LINES : CREDIT_LINES
		if hit == .Up {
			b.sub += b.speed
			if b.sub > 19 {
				b.top -= 1
				if b.top < -6 do b.top = lines
				b.sub = 0
			}
		} else {
			b.sub -= b.speed
			if b.sub < 1 {
				b.top += 1
				if b.top > lines - 1 do b.top = -6
				b.sub = 20
			}
		}
		b.speed_n += 1
		if b.speed_n > b.speed * 3 {
			b.speed += 5
			b.speed_n = 0
			if b.speed > 10 do b.speed = 20
		}
	} else {
		b.speed, b.speed_n = 5, 0
	}
}

// --- layout and pointer --------------------------------------------------------

box_left :: proc(w := -1) -> int {return BOX_X + (BOX_W - (w < 0 ? game.ui.box.w : w)) / 2}
box_top :: proc(h := -1) -> int {return BOX_Y + (BOX_H - (h < 0 ? game.ui.box.h : h)) / 2}

in_rect :: proc(px, py, x, y, w, h: int) -> bool {return px >= x && px < x + w && py >= y && py < y + h}

// Row y of item i on the current page, and its button bitmap.
item_row :: proc(page: Box_Page, i: int) -> (y: int, bmp: ^Bitmap, frames: int) {
	a := &assets.options_box
	top := BOX_Y
	#partial switch page {
	case .Menu:
		return top + 3 + 32 * i, &a.button, 3
	case .Utilities:
		if i == 4 do return top + 0x89, &a.back, 3
		return top + 3 + 32 * i, &a.button, 3
	case .Settings:
		if i == 5 do return top + 0x89, &a.back, 3
		if i == 0 do return top + 3, &a.minus, 3
		return top + 3 + 26 * i, &a.toggle, 6
	}
	return top + 0x89, &a.back, 3 // Back
}

item_count :: proc(page: Box_Page) -> int {
	switch page {
	case .Menu: return 5
	case .Utilities: return 5
	case .Settings: return 6
	case .Stats, .Credits, .Help, .Version: return 1
	}
	return 0
}

// What is under (px, py). Packed with the item index for `held`.
box_hit :: proc(px, py: int) -> (Box_Hit, int) {
	b := &game.ui.box
	a := &assets.options_box
	if b.state != .Open do return .None, 0
	if in_rect(px, py, box_left() + 0x1bd, CLOSE_Y, a.close.w, a.close.h / 3) do return .Close, 0
	if b.switching do return .None, 0
	for i in 0 ..< item_count(b.page) {
		y, bmp, frames := item_row(b.page, i)
		fh := bmp.h / frames
		if b.page == .Settings && i == 0 {
			if in_rect(px, py, BOX_CX + 12, y, a.minus.w, fh) do return .Minus, 0
			if in_rect(px, py, BOX_CX + 12 + a.minus.w, y, a.plus.w, a.plus.h / 3) do return .Plus, 0
			continue
		}
		if in_rect(px, py, BOX_CX + 12, y, bmp.w, fh) do return .Item, i
		if b.page == .Utilities && i == 3 {
			mh := a.minus.h / 3
			if in_rect(px, py, SAVER_X, y, a.minus.w, mh) do return .Saver_Minus, 0
			if in_rect(px, py, SAVER_X + a.minus.w, y, a.plus.w, mh) do return .Saver_Plus, 0
		}
	}
	if b.page == .Help || b.page == .Credits {
		if in_rect(px, py, BOX_CX + 0xd7, ARROW_Y, a.up.w, a.up.h / 3) do return .Up, 0
		if in_rect(px, py, BOX_CX + 0xd7 + a.up.w, ARROW_Y, a.down.w, a.down.h / 3) do return .Down, 0
	}
	return .None, 0
}

// The window and its frame, for routing the pointer.
box_covers :: proc(vx, vy: int) -> bool {
	b := &game.ui.box
	if b.state == .Closed do return false
	return in_rect(vx, vy, box_left() - 10, 0x90, assets.options_box.frame.w, assets.options_box.frame.h)
}

// Pointer events in the tank view while the box is up; true when taken.
box_pointer :: proc(ev: Pointer_Event, vx, vy: int) -> bool {
	b := &game.ui.box
	b.mx, b.my = vx, vy
	b.inside = ev != .Leave && box_covers(vx, vy)
	#partial switch ev {
	case .Leave:
		b.down, b.held = false, -1
		return false
	case .Down:
		if !b.inside do return false
		b.down = true
		hit, i := box_hit(vx, vy)
		b.held = hit == .None ? -1 : int(hit) << 8 | i
		return true
	case .Up:
		was := b.held
		b.down, b.held = false, -1
		if was < 0 do return b.inside
		hit, i := box_hit(vx, vy)
		if int(hit) << 8 | i == was do box_activate(hit, i)
		return true
	}
	if b.inside do set_cursor(0)
	return b.inside
}

box_activate :: proc(hit: Box_Hit, i: int) {
	b := &game.ui.box
	#partial switch hit {
	case .Close:
		box_toggle()
		return
	case .Minus:
		// (sic: the left button counts up, the right one down; both wrap)
		settings.frame_rate = (settings.frame_rate + 1) % 3
		settings_changed()
		return
	case .Plus:
		settings.frame_rate = (settings.frame_rate + 2) % 3
		settings_changed()
		return
	case .Saver_Minus:
		settings.saver_idle = (settings.saver_idle + len(SAVER_IDLE) - 1) % len(SAVER_IDLE)
		settings_changed()
		return
	case .Saver_Plus:
		settings.saver_idle = (settings.saver_idle + 1) % len(SAVER_IDLE)
		settings_changed()
		return
	case .Item:
	case:
		return
	}
	switch b.page {
	case .Menu:
		pages := [5]Box_Page{.Settings, .Help, .Stats, .Credits, .Utilities}
		if pages[i] == .Help || pages[i] == .Credits {
			b.top, b.sub = 0, 20
			b.speed, b.speed_n = 5, 0
			b.from_scroll = scroll_pos(b.top, b.sub)
		}
		box_switch(pages[i])
	case .Settings:
		switch i {
		case 1:
			settings.sound = !settings.sound
			host_set_sound(settings.sound)
			host_sound(400)
		case 2:
			host_fullscreen()
		case 3:
			settings.help_text = !settings.help_text
			settings_changed()
		case 4:
			settings.smooth = !settings.smooth
			settings_changed()
		case 5:
			box_switch(.Menu)
		}
	case .Utilities:
		switch i {
		case 0: download_crickets()
		case 1: tank_resurrect()
		case 2: box_switch(.Version)
		case 3: host_saver() // full screen now
		case 4: box_switch(.Menu)
		}
	case .Version:
		box_switch(.Utilities)
	case .Stats, .Credits, .Help:
		box_switch(.Menu)
	}
}

// Download Crickets went to the Virtual Creatures site for more; the port
// adds a box's worth to the store.
DOWNLOAD_CRICKETS :: 12

download_crickets :: proc() {
	game.storage += DOWNLOAD_CRICKETS
	refill_box()
	host_message("DOWNLOAD CRICKETS",
		fmt.tprintf("%d crickets have been added to your store.", DOWNLOAD_CRICKETS))
}

settings_changed :: proc() {
	host_settings(i32(settings.frame_rate), settings.smooth, settings.help_text, i32(SAVER_IDLE[settings.saver_idle]))
}

// --- drawing --------------------------------------------------------------------------

box_draw :: proc() {
	b := &game.ui.box
	a := &assets.options_box
	if b.state == .Closed do return
	w, h := lerp_pos(b.from_w, b.w, 100), lerp_pos(b.from_h, b.h, 50)
	wipe, pic := lerp_pos(b.from_wipe, b.wipe, 100), lerp_pos(b.from_pic, b.pic, 50)
	left, top := box_left(w), box_top(h)

	// the see-through background: palette 6 on every other pixel
	if b.state == .Open && !b.switching {
		dither(BOX_CX, top, BOX_W - PIC_W, h)
	} else {
		dither(left, top, w, h)
	}
	if b.state != .Open {
		draw_stretched_keyed(&a.frame, left, top, w, h)
	} else if !b.switching {
		box_draw_page()
	}

	// window frame, title bar, title, picture
	draw_keyed(&a.frame, left - 10, 0x90)
	page := b.page
	if b.switching && b.wipe_v < 1 do page = b.next
	title, pic_bmp, pic_frames := page_art(page)
	pic_x := pic
	frame := 0
	if pic_bmp == &a.stats {
		frame = b.mood
	}
	ph := pic_bmp.h / pic_frames
	if !b.switching {
		draw_keyed(&a.bar, left + 0x2a, BAR_Y)
		draw_keyed(title, left + 0x43, BAR_Y + 5)
		blit(pic_bmp, left, top + 1, 0, frame * ph, pic_bmp.w, ph - 2)
	} else {
		draw_keyed_cols(&a.bar, left + 0x2a + wipe, BAR_Y, 0, a.bar.w - wipe)
		if title.w + 0x19 + wipe <= a.bar.w {
			draw_keyed(title, left + 0x43 + wipe, BAR_Y + 5)
		}
		blit(pic_bmp, left, top + 1, pic_x, frame * ph, pic_bmp.w - pic_x, ph - 2)
	}

	// close button
	hit, _ := box_hit(b.mx, b.my)
	cx := left + 0x1bd
	ch := a.close.h / 3
	draw_keyed_part(&a.close, cx, CLOSE_Y, ctl_frame(.Close, 0) * ch, ch)
	if hit == .Close && settings.help_text {
		ui_text(cx, CLOSE_Y + ch + 2, "Close the Options box.")
	}
}

page_art :: proc(page: Box_Page) -> (title, pic: ^Bitmap, frames: int) {
	a := &assets.options_box
	switch page {
	case .Menu: return &a.titles[2], &a.logo, 1
	case .Stats: return &a.titles[0], &a.stats, 5
	case .Credits: return &a.titles[1], &a.beach, 1
	case .Settings: return &a.titles[3], &a.logo, 1
	case .Help: return &a.titles[4], &a.logo, 1
	case .Utilities, .Version: return &a.titles[5], &a.logo, 1
	}
	return &a.titles[2], &a.logo, 1
}

// Frame of a control: 1 hovered, 2 pressed (held and still over it).
ctl_frame :: proc(hit: Box_Hit, i: int) -> int {
	b := &game.ui.box
	h, hi := box_hit(b.mx, b.my)
	if !b.inside || h != hit || hi != i do return 0
	if b.down && b.held == int(hit) << 8 | i do return 2
	return 1
}

box_text :: proc(x, y: int, s: string, font := FONT_BIG, color := WHITE) {
	ui_text_ex(x, y, 0, 0, s, i32(font), i32(color), 0)
}

box_draw_page :: proc() {
	b := &game.ui.box
	a := &assets.options_box
	top := BOX_Y
	switch b.page {
	case .Menu:
		for name, i in MENU_ITEMS {
			y, bmp, n := item_row(.Menu, i)
			fh := bmp.h / n
			draw_keyed_part(bmp, BOX_CX + 12, y, ctl_frame(.Item, i) * fh, fh)
			box_text(BOX_CX + 0x50, y + 4, name)
		}
	case .Settings:
		for name, i in SETTING_ITEMS {
			y, bmp, n := item_row(.Settings, i)
			fh := bmp.h / n
			if i == 0 {
				draw_keyed_part(&a.minus, BOX_CX + 12, y, ctl_frame(.Minus, 0) * fh, fh)
				ph := a.plus.h / 3
				draw_keyed_part(&a.plus, BOX_CX + 12 + a.minus.w, y, ctl_frame(.Plus, 0) * ph, ph)
			} else {
				on := i == 1 ? settings.sound : i == 2 ? settings.fullscreen : i == 3 ? settings.help_text : settings.smooth
				draw_keyed_part(bmp, BOX_CX + 12, y, ((on ? 3 : 0) + ctl_frame(.Item, i)) * fh, fh)
			}
			box_text(BOX_CX + 0x50, y + 4, name)
		}
		draw_back(5)
		draw_keyed(&a.fps, BOX_CX + 0xc9, top + 8)
		fps := [3]string{"10", "14", "18"}
		box_text(BOX_CX + 0xcc, top + 10, fps[clamp(settings.frame_rate, 0, 2)], FONT_SMALL, RED)
	case .Utilities:
		for name, i in UTILITY_ITEMS {
			y, bmp, n := item_row(.Utilities, i)
			fh := bmp.h / n
			draw_keyed_part(bmp, BOX_CX + 12, y, ctl_frame(.Item, i) * fh, fh)
			box_text(BOX_CX + 0x50, y + 4, name)
			if i == 3 {
				// port: how long idle before the screensaver starts
				mh := a.minus.h / 3
				draw_keyed_part(&a.minus, SAVER_X, y, ctl_frame(.Saver_Minus, 0) * mh, mh)
				draw_keyed_part(&a.plus, SAVER_X + a.minus.w, y, ctl_frame(.Saver_Plus, 0) * mh, mh)
				m := SAVER_IDLE[settings.saver_idle]
				box_text(BOX_CX + 0x50, y + 21, m == 0 ? "when idle: never" : fmt.tprintf("when idle: after %d min", m), FONT_SMALL, LIGHT_YELLOW)
			}
		}
		draw_back(4)
	case .Stats:
		draw_stats()
		draw_back(0)
	case .Credits:
		draw_lines(CREDITS[:], false)
		draw_arrows()
		draw_back(0)
	case .Help:
		draw_lines(HELP[:], true)
		draw_arrows()
		draw_back(0)
	case .Version:
		y := top + 3
		box_text(BOX_CX + 0x50, y + 4, "VERSION INFO", FONT_BIG, LIGHT_YELLOW)
		y += 0x1e
		name := data_variant == "rk" ? "Red Knee Tarantula" : "Chile Rose Tarantula"
		box_text(BOX_CX + 8, y, fmt.tprintf("Creature : %s", name), FONT_SMALL)
		y += 0x18
		box_text(BOX_CX + 8, y, "Engine Version No : 2.0.0b", FONT_SMALL)
		y += 0xc
		box_text(BOX_CX + 8, y, "VCG.DLL Version No : 2.0.0b", FONT_SMALL)
		y += 0xc
		box_text(BOX_CX + 8, y, "VCG2.DLL Version No : 2.0.0", FONT_SMALL)
		y += 0x18
		box_text(BOX_CX + 8, y, "REGISTERED VERSION", FONT_SMALL)
		draw_back(0)
	}
}

draw_back :: proc(i: int) {
	a := &assets.options_box
	y := BOX_Y + 0x89
	fh := a.back.h / 3
	draw_keyed_part(&a.back, BOX_CX + 12, y, ctl_frame(.Item, i) * fh, fh)
	box_text(BOX_CX + 0x50, y + 4, "Back")
}

draw_arrows :: proc() {
	a := &assets.options_box
	uh, dh := a.up.h / 3, a.down.h / 3
	draw_keyed_part(&a.up, BOX_CX + 0xd7, ARROW_Y, ctl_frame(.Up, 0) * uh, uh)
	draw_keyed_part(&a.down, BOX_CX + 0xd7 + a.up.w, ARROW_Y, ctl_frame(.Down, 0) * dh, dh)
}

// Scrolling lines of help or credits: nine rows 20 px apart, clipped at
// the box's lower edge.
draw_lines :: proc(lines: []Line, help: bool) {
	b := &game.ui.box
	top := BOX_Y
	// between steps when smooth (unless the scroll wrapped round)
	pos := lerp_pos(b.from_scroll, scroll_pos(b.top, b.sub), 40)
	first := pos >= 0 ? (pos + 19) / 20 : -((-pos) / 20) // ceil(pos / 20)
	b_sub := first * 20 - pos
	for row in 0 ..< 9 {
		idx := first + row
		if idx < 0 || idx >= len(lines) do continue
		l := lines[idx]
		y := b_sub + row * 20 + top
		if y >= BOX_CLIP do continue
		bottom := min(y + 20, BOX_CLIP)
		left := BOX_CX + 5
		switch l.icon {
		case 1:
			ui := &game.ui
			btn := &ui.buttons[l.index]
			blit_clipped_keyed(&btn.bmp, BOX_CX + 2, row * 20 - btn.fh / 2 + b_sub - 4 + top,
				l.frame * btn.fh, btn.fw, btn.fh, top + 3, BOX_CLIP)
			left = BOX_CX + btn.fw + 6
		case 2:
			g := &game.ui.gauges[l.index]
			n := l.index == 0 ? 8 : 10
			fh := g.h / n
			blit_clipped_keyed(g, BOX_CX + 2, row * 20 - fh / 2 + b_sub - 4 + top,
				l.frame * fh, g.w, fh, top + 3, BOX_CLIP)
			left = BOX_CX + g.w + 6
		}
		if l.text == "" do continue
		font, color := FONT_SMALL, WHITE
		switch l.style {
		case 1: font = FONT_BIG
		case 2: font, color = FONT_ITALIC, ORANGE
		}
		if help && l.style == 1 {
			fill_rect(BOX_CX + 4, y, BOX_X + 0x1d4 - (BOX_CX + 4), min(y + 18, BOX_CLIP) - y, TEAL)
		}
		flags: i32 = 4 // clip
		if l.center do flags |= 1
		ui_text_ex(left, y, BOX_TEXT_R - left, bottom - y, l.text, i32(font), i32(color), flags)
	}
}

draw_stats :: proc() {
	b := &game.ui.box
	l := &game.life
	st := &game.stats
	x := BOX_CX + 0xc
	y := BOX_Y - 2
	now := host_time()
	box_text(x, y + 4, fmt.tprintf("Birth Date     : %s", format_date(l.born_at)), FONT_SMALL)
	y += 0xc
	if l.dead {
		box_text(x, y + 4, fmt.tprintf("Death Date   : %s", format_date(l.died_at)), FONT_SMALL)
		y += 0xc
	}
	end := l.dead && l.died_at > 0 ? l.died_at : now
	box_text(x, y + 4, fmt.tprintf("Time Alive   : %s", format_span(end - l.born_at)), FONT_SMALL)
	y += l.dead ? 0x10 : 0x1c
	box_text(x, y + 4, fmt.tprintf("Total No of Crickets Eaten : %d", game.eaten), FONT_SMALL)
	y += 0xc
	box_text(x, y + 4, fmt.tprintf("No of Resurrections : %d", l.resurrections), FONT_SMALL)
	y += 0x10
	box_text(x, y + 4, fmt.tprintf("Health : %03d%%     Thirst : %03d%%     Hunger : %03d%%",
		st.health, st.water, st.food), FONT_SMALL)
	y += 0x10
	box_text(x, y + 4, "Prognosis :", FONT_SMALL)
	ui_text_ex(x, y + 0x10, BOX_TEXT_R - x, 0x1a, PROGNOSIS[b.mood * 4 + b.variant],
		FONT_SMALL, WHITE, 2)
}

// The stats picture and prognosis follow the temperament; a new state
// picks one of its four sayings (0x40ed40, while drawing).
stats_mood :: proc() {
	b := &game.ui.box
	t := game.stats.temperament
	state := t >= 7 ? 0 : t >= 5 ? 1 : t >= 3 ? 2 : t >= 1 ? 3 : 4
	if state != b.mood {
		b.mood = state
		b.variant = min(rand_n(4), 3)
	}
}

DAYS := [7]string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
MONTHS := [12]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

// "%s %02d %s %04d   %02d:%02d:%02d" (0x41da00), in UTC: the host gives
// unix seconds only.
format_date :: proc(t: f64) -> string {
	if t <= 0 do return "-"
	secs := i64(t) + i64(host_tz_offset()) * 60
	days := secs / 86400
	rem := secs % 86400
	if rem < 0 {rem += 86400; days -= 1}
	// civil from days (Howard Hinnant)
	z := days + 719468
	era := (z >= 0 ? z : z - 146096) / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	yy := yoe + era * 400
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	d := doy - (153 * mp + 2) / 5 + 1
	m := mp < 10 ? mp + 3 : mp - 9
	if m <= 2 do yy += 1
	wd := (days % 7 + 11) % 7 // 1970-01-01 was a Thursday
	return fmt.tprintf("%s %02d %s %04d   %02d:%02d:%02d", DAYS[wd], d, MONTHS[m - 1], yy,
		rem / 3600, rem / 60 % 60, rem % 60)
}

format_span :: proc(secs: f64) -> string {
	m := max(0, int(secs / 60))
	return fmt.tprintf("Days: %d, Hours: %d, Minutes: %d", m / 1440, m / 60 % 24, m % 60)
}

// --- drawing helpers ------------------------------------------------------------------

dither :: proc(x0, y0, w, h: int) {
	for j := 0; j < h; j += 2 {
		y := y0 + j
		if y < 0 || y >= dst.h do continue
		for i := 0; i < w; i += 2 {
			x := x0 + i
			if x >= 0 && x < dst.w do dst.px[y * dst.w + x] = 6
		}
	}
}

fill_rect :: proc(x0, y0, w, h: int, rgb: int) {
	// solid colour: the nearest palette entry
	p := nearest_palette(rgb)
	for y in max(y0, 0) ..< min(y0 + h, dst.h) do for x in max(x0, 0) ..< min(x0 + w, dst.w) {
		dst.px[y * dst.w + x] = p
	}
}

nearest_palette :: proc(rgb: int) -> u8 {
	r, g, bl := (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
	best, dist := 0, max(int)
	for c, i in state.palette {
		dr, dg, db := int(c[0]) - r, int(c[1]) - g, int(c[2]) - bl
		if d := dr * dr + dg * dg + db * db; d < dist do best, dist = i, d
	}
	return u8(best)
}

// Unkeyed copy of part of a bitmap (BitBlt).
blit :: proc(b: ^Bitmap, x0, y0, sx, sy, w, h: int) {
	for j in 0 ..< h {
		y := y0 + j
		if y < 0 || y >= dst.h || sy + j >= b.h do continue
		for i in 0 ..< w {
			x := x0 + i
			if x < 0 || x >= dst.w || sx + i >= b.w do continue
			dst.px[y * dst.w + x] = b.pixels[(sy + j) * b.w + sx + i]
		}
	}
}

// Keyed copy of the columns [0, w) of a bitmap.
draw_keyed_cols :: proc(b: ^Bitmap, x0, y0, sx, w: int) {
	if len(b.pixels) == 0 do return
	key := b.pixels[0]
	for j in 0 ..< b.h {
		y := y0 + j
		if y < 0 || y >= dst.h do continue
		for i in 0 ..< w {
			x := x0 + i
			if x < 0 || x >= dst.w || sx + i >= b.w do continue
			if p := b.pixels[j * b.w + sx + i]; p != key do dst.px[y * dst.w + x] = p
		}
	}
}

// Keyed rows [sy, sy+h), clipped to [clip_top, clip_bottom) vertically.
blit_clipped_keyed :: proc(b: ^Bitmap, x0, y0, sy, w, h, clip_top, clip_bottom: int) {
	if len(b.pixels) == 0 do return
	key := b.pixels[0]
	for j in 0 ..< h {
		y := y0 + j
		if y < clip_top || y >= clip_bottom || y < 0 || y >= dst.h || sy + j >= b.h do continue
		for i in 0 ..< w {
			x := x0 + i
			if x < 0 || x >= dst.w do continue
			if p := b.pixels[(sy + j) * b.w + i]; p != key do dst.px[y * dst.w + x] = p
		}
	}
}

// A bitmap stretched to w x h, keyed (StretchBlt then the keyed copy).
draw_stretched_keyed :: proc(b: ^Bitmap, x0, y0, w, h: int) {
	if w <= 0 || h <= 0 || len(b.pixels) == 0 do return
	key := b.pixels[0]
	for j in 0 ..< h {
		y := y0 + j
		if y < 0 || y >= dst.h do continue
		sy := j * b.h / h
		for i in 0 ..< w {
			x := x0 + i
			if x < 0 || x >= dst.w do continue
			if p := b.pixels[sy * b.w + i * b.w / w]; p != key do dst.px[y * dst.w + x] = p
		}
	}
}

_ :: strings
