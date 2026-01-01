import { Session, Page } from '../types';

const API_BASE = 'http://localhost:3001/api';

export async function fetchSession(): Promise<Session> {
  const response = await fetch(`${API_BASE}/session`);
  if (!response.ok) {
    throw new Error('Failed to fetch session');
  }
  return response.json();
}

export async function fetchPage(chapter: string, pageNum: number): Promise<Page> {
  const response = await fetch(`${API_BASE}/page/${chapter}/${pageNum}`);
  if (!response.ok) {
    throw new Error(`Failed to fetch page ${chapter}/${pageNum}`);
  }
  return response.json();
}

export async function savePage(
  chapter: string,
  pageNum: number,
  columns: any[],
  maskData?: string
): Promise<void> {
  const response = await fetch(`${API_BASE}/save`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      chapter,
      pageNum,
      columns,
      maskData,
    }),
  });

  if (!response.ok) {
    throw new Error('Failed to save page');
  }
}

export async function finishSession(): Promise<void> {
  const response = await fetch(`${API_BASE}/finish`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error('Failed to finish session');
  }
}
