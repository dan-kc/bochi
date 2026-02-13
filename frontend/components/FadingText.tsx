import { Platform, Text, View, StyleSheet } from "react-native";
import MaskedView from "@react-native-masked-view/masked-view";
import { LinearGradient } from "expo-linear-gradient";

interface FadingTextProps {
  children: string;
  numberOfLines: number;
  className?: string;
  fadeWidth?: number;
}

function WebFadingText({
  children,
  numberOfLines,
  className,
  fadeWidth = 40,
}: FadingTextProps) {
  // Web-specific CSS properties not in React Native types
  const lineClampStyle = {
    display: "-webkit-box",
    WebkitLineClamp: numberOfLines,
    WebkitBoxOrient: "vertical",
    overflow: "hidden",
    maskImage: `linear-gradient(to right, black calc(100% - ${fadeWidth}px), transparent 100%)`,
    WebkitMaskImage: `linear-gradient(to right, black calc(100% - ${fadeWidth}px), transparent 100%)`,
  } as const;

  return (
    <Text className={className} style={lineClampStyle as any}>
      {children}
    </Text>
  );
}

function NativeFadingText({
  children,
  numberOfLines,
  className,
  fadeWidth = 40,
}: FadingTextProps) {
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
      <Text className={className} numberOfLines={numberOfLines} ellipsizeMode="clip">
        {children}
      </Text>
    </MaskedView>
  );
}

export function FadingText(props: FadingTextProps) {
  if (Platform.OS === "web") {
    return <WebFadingText {...props} />;
  }
  return <NativeFadingText {...props} />;
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
