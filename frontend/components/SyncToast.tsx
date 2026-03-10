import { useRef, useEffect, useCallback, useState } from "react";
import {
  View,
  Text,
  Pressable,
  Animated,
  PanResponder,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useSyncOptional } from "@/lib/sync";

type ToastType = "failure" | "recovery";

export function SyncToast() {
  const sync = useSyncOptional();
  const [toast, setToast] = useState<ToastType | null>(null);
  const translateY = useRef(new Animated.Value(100)).current;

  const hasShownFailure = useRef(false);
  const wasInError = useRef(false);

  const dismiss = useCallback(() => {
    Animated.timing(translateY, {
      toValue: 100,
      duration: 200,
      useNativeDriver: true,
    }).start(() => setToast(null));
  }, [translateY]);

  const show = useCallback(
    (type: ToastType) => {
      setToast(type);
      translateY.setValue(100);
      Animated.spring(translateY, {
        toValue: 0,
        useNativeDriver: true,
        damping: 20,
        stiffness: 200,
      }).start();
    },
    [translateY],
  );

  const panResponder = useRef(
    PanResponder.create({
      onMoveShouldSetPanResponder: (_, gestureState) =>
        Math.abs(gestureState.dy) > 10,
      onPanResponderMove: (_, gestureState) => {
        if (gestureState.dy > 0) {
          translateY.setValue(gestureState.dy);
        }
      },
      onPanResponderRelease: (_, gestureState) => {
        if (gestureState.dy > 40) {
          dismiss();
        } else {
          Animated.spring(translateY, {
            toValue: 0,
            useNativeDriver: true,
            damping: 20,
            stiffness: 200,
          }).start();
        }
      },
    }),
  ).current;

  useEffect(() => {
    if (!sync) return;

    const { syncStatus } = sync;

    if (syncStatus === "error") {
      wasInError.current = true;
      if (!hasShownFailure.current) {
        hasShownFailure.current = true;
        show("failure");
      }
    } else if (syncStatus === "synced") {
      hasShownFailure.current = false;
      if (wasInError.current) {
        wasInError.current = false;
        show("recovery");
      }
    }
  }, [sync?.syncStatus, show]);

  if (!toast) return null;

  const isFailure = toast === "failure";

  return (
    <Animated.View
      {...panResponder.panHandlers}
      style={{
        position: "absolute",
        bottom: 90,
        left: 16,
        right: 16,
        transform: [{ translateY }],
      }}
    >
      <View
        className="flex-row items-center rounded-xl px-4 py-3"
        style={{ backgroundColor: isFailure ? "#f54900" : "#197291" }}
      >
        <Ionicons
          name={isFailure ? "cloud-offline" : "cloud-done"}
          size={20}
          color="#fff"
        />
        <Text className="flex-1 ml-3 text-sm font-medium" style={{ color: "#fff" }}>
          {isFailure ? "Sync failed \u2014 offline" : "Back online"}
        </Text>
        <Pressable onPress={dismiss} hitSlop={8}>
          <Ionicons name="close" size={20} color="#fff" />
        </Pressable>
      </View>
    </Animated.View>
  );
}
