import { useState, useCallback } from "react";
import { View, Text, Pressable, Modal } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useTasks } from "@/lib/TaskContext";
import { TaskItem } from "@/components/TaskItem";
import { TaskForm } from "@/components/TaskForm";
import { DifficultyRanker } from "@/components/DifficultyRanker";
import { SyncStatusIcon } from "@/components/SyncStatusIcon";
import type { Task, TaskInput } from "@/lib/task";

type SortMode = "newest" | "difficulty";

export default function Tasks() {
  const {
    tasks,
    rankedTasks,
    selectedTask,
    createTask,
    updateTask,
    deleteTask,
    selectTask,
    setIsEditing,
  } = useTasks();

  const [isModalVisible, setIsModalVisible] = useState(false);
  const [isRankingVisible, setIsRankingVisible] = useState(false);
  const [taskToRank, setTaskToRank] = useState<Task | null>(null);
  const [sortMode, setSortMode] = useState<SortMode>("newest");

  // Use sorted tasks based on mode
  const displayTasks = sortMode === "difficulty" ? rankedTasks : tasks;

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

  const handleSetDifficulty = useCallback(
    (task: Task) => {
      setTaskToRank(task);
      setIsRankingVisible(true);
    },
    [],
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
        onSetDifficulty={handleSetDifficulty}
        isDifficultyView={sortMode === "difficulty"}
      />
    ),
    [handleTaskPress, handleSetDifficulty, sortMode],
  );

  const keyExtractor = useCallback((item: Task) => item.id, []);

  return (
    <SafeAreaView className="flex-1 bg-white" edges={["top"]}>
      <View className="flex-1">
        <View className="p-4 border-b border-gray-200">
          <View className="flex-row justify-between items-center mb-3">
            <Text className="text-2xl font-bold text-gray-900">Tasks</Text>
            <SyncStatusIcon />
          </View>
          <View className="flex-row gap-2">
            <Pressable
              onPress={() => setSortMode("newest")}
              className={`flex-1 py-2 px-3 rounded-lg items-center border ${
                sortMode === "newest"
                  ? "bg-blue-500 border-blue-500"
                  : "bg-white border-gray-300"
              }`}
            >
              <Text
                className={`font-medium text-sm ${
                  sortMode === "newest" ? "text-white" : "text-gray-700"
                }`}
              >
                Newest
              </Text>
            </Pressable>
            <Pressable
              onPress={() => setSortMode("difficulty")}
              className={`flex-1 py-2 px-3 rounded-lg items-center border ${
                sortMode === "difficulty"
                  ? "bg-orange-500 border-orange-500"
                  : "bg-white border-gray-300"
              }`}
            >
              <Text
                className={`font-medium text-sm ${
                  sortMode === "difficulty" ? "text-white" : "text-gray-700"
                }`}
              >
                By Difficulty
              </Text>
            </Pressable>
          </View>
        </View>

        {displayTasks.length === 0 ? (
          <View className="flex-1 items-center justify-center p-4">
            <Text className="text-gray-500 text-center mb-4">
              {sortMode === "difficulty"
                ? "No ranked tasks yet. Create tasks and set their difficulty."
                : "No tasks yet. Add your first task to get started."}
            </Text>
          </View>
        ) : (
          <LegendList
            data={displayTasks}
            renderItem={renderItem}
            keyExtractor={keyExtractor}
            extraData={sortMode}
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
                existingTasks={rankedTasks.filter(t => t.id !== taskToRank.id)}
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
