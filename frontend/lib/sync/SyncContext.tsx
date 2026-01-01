import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useRef,
  type ReactNode,
} from "react";
import { useAuth } from "../AuthContext";
import { SyncService } from "./syncService";
import { getLastSyncTime } from "./syncStorage";
import type { SyncStatus } from "./types";

interface SyncContextType {
  syncStatus: SyncStatus;
  lastSyncTime: string | null;
  syncError: string | null;
  notifyChange: () => void;
  triggerSync: () => void;
}

const SyncContext = createContext<SyncContextType | null>(null);

interface SyncProviderProps {
  children: ReactNode;
}

export function SyncProvider({ children }: SyncProviderProps) {
  const { user } = useAuth();
  const [syncStatus, setSyncStatus] = useState<SyncStatus>("idle");
  const [lastSyncTime, setLastSyncTime] = useState<string | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);

  const syncServiceRef = useRef<SyncService | null>(null);

  useEffect(() => {
    if (user) {
      // Load persisted lastSyncTime
      getLastSyncTime().then((time) => {
        if (time) setLastSyncTime(time);
      });

      // Create sync service when user logs in
      syncServiceRef.current = new SyncService({
        onStatusChange: (status, error) => {
          setSyncStatus(status);
          setSyncError(status === "error" ? (error ?? "Sync failed") : null);
        },
        onSyncComplete: (serverTime) => {
          setLastSyncTime(serverTime);
          // No need to refresh tasks - taskStore is reactive!
          // React components using useTasks() will automatically re-render
        },
      });

      // Trigger initial sync on login
      syncServiceRef.current.triggerSync();
    } else {
      // Cancel and clear sync service on logout
      syncServiceRef.current?.cancel();
      syncServiceRef.current = null;
      setSyncStatus("idle");
      setSyncError(null);
      setLastSyncTime(null);
    }

    return () => {
      syncServiceRef.current?.cancel();
    };
  }, [user]);

  const notifyChange = useCallback(() => {
    syncServiceRef.current?.notifyChange();
  }, []);

  const triggerSync = useCallback(() => {
    syncServiceRef.current?.triggerSync();
  }, []);

  return (
    <SyncContext.Provider
      value={{
        syncStatus,
        lastSyncTime,
        syncError,
        notifyChange,
        triggerSync,
      }}
    >
      {children}
    </SyncContext.Provider>
  );
}

export function useSync(): SyncContextType {
  const context = useContext(SyncContext);
  if (!context) {
    throw new Error("useSync must be used within a SyncProvider");
  }
  return context;
}

/**
 * Optional hook that returns null if not within SyncProvider.
 * Useful for components that may render before auth is ready.
 */
export function useSyncOptional(): SyncContextType | null {
  return useContext(SyncContext);
}
