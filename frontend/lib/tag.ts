export interface Tag {
  id: string;
  user_id: string;
  name: string;
  color_hex: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface TagInput {
  name: string;
  color_hex: string;
  deleted_at?: string | null;
}

export function createEmptyTagInput(): TagInput {
  return {
    name: "",
    color_hex: generateRandomColor(),
    deleted_at: null,
  };
}

/**
 * Generates a random color in #RRGGBBAA format
 * Uses HSL to ensure vibrant colors with good saturation
 */
export function generateRandomColor(): string {
  const hue = Math.floor(Math.random() * 360);
  const saturation = 70 + Math.floor(Math.random() * 20); // 70-90%
  const lightness = 45 + Math.floor(Math.random() * 15); // 45-60%
  return hslToHex(hue, saturation, lightness) + "FF"; // Full opacity
}

/**
 * Converts HSL to hex color
 */
function hslToHex(h: number, s: number, l: number): string {
  s /= 100;
  l /= 100;

  const a = s * Math.min(l, 1 - l);
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    const color = l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1);
    return Math.round(255 * color)
      .toString(16)
      .padStart(2, "0");
  };

  return `#${f(0)}${f(8)}${f(4)}`.toUpperCase();
}
