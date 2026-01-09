import React from 'react';
import { Play, Pause, SkipBack, SkipForward, X } from 'lucide-react';
import type { Book } from '../App';

interface NotificationPlayerProps {
  book: Book;
  isPlaying: boolean;
  onPlayPause: () => void;
  onPrevious: () => void;
  onNext: () => void;
  onClose: () => void;
  currentTime: number;
  duration: number;
  isExpanded?: boolean;
}

export function NotificationPlayer({
  book,
  isPlaying,
  onPlayPause,
  onPrevious,
  onNext,
  onClose,
  currentTime,
  duration,
  isExpanded = false
}: NotificationPlayerProps) {
  const progress = (currentTime / duration) * 100;

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (isExpanded) {
    return (
      <div className="bg-[#1a1a2e] text-white rounded-2xl shadow-2xl overflow-hidden mx-4 my-2">
        {/* Header */}
        <div className="px-4 pt-4 pb-2 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-[#6366f1] rounded flex items-center justify-center text-xs">
              📚
            </div>
            <span className="text-sm text-gray-400">Audiobook Player</span>
          </div>
          <button
            onClick={onClose}
            className="w-6 h-6 rounded-full bg-[#2a2a3e] flex items-center justify-center hover:bg-[#3a3a4e]"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Content */}
        <div className="px-4 pb-4">
          <div className="flex gap-4 items-center mb-3">
            <img
              src={book.cover}
              alt={book.title}
              className="w-16 h-16 object-cover rounded-lg flex-shrink-0"
            />
            <div className="flex-1 min-w-0">
              <h3 className="text-sm font-medium line-clamp-1">{book.title}</h3>
              <p className="text-xs text-gray-400 line-clamp-1">{book.author}</p>
              <p className="text-xs text-gray-500 mt-1">Chapter {book.currentChapter}</p>
            </div>
          </div>

          {/* Progress Bar */}
          <div className="mb-2">
            <div className="h-1 bg-gray-700 rounded-full overflow-hidden">
              <div 
                className="h-full bg-[#6366f1] transition-all"
                style={{ width: `${progress}%` }}
              />
            </div>
          </div>

          {/* Time Labels */}
          <div className="flex justify-between text-xs text-gray-500 mb-3">
            <span>{formatTime(currentTime)}</span>
            <span>{formatTime(duration)}</span>
          </div>

          {/* Controls */}
          <div className="flex items-center justify-center gap-6">
            <button
              onClick={onPrevious}
              className="w-10 h-10 rounded-full bg-[#2a2a3e] flex items-center justify-center hover:bg-[#3a3a4e] transition-colors"
            >
              <SkipBack className="w-5 h-5" fill="white" />
            </button>

            <button
              onClick={onPlayPause}
              className="w-10 h-10 rounded-full bg-[#6366f1] flex items-center justify-center hover:bg-[#818cf8] transition-colors"
            >
              {isPlaying ? (
                <Pause className="w-5 h-5 text-white" fill="white" />
              ) : (
                <Play className="w-5 h-5 text-white ml-0.5" fill="white" />
              )}
            </button>

            <button
              onClick={onNext}
              className="w-10 h-10 rounded-full bg-[#2a2a3e] flex items-center justify-center hover:bg-[#3a3a4e] transition-colors"
            >
              <SkipForward className="w-5 h-5" fill="white" />
            </button>
          </div>

          {/* Additional Controls */}
          <div className="flex justify-center gap-4 mt-3">
            <button className="text-xs text-gray-400 hover:text-white px-3 py-1.5 rounded-lg bg-[#2a2a3e] hover:bg-[#3a3a4e] transition-colors">
              1.0x Speed
            </button>
            <button className="text-xs text-gray-400 hover:text-white px-3 py-1.5 rounded-lg bg-[#2a2a3e] hover:bg-[#3a3a4e] transition-colors">
              Sleep Timer
            </button>
          </div>
        </div>
      </div>
    );
  }

  // Collapsed notification
  return (
    <div className="bg-[#1a1a2e] text-white rounded-2xl shadow-lg overflow-hidden mx-4 my-2">
      <div className="px-4 py-3 flex items-center gap-3">
        <img
          src={book.cover}
          alt={book.title}
          className="w-12 h-12 object-cover rounded-lg flex-shrink-0"
        />
        
        <div className="flex-1 min-w-0">
          <h3 className="text-sm line-clamp-1">{book.title}</h3>
          <p className="text-xs text-gray-400 line-clamp-1">{book.author}</p>
        </div>

        <div className="flex items-center gap-2 flex-shrink-0">
          <button
            onClick={onPrevious}
            className="w-8 h-8 rounded-full bg-[#2a2a3e] flex items-center justify-center hover:bg-[#3a3a4e] transition-colors"
          >
            <SkipBack className="w-4 h-4" fill="white" />
          </button>

          <button
            onClick={onPlayPause}
            className="w-10 h-10 rounded-full bg-[#f59e0b] flex items-center justify-center hover:bg-[#fbbf24] transition-colors"
          >
            {isPlaying ? (
              <Pause className="w-5 h-5 text-black" fill="black" />
            ) : (
              <Play className="w-5 h-5 text-black ml-0.5" fill="black" />
            )}
          </button>

          <button
            onClick={onNext}
            className="w-8 h-8 rounded-full bg-[#2a2a3e] flex items-center justify-center hover:bg-[#3a3a4e] transition-colors"
          >
            <SkipForward className="w-4 h-4" fill="white" />
          </button>
        </div>
      </div>

      {/* Progress indicator */}
      <div className="h-0.5 bg-gray-700">
        <div 
          className="h-full bg-[#6366f1] transition-all"
          style={{ width: `${progress}%` }}
        />
      </div>
    </div>
  );
}