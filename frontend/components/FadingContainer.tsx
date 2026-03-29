import { Platform, View, StyleSheet, type ViewStyle } from "react-native";
import MaskedView from "@react-native-masked-view/masked-view";
import { LinearGradient } from "expo-linear-gradient";

interface FadingContainerProps {
  children: React.ReactNode;
  fadeWidth?: number;
  style?: ViewStyle | ViewStyle[];
}

function WebFadingContainer({
  children,
  fadeWidth = 40,
  style,
}: FadingContainerProps) {
  // Web-specific CSS properties not in React Native types
  const webStyle = {
    overflow: "hidden",
    maskImage: `linear-gradient(to right, black calc(100% - ${fadeWidth}px), transparent 100%)`,
    WebkitMaskImage: `linear-gradient(to right, black calc(100% - ${fadeWidth}px), transparent 100%)`,
  } as const;

  return (
    <View style={[style, webStyle as any]}>
      {children}
    </View>
  );
}

function NativeFadingContainer({
  children,
  fadeWidth = 40,
  style,
}: FadingContainerProps) {
  return (
    <MaskedView
      style={styles.maskedView}
      maskElement={
        <View style={styles.maskContainer}>
          <View style={styles.solidMask} />
          <LinearGradient
            colors={["black", "transparent"]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 0 }}
            style={{ width: fadeWidth }}
          />
        </View>
      }
    >
      <View style={style}>{children}</View>
    </MaskedView>
  );
}

export function FadingContainer(props: FadingContainerProps) {
  if (Platform.OS === "web") {
    return <WebFadingContainer {...props} />;
  }
  return <NativeFadingContainer {...props} />;
}

const styles = StyleSheet.create({
  maskedView: {
    flexDirection: "row",
  },
  maskContainer: {
    flex: 1,
    flexDirection: "row",
  },
  solidMask: {
    flex: 1,
    backgroundColor: "black",
  },
});
