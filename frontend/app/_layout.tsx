import { Slot } from "expo-router";
import { AuthProvider } from "@/lib/AuthContext";
import { SyncProvider } from "@/lib/sync";
import { HabitProvider } from "@/lib/HabitContext";
import { PriceUpdateProvider } from "@/lib/PriceUpdateContext";
import "../global.css";

export default function RootLayout() {
  return (
    <AuthProvider>
      <SyncProvider>
        <PriceUpdateProvider>
          <HabitProvider>
            <Slot />
          </HabitProvider>
        </PriceUpdateProvider>
      </SyncProvider>
    </AuthProvider>
  );
}
