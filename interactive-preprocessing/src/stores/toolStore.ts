import { createSignal } from 'solid-js';
import { Tool, ToolState } from '../types';

const initialState: ToolState = {
  activeTool: 'brush',
  brushSize: 30,
  brushColor: '#ffffff',
  autoDetectColor: true,
};

export const [toolState, setToolState] = createSignal<ToolState>(initialState);

export function setActiveTool(tool: Tool) {
  setToolState({ ...toolState(), activeTool: tool });
}

export function setBrushSize(size: number) {
  setToolState({ ...toolState(), brushSize: size });
}

export function setBrushColor(color: string) {
  setToolState({ ...toolState(), brushColor: color, autoDetectColor: false });
}

export function enableAutoDetectColor() {
  setToolState({ ...toolState(), autoDetectColor: true });
}
