import { createContext, useContext, useEffect } from "react";
import { useColorScheme } from "nativewind";
import AsyncStorage from "@react-native-async-storage/async-storage";

const THEME_STORAGE_KEY = "@theme_preference";

interface ThemeContextValue {
  colorScheme: "light" | "dark" | undefined;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue>({
  colorScheme: "light",
  toggleTheme: () => {},
});

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const { colorScheme, setColorScheme, toggleColorScheme } = useColorScheme();

  useEffect(() => {
    AsyncStorage.getItem(THEME_STORAGE_KEY).then((stored) => {
      if (stored === "dark" || stored === "light") {
        setColorScheme(stored);
      }
    });
  }, [setColorScheme]);

  const toggleTheme = () => {
    const next = colorScheme === "dark" ? "light" : "dark";
    setColorScheme(next);
    AsyncStorage.setItem(THEME_STORAGE_KEY, next);
  };

  return (
    <ThemeContext.Provider value={{ colorScheme, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}
