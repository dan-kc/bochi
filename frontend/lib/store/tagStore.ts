import type { Tag, TagInput } from "../tag";
import { generateRandomColor } from "../tag";
import { markTagDirty, markTagsDirty } from "../sync/syncStorage";
import { EntityStore, generateUUID } from "./createStore";

const TAGS_STORAGE_KEY = "tofustash_tags";

// ============ Tag Normalization ============

export function normalizeTag(tag: Partial<Tag>): Tag {
  return {
    id: tag.id ?? "",
    user_id: tag.user_id ?? "",
    name: tag.name ?? "",
    color_hex: tag.color_hex ?? generateRandomColor(),
    created_at: tag.created_at ?? new Date().toISOString(),
    updated_at: tag.updated_at ?? new Date().toISOString(),
    deleted_at: tag.deleted_at ?? null,
  };
}

// ============ Tag Store ============

class TagStore extends EntityStore<Tag> {
  constructor() {
    super({
      storageKey: TAGS_STORAGE_KEY,
      normalize: normalizeTag,
      markDirty: markTagDirty,
      markManyDirty: markTagsDirty,
      enableVisibilityReload: true,
      enableAppStateReload: true,
    });
  }

  // ============ Tag-specific Selectors ============

  getAllTags(userId: string): Tag[] {
    return this.getAll(userId);
  }

  getTagById(id: string): Tag | undefined {
    return this.getById(id);
  }

  getTagCount(userId: string): number {
    return this.state.allIds.filter(
      (id) => this.state.byId[id].user_id === userId && !this.state.byId[id].deleted_at,
    ).length;
  }

  // Get all tags including deleted (for UI with restore option)
  getAllTagsIncludingDeleted(userId: string): Tag[] {
    return this.state.allIds
      .map((id) => this.state.byId[id])
      .filter((t) => t.user_id === userId)
      .sort((a, b) => {
        // Sort deleted tags to the end
        if (a.deleted_at && !b.deleted_at) return 1;
        if (!a.deleted_at && b.deleted_at) return -1;
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      });
  }

  // ============ Tag Mutations ============

  async createTag(userId: string, input: TagInput): Promise<Tag> {
    const now = new Date().toISOString();
    const tag: Tag = {
      id: generateUUID(),
      user_id: userId,
      name: input.name,
      color_hex: input.color_hex,
      created_at: now,
      updated_at: now,
      deleted_at: input.deleted_at ?? null,
    };

    await this.addItem(tag);
    return tag;
  }

  async updateTag(id: string, input: Partial<TagInput>): Promise<Tag | null> {
    const existing = this.state.byId[id];
    if (!existing) return null;

    const updates: Partial<Tag> = {};
    if (input.name !== undefined) updates.name = input.name;
    if (input.color_hex !== undefined) updates.color_hex = input.color_hex;
    if (input.deleted_at !== undefined) updates.deleted_at = input.deleted_at;

    return this.updateItem(id, updates);
  }

  async deleteTag(id: string): Promise<boolean> {
    const result = await this.updateItem(id, { deleted_at: new Date().toISOString() });
    return result !== null;
  }

  async restoreTag(id: string): Promise<boolean> {
    const result = await this.updateItem(id, { deleted_at: null });
    return result !== null;
  }

  // ============ Sync Helpers ============

  async mergeTags(serverTags: Partial<Tag>[], userId?: string): Promise<void> {
    return this.merge(serverTags, userId);
  }

  getDirtyTags(dirtyIds: Set<string>): Tag[] {
    return this.getDirty(dirtyIds);
  }

  async purgeDeletedTags(): Promise<void> {
    return this.purgeDeleted();
  }

  async clearAllTags(): Promise<void> {
    return this.clearAll();
  }
}

export const tagStore = new TagStore();
