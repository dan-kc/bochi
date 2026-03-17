import { type ReactNode, useCallback } from "react";
import { StyleSheet, View } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withSequence,
  withTiming,
  runOnJS,
} from "react-native-reanimated";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";

const THRESHOLD = -80;
const SPRING_CONFIG = { damping: 20, stiffness: 200 };

interface SwipeableRowProps {
  children: ReactNode;
  onAction: () => void;
  actionColor: string;
  actionIcon: keyof typeof Ionicons.glyphMap;
}

export function SwipeableRow({
  children,
  onAction,
  actionColor,
  actionIcon,
}: SwipeableRowProps) {
  const translateX = useSharedValue(0);
  const flashOpacity = useSharedValue(0);
  const passedThreshold = useSharedValue(false);

  const triggerHaptic = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  }, []);

  const triggerAction = useCallback(() => {
    onAction();
  }, [onAction]);

  const pan = Gesture.Pan()
    .activeOffsetX([-15, 15])
    .failOffsetY([-10, 10])
    .onUpdate((e) => {
      // Only allow swipe left (negative)
      const x = Math.min(0, e.translationX);
      translateX.value = x;

      if (x <= THRESHOLD && !passedThreshold.value) {
        passedThreshold.value = true;
        runOnJS(triggerHaptic)();
      } else if (x > THRESHOLD && passedThreshold.value) {
        passedThreshold.value = false;
      }
    })
    .onEnd(() => {
      if (translateX.value <= THRESHOLD) {
        // Flash and snap back
        flashOpacity.value = withSequence(
          withTiming(0.3, { duration: 100 }),
          withTiming(0, { duration: 200 }),
        );
        runOnJS(triggerAction)();
      }
      translateX.value = withSpring(0, SPRING_CONFIG);
      passedThreshold.value = false;
    });

  const rowStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }],
  }));

  const flashStyle = useAnimatedStyle(() => ({
    opacity: flashOpacity.value,
  }));

  const iconOpacity = useAnimatedStyle(() => {
    const progress = Math.min(1, Math.abs(translateX.value) / Math.abs(THRESHOLD));
    return { opacity: progress };
  });

  return (
    <View style={styles.container}>
      {/* Revealed action panel behind the row */}
      <View style={[styles.actionPanel, { backgroundColor: actionColor }]}>
        <Animated.View style={[styles.iconContainer, iconOpacity]}>
          <Ionicons name={actionIcon} size={28} color="white" />
        </Animated.View>
      </View>

      {/* Sliding row */}
      <GestureDetector gesture={pan}>
        <Animated.View style={rowStyle}>
          {children}
          {/* Flash overlay */}
          <Animated.View
            style={[styles.flash, { backgroundColor: actionColor }, flashStyle]}
            pointerEvents="none"
          />
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: "relative",
    overflow: "hidden",
  },
  actionPanel: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: "center",
    alignItems: "flex-end",
    paddingRight: 24,
  },
  iconContainer: {
    justifyContent: "center",
    alignItems: "center",
  },
  flash: {
    ...StyleSheet.absoluteFillObject,
    borderRadius: 0,
  },
});
