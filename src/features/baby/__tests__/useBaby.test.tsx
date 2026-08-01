import { render, waitFor } from '@testing-library/react-native';
import { useEffect } from 'react';
import { Text } from 'react-native';

import type { BabyInput } from '../../../domain/types';
import { MemoryBabyRepository } from '../../../test/memoryRepositories';
import { BabyRepositoryProvider, useBaby } from '../useBaby';

const input: BabyInput = {
  name: '安安',
  birthDate: '2025-06-15',
  sex: 'female',
  avatarPath: null,
};

test('loads and saves the baby profile through the supplied repository', async () => {
  const repository = new MemoryBabyRepository();

  function ProfileProbe() {
    const { baby, loading, save } = useBaby();

    useEffect(() => {
      if (!loading && baby === null) {
        void save(input);
      }
    }, [baby, loading, save]);

    return <Text>{loading ? '加载中' : baby?.name ?? '暂无资料'}</Text>;
  }

  const view = await render(
    <BabyRepositoryProvider repository={repository}>
      <ProfileProbe />
    </BabyRepositoryProvider>,
  );

  await waitFor(() => expect(view.getByText('安安')).toBeTruthy());
  await expect(repository.get()).resolves.toMatchObject({ name: '安安' });
});
