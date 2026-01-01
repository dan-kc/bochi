import { Slot } from "expo-router";
import { AuthProvider } from "@/lib/AuthContext";
import { SyncProvider } from "@/lib/sync";
import { TaskProvider } from "@/lib/TaskContext";
import "../global.css";

export default function RootLayout() {
  return (
    <AuthProvider>
      <SyncProvider>
        <TaskProvider>
          <Slot />
        </TaskProvider>
      </SyncProvider>
    </AuthProvider>
  );
}
