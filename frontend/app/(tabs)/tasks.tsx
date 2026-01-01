import { useState, useCallback } from "react";
import { View, Text, Pressable, Modal } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { LegendList } from "@legendapp/list";
import { useTasks } from "@/lib/TaskContext";
import { TaskItem } from "@/components/TaskItem";
import { TaskForm } from "@/components/TaskForm";
import { SyncStatusIcon } from "@/components/SyncStatusIcon";
import type { Task, TaskInput } from "@/lib/task";

export default function Tasks() {
  const {
    tasks,
    selectedTask,
    createTask,
    updateTask,
    deleteTask,
    selectTask,
    setIsEditing,
  } = useTasks();

  const [isModalVisible, setIsModalVisible] = useState(false);

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
      } else {
        await createTask(input);
      }
      setIsModalVisible(false);
      selectTask(null);
    },
    [selectedTask, updateTask, createTask, selectTask],
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

  const renderItem = useCallback(
    ({ item }: { item: Task }) => (
      <TaskItem task={item} onPress={handleTaskPress} />
    ),
    [handleTaskPress],
  );

  const keyExtractor = useCallback((item: Task) => item.id, []);

  return (
    <SafeAreaView className="flex-1 bg-white" edges={["top"]}>
      <View className="flex-1">
        <View className="p-4 border-b border-gray-200 flex-row justify-between items-center">
          <Text className="text-2xl font-bold text-gray-900">Tasks</Text>
          <SyncStatusIcon />
        </View>

        {tasks.length === 0 ? (
          <View className="flex-1 items-center justify-center p-4">
            <Text className="text-gray-500 text-center mb-4">
              No tasks yet. Add your first task to get started.
            </Text>
          </View>
        ) : (
          <LegendList
            data={tasks}
            renderItem={renderItem}
            keyExtractor={keyExtractor}
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
            />
          </SafeAreaView>
        </Modal>
      </View>
    </SafeAreaView>
  );
}
