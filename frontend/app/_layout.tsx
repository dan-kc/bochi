import { Slot } from "expo-router";
import { AuthProvider } from "@/lib/AuthContext";
import { SyncProvider } from "@/lib/sync";
import { TaskProvider } from "@/lib/TaskContext";
import { PriceUpdateProvider } from "@/lib/PriceUpdateContext";
import "../global.css";

export default function RootLayout() {
  return (
    <AuthProvider>
      <SyncProvider>
        <PriceUpdateProvider>
          <TaskProvider>
            <Slot />
          </TaskProvider>
        </PriceUpdateProvider>
      </SyncProvider>
    </AuthProvider>
  );
}
