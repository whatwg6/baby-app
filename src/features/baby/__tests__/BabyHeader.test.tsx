import { render } from '@testing-library/react-native';

import type { Baby } from '../../../domain/types';
import BabyHeader from '../BabyHeader';

const baby: Baby = {
  id: 'baby-1',
  name: '安安',
  birthDate: '2025-06-15',
  sex: 'female',
  avatarPath: null,
  createdAt: '2025-06-15T00:00:00.000Z',
  updatedAt: '2025-06-15T00:00:00.000Z',
};

test('shows the baby name and age calculated from the supplied current date', async () => {
  const view = await render(
    <BabyHeader baby={baby} now={new Date(2026, 7, 1, 12)} />,
  );

  expect(view.getByText('安安')).toBeTruthy();
  expect(view.getByText('1岁1个月')).toBeTruthy();
});
