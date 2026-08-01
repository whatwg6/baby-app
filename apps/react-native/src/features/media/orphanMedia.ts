import type { MediaReferenceRepository } from '../../data/repositories';
import type { MediaService } from './mediaStorage';

export async function removeUnreferencedMedia(dependencies: {
  mediaReferences: MediaReferenceRepository;
  media: MediaService;
}): Promise<void> {
  const referencedPaths = await dependencies.mediaReferences.listReferencedMediaPaths();
  await dependencies.media.removeOrphans(referencedPaths);
}
