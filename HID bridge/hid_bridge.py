"""HID -> MIDI bridge for ReaScratch: NI Traktor Kontrol S4 MK3 / S2 MK3, S3, S4 MK2, S2 MK2, S2 MK1 (USB HID, no
authentication).

ReaScratch (a JSFX) reads MIDI only, so this program reads the unit's HID input reports and sends MIDI with the
DDJ-FLX4's numbers to a virtual MIDI port (Windows: a loopMIDI port; macOS: it makes its own port "ReaScratch HID
Bridge" when no port matches --port). In ReaScratch pick the
preset "HID bridge (NI S2/S3/S4) deck 1 / deck 2" (the FLX4's numbers, a finer jog: 2880 ticks per turn).

Usage (ReaScratch-HID-Bridge.exe / the macOS app take the same options; with Python, from this file's folder):
  python hid_bridge.py --list-ports                       # MIDI output ports
  python hid_bridge.py                                    # find a unit, send to the "loopMIDI Port" port
  python hid_bridge.py --port "loopMIDI Port" --tempo-invert --s2-ticks 1024
  python hid_bridge.py --dry-run                          # print the MIDI instead of sending it
  python hid_bridge.py --selftest                         # no unit needed: feed made-up reports, check the MIDI
  python hid_bridge.py --report                           # for testers: hid_bridge_report.txt to send back (read only)

What it sends (left deck = MIDI ch 1, right deck = ch 2; deck C / D (S4, S3: CH3 / CH4) are ignored: left is always ch 1):
  jog top    CC 0x22, 64-centre relative (64 + ticks, split into steps of at most 63), 2880 ticks per turn
  jog touch  note 0x36        PLAY 0x0B   CUE 0x0C   SYNC 0x58 (SHIFT + SYNC = 0x60, tempo range)   SHIFT 0x3F
  tempo      CC 0x00 / 0x20 (14-bit, the maximum = the + end)         channel fader CC 0x13 (ch 1 / 2)
  headphone cue (PFL) note 0x54     crossfader ch 7 CC 0x1F / 0x3F (14-bit)
  pads       HOT CUE mode: ch 8 / 10 notes 0-7 (SHIFT: ch 9 / 11)      SAMPLES mode: ch 8 / 10 notes 0x30-0x37
             (S2 MK1 / MK2: the SAMPLES button flips the 4 pads between the modes; S4 MK2: the HOTCUE row = hot cues 1-4,
             the REMIX row = samples 1-4)
Report layouts from Mixxx's mappings. Not
tried on any unit yet. The older units (S3, S4 MK2, S2 MK2, S2 MK1) count the jog in 8 bits (768 / 1024 per turn,
Mixxx's values; --s3-ticks / --mk2-ticks) and their faders reach 16..4080 (stretched to the full range); the S2 MK1's
top touch is a pressure value, cut at the unit's own calibration (feature report 0xD4). MK3:
  the S4's ticks per turn of the relative counter (2880 assumed), the S2's (600 assumed, --s2-ticks), which end of the
  tempo fader sends the maximum (assumed the top = the slow end, so it is turned over; --tempo-invert turns that off).
Lights (⚪77): ReaScratch's lights (light type "Reloop RGB", which the HID bridge presets pick) come in on a second MIDI
  port, "ReaScratch LED" (--led-port; Windows: a second loopMIDI port of that name, enabled in REAPER as an output only:
  as an input it would bring the lights back as button presses; macOS: the bridge makes it), and go out as the unit's
  LED output reports: PLAY, CUE, SYNC, headphone cue, SHIFT, the pad mode buttons, the pads in their colours (the
  nearest of the unit's colours). Positions from Mixxx's mappings, not tried
  on a unit. Without the port the lights are left alone (--no-lights: never touched); Ctrl+C turns them off.
The S4 MK3 gets one output report at start: its jog motors' torque to 0 (Mixxx does the same; --no-motor-off skips it).
Needs: pip install --user hidapi mido python-rtmidi   (or the built ReaScratch-HID-Bridge.exe / macOS app: no Python)
macOS: hidapi opens the unit exclusively there, so Traktor cannot use it at the same time (quit Traktor first).
"""
import argparse
import re
import struct
import sys
import time

NI = 0x17CC
OUT_TPR = 2880          # ticks per turn sent to ReaScratch (its preset: 2880 x 33.33 / 60 = 1600 ticks/s)

# FLX4 numbers (deck channel = 0 / 1 as MIDI channel index)
N_TOUCH, N_PLAY, N_CUE, N_SYNC, N_RANGE, N_SHIFT, N_PFL = 0x36, 0x0B, 0x0C, 0x58, 0x60, 0x3F, 0x54
CC_JOG, CC_TEMPO, CC_VOL = 0x22, 0x00, 0x13
XF_CH, CC_XF = 6, 0x1F
PAD_CH, PAD_SHIFT_CH, SAMPLE_NOTE = (7, 9), (8, 10), 0x30


def u16(b, o):
    return b[o] | (b[o + 1] << 8)


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def bit(b, o, k):
    return (b[o] >> k) & 1 if o < len(b) else 0


def mb(b, o, mask):
    """1 when any bit of mask is set in byte o"""
    return 1 if o < len(b) and b[o] & mask else 0


def d8(prev, cur):
    """the step of an 8-bit jog counter (S3, S4 MK2, S2 MK2 / MK1: the lowest byte of the 32-bit field), -128..127"""
    return ((cur - prev + 128) & 255) - 128


def lt_rgb(v):
    """a light value from ReaScratch (its light type "Reloop RGB": 0 = off, bit 6 = bright, RR GG BB; a one-colour
    button's on = 127) -> (r, g, b) 0..1, the dark shade at a third"""
    if not v:
        return (0.0, 0.0, 0.0)
    k = 1.0 if v & 0x40 else 1 / 3
    return (((v >> 4) & 3) / 3 * k, ((v >> 2) & 3) / 3 * k, (v & 3) / 3 * k)


def lt_level(v):
    """a light value -> one brightness 0..1 (one-colour LEDs): bright 1, the dark shade a third"""
    return 0.0 if not v else 1.0 if v & 0x40 else 1 / 3


class Lights:
    """What ReaScratch lights, from its MIDI out (the port "ReaScratch LED"): (channel, note) -> value. Fed by a MIDI
    input callback (another thread), read by the HID loop"""
    def __init__(self):
        self.v = {}

    def midi(self, data):
        if len(data) >= 3 and data[0] & 0xE0 == 0x80:          # note on / off
            self.v[(data[0] & 15, data[1])] = data[2] if data[0] & 0x10 else 0

    def get(self, ch, n):
        return self.v.get((ch, n), 0)

    def deck(self, d):
        """deck d's lights as the unit shows them now: play, cue, sync, pfl (values), pads (8 values: the pad mode
        and SHIFT pick hot cues / their SHIFT layer / samples), samples (8 values, the S4 MK2's REMIX row)"""
        ch = d.ch
        if d.pad_mode == "samples":
            pads = [self.get(PAD_CH[ch], SAMPLE_NOTE + i) for i in range(8)]
        else:
            pc = (PAD_SHIFT_CH if d.shift else PAD_CH)[ch]
            pads = [self.get(pc, i) for i in range(8)]
        return {"play": self.get(ch, N_PLAY), "cue": self.get(ch, N_CUE), "sync": self.get(ch, N_SYNC),
                "pfl": self.get(ch, N_PFL), "pads": pads,
                "samples": [self.get(PAD_CH[ch], SAMPLE_NOTE + i) for i in range(8)]}


# the S4 MK3's / S3's colours (Mixxx's S4MK3.js colour map; the S3 has the same values): a hue's value, + a brightness 0..3
HUES = [(0xCC0000, 4), (0xCC5E00, 8), (0xCC7800, 12), (0xCC9200, 16), (0xCCCC00, 20), (0x81CC00, 24), (0x00CC00, 28),
        (0x00CC49, 32), (0x00CCCC, 36), (0x0091CC, 40), (0x0000CC, 44), (0xCC00CC, 48), (0xAD65FF, 52), (0xCC0079, 56),
        (0xCC477E, 60), (0xCC4761, 64), (0xCCCCCC, 68)]
