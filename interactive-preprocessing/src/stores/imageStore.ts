import { createSignal } from 'solid-js';
import { Column } from '../types';
import { currentPage, setCurrentPage } from './sessionStore';

export const [columns, setColumns] = createSignal<Column[]>([]);
export const [isDirty, setIsDirty] = createSignal(false);

export function addColumn(col: Column) {
  const page = currentPage();
  if (!page) return;

  const newColumns = [...columns(), col];
  setColumns(newColumns);
  setCurrentPage({ ...page, columns: newColumns });
  setIsDirty(true);
}

export function removeColumn(id: string) {
  const page = currentPage();
  if (!page) return;

  const newColumns = columns().filter(c => c.id !== id);
  setColumns(newColumns);
  setCurrentPage({ ...page, columns: newColumns });
  setIsDirty(true);
}

export function updateColumn(id: string, updates: Partial<Column>) {
  const page = currentPage();
  if (!page) return;

  const newColumns = columns().map(c =>
    c.id === id ? { ...c, ...updates } : c
  );
  setColumns(newColumns);
  setCurrentPage({ ...page, columns: newColumns });
  setIsDirty(true);
}

export function clearColumns() {
  const page = currentPage();
  if (!page) return;

  setColumns([]);
  setCurrentPage({ ...page, columns: [] });
  setIsDirty(true);
}

export function reorderColumn(id: string, newOrder: number) {
  updateColumn(id, { order: newOrder });
}

// Sync columns from page when page changes
export function syncColumnsFromPage() {
  const page = currentPage();
  if (page) {
    setColumns(page.columns || []);
    setIsDirty(false);
  }
}
