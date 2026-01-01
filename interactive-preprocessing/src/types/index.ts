export interface Column {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  order: number;
}

export interface Page {
  chapter: string;
  pageNum: number;
  imagePath: string;
  imageData?: string; // base64
  columns: Column[];
  maskData?: ImageData;
  processed: boolean;
}

export interface Session {
  chapters: ChapterInfo[];
  currentPage: number;
  status: 'active' | 'paused' | 'completed';
  totalPages: number;
  processedPages: string[]; // Array of "chapter:pageNum" strings
}

export interface ChapterInfo {
  name: string;
  pages: string[];
}

export type Tool = 'select' | 'brush' | 'eyedropper';

export interface ToolState {
  activeTool: Tool;
  brushSize: number;
  brushColor: string;
  autoDetectColor: boolean;
}

export interface ProgressUpdate {
  total: number;
  processed: number;
  percentage: number;
}