# the S2 MK3's pad palette (S2MK3.js PadColorMap), four shades a hue: the third of each four (0x06, 0x0A ...) as the
# bright one, two below it the dark one (read from the table's colours; not tried on a unit)
S2_PADS = [(0xFF2916, 0x06), (0xFD5921, 0x0A), (0xFD7BAB, 0x0E), (0xF8AB36, 0x12), (0xE9BA3D, 0x16), (0xB6B959, 0x1A),
           (0x2CCF68, 0x1E), (0x3FD2B0, 0x22), (0x0DE1FF, 0x26), (0x00C3FF, 0x2A), (0x00A1FF, 0x2E), (0xE298FE, 0x32),
           (0xF263E3, 0x36), (0xFC4DC0, 0x3A), (0xFB359F, 0x3E), (0xFB3672, 0x42)]


def nearest(rgb, table):
    """the table's value whose colour is the nearest to rgb by hue (both scaled to their brightest part)"""
    m = max(rgb) or 1
    c = [x / m for x in rgb]
    best, bv = None, 9.0
    for col, val in table:
        t = [(col >> 16) & 255, (col >> 8) & 255, col & 255]
        tm = max(t)
        d = sum((c[i] - t[i] / tm) ** 2 for i in range(3))
        if d < bv:
            best, bv = val, d
    return best


def is_white(v):
    return v and ((v >> 4) & 3) == ((v >> 2) & 3) == (v & 3)


