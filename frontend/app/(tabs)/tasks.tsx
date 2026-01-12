import { useState, useCallback, useEffect, useMemo } from "react";
import { View, Text, Pressable, Modal } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useTasks } from "@/lib/TaskContext";
import { usePriceUpdate } from "@/lib/PriceUpdateContext";
import { TaskItem } from "@/components/TaskItem";
import { TaskForm } from "@/components/TaskForm";
import { DifficultyRanker } from "@/components/DifficultyRanker";
import { SyncStatusIcon } from "@/components/SyncStatusIcon";
import { BalanceDisplay } from "@/components/BalanceDisplay";
import { TaskTabs } from "@/components/TaskTabs";
import { SortDropdown } from "@/components/SortDropdown";
import type { Task, TaskInput } from "@/lib/task";
import { isHabit } from "@/lib/task";
import { type TabType, SORT_OPTIONS } from "@/lib/sortOptions";
import { sortTasks, getDisplayMode } from "@/lib/taskSorting";
import { useSortPreference } from "@/lib/store/sortPreferencesStore";

export default function Tasks() {
  const {
    tasks,
    rankedTasks,
    selectedTask,
    createTask,
    updateTask,
    deleteTask,
    completeTask,
    selectTask,
    setIsEditing,
  } = useTasks();

  const [isModalVisible, setIsModalVisible] = useState(false);
  const [isRankingVisible, setIsRankingVisible] = useState(false);
  const [taskToRank, setTaskToRank] = useState<Task | null>(null);
  const [activeTab, setActiveTab] = useState<TabType>("both");
  const [sortKey, setSortKey] = useSortPreference(activeTab);

  // Price update context
  const { updatePrices, prices } = usePriceUpdate();

  // Filter out completed non-habit tasks, then filter by tab and sort
  const displayTasks = useMemo(() => {
    // First filter out completed non-habits
    let filtered = tasks.filter((t) => !t.completed_at || isHabit(t));

    // Then filter by tab
    if (activeTab === "habit") {
      filtered = filtered.filter((t) => t.habit);
    } else if (activeTab === "todo") {
      filtered = filtered.filter((t) => !t.habit);
    }

    // Finally sort
    return sortTasks(filtered, sortKey, prices);
  }, [tasks, activeTab, sortKey, prices]);

  const displayMode = getDisplayMode(sortKey);

  // Update prices when tasks change
  useEffect(() => {
    updatePrices(tasks);
  }, [tasks, updatePrices]);

  const handleAddTask = useCallback(() => {
    selectTask(null);
    setIsEditing(false);
    setIsModalVisible(true);
  }, [selectTask, setIsEditing]);

  const handleTaskPress = useCallback(
    (task: Task) => {
      selectTask(task);
      setIsEditing(true);
      setIsModalVisible(true);
    },
    [selectTask, setIsEditing],
  );

  const handleSave = useCallback(
    async (input: TaskInput) => {
      if (selectedTask) {
        await updateTask(selectedTask.id, input);
        setIsModalVisible(false);
        selectTask(null);
      } else {
        const newTask = await createTask(input);
        setIsModalVisible(false);
        selectTask(null);
        // After creating a new task, offer to set difficulty
        if (rankedTasks.length > 0) {
          setTaskToRank(newTask);
          setIsRankingVisible(true);
        }
      }
    },
    [selectedTask, updateTask, createTask, selectTask, rankedTasks.length],
  );

  const handleCancel = useCallback(() => {
    setIsModalVisible(false);
    selectTask(null);
  }, [selectTask]);

  const handleDelete = useCallback(async () => {
    if (selectedTask) {
      await deleteTask(selectedTask.id);
      setIsModalVisible(false);
      selectTask(null);
    }
  }, [selectedTask, deleteTask, selectTask]);

  const handleRankComplete = useCallback(
    async (rank: string) => {
      if (taskToRank) {
        await updateTask(taskToRank.id, { difficulty_rank: rank });
      }
      setIsRankingVisible(false);
      setTaskToRank(null);
    },
    [taskToRank, updateTask],
  );

  const handleRankSkip = useCallback(() => {
    setIsRankingVisible(false);
    setTaskToRank(null);
  }, []);

  const handleComplete = useCallback(
    async (task: Task) => {
      await completeTask(task);
    },
    [completeTask],
  );

  const handleRerank = useCallback(() => {
    if (selectedTask) {
      setIsModalVisible(false);
      setTaskToRank(selectedTask);
      setIsRankingVisible(true);
    }
  }, [selectedTask]);

  const renderItem = useCallback(
    ({ item }: { item: Task }) => (
      <TaskItem
        task={item}
        onPress={handleTaskPress}
        onComplete={handleComplete}
        displayMode={displayMode}
      />
    ),
    [handleTaskPress, handleComplete, displayMode],
  );

  const keyExtractor = useCallback((item: Task) => item.id, []);

  return (
    <SafeAreaView className="flex-1 bg-white" edges={["top"]}>
      <View className="flex-1">
        <View className="p-4 border-b border-gray-200">
          <View className="flex-row justify-between items-center mb-3">
            <Text className="text-2xl font-bold text-gray-900">Tasks</Text>
            <View className="flex-row items-center gap-2">
              <BalanceDisplay />
              <SyncStatusIcon />
            </View>
          </View>
          <View className="flex-row justify-between items-center">
            <TaskTabs activeTab={activeTab} onTabChange={setActiveTab} />
            <SortDropdown
              options={SORT_OPTIONS[activeTab]}
              selectedKey={sortKey}
              onSelect={setSortKey}
            />
          </View>
        </View>

        {displayTasks.length === 0 ? (
          <View className="flex-1 items-center justify-center p-4">
            <Text className="text-gray-500 text-center mb-4">
              {activeTab === "habit"
                ? "No habits yet. Add your first habit to get started."
                : activeTab === "todo"
                  ? "No todos yet. Add your first todo to get started."
                  : "No tasks yet. Add your first task to get started."}
            </Text>
          </View>
        ) : (
          <LegendList
            data={displayTasks}
            renderItem={renderItem}
            keyExtractor={keyExtractor}
            extraData={{ activeTab, sortKey, displayMode }}
            contentContainerStyle={{ padding: 16 }}
            estimatedItemSize={100}
          />
        )}

        <View className="p-4 border-t border-gray-200">
          <Pressable
            onPress={handleAddTask}
            className="bg-blue-500 py-3 px-6 rounded-lg items-center"
          >
            <Text className="text-white font-semibold text-base">Add Task</Text>
          </Pressable>
        </View>

        <Modal
          visible={isModalVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleCancel}
        >
          <SafeAreaView className="flex-1 bg-white">
            <TaskForm
              task={selectedTask}
              onSave={handleSave}
              onCancel={handleCancel}
              onDelete={selectedTask ? handleDelete : undefined}
              onRerank={selectedTask ? handleRerank : undefined}
            />
          </SafeAreaView>
        </Modal>

        <Modal
          visible={isRankingVisible}
          animationType="slide"
          presentationStyle="pageSheet"
          onRequestClose={handleRankSkip}
        >
          <SafeAreaView className="flex-1 bg-white">
            {taskToRank && (
              <DifficultyRanker
                task={taskToRank}
                existingTasks={rankedTasks.filter(t => t.id !== taskToRank.id && t.difficulty_rank !== null)}
                onComplete={handleRankComplete}
                onSkip={handleRankSkip}
              />
            )}
          </SafeAreaView>
        </Modal>
      </View>
    </SafeAreaView>
  );
}
