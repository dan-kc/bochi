import { Slot } from "expo-router";
import { AuthProvider } from "@/lib/AuthContext";
import { SyncProvider } from "@/lib/sync";
import { HabitProvider } from "@/lib/HabitContext";
import { PriceUpdateProvider } from "@/lib/PriceUpdateContext";
import { RewardProvider } from "@/lib/RewardContext";
import { RewardPriceUpdateProvider } from "@/lib/RewardPriceUpdateContext";
import "../global.css";

export default function RootLayout() {
  return (
    <AuthProvider>
      <SyncProvider>
        <PriceUpdateProvider>
          <HabitProvider>
            <RewardPriceUpdateProvider>
              <RewardProvider>
                <Slot />
              </RewardProvider>
            </RewardPriceUpdateProvider>
          </HabitProvider>
        </PriceUpdateProvider>
      </SyncProvider>
    </AuthProvider>
  );
}