def stretch12(v):
    """the older units' faders reach 16..4080 (Mixxx's ends): stretch to 0..4095"""
    return max(0, min(4095, (v - 16) * 4095 // 4064))


class Midi:
    """Collects / sends MIDI: send(status, d1, d2)."""
    def __init__(self, port=None, dry=False):
        self.port, self.dry, self.log = port, dry, []

    def send(self, st, d1, d2):
        self.log.append((st, d1, d2))
        if self.dry:
            print(f"{st:02X} {d1:02X} {d2:02X}")
        elif self.port is not None:
            import mido
            self.port.send(mido.Message.from_bytes([st, d1 & 127, d2 & 127]))


class Deck:
    def __init__(self, midi, ch):
        self.m, self.ch = midi, ch
        self.btn = {}
        self.shift = 0
        self.pad_mode = "hotcue"
        self.held_pads = {}
        self.tempo = None
        self.vol = None
        self.jog_acc = 0.0

    def note(self, n, on, ch=None):
        c = self.ch if ch is None else ch
        self.m.send((0x90 if on else 0x80) | c, n, 127 if on else 0)

    def edge(self, name, v):
        """True / False on a change of a button, None when unchanged."""
        old = self.btn.get(name, 0)
        self.btn[name] = v
        return None if v == old else bool(v)

    def buttons(self, play, cue, sync, shift, touch, pfl, mode_hot, mode_smp, pads, smp_toggle=False, smp_pads=()):
        """touch None = sent apart (touch()); smp_toggle: one SAMPLES button flips hot cue / samples (S2 MK1 / MK2);
        smp_pads: pads that always pick a sample (the S4 MK2's REMIX row)"""
        e = self.edge("shift", shift)
        if e is not None:
            self.shift = int(e)
            self.note(N_SHIFT, e)
        for name, v, n in (("play", play, N_PLAY), ("cue", cue, N_CUE), ("touch", touch, N_TOUCH), ("pfl", pfl, N_PFL)):
            if v is None:
                continue
            e = self.edge(name, v)
            if e is not None:
                self.note(n, e)
        e = self.edge("sync", sync)
        if e is not None:
            self.note(N_RANGE if self.shift else N_SYNC, e)
        if self.edge("mode_hot", mode_hot):
            self.pad_mode = "hotcue"
        if self.edge("mode_smp", mode_smp):
            self.pad_mode = "hotcue" if smp_toggle and self.pad_mode == "samples" else "samples"
        for i, v in enumerate(pads):
            e = self.edge(f"pad{i}", v)
            if e is True:
                if self.pad_mode == "samples":
                    ch, n = PAD_CH[self.ch], SAMPLE_NOTE + i
                else:
                    ch, n = (PAD_SHIFT_CH if self.shift else PAD_CH)[self.ch], i
                self.held_pads[i] = (ch, n)
                self.note(n, True, ch)
            elif e is False and i in self.held_pads:
                ch, n = self.held_pads.pop(i)
                self.note(n, False, ch)
        for i, v in enumerate(smp_pads):
            e = self.edge(f"spad{i}", v)
            if e is not None:
                self.note(SAMPLE_NOTE + i, e, PAD_CH[self.ch])

    def touch(self, v):
        e = self.edge("touch", v)
        if e is not None:
            self.note(N_TOUCH, e)

    def jog(self, ticks, tpr):
        """ticks of the unit -> OUT_TPR ticks, 64-centre steps of at most 63."""
        self.jog_acc += ticks * OUT_TPR / tpr
        t = int(self.jog_acc)
        self.jog_acc -= t
        while t:
            s = max(-63, min(63, t))
            self.m.send(0xB0 | self.ch, CC_JOG, 64 + s)
            t -= s

    def tempo12(self, v, invert):
        v = 4095 - v if invert else v
        v14 = min(16383, v * 4 + (v >> 10))
        if v14 != self.tempo:
            self.tempo = v14
            self.m.send(0xB0 | self.ch, CC_TEMPO, v14 >> 7)
            self.m.send(0xB0 | self.ch, CC_TEMPO + 32, v14 & 127)

    def volume12(self, v):
        v7 = v * 127 // 4095
        if v7 != self.vol:
            self.vol = v7
            self.m.send(0xB0 | self.ch, CC_VOL, v7)


class Mixer:
    def __init__(self, midi):
        self.m, self.xf = midi, None

    def crossfader12(self, v):
        v14 = min(16383, v * 4 + (v >> 10))
        if v14 != self.xf:
            self.xf = v14
            self.m.send(0xB0 | XF_CH, CC_XF, v14 >> 7)
            self.m.send(0xB0 | XF_CH, CC_XF + 32, v14 & 127)


class S4MK3:
    pid, name, iface, upage = 0x1720, "Traktor Kontrol S4 MK3", 3, 0xFF01
    PADS_L = [(4, 5), (4, 4), (4, 7), (4, 6), (4, 3), (4, 2), (4, 1), (4, 0)]
    PADS_R = [(14, 5), (14, 4), (14, 7), (14, 6), (14, 3), (14, 2), (14, 1), (14, 0)]

    def __init__(self, midi, args):
        self.decks = [Deck(midi, 0), Deck(midi, 1)]
        self.mix, self.args = Mixer(midi), args
        self.pos = [None, None]

    def handle(self, b):
        rid = b[0]
        if rid == 1 and len(b) >= 19:
            L, R = self.decks
            L.buttons(bit(b, 5, 0), bit(b, 5, 1), bit(b, 6, 7), bit(b, 6, 1), bit(b, 17, 4), bit(b, 8, 3),
                      bit(b, 5, 2), bit(b, 5, 4), [bit(b, o, k) for o, k in self.PADS_L])
            R.buttons(bit(b, 13, 0), bit(b, 15, 5), bit(b, 15, 4), bit(b, 15, 1), bit(b, 17, 5), bit(b, 8, 6),
                      bit(b, 13, 2), bit(b, 13, 4), [bit(b, o, k) for o, k in self.PADS_R])
        elif rid == 2 and len(b) >= 15:
            self.mix.crossfader12(u16(b, 1))
            self.decks[0].volume12(u16(b, 3))
            self.decks[1].volume12(u16(b, 5))
            self.decks[0].tempo12(u16(b, 13), not self.args.tempo_invert)
            self.decks[1].tempo12(u16(b, 11), not self.args.tempo_invert)
        elif rid == 3 and len(b) >= 44:
            for i, off in ((0, 12), (1, 40)):
                p = u32(b, off)
                if self.pos[i] is not None:
                    d = (p - self.pos[i]) & 0xFFFFFFFF
                    if d >= 1 << 31:
                        d -= 1 << 32
                    if d:
                        self.decks[i].jog(d, self.args.s4_ticks)
                self.pos[i] = p

    def start(self, h):
        if not self.args.no_motor_off:
            h.write(bytes([49, 1, 0x20, 1, 0, 0, 1, 0x20, 1, 0, 0]))   # jog motors: torque 0 (as Mixxx does)


class S2MK3:
    pid, name, iface, upage = 0x1710, "Traktor Kontrol S2 MK3", 3, 0xFF01
    PADS_L = [(2, 0x10), (2, 0x20), (2, 0x40), (2, 0x80), (3, 0x01), (3, 0x02), (3, 0x04), (3, 0x08)]
    PADS_R = [(5, 0x40), (5, 0x80), (6, 0x01), (6, 0x02), (6, 0x04), (6, 0x08), (6, 0x10), (6, 0x20)]

    def __init__(self, midi, args):
        self.decks = [Deck(midi, 0), Deck(midi, 1)]
        self.mix, self.args = Mixer(midi), args
        self.tick = [None, None]

    def handle(self, b):
        rid, m = b[0], mb
        if rid == 1 and len(b) >= 20:
            L, R = self.decks
            L.buttons(m(b, 2, 8), m(b, 2, 4), m(b, 2, 1), m(b, 1, 0x20), m(b, 8, 0x40), m(b, 4, 1),
                      m(b, 1, 0x40), m(b, 1, 0x80), [m(b, o, k) for o, k in self.PADS_L])
            R.buttons(m(b, 5, 0x20), m(b, 5, 0x10), m(b, 5, 4), m(b, 4, 0x80), m(b, 8, 0x80), m(b, 4, 2),
                      m(b, 5, 1), m(b, 5, 2), [m(b, o, k) for o, k in self.PADS_R])
            for i, off in ((0, 0x0C), (1, 0x10)):
                t = u32(b, off) & 0x3FF
                if self.tick[i] is not None:
                    d = t - self.tick[i]
                    d = d - 1024 if d > 512 else d + 1024 if d < -512 else d
                    if d:
                        self.decks[i].jog(d, self.args.s2_ticks)
                self.tick[i] = t
        elif rid == 2 and len(b) >= 11:
            self.decks[0].tempo12(u16(b, 1), not self.args.tempo_invert)
            self.decks[1].tempo12(u16(b, 9), not self.args.tempo_invert)
            self.decks[0].volume12(u16(b, 3))
            self.decks[1].volume12(u16(b, 7))
            self.mix.crossfader12(u16(b, 5))

    def start(self, h):
        pass


class Old8:
    """the older units (S3, S4 MK2, S2 MK2, S2 MK1; layouts from Mixxx's mappings): report 1 = buttons + jogs (32-bit fields,
    the lowest byte counts the jog's steps), report 2 = faders (16..4080). Per class: JOG (offsets), TPR_ARG (the
    ticks-per-turn option), FADERS (offsets in report 2)"""
    JOG = (0x01, 0x05)
    TPR_ARG = "mk2_ticks"
    FADERS = {}

    def __init__(self, midi, args):
        self.decks = [Deck(midi, 0), Deck(midi, 1)]
        self.mix, self.args = Mixer(midi), args
        self.tick = [None, None]

    def jogs(self, b):
        for i, off in enumerate(self.JOG):
            t = b[off]
            if self.tick[i] is not None:
                d = d8(self.tick[i], t)
                if d:
                    self.decks[i].jog(d, getattr(self.args, self.TPR_ARG))
            self.tick[i] = t

    def faders(self, b):
        f = self.FADERS
        inv = not self.args.tempo_invert
        self.decks[0].tempo12(stretch12(u16(b, f["tempo"][0])), inv)
        self.decks[1].tempo12(stretch12(u16(b, f["tempo"][1])), inv)
        self.decks[0].volume12(stretch12(u16(b, f["vol"][0])))
        self.decks[1].volume12(stretch12(u16(b, f["vol"][1])))
        self.mix.crossfader12(stretch12(u16(b, f["xf"])))

    def start(self, h):
        pass


class S3(Old8):
    pid, name, iface, upage = 0x1900, "Traktor Kontrol S3", 3, 0xFF01
    JOG = (0x0E, 0x12)
    TPR_ARG = "s3_ticks"
    FADERS = {"tempo": (0x01, 0x0D), "vol": (0x05, 0x07), "xf": 0x0B}
    PADS_L = [(3, 0x02), (3, 0x04), (3, 0x08), (3, 0x10), (3, 0x20), (3, 0x40), (3, 0x80), (4, 0x01)]
    PADS_R = [(6, 0x04), (6, 0x08), (6, 0x10), (6, 0x20), (6, 0x40), (6, 0x80), (7, 0x01), (7, 0x02)]

    def handle(self, b):
        if b[0] == 1 and len(b) >= 0x16:
            L, R = self.decks
            L.buttons(mb(b, 3, 0x01), mb(b, 2, 0x80), mb(b, 2, 0x08), mb(b, 1, 0x01), mb(b, 0x0A, 0x10), mb(b, 8, 0x01),
                      mb(b, 2, 0x20), mb(b, 2, 0x40), [mb(b, o, k) for o, k in self.PADS_L])
            R.buttons(mb(b, 6, 0x02), mb(b, 6, 0x01), mb(b, 5, 0x10), mb(b, 4, 0x02), mb(b, 0x0A, 0x20), mb(b, 8, 0x02),
                      mb(b, 5, 0x40), mb(b, 5, 0x80), [mb(b, o, k) for o, k in self.PADS_R])
            self.jogs(b)
        elif b[0] == 2 and len(b) >= 0x0F:
            self.faders(b)


class S2MK2(Old8):
    pid, name, iface, upage = 0x1320, "Traktor Kontrol S2 MK2", 3, None
    FADERS = {"tempo": (0x07, 0x09), "vol": (0x13, 0x15), "xf": 0x05}
    ROW = (0x80, 0x40, 0x20, 0x10)

    def handle(self, b):
        if b[0] == 1 and len(b) >= 0x0D:
            L, R = self.decks
            L.buttons(mb(b, 0x0B, 1), mb(b, 0x0B, 2), mb(b, 0x0B, 4), mb(b, 0x0B, 8), mb(b, 0x0A, 1), mb(b, 0x0C, 0x10),
                      0, mb(b, 0x0C, 0x02), [mb(b, 0x0B, k) for k in self.ROW], smp_toggle=True)
            R.buttons(mb(b, 9, 1), mb(b, 9, 2), mb(b, 9, 4), mb(b, 9, 8), mb(b, 0x0A, 2), mb(b, 0x0A, 0x10),
                      0, mb(b, 0x0C, 0x01), [mb(b, 9, k) for k in self.ROW], smp_toggle=True)
            self.jogs(b)
        elif b[0] == 2 and len(b) >= 0x17:
            self.faders(b)


class S4MK2(Old8):
    pid, name, iface, upage = 0x1310, "Traktor Kontrol S4 MK2", 4, 0xFF01
    FADERS = {"tempo": (0x09, 0x0B), "vol": (0x37, 0x39), "xf": 0x07}
    ROW = (0x80, 0x40, 0x20, 0x10)

    def handle(self, b):
        """by length, as Mixxx does (s4mk2.js incomingData): 21 = report 1; report 2 = 79 bytes on Windows, but on macOS
        / Linux 64 bytes (with its ID) and then the last 15 bytes without an ID. Every fader read here is within the
        first 64 bytes (the last at 0x3A), so the 64-byte part is read and the 15-byte rest dropped: its first byte is
        data and could look like a report ID"""
        n = len(b)
        if n == 15:
            return
        if b[0] == 1 and n == 21:
            L, R = self.decks
            L.buttons(mb(b, 0x0D, 1), mb(b, 0x0D, 2), mb(b, 0x0D, 4), mb(b, 0x0D, 8), mb(b, 0x11, 1), mb(b, 0x0F, 0x40),
                      0, 0, [mb(b, 0x0D, k) for k in self.ROW], smp_pads=[mb(b, 0x0E, k) for k in self.ROW])
            R.buttons(mb(b, 0x0C, 1), mb(b, 0x0C, 2), mb(b, 0x0C, 4), mb(b, 0x0C, 8), mb(b, 0x11, 2), mb(b, 0x0A, 0x40),
                      0, 0, [mb(b, 0x0C, k) for k in self.ROW], smp_pads=[mb(b, 0x0B, k) for k in self.ROW])
            self.jogs(b)
        elif b[0] == 2 and n in (64, 79):
            self.faders(b)


class S2MK1(Old8):
    """the top touch is a pressure value (report 2): touched above the unit's calibration (feature report 0xD4: idle /
    pressed, big-endian, left then right), with a little hysteresis. Without the calibration the first value is taken as
    idle and a touch as idle + JOG_GUESS (a guess)"""
    pid, name, iface, upage = 0x1101, "Traktor Kontrol S2 MK1", None, None
    FADERS = {"tempo": (0x0F, 0x1F), "vol": (0x2B, 0x2D), "xf": 0x2F}
    PRESS = (0x0D, 0x1D)
    ROW = (0x08, 0x04, 0x02, 0x01)
    JOG_GUESS = 150

    def __init__(self, midi, args):
        super().__init__(midi, args)
        self.cal = [None, None]    # (idle, pressed) per deck

    def calibrate(self, rep):
        """rep = the feature report 0xD4 as read (byte 0 = the report ID)"""
        if rep and len(rep) >= 9:
            def be(o):
                return (rep[o] << 8) | rep[o + 1]
            self.cal = [(be(1), be(3)), (be(5), be(7))]

    def start(self, h):
        try:
            self.calibrate(bytes(h.get_feature_report(0xD4, 33)))
        except (OSError, IOError, ValueError):
            pass
        print("jog touch calibration:", self.cal if self.cal[0] else "not read (a guess from the first values)")

    def handle(self, b):
        if b[0] == 1 and len(b) >= 0x0E:
            L, R = self.decks
            L.buttons(mb(b, 0x0D, 0x10), mb(b, 0x0D, 0x20), mb(b, 0x0D, 0x40), mb(b, 0x0D, 0x80), None, mb(b, 9, 0x80),
                      0, mb(b, 0x0B, 0x02), [mb(b, 0x0D, k) for k in self.ROW], smp_toggle=True)
            R.buttons(mb(b, 0x0C, 0x10), mb(b, 0x0C, 0x20), mb(b, 0x0C, 0x40), mb(b, 0x0C, 0x80), None, mb(b, 0x0B, 0x80),
                      0, mb(b, 0x0B, 0x01), [mb(b, 0x0C, k) for k in self.ROW], smp_toggle=True)
            self.jogs(b)
        elif b[0] == 2 and len(b) >= 0x31:
            self.faders(b)
            for i, off in enumerate(self.PRESS):
                v = u16(b, off)
                if self.cal[i] is None:
                    self.cal[i] = (v, v + self.JOG_GUESS)
                idle, pressed = self.cal[i]
                span = max(1, pressed - idle)
                was = self.decks[i].btn.get("touch", 0)
                self.decks[i].touch(int(v > idle + span * (0.4 if was else 0.6)))   # on at 60 % of the way, off below 40 %


# --- lights (⚪77): ReaScratch's lights (Lights) -> the units' LED output reports. Positions and values from Mixxx's
# mappings (byte 0 = the report ID). Each method gives the whole reports
# ({ID: bytes}); run() writes one only when it changed. Not tried on any unit yet. The pad mode / SHIFT buttons show
# the bridge's own state (the units keep none)

def _pal_pad(v, bright, dim, white=68):
    """S4 MK3 / S3: a hue + a brightness; 0 = off"""
    if not v:
        return 0
    return (white if is_white(v) else nearest(lt_rgb(v), HUES)) + (bright if v & 0x40 else dim)


def _rgb(v, top):
    return [round(x * top) for x in lt_rgb(v)]


def leds_s4mk3(self, L):
    r = bytearray(95); r[0] = 0x80
    one = lambda v: 0 if not v else 70 if v & 0x40 else 68     # white + 2 (Mixxx's on) / + 0
    for d, (play, cue, sync, shift, hot, smp, pad0, pfl) in zip(self.decks, ((56, 9, 15, 60, 10, 58, 1, 78),
                                                                             (67, 32, 38, 71, 33, 69, 24, 82))):
        s = L.deck(d)
        r[play], r[cue], r[sync], r[pfl] = one(s["play"]), one(s["cue"]), one(s["sync"]), one(s["pfl"])
        r[shift] = 70 if d.shift else 0
        r[hot] = 70 if d.pad_mode == "hotcue" else 0
        r[smp] = 70 if d.pad_mode == "samples" else 0
        for i, v in enumerate(s["pads"]):
            r[pad0 + i] = _pal_pad(v, 2, 0)
    return {0x80: bytes(r)}


def leds_s2mk3(self, L):
    r = bytearray(62); r[0] = 0x80
    one = lambda v: 0 if not v else 0x7E if v & 0x40 else 0x7C

    def pad(v):
        if not v:
            return 0x02                                             # Mixxx's "completely off" for the pads
        if is_white(v):
            return 0x7E if v & 0x40 else 0x7C
        b = nearest(lt_rgb(v), S2_PADS)
        return b if v & 0x40 else b - 2
    for d, (play, cue, sync, pfl, shift, hot, smp, pad0) in zip(self.decks, ((0x0C, 0x0B, 0x09, 0x1A, 0x06, 0x07, 0x08, 0x0D),
                                                                             (0x33, 0x32, 0x30, 0x1B, 0x2D, 0x2E, 0x2F, 0x34))):
        s = L.deck(d)
        r[play], r[cue], r[sync], r[pfl] = one(s["play"]), one(s["cue"]), one(s["sync"]), one(s["pfl"])
        r[shift] = 0x7E if d.shift else 0
        r[hot] = 0x7E if d.pad_mode == "hotcue" else 0
        r[smp] = 0x7E if d.pad_mode == "samples" else 0
        for i, v in enumerate(s["pads"]):
            r[pad0 + i] = pad(v)
    return {0x80: bytes(r)}


def leds_s3(self, L):
    r = bytearray(83); r[0] = 0x80
    one = lambda v: 0 if not v else 0x47 if v & 0x40 else 0x45    # white + 3 / + 1 (Mixxx's bright / dim)
    for d, (play, cue, sync, pfl, shift, hot, smp, pad0) in zip(self.decks, ((0x11, 0x10, 0x0C, 0x39, 0x01, 0x0E, 0x0F, 0x12),
                                                                             (0x2A, 0x29, 0x25, 0x3A, 0x1A, 0x27, 0x28, 0x2B))):
        s = L.deck(d)
        r[play] = 0x77 if s["play"] else 0x20                       # PLAY / SHIFT / PFL: one colour (Mixxx's values)
        r[pfl] = 0xFF if s["pfl"] else 0x04
        r[shift] = 0x77 if d.shift else 0x20
        r[cue], r[sync] = one(s["cue"]), one(s["sync"])
        r[hot] = 0x47 if d.pad_mode == "hotcue" else 0
        r[smp] = 0x47 if d.pad_mode == "samples" else 0
        for i, v in enumerate(s["pads"]):
            r[pad0 + i] = _pal_pad(v, 3, 1, 0x44)
    return {0x80: bytes(r)}


def _one127(v, dim):
    return 0 if not v else 0x7F if v & 0x40 else dim


def leds_s4mk2(self, L):
    a = bytearray(63); a[0] = 0x81
    b = bytearray(61); b[0] = 0x82
    for d, (play, cue, sync, shift, hot0, remix0, pfl) in zip(self.decks, ((0x20, 0x1F, 0x1E, 0x1D, 0x01, 0x19, 0x18),
                                                                          (0x28, 0x27, 0x26, 0x25, 0x0D, 0x21, 0x19))):
        s = L.deck(d)
        a[play], a[cue], a[sync] = _one127(s["play"], 9), _one127(s["cue"], 9), _one127(s["sync"], 9)
        a[shift] = 0x7F if d.shift else 0
        b[pfl] = _one127(s["pfl"], 9)
        for i in range(4):
            a[hot0 + 3 * i: hot0 + 3 * i + 3] = bytes(_rgb(s["pads"][i], 0x7F))
            a[remix0 + i] = _one127(s["samples"][i], 9)
    return {0x81: bytes(a), 0x82: bytes(b)}


def leds_s2mk2(self, L):
    top = bytearray(39); top[0] = 0x80
    bot = bytearray(34); bot[0] = 0x81
    for d, (play, cue, sync, shift, pad0, pfl) in zip(self.decks, ((0x1C, 0x1B, 0x1A, 0x19, 0x01, 0x1B),
                                                                   (0x20, 0x1F, 0x1E, 0x1D, 0x0D, 0x1F))):
        s = L.deck(d)
        bot[play], bot[cue], bot[sync] = _one127(s["play"], 1), _one127(s["cue"], 1), _one127(s["sync"], 1)
        bot[shift] = 0x7F if d.shift else 0
        top[pfl] = _one127(s["pfl"], 1)
        for i in range(4):
            bot[pad0 + 3 * i: pad0 + 3 * i + 3] = bytes(_rgb(s["pads"][i], 0x7F))
    return {0x80: bytes(top), 0x81: bytes(bot)}


def leds_s2mk1(self, L):
    """values 0..0x1F; the pads have green and blue only (no red in Mixxx's mapping): red is shown as blue"""
    r = bytearray(62); r[0] = 0x80
    one = lambda v: 0 if not v else 0x1F if v & 0x40 else 0x08
    for d, (play, cue, sync, shift, pfl, smp, pads) in zip(self.decks, (
            (0x03, 0x07, 0x04, 0x08, 0x20, 0x35, ((0x0C, 0x10), (0x0B, 0x0F), (0x0A, 0x0E), (0x09, 0x0D))),
            (0x23, 0x27, 0x24, 0x28, 0x1D, 0x34, ((0x2C, 0x30), (0x2B, 0x2F), (0x2A, 0x2E), (0x29, 0x2D))))):
        s = L.deck(d)
        r[play], r[cue], r[sync], r[pfl] = one(s["play"]), one(s["cue"]), one(s["sync"]), one(s["pfl"])
        r[shift] = 0x1F if d.shift else 0
        r[smp] = 0x1F if d.pad_mode == "samples" else 0
        for i, (go, bo) in enumerate(pads):
            rr, g, bb = _rgb(s["pads"][i], 0x1F)
            r[go], r[bo] = g, max(bb, rr)
    return {0x80: bytes(r)}


S4MK3.leds, S2MK3.leds, S3.leds, S4MK2.leds, S2MK2.leds, S2MK1.leds = \
    leds_s4mk3, leds_s2mk3, leds_s3, leds_s4mk2, leds_s2mk2, leds_s2mk1

MODELS = [S4MK3, S2MK3, S3, S4MK2, S2MK2, S2MK1]


def lights_off(unit, h):
    """every LED report of the unit as zeros (Mixxx does the same on its shutdown)"""
    for rid, data in unit.leds(Lights()).items():
        h.write(bytes([rid]) + bytes(len(data) - 1))


def open_led_port(args, out_name):
    """the MIDI input for ReaScratch's lights: a port matching --led-port (Windows: a second loopMIDI port), else on
    macOS a new virtual port of that name. Never the bridge's own output port (loopMIDI sends a port straight back)"""
    if args.no_lights:
        return None, None
    import mido
    lights = Lights()
    names = mido.get_input_names()
    pick = sorted((n for n in names if args.led_port.lower() in n.lower()), key=len)
    base = lambda n: re.sub(r" \d+$", "", n).lower()                 # Windows: mido adds the port's index
    pick = [n for n in pick if not out_name or base(n) != base(out_name)]
    cb = lambda msg: lights.midi(msg.bytes())
    if pick:
        port = mido.open_input(pick[0], callback=cb)
        print(f"lights from: {pick[0]}")
    elif sys.platform == "darwin":
        port = mido.open_input(args.led_port, virtual=True, callback=cb)
        print(f"lights from: a new virtual port '{args.led_port}' (enable it as a MIDI output in REAPER's preferences)")
    else:
        print(f"no MIDI port matching '{args.led_port}': the lights stay off. To light them, add a second loopMIDI "
              f"port named '{args.led_port}' (REAPER: enable its output only, not its input) and start again.")
        print(f"ボタンの明かりは使いません。使うときは loopMIDI にポート「{args.led_port}」を足し（REAPER では出力だけ"
              "有効にし、入力は無効に）、もう一度起動してください。")
        return None, None
    return port, lights


def open_unit(hid):
    for cls in MODELS:
        for d in hid.enumerate(NI, cls.pid):
            if (cls.iface is None or d.get("interface_number") == cls.iface) and \
                    (cls.upage is None or d.get("usage_page") == cls.upage):
                h = hid.device()
                h.open_path(d["path"])
                return cls, h
    return None, None


def run(args):
    import hid
    import mido
    port = None
    if not args.dry_run:
        names = mido.get_output_names()
        pick = sorted((n for n in names if args.port.lower() in n.lower()), key=len)   # the closest name first
        if pick:
            port = mido.open_output(pick[0])
            print(f"MIDI out: {pick[0]}")
        elif sys.platform == "darwin":
            port = mido.open_output("ReaScratch HID Bridge", virtual=True)
            print("MIDI out: a new virtual port 'ReaScratch HID Bridge' (enable it as a MIDI input in REAPER's preferences)")
        else:
            print(f"no MIDI output port matching '{args.port}' (have: {names}).")
            print("Install loopMIDI (https://www.tobias-erichsen.de/software/loopmidi.html) and add a port, then start again.")
            print("loopMIDI を入れてポートを1つ作り（名前は loopMIDI Port のまま）、もう一度起動してください。")
            return 1
    midi = Midi(port, args.dry_run)
    led_in, lights = open_led_port(args, port.name if port is not None else None)
    told = False
    while True:
        cls, h = open_unit(hid)
        if not h:
            if not told:
                print("waiting for a Traktor Kontrol S4 / S3 / S2 (USB; an S4 also needs its power adapter). Ctrl+C to stop")
                print("Traktor Kontrol S4 / S3 / S2 を待っています（USB。S4 は電源アダプターも）。止めるときは Ctrl+C")
                told = True
            time.sleep(2)
            continue
        told = False
        unit = cls(midi, args)
        print(f"connected: {cls.name}")
        try:
            unit.start(h)
            h.set_nonblocking(False)
            sent = {}
            while True:
                data = h.read(512, 20 if lights else 1000)
                if data:
                    unit.handle(bytes(data))
                if lights:
                    for rid, rep in unit.leds(lights).items():
                        if sent.get(rid) != rep:
                            h.write(rep)
                            sent[rid] = rep
        except (OSError, IOError) as e:
            print(f"lost the unit ({e}); reconnecting")
            time.sleep(1)
        except KeyboardInterrupt:
            if lights:
                try:
                    lights_off(unit, h)
                except (OSError, IOError, ValueError):
                    pass
            print("stopped")
            return 0
        finally:
            h.close()


def selftest():
    """Made-up reports -> the MIDI ReaScratch's FLX4-style preset expects."""
    class A:
        tempo_invert = False
        no_motor_off = True
        s4_ticks = 2880
        s2_ticks = 600
        s3_ticks = 768
        mk2_ticks = 1024
    ok = True

    def check(what, got, want):
        nonlocal ok
        good = got == want
        ok &= good
        print(f"{'OK ' if good else 'NG '} {what}: {got}" + ("" if good else f"  (want {want})"))

    # S4 MK3
    m = Midi()
    u = S4MK3(m, A)
    r1 = bytearray(23); r1[0] = 1
    u.handle(bytes(r1))
    r1[5] |= 1; u.handle(bytes(r1))                                # left PLAY down
    check("S4 left PLAY", m.log[-1:], [(0x90, N_PLAY, 127)])
    r1[5] &= ~1; r1[17] |= 0x20; u.handle(bytes(r1))              # PLAY up, right touch on
    check("S4 PLAY up + right touch", m.log[-2:], [(0x80, N_PLAY, 0), (0x91, N_TOUCH, 127)])
    r1[6] |= 0x02; u.handle(bytes(r1)); r1[6] |= 0x80; u.handle(bytes(r1))    # left SHIFT, then SYNC
    check("S4 SHIFT + SYNC -> range", m.log[-2:], [(0x90, N_SHIFT, 127), (0x90, N_RANGE, 127)])
    r1[4] |= 1 << 5; u.handle(bytes(r1))                           # left pad 1 with SHIFT (hot cue delete)
    check("S4 SHIFT + pad 1", m.log[-1:], [(0x98, 0, 127)])
    r1[6] &= ~0x82; r1[4] &= ~(1 << 5); u.handle(bytes(r1))
    r1[5] |= 1 << 4; u.handle(bytes(r1)); r1[5] &= ~(1 << 4)       # SAMPLES mode
    r1[4] |= 1 << 0; u.handle(bytes(r1))                           # pad 8
    check("S4 SAMPLES pad 8", m.log[-1:], [(0x97, SAMPLE_NOTE + 7, 127)])
    r2 = bytearray(79); r2[0] = 2
    struct.pack_into("<H", r2, 13, 0); struct.pack_into("<H", r2, 1, 4095); u.handle(bytes(r2))
    check("S4 left tempo at 0 (top) -> 14-bit max (+ end, turned over)", [x for x in m.log if x[0] == 0xB0 and x[1] in (0, 32)][-2:],
          [(0xB0, 0, 127), (0xB0, 32, 127)])
    check("S4 crossfader 4095", [x for x in m.log if x[0] == 0xB6][-2:], [(0xB6, 0x1F, 127), (0xB6, 0x3F, 127)])
    r3 = bytearray(46); r3[0] = 3
    struct.pack_into("<I", r3, 12, 0xFFFFFFF0); u.handle(bytes(r3))
    n0 = len(m.log)
    struct.pack_into("<I", r3, 12, 0x00000010); u.handle(bytes(r3))   # +32 across the 2^32 wrap
    check("S4 left jog +32 across the wrap", m.log[n0:], [(0xB0, CC_JOG, 64 + 32)])
    n0 = len(m.log)
    struct.pack_into("<I", r3, 12, 0x10 + 2880); u.handle(bytes(r3))  # one full turn
    check("S4 one turn = 2880 ticks", sum(x[2] - 64 for x in m.log[n0:]), 2880)
    check("S4 steps within 1..127", all(1 <= x[2] <= 127 for x in m.log[n0:]), True)
    # S2 MK3
    m = Midi()
    u = S2MK3(m, A)
    s1 = bytearray(20); s1[0] = 1
    struct.pack_into("<I", s1, 0x10, (5 << 10) | 1020); u.handle(bytes(s1))
    n0 = len(m.log)
    struct.pack_into("<I", s1, 0x10, (6 << 10) | 4); u.handle(bytes(s1))   # +8 ticks across the 1024 wrap
    check("S2 right jog +8 ticks (x 2880/600)", m.log[n0:], [(0xB1, CC_JOG, 64 + 38)])
    s1[2] |= 0x08; u.handle(bytes(s1))
    check("S2 left PLAY", m.log[-1:], [(0x90, N_PLAY, 127)])
    s1[4] |= 0x02; u.handle(bytes(s1))
    check("S2 right PFL", m.log[-1:], [(0x91, N_PFL, 127)])
    s2 = bytearray(39); s2[0] = 2
    struct.pack_into("<H", s2, 7, 4095); u.handle(bytes(s2))
    check("S2 right volume 4095", [x for x in m.log if x[0] == 0xB1 and x[1] == CC_VOL][-1:], [(0xB1, CC_VOL, 127)])
    # S3: report 1 = buttons, touch bits, jogs (lowest byte of the 32-bit fields at 0x0E / 0x12); report 2 = faders
    m = Midi()
    u = S3(m, A)
    t1 = bytearray(0x16); t1[0] = 1
    t1[0x0E] = 250; u.handle(bytes(t1))
    n0 = len(m.log)
    t1[0x0E] = 2; u.handle(bytes(t1))                                  # +8 steps across the 8-bit wrap
    check("S3 left jog +8 steps (x 2880/768)", m.log[n0:], [(0xB0, CC_JOG, 64 + 30)])
    t1[3] |= 0x01; u.handle(bytes(t1))
    check("S3 left PLAY", m.log[-1:], [(0x90, N_PLAY, 127)])
    t1[0x0A] |= 0x20; u.handle(bytes(t1))
    check("S3 right touch", m.log[-1:], [(0x91, N_TOUCH, 127)])
    t1[5] |= 0x80; u.handle(bytes(t1)); t1[5] &= ~0x80; u.handle(bytes(t1))   # right SAMPLES
    t1[7] |= 0x02; u.handle(bytes(t1))                                  # right pad 8
    check("S3 right SAMPLES pad 8", m.log[-1:], [(0x99, SAMPLE_NOTE + 7, 127)])
    t2 = bytearray(0x0F); t2[0] = 2
    struct.pack_into("<H", t2, 0x07, 4080); u.handle(bytes(t2))
    check("S3 right volume 4080 (the end) -> 127", [x for x in m.log if x[0] == 0xB1 and x[1] == CC_VOL][-1:], [(0xB1, CC_VOL, 127)])
    struct.pack_into("<H", t2, 0x0B, 16); u.handle(bytes(t2))
    check("S3 crossfader 16 (the end) -> 0", [x for x in m.log if x[0] == 0xB6][-2:], [(0xB6, 0x1F, 0), (0xB6, 0x3F, 0)])
    # S2 MK2: the SAMPLES button flips the 4 pads (hot cue <-> samples)
    m = Midi()
    u = S2MK2(m, A)
    k1 = bytearray(0x0D); k1[0] = 1
    k1[1] = 100; u.handle(bytes(k1))
    n0 = len(m.log)
    k1[1] = 90; u.handle(bytes(k1))                                    # -10 steps
    check("S2 MK2 left jog -10 steps (x 2880/1024)", sum(x[2] - 64 for x in m.log[n0:]), -28)
    k1[0x0B] |= 0x80; u.handle(bytes(k1)); k1[0x0B] &= ~0x80; u.handle(bytes(k1))
    check("S2 MK2 left pad 1 = hot cue", m.log[-2:], [(0x97, 0, 127), (0x87, 0, 0)])
    k1[0x0C] |= 0x02; u.handle(bytes(k1)); k1[0x0C] &= ~0x02; u.handle(bytes(k1))   # SAMPLES: on
    k1[0x0B] |= 0x80; u.handle(bytes(k1)); k1[0x0B] &= ~0x80; u.handle(bytes(k1))
    check("S2 MK2 SAMPLES, pad 1 = sample 1", m.log[-2:], [(0x97, SAMPLE_NOTE, 127), (0x87, SAMPLE_NOTE, 0)])
    k1[0x0C] |= 0x02; u.handle(bytes(k1)); k1[0x0C] &= ~0x02; u.handle(bytes(k1))   # SAMPLES again: back to hot cues
    k1[0x09] |= 0x10; u.handle(bytes(k1))
    check("S2 MK2 right pad 4 = hot cue 4", m.log[-1:], [(0x99, 3, 127)])
    k1[0x0A] |= 0x01; u.handle(bytes(k1))
    check("S2 MK2 left touch", m.log[-1:], [(0x90, N_TOUCH, 127)])
    k2 = bytearray(0x17); k2[0] = 2
    struct.pack_into("<H", k2, 0x13, 4080); u.handle(bytes(k2))
    check("S2 MK2 left volume", [x for x in m.log if x[0] == 0xB0 and x[1] == CC_VOL][-1:], [(0xB0, CC_VOL, 127)])
    # S4 MK2: HOTCUE row = hot cues, REMIX row = samples, no mode buttons
    m = Midi()
    u = S4MK2(m, A)
    f1 = bytearray(21); f1[0] = 1
    u.handle(bytes(f1))
    f1[0x0C] |= 0x01; u.handle(bytes(f1))
    check("S4 MK2 right PLAY", m.log[-1:], [(0x91, N_PLAY, 127)])
    f1[0x0D] |= 0x08; u.handle(bytes(f1)); f1[0x0D] |= 0x80; u.handle(bytes(f1))   # left SHIFT + HOTCUE 1
    check("S4 MK2 SHIFT + HOTCUE 1", m.log[-1:], [(0x98, 0, 127)])
    f1[0x0D] &= ~0x88; u.handle(bytes(f1))
    f1[0x0B] |= 0x10; u.handle(bytes(f1))                              # right REMIX 4
    check("S4 MK2 right REMIX 4 = sample 4", m.log[-1:], [(0x99, SAMPLE_NOTE + 3, 127)])
    f1[0x11] |= 0x01; u.handle(bytes(f1))
    check("S4 MK2 left touch", m.log[-1:], [(0x90, N_TOUCH, 127)])
    f1[0x05] = 5; u.handle(bytes(f1)); n0 = len(m.log)
    f1[0x05] = 255; u.handle(bytes(f1))                                # right jog -6 across 0 (5 -> 255)
    check("S4 MK2 right jog -6", sum(x[2] - 64 for x in m.log[n0:] if x[0] == 0xB1), -16)   # -6 x 2880 / 1024 = -16.9: -16 sent, the rest kept
    f2 = bytearray(79); f2[0] = 2
    struct.pack_into("<H", f2, 0x0B, 16); u.handle(bytes(f2))          # right tempo at 16 = the top end
    check("S4 MK2 right tempo at the top -> 14-bit max (turned over)", [x for x in m.log if x[0] == 0xB1 and x[1] in (0, 32)][-2:],
          [(0xB1, 0, 127), (0xB1, 32, 127)])
    # S4 MK2 on macOS: report 2 as 64 bytes + a 15-byte rest without an ID (whose first byte here looks like report 1)
    m = Midi()
    u = S4MK2(m, A)
    mac = bytearray(64); mac[0] = 2
    struct.pack_into("<H", mac, 0x37, 4080); u.handle(bytes(mac))
    rest = bytearray(15); rest[0] = 1; rest[0x0D] = 0xFF
    n0 = len(m.log); u.handle(bytes(rest))
    check("S4 MK2 macOS: 64-byte part read (left volume)", [x for x in m.log if x[0] == 0xB0 and x[1] == CC_VOL][-1:], [(0xB0, CC_VOL, 127)])
    check("S4 MK2 macOS: the 15-byte rest ignored (not read as report 1)", m.log[n0:], [])
    # S2 MK1: the top touch from the pressure value and the unit's calibration
    m = Midi()
    u = S2MK1(m, A)
    u.calibrate(bytes([0xD4, 0x0C, 0x1B, 0x0C, 0xE6, 0x0C, 0x9A, 0x0D, 0x58]))
    check("S2 MK1 calibration read (big-endian)", u.cal, [(0x0C1B, 0x0CE6), (0x0C9A, 0x0D58)])
    g2 = bytearray(0x31); g2[0] = 2
    struct.pack_into("<H", g2, 0x0D, 0x0C1B); struct.pack_into("<H", g2, 0x1D, 0x0C9A); u.handle(bytes(g2))
    n0 = len(m.log)
    struct.pack_into("<H", g2, 0x0D, 0x0CB0); u.handle(bytes(g2))       # 74 % of the way: touched
    check("S2 MK1 left pressed -> touch", [x for x in m.log[n0:] if x[1] == N_TOUCH], [(0x90, N_TOUCH, 127)])
    n0 = len(m.log)
    struct.pack_into("<H", g2, 0x0D, 0x0C70); u.handle(bytes(g2))       # 42 %: still touched (hysteresis)
    struct.pack_into("<H", g2, 0x0D, 0x0C40); u.handle(bytes(g2))       # 18 %: let go
    check("S2 MK1 left hysteresis, then let go", [x for x in m.log[n0:] if x[1] == N_TOUCH], [(0x80, N_TOUCH, 0)])
    g1 = bytearray(0x0E); g1[0] = 1
    u.handle(bytes(g1))
    g1[0x0C] |= 0x10; u.handle(bytes(g1))
    check("S2 MK1 right PLAY", m.log[-1:], [(0x91, N_PLAY, 127)])
    g1[0x0D] |= 0x08; u.handle(bytes(g1))
    check("S2 MK1 left pad 1 (bit 0x08)", m.log[-1:], [(0x97, 0, 127)])
    u2 = S2MK1(Midi(), A)
    g2b = bytearray(0x31); g2b[0] = 2
    struct.pack_into("<H", g2b, 0x0D, 3000); u2.handle(bytes(g2b))
    struct.pack_into("<H", g2b, 0x0D, 3000 + 120); u2.handle(bytes(g2b))
    check("S2 MK1 without calibration: idle = the first value, touch at idle + 90", u2.decks[0].btn.get("touch"), 1)
    # lights: ReaScratch's MIDI (Reloop RGB values) -> the LED reports
    lt = Lights()
    lt.midi(bytes([0x90, N_PLAY, 127]))                               # deck A playing
    lt.midi(bytes([0x97, 0, 0x40 | 0x30]))                            # deck A hot cue 1: bright red
    lt.midi(bytes([0x97, 1, 0x0C]))                                   # hot cue 2: dark green
    lt.midi(bytes([0x98, 0, 0x30]))                                   # its SHIFT layer: dark red
    lt.midi(bytes([0x91, N_CUE, 127]))                                # deck B stopped: CUE
    lt.midi(bytes([0x99, SAMPLE_NOTE + 2, 0x40 | 0x0C]))              # deck B sample 3 in use: bright green
    lt.midi(bytes([0x80, N_PLAY, 0])); lt.midi(bytes([0x90, N_PLAY, 127]))   # a note off, then on again
    check("lights: Reloop RGB decoded", (lt_rgb(0x70), lt_rgb(0x0C)), ((1.0, 0.0, 0.0), (0.0, 1 / 3, 0.0)))
    u = S4MK3(Midi(), A)
    r = u.leds(lt)[0x80]
    check("S4 MK3 LEDs: length, A PLAY, A pad 1 red + 2, pad 2 green + 0, B CUE, A HOTCUE mode",
          (len(r), r[56], r[1], r[2], r[32], r[10], r[67]), (95, 70, 6, 28, 70, 70, 0))
    u.decks[0].shift = 1
    check("S4 MK3 LEDs: SHIFT held -> its layer (dark red), the SHIFT button lit", (u.leds(lt)[0x80][1], u.leds(lt)[0x80][60]), (4, 70))
    u.decks[1].pad_mode = "samples"
    check("S4 MK3 LEDs: B in SAMPLES -> sample 3 green + 2, the SAMPLES button", (u.leds(lt)[0x80][26], u.leds(lt)[0x80][69]), (30, 70))
    u = S2MK3(Midi(), A)
    r = u.leds(lt)[0x80]
    check("S2 MK3 LEDs: A PLAY 0x7E, pad 1 bright red 0x06, pad 2 dark green 0x1C, pad 3 off 0x02, B CUE",
          (len(r), r[0x0C], r[0x0D], r[0x0E], r[0x0F], r[0x32]), (62, 0x7E, 0x06, 0x1C, 0x02, 0x7E))
    u = S3(Midi(), A)
    r = u.leds(lt)[0x80]
    check("S3 LEDs: A PLAY 0x77, B PLAY 0x20, A pad 1 red + 3, pad 2 green + 1, A PFL off 0x04",
          (r[0x11], r[0x2A], r[0x12], r[0x13], r[0x39]), (0x77, 0x20, 0x07, 0x1D, 0x04))
    u = S4MK2(Midi(), A)
    rr = u.leds(lt)
    check("S4 MK2 LEDs: A PLAY, HOTCUE 1 RGB, HOTCUE 2 dark green, B REMIX 3 bright, report lengths",
          (rr[0x81][0x20], list(rr[0x81][1:4]), list(rr[0x81][4:7]), rr[0x81][0x23], len(rr[0x81]), len(rr[0x82])),
          (0x7F, [127, 0, 0], [0, 42, 0], 0x7F, 63, 61))
    u = S2MK2(Midi(), A)
    rr = u.leds(lt)
    check("S2 MK2 LEDs: A PLAY, pad 1 RGB, B CUE", (rr[0x81][0x1C], list(rr[0x81][1:4]), rr[0x81][0x1F]), (0x7F, [127, 0, 0], 0x7F))
    u = S2MK1(Midi(), A)
    r = u.leds(lt)[0x80]
    check("S2 MK1 LEDs: A PLAY 0x1F, pad 1 red shown as blue, pad 2 green", (r[0x03], r[0x0C], r[0x10], r[0x0B], r[0x0F]),
          (0x1F, 0, 0x1F, 10, 0))
    class H:
        def __init__(self): self.w = []
        def write(self, b): self.w.append(bytes(b))
    h = H(); lights_off(S4MK2(Midi(), A), h)
    check("lights off: every report zeros after its ID", [(b[0], len(b), any(b[1:])) for b in h.w], [(0x81, 63, False), (0x82, 61, False)])
    print("selftest", "passed" if ok else "FAILED")
    return 0 if ok else 1


def report(seconds=15):
    """For testers (⚪88): one text file to send back. The computer, the Python parts, the selftest, the MIDI ports, the
    NI units found, and `seconds` of the unit's reports while the tester moves it (read only: nothing is sent to the
    unit, no motor-off, no lights). No user name or folder goes into the file."""
    import contextlib
    import hashlib
    import io
    import os
    import platform
    here = os.path.dirname(os.path.abspath(sys.executable if getattr(sys, "frozen", False) else __file__))
    out = os.path.join(here, "hid_bridge_report.txt")
    lines = []
    say = lines.append
    say("ReaScratch HID bridge report")
    say(time.strftime("date: %Y-%m-%d %H:%M"))
    me = sys.executable if getattr(sys, "frozen", False) else os.path.abspath(__file__)
    with open(me, "rb") as f:
        say(f"program: {'exe' if getattr(sys, 'frozen', False) else 'hid_bridge.py'} sha256 {hashlib.sha256(f.read()).hexdigest()[:12]}")
    mac = platform.mac_ver()[0]
    say(f"system: {platform.system()} {platform.release()}" + (f" (macOS {mac})" if mac else "") + f", {platform.machine()}")
    say(f"python: {platform.python_version()}")
    for mod, dist in (("hid", "hidapi"), ("mido", "mido"), ("rtmidi", "python-rtmidi")):
        try:
            m = __import__(mod)
            try:
                from importlib.metadata import version
                v = version(dist)
            except Exception:
                v = getattr(m, "__version__", "?")
            say(f"{dist}: {v}")
        except Exception as e:
            say(f"{dist}: cannot import ({e})")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = selftest()
    ng = [s for s in buf.getvalue().splitlines() if s.startswith("NG")]
    say(f"selftest: {'passed' if code == 0 else 'FAILED'}" + "".join("\n  " + s for s in ng))

    say("")
    try:
        import mido
        say(f"MIDI outputs: {mido.get_output_names()}")
        say(f"MIDI inputs: {mido.get_input_names()}")
        if sys.platform == "darwin":
            p = mido.open_output("ReaScratch HID Bridge test", virtual=True)
            time.sleep(0.5)
            say(f"virtual port: made, seen as an input: {any('ReaScratch HID Bridge test' in n for n in mido.get_input_names())}")
            p.close()
    except Exception as e:
        say(f"MIDI: error ({type(e).__name__}: {e})")

    say("")
    try:
        import hid
        devs = hid.enumerate(NI, 0)
    except Exception as e:
        devs = None
        say(f"HID: error ({type(e).__name__}: {e})")
    if devs is not None:
        say(f"NI HID interfaces: {len(devs)}")
        for d in devs:
            say(f"  pid 0x{d.get('product_id', 0):04X} '{d.get('product_string')}' interface {d.get('interface_number')} "
                f"usage_page 0x{d.get('usage_page') or 0:04X} usage 0x{d.get('usage') or 0:04X}")
        print("\n".join(lines))
        cls, h = None, None
        try:
            cls, h = open_unit(hid)
        except Exception as e:
            say(f"open: error ({type(e).__name__}: {e})  <- on macOS: quit Traktor; allow Input Monitoring if asked")
        if h:
            say(f"opened: {cls.name}")
            print(f"\nconnected: {cls.name}. For {seconds} seconds: turn both jogs (touching the top, then the side), "
                  "press PLAY and CUE on both decks, move the tempo faders and the crossfader.")
            print(f"{cls.name} につながりました。{seconds}秒のあいだに: 両方のジョグを回す（天面に触れて、次に側面）、"
                  "両デッキの PLAY と CUE を押す、テンポのフェーダーとクロスフェーダーを動かす。")
            midi = Midi()
            unit = cls(midi, argparse.Namespace(tempo_invert=False, no_motor_off=True, s4_ticks=2880, s2_ticks=600,
                                                  s3_ticks=768, mk2_ticks=1024))
            seen, err = {}, None
            end = time.time() + seconds
            try:
                h.set_nonblocking(False)
                while time.time() < end:
                    data = h.read(512, 200)
                    if data:
                        b = bytes(data)
                        s = seen.setdefault(b[0], {"n": 0, "lens": set(), "first": b, "changes": 0, "last": b})
                        s["n"] += 1
                        s["lens"].add(len(b))
                        s["changes"] += b != s["last"]
                        s["last"] = b
                        unit.handle(b)
            except Exception as e:
                err = f"{type(e).__name__}: {e}"
            finally:
                h.close()
            say(f"reports in {seconds} s:" + ("" if seen else " none (the unit sent nothing)"))
            for rid in sorted(seen):
                s = seen[rid]
                say(f"  id 0x{rid:02X}: {s['n']} reports, {s['changes']} changes, length {sorted(s['lens'])}, "
                    f"first {s['first'][:24].hex(' ')}")
            if err:
                say(f"read: error ({err})")
            kinds = {}
            for st, d1, _ in midi.log:
                kinds[f"{st:02X} {d1:02X}"] = kinds.get(f"{st:02X} {d1:02X}", 0) + 1
            say(f"MIDI it would send: {len(midi.log)} messages; by status/number: "
                + ", ".join(f"{k} x{n}" for k, n in sorted(kinds.items())))
        elif not any("open: error" in s for s in lines):
            say("no supported unit found (connect it and run again; an S4 also needs its power adapter)")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"\nsaved: {out}\nSend this file (attach it to a GitHub issue or the forum thread).")
    print("このファイルを送ってください（GitHub の issue かフォーラムのスレッドに添付）。")
    if sys.platform == "darwin":
        import subprocess
        subprocess.call(["open", "-R", out])     # show it in Finder
    return 0


def main():
    sys.stdout.reconfigure(line_buffering=True, errors="replace")   # ((⚪179) --help printed the ⚪ marks of the docstring: a Japanese console (cp932) stopped it)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="loopMIDI Port", help="MIDI output port (part of its name; the shortest match wins)")
    ap.add_argument("--list-ports", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--report", nargs="?", type=int, const=15, metavar="SECONDS",
                    help="for testers: write hid_bridge_report.txt (computer, ports, the unit's reports for SECONDS s)")
    ap.add_argument("--tempo-invert", action="store_true", help="the tempo fader's maximum is already the + end")
    ap.add_argument("--s4-ticks", type=float, default=2880, help="S4 MK3 relative counter per jog turn")
    ap.add_argument("--s2-ticks", type=float, default=600, help="S2 MK3 counter ticks per jog turn")
    ap.add_argument("--s3-ticks", type=float, default=768, help="S3 jog steps per turn (8-bit counter)")
    ap.add_argument("--mk2-ticks", type=float, default=1024, help="S4 MK2 / S2 MK2 / S2 MK1 jog steps per turn (8-bit counter)")
    ap.add_argument("--no-motor-off", action="store_true")
    ap.add_argument("--led-port", default="ReaScratch LED",
                    help="MIDI input with ReaScratch's lights (Windows: a second loopMIDI port of this name)")
    ap.add_argument("--no-lights", action="store_true", help="leave the unit's lights alone")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.report is not None:
        return report(a.report)
    if a.list_ports:
        import mido
        print("\n".join(mido.get_output_names()))
        return 0
    return run(a)


if __name__ == "__main__":
    code = main()
    if getattr(sys, "frozen", False) and code:      # double-clicked exe: keep the window open to read the message
        try:
            input("press Enter to close / Enter で閉じます")
        except EOFError:                            # started without a console input (not double-clicked)
            pass
    sys.exit(code)
