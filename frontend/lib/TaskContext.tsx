import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import type { Task, TaskInput } from "./task";
import { useAuth } from "./AuthContext";
import { useSyncOptional } from "./sync";
import { useTasks as useTasksFromStore, useTaskActions, useTasksSortedByDifficulty, LOCAL_USER_ID } from "./store";
import { completeTask as completeTaskAction } from "./completeTask";

interface TaskContextType {
  tasks: Task[];
  rankedTasks: Task[];
  selectedTask: Task | null;
  isEditing: boolean;
  createTask: (input: TaskInput) => Promise<Task>;
  updateTask: (id: string, input: Partial<TaskInput>) => Promise<Task | null>;
  deleteTask: (id: string) => Promise<boolean>;
  completeTask: (task: Task) => Promise<number>;
  selectTask: (task: Task | null) => void;
  setIsEditing: (editing: boolean) => void;
}

const TaskContext = createContext<TaskContextType | null>(null);

export function TaskProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const sync = useSyncOptional();
  const actions = useTaskActions();

  // Use user ID from auth, fallback to local-user for offline mode
  const userId = user?.id ?? LOCAL_USER_ID;

  // Get tasks from reactive store (fine-grained subscription)
  const tasks = useTasksFromStore(userId);
  const rankedTasks = useTasksSortedByDifficulty(userId);

  // UI state (not persisted)
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [isEditing, setIsEditing] = useState(false);

  const createTask = useCallback(
    async (input: TaskInput): Promise<Task> => {
      const task = await actions.createTask(userId, input);
      // Notify sync service of change
      sync?.notifyChange();
      return task;
    },
    [userId, sync, actions],
  );

  const updateTask = useCallback(
    async (id: string, input: Partial<TaskInput>): Promise<Task | null> => {
      const updated = await actions.updateTask(id, input);
      if (updated) {
        // Notify sync service of change
        sync?.notifyChange();
      }
      return updated;
    },
    [sync, actions],
  );

  const deleteTask = useCallback(
    async (id: string): Promise<boolean> => {
      const success = await actions.deleteTask(id);
      if (success) {
        // Notify sync service of change
        sync?.notifyChange();
      }
      return success;
    },
    [sync, actions],
  );

  const completeTask = useCallback(
    async (task: Task): Promise<number> => {
      const amount = await completeTaskAction(task, tasks, userId, () => {
        sync?.notifyChange();
      });
      return amount;
    },
    [tasks, userId, sync],
  );

  const selectTask = useCallback((task: Task | null) => {
    setSelectedTask(task);
  }, []);

  return (
    <TaskContext.Provider
      value={{
        tasks,
        rankedTasks,
        selectedTask,
        isEditing,
        createTask,
        updateTask,
        deleteTask,
        completeTask,
        selectTask,
        setIsEditing,
      }}
    >
      {children}
    </TaskContext.Provider>
  );
}

export function useTasks(): TaskContextType {
  const context = useContext(TaskContext);
  if (!context) {
    throw new Error("useTasks must be used within a TaskProvider");
  }
  return context;
}
