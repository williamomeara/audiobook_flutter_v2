import React from 'react';
import { ArrowLeft, MoreVertical } from 'lucide-react';
import type { Book } from '../App';

interface ReaderProps {
  book: Book;
  onBack: () => void;
}

export function Reader({ book, onBack }: ReaderProps) {
  return (
    <div className="min-h-screen bg-[#0f1419] text-white">
      {/* Header */}
      <div className="px-5 pt-14 pb-4 flex items-center justify-between">
        <button 
          onClick={onBack}
          className="w-10 h-10 rounded-full bg-[#1a2332] flex items-center justify-center"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1 mx-4 truncate text-center">
          <div className="text-sm truncate">{book.title}</div>
          <div className="text-xs text-gray-400">Letter 2</div>
        </div>
        <button className="w-10 h-10 rounded-full bg-[#1a2332] flex items-center justify-center">
          <MoreVertical className="w-5 h-5" />
        </button>
      </div>

      {/* Content */}
      <div className="px-6 py-8 leading-relaxed text-gray-300">
        <p className="mb-4">
          This view represents the reading experience. In your actual implementation, 
          this would display the full text content with reading controls.
        </p>
      </div>
    </div>
  );
}
