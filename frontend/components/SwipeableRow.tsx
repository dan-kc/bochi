import { type ReactNode, useCallback, useRef } from "react";
import {
  StyleSheet,
  View,
  Animated,
  PanResponder,
  type GestureResponderEvent,
  type PanResponderGestureState,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";

const THRESHOLD = -80;

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
  const translateX = useRef(new Animated.Value(0)).current;
  const flashOpacity = useRef(new Animated.Value(0)).current;
  const passedThreshold = useRef(false);

  const triggerHaptic = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  }, []);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => false,
      onMoveShouldSetPanResponder: (
        _evt: GestureResponderEvent,
        gestureState: PanResponderGestureState
      ) => {
        // Only respond to horizontal swipes
        return (
          Math.abs(gestureState.dx) > 15 &&
          Math.abs(gestureState.dy) < 10
        );
      },
      onPanResponderMove: (
        _evt: GestureResponderEvent,
        gestureState: PanResponderGestureState
      ) => {
        // Only allow swipe left (negative)
        const x = Math.min(0, gestureState.dx);
        translateX.setValue(x);

        if (x <= THRESHOLD && !passedThreshold.current) {
          passedThreshold.current = true;
          triggerHaptic();
        } else if (x > THRESHOLD && passedThreshold.current) {
          passedThreshold.current = false;
        }
      },
      onPanResponderRelease: (
        _evt: GestureResponderEvent,
        gestureState: PanResponderGestureState
      ) => {
        const x = Math.min(0, gestureState.dx);

        if (x <= THRESHOLD) {
          // Flash and trigger action
          Animated.sequence([
            Animated.timing(flashOpacity, {
              toValue: 0.3,
              duration: 100,
              useNativeDriver: true,
            }),
            Animated.timing(flashOpacity, {
              toValue: 0,
              duration: 200,
              useNativeDriver: true,
            }),
          ]).start();
          onAction();
        }

        // Spring back to original position
        Animated.spring(translateX, {
          toValue: 0,
          damping: 20,
          stiffness: 200,
          useNativeDriver: true,
        }).start();

        passedThreshold.current = false;
      },
      onPanResponderTerminate: () => {
        // Reset on termination
        Animated.spring(translateX, {
          toValue: 0,
          damping: 20,
          stiffness: 200,
          useNativeDriver: true,
        }).start();
        passedThreshold.current = false;
      },
    })
  ).current;

  const iconOpacity = translateX.interpolate({
    inputRange: [THRESHOLD, 0],
    outputRange: [1, 0],
    extrapolate: "clamp",
  });

  return (
    <View style={styles.container}>
      {/* Revealed action panel behind the row */}
      <View style={[styles.actionPanel, { backgroundColor: actionColor }]}>
        <Animated.View style={[styles.iconContainer, { opacity: iconOpacity }]}>
          <Ionicons name={actionIcon} size={28} color="white" />
        </Animated.View>
      </View>

      {/* Sliding row */}
      <Animated.View
        style={{ transform: [{ translateX }] }}
        {...panResponder.panHandlers}
      >
        {children}
        {/* Flash overlay */}
        <Animated.View
          style={[
            styles.flash,
            { backgroundColor: actionColor, opacity: flashOpacity },
          ]}
          pointerEvents="none"
        />
      </Animated.View>
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
