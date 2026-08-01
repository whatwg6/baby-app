import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, spacing } from '../ui/theme';

type AppErrorBoundaryProps = {
  children: ReactNode;
  onRetry(): void;
  onError?(error: Error, info: ErrorInfo): void;
};

type AppErrorBoundaryState = { failed: boolean };

export class AppErrorBoundary extends Component<
  AppErrorBoundaryProps,
  AppErrorBoundaryState
> {
  state: AppErrorBoundaryState = { failed: false };

  static getDerivedStateFromError(): AppErrorBoundaryState {
    return { failed: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    this.props.onError?.(error, info);
  }

  private readonly retry = () => {
    this.props.onRetry();
    this.setState({ failed: false });
  };

  render() {
    if (this.state.failed) {
      return (
        <View style={styles.container}>
          <Text style={styles.message}>无法打开本地数据</Text>
          <Pressable accessibilityRole="button" onPress={this.retry}>
            <Text style={styles.retry}>重试</Text>
          </Pressable>
        </View>
      );
    }
    return this.props.children;
  }
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    backgroundColor: colors.background,
    flex: 1,
    gap: spacing.md,
    justifyContent: 'center',
    padding: spacing.lg,
  },
  message: { color: colors.text, fontSize: 16 },
  retry: { color: colors.accent, fontSize: 16, fontWeight: '700' },
});
