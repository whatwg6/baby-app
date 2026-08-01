import { render, waitFor } from '@testing-library/react-native';

import Index from '../../../../app/index';
import type { BabyRepository } from '../../../data/repositories';
import { BabyRepositoryProvider } from '../useBaby';

const mockReplace = jest.fn();

jest.mock('expo-router', () => ({
  useRouter: () => ({ replace: mockReplace }),
}));

test('keeps the user on an error screen when loading the profile fails', async () => {
  const repository: BabyRepository = {
    get: jest.fn().mockRejectedValue(new Error('database is unavailable')),
    save: jest.fn(),
    clear: jest.fn(),
  };

  const view = await render(
    <BabyRepositoryProvider repository={repository}>
      <Index />
    </BabyRepositoryProvider>,
  );

  await waitFor(() => expect(view.getByText('暂时无法读取宝宝资料')).toBeTruthy());
  expect(mockReplace).not.toHaveBeenCalled();
});
