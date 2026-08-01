import { Tabs } from 'expo-router';

import { colors } from '../../src/ui/theme';

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerStyle: { backgroundColor: colors.background },
        headerTintColor: colors.text,
        tabBarActiveTintColor: colors.accent,
        tabBarInactiveTintColor: colors.muted,
      }}
    >
      <Tabs.Screen name="timeline" options={{ title: '时间轴' }} />
      <Tabs.Screen name="add" options={{ title: '记录' }} />
      <Tabs.Screen name="baby" options={{ title: '宝宝' }} />
    </Tabs>
  );
}
