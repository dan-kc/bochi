import { useColorScheme } from "react-native";

export interface Colors {
  background: string;
  foreground: string;
  accent: string;
  accentSecondary: string;
  surface: string;
  border: string;
  muted: string;
  white: string;
  black: string;
}

export const lightColors: Colors = {
  background: "#fffeff",
  foreground: "#322f39",
  accent: "#f54900",
  accentSecondary: "#197291",
  surface: "#f5f4f6",
  border: "#e5e3e7",
  muted: "#7d7888",
  white: "#ffffff",
  black: "#000000",
};

export const darkColors: Colors = {
  background: "#1b1a1f",
  foreground: "#e9e3da",
  accent: "#f54900",
  accentSecondary: "#197291",
  surface: "#252429",
  border: "#2e2d33",
  muted: "#9e9890",
  white: "#ffffff",
  black: "#000000",
};

export function useColors(): Colors {
  const colorScheme = useColorScheme();
  return colorScheme === "dark" ? darkColors : lightColors;
}

// Tailwind-compatible spacing scale (value * 4)
export const spacing = {
  0: 0,
  0.5: 2,
  1: 4,
  1.5: 6,
  2: 8,
  2.5: 10,
  3: 12,
  3.5: 14,
  4: 16,
  5: 20,
  6: 24,
  7: 28,
  8: 32,
  9: 36,
  10: 40,
  11: 44,
  12: 48,
  14: 56,
  16: 64,
  20: 80,
  24: 96,
} as const;

// Font sizes matching Tailwind defaults
export const fontSize = {
  xs: 12,
  sm: 14,
  base: 16,
  lg: 18,
  xl: 20,
  "2xl": 24,
  "3xl": 30,
  "4xl": 36,
  "5xl": 48,
} as const;

// Common border radius values
export const borderRadius = {
  none: 0,
  sm: 2,
  DEFAULT: 4,
  md: 6,
  lg: 8,
  xl: 12,
  "2xl": 16,
  "3xl": 24,
  full: 9999,
} as const;

// Font weights
export const fontWeight = {
  normal: "400" as const,
  medium: "500" as const,
  semibold: "600" as const,
  bold: "700" as const,
};
