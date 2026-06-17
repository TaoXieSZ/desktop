// KeyboardEvent.code -> USB HID keyboard usage (page 0x07).
// We key off `code` (physical position) not `key`, so the mapping is layout- and
// shift-independent. Used by the profile editor's keyboard-capture mode.

export const CODE_TO_HID: Readonly<Record<string, number>> = Object.freeze({
  // Letters
  KeyA: 0x04, KeyB: 0x05, KeyC: 0x06, KeyD: 0x07, KeyE: 0x08, KeyF: 0x09,
  KeyG: 0x0a, KeyH: 0x0b, KeyI: 0x0c, KeyJ: 0x0d, KeyK: 0x0e, KeyL: 0x0f,
  KeyM: 0x10, KeyN: 0x11, KeyO: 0x12, KeyP: 0x13, KeyQ: 0x14, KeyR: 0x15,
  KeyS: 0x16, KeyT: 0x17, KeyU: 0x18, KeyV: 0x19, KeyW: 0x1a, KeyX: 0x1b,
  KeyY: 0x1c, KeyZ: 0x1d,
  // Digits (1-9 then 0)
  Digit1: 0x1e, Digit2: 0x1f, Digit3: 0x20, Digit4: 0x21, Digit5: 0x22,
  Digit6: 0x23, Digit7: 0x24, Digit8: 0x25, Digit9: 0x26, Digit0: 0x27,
  // Control / whitespace
  Enter: 0x28, Escape: 0x29, Backspace: 0x2a, Tab: 0x2b, Space: 0x2c,
  CapsLock: 0x39,
  // Punctuation
  Minus: 0x2d, Equal: 0x2e, BracketLeft: 0x2f, BracketRight: 0x30,
  Backslash: 0x31, Semicolon: 0x33, Quote: 0x34, Backquote: 0x35,
  Comma: 0x36, Period: 0x37, Slash: 0x38,
  // F1-F12 then F13-F24
  F1: 0x3a, F2: 0x3b, F3: 0x3c, F4: 0x3d, F5: 0x3e, F6: 0x3f,
  F7: 0x40, F8: 0x41, F9: 0x42, F10: 0x43, F11: 0x44, F12: 0x45,
  F13: 0x68, F14: 0x69, F15: 0x6a, F16: 0x6b, F17: 0x6c, F18: 0x6d,
  F19: 0x6e, F20: 0x6f, F21: 0x70, F22: 0x71, F23: 0x72, F24: 0x73,
  // System
  PrintScreen: 0x46, ScrollLock: 0x47, Pause: 0x48,
  // Navigation
  Insert: 0x49, Home: 0x4a, PageUp: 0x4b, Delete: 0x4c, End: 0x4d, PageDown: 0x4e,
  ArrowRight: 0x4f, ArrowLeft: 0x50, ArrowDown: 0x51, ArrowUp: 0x52,
  // Numpad
  NumLock: 0x53, NumpadDivide: 0x54, NumpadMultiply: 0x55, NumpadSubtract: 0x56,
  NumpadAdd: 0x57, NumpadEnter: 0x58, Numpad1: 0x59, Numpad2: 0x5a, Numpad3: 0x5b,
  Numpad4: 0x5c, Numpad5: 0x5d, Numpad6: 0x5e, Numpad7: 0x5f, Numpad8: 0x60,
  Numpad9: 0x61, Numpad0: 0x62, NumpadDecimal: 0x63,
  // Modifiers (left then right)
  ControlLeft: 0xe0, ShiftLeft: 0xe1, AltLeft: 0xe2, MetaLeft: 0xe3,
  ControlRight: 0xe4, ShiftRight: 0xe5, AltRight: 0xe6, MetaRight: 0xe7,
});

export const MODIFIER_HID: ReadonlySet<number> = new Set([
  0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7,
]);

/** Translate a KeyboardEvent.code to its HID usage, or null when unmapped. */
export function codeToHid(code: string): number | null {
  const value = CODE_TO_HID[code];
  return value === undefined ? null : value;
}

export function isModifierCode(code: string): boolean {
  const hid = CODE_TO_HID[code];
  return hid !== undefined && MODIFIER_HID.has(hid);
}

/**
 * Held-modifier usages for an event, in deterministic order (Ctrl, Shift, Alt, GUI).
 * Held modifiers default to the left-hand usage codes; the pressed key keeps its own code.
 */
export function heldModifierUsages(event: {
  ctrlKey: boolean;
  shiftKey: boolean;
  altKey: boolean;
  metaKey: boolean;
}): number[] {
  const out: number[] = [];
  if (event.ctrlKey) out.push(0xe0);
  if (event.shiftKey) out.push(0xe1);
  if (event.altKey) out.push(0xe2);
  if (event.metaKey) out.push(0xe3);
  return out;
}

const MODIFIER_GLYPH: Record<number, string> = {
  0xe0: '⌃', 0xe4: '⌃', 0xe1: '⇧', 0xe5: '⇧',
  0xe2: '⌥', 0xe6: '⌥', 0xe3: '⌘', 0xe7: '⌘',
};

const ARROW_GLYPH: Record<number, string> = {
  0x4f: '→', 0x50: '←', 0x51: '↓', 0x52: '↑',
};

const HID_TO_NAME: Record<number, string> = Object.freeze(
  Object.entries(CODE_TO_HID).reduce<Record<number, string>>((acc, [code, hid]) => {
    if (acc[hid] === undefined) acc[hid] = code;
    return acc;
  }, {}),
);

/** Readable name for a single HID usage (e.g. 0x16 -> "S", 0x3e -> "F5"). */
export function hidToLabel(hid: number): string {
  if (ARROW_GLYPH[hid]) return ARROW_GLYPH[hid];
  const name = HID_TO_NAME[hid];
  if (!name) return `0x${hid.toString(16)}`;
  if (name.startsWith('Key')) return name.slice(3);
  if (name.startsWith('Digit')) return name.slice(5);
  return name;
}

/** Combined label for a captured chord, e.g. [0xe3,0x16] -> "⌘ + S". */
export function formatHidLabel(hidCodes: number[]): string {
  if (hidCodes.length === 0) return '（未设置）';
  return hidCodes
    .map((code) => (MODIFIER_HID.has(code) ? MODIFIER_GLYPH[code] ?? hidToLabel(code) : hidToLabel(code)))
    .join(' + ');
}
