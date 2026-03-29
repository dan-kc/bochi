import { Slot } from "expo-router";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { AuthProvider } from "@/lib/AuthContext";
import { SyncProvider } from "@/lib/sync";
import { HabitProvider } from "@/lib/HabitContext";
import { PriceUpdateProvider } from "@/lib/PriceUpdateContext";
import { RewardProvider } from "@/lib/RewardContext";
import { RewardPriceUpdateProvider } from "@/lib/RewardPriceUpdateContext";
import { ThemeProvider } from "@/lib/ThemeContext";
import { SyncToast } from "@/components/SyncToast";

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <ThemeProvider>
        <AuthProvider>
          <SyncProvider>
            <PriceUpdateProvider>
              <HabitProvider>
                <RewardPriceUpdateProvider>
                  <RewardProvider>
                    <Slot />
                    <SyncToast />
                  </RewardProvider>
                </RewardPriceUpdateProvider>
              </HabitProvider>
            </PriceUpdateProvider>
          </SyncProvider>
        </AuthProvider>
      </ThemeProvider>
    </GestureHandlerRootView>
  );
}
