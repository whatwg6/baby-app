jest.mock('expo-video', () => {
  const React = require('react') as typeof import('react');
  const { View } = require('react-native') as typeof import('react-native');

  return {
    useVideoPlayer: jest.fn(() => ({ play: jest.fn() })),
    VideoView: ({ player: _player, ...props }: Record<string, unknown>) => (
      React.createElement(View, props)
    ),
  };
});
