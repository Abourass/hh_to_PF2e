import { createSignal } from 'solid-js';
import { Session, Page } from '../types';
import { fetchSession, fetchPage, savePage } from '../services/api';

export const [session, setSession] = createSignal<Session | null>(null);
export const [currentPage, setCurrentPage] = createSignal<Page | null>(null);
export const [pageIndex, setPageIndex] = createSignal(0);
export const [isSaving, setIsSaving] = createSignal(false);

// Load session on mount
export async function initSession() {
  try {
    const data = await fetchSession();
    setSession(data);

    // Load first unprocessed page or first page
    const firstUnprocessed = findFirstUnprocessedPage(data);
    if (firstUnprocessed !== -1) {
      await loadPage(firstUnprocessed);
    } else if (data.totalPages > 0) {
      await loadPage(0);
    }
  } catch (error) {
    console.error('Failed to load session:', error);
  }
}

function findFirstUnprocessedPage(session: Session): number {
  let index = 0;
  for (const chapter of session.chapters) {
    for (let i = 0; i < chapter.pages.length; i++) {
      const pagePath = chapter.pages[i];
      const match = pagePath.match(/page-(\d+)\.png$/);
      if (match) {
        const pageNum = parseInt(match[1], 10);
        const pageId = `${chapter.name}:${pageNum}`;
        if (!session.processedPages?.includes(pageId)) {
          return index;
        }
      }
      index++;
    }
  }
  return -1; // All processed
}

export async function loadPage(index: number) {
  const s = session();
  if (!s) return;

  // Calculate which chapter/page based on index
  let currentIndex = 0;
  for (const chapter of s.chapters) {
    if (currentIndex + chapter.pages.length > index) {
      const pageIndexInChapter = index - currentIndex;
      const pagePath = chapter.pages[pageIndexInChapter];

      // Extract the actual page number from the path
      // e.g., "converted_harbinger_house/intro/.temp/page-1.png" -> "1"
      // or "converted_harbinger_house/chapter2/.temp/page-01.png" -> "1"
      const match = pagePath.match(/page-(\d+)\.png$/);
      if (!match) {
        console.error('Could not extract page number from:', pagePath);
        return;
      }

      const pageNum = parseInt(match[1], 10);
      const pageData = await fetchPage(chapter.name, pageNum);
      setCurrentPage(pageData);
      setPageIndex(index);
      return;
    }
    currentIndex += chapter.pages.length;
  }
}

export async function nextPage() {
  const s = session();
  if (!s || pageIndex() >= s.totalPages - 1) return;

  await saveCurrentPage();
  await loadPage(pageIndex() + 1);
}

export async function prevPage() {
  if (pageIndex() <= 0) return;

  await saveCurrentPage();
  await loadPage(pageIndex() - 1);
}

export async function saveCurrentPage() {
  const page = currentPage();
  if (!page || isSaving()) return;

  setIsSaving(true);
  try {
    // Get mask data from canvas if available
    const maskData = getMaskData();
    await savePage(page.chapter, page.pageNum, page.columns, maskData);
  } catch (error) {
    console.error('Failed to save page:', error);
  } finally {
    setIsSaving(false);
  }
}

// Helper to get mask data - will be set by ImageCanvas
let maskDataGetter: (() => string | undefined) | null = null;

export function setMaskDataGetter(getter: () => string | undefined) {
  maskDataGetter = getter;
}

function getMaskData(): string | undefined {
  return maskDataGetter?.();
}

export function canGoNext() {
  const s = session();
  return s ? pageIndex() < s.totalPages - 1 : false;
}

export function canGoPrev() {
  return pageIndex() > 0;
}
