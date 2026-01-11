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
import { getLastSyncTime, clearLastSyncTime } from "./syncStorage";
import type { SyncStatus } from "./types";

interface SyncContextType {
  syncStatus: SyncStatus;
  lastSyncTime: string | null;
  syncError: string | null;
  notifyChange: () => void;
  triggerSync: () => void;
  waitForSync: () => Promise<void>;
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
  const syncWaitersRef = useRef<Array<() => void>>([]);
  const previousUserIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (user) {
      // Detect user change (login/switch accounts)
      const userChanged = previousUserIdRef.current !== null && previousUserIdRef.current !== user.id;
      previousUserIdRef.current = user.id;

      // When user changes, clear lastSyncTime to force a full sync
      // This ensures we pull ALL tasks for the new user, not just recent changes
      if (userChanged) {
        clearLastSyncTime();
        setLastSyncTime(null);
      } else {
        // Load persisted lastSyncTime only if user didn't change
        getLastSyncTime().then((time) => {
          if (time) setLastSyncTime(time);
        });
      }

      // Create sync service when user logs in
      syncServiceRef.current = new SyncService(
        {
          onStatusChange: (status, error) => {
            setSyncStatus(status);
            setSyncError(status === "error" ? (error ?? "Sync failed") : null);
            // Resolve waiters on sync completion (success or error)
            if (status === "synced" || status === "error") {
              const waiters = syncWaitersRef.current;
              syncWaitersRef.current = [];
              waiters.forEach((resolve) => resolve());
            }
          },
          onSyncComplete: (serverTime) => {
            setLastSyncTime(serverTime);
            // No need to refresh tasks - taskStore is reactive!
            // React components using useTasks() will automatically re-render
          },
        },
        user.id,
      );

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

  const waitForSync = useCallback((): Promise<void> => {
    return new Promise((resolve) => {
      syncWaitersRef.current.push(resolve);
      // The sync will be triggered by the useEffect when user changes,
      // or if already synced, trigger manually
      // Note: We don't trigger here because after login() the user context
      // changes, which causes a re-render and new SyncService creation.
      // The new SyncService automatically triggers sync on creation.
    });
  }, []);

  return (
    <SyncContext.Provider
      value={{
        syncStatus,
        lastSyncTime,
        syncError,
        notifyChange,
        triggerSync,
        waitForSync,
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
