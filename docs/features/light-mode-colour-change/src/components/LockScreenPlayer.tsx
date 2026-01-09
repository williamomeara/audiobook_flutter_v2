import React, { useState } from 'react';
import { Play, Pause, SkipBack, SkipForward, ChevronDown } from 'lucide-react';
import type { Book } from '../App';

interface LockScreenPlayerProps {
  book: Book;
  isPlaying: boolean;
  onPlayPause: () => void;
  onPrevious: () => void;
  onNext: () => void;
  onDismiss: () => void;
  currentTime: number;
  duration: number;
}

export function LockScreenPlayer({
  book,
  isPlaying,
  onPlayPause,
  onPrevious,
  onNext,
  onDismiss,
  currentTime,
  duration
}: LockScreenPlayerProps) {
  const progress = (currentTime / duration) * 100;

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  return (
    <div className="fixed inset-0 bg-gradient-to-b from-[#1a1a2e] to-[#0f0f1e] flex flex-col items-center justify-center text-white p-8">
      {/* Time at top */}
      <div className="absolute top-8 left-0 right-0 text-center">
        <div className="text-6xl font-light tracking-wide">12:34</div>
        <div className="text-sm text-gray-400 mt-1">Thursday, January 8</div>
      </div>

      {/* Player Card */}
      <div className="w-full max-w-md mt-32">
        {/* Drag Handle */}
        <div className="flex justify-center mb-4">
          <ChevronDown className="w-6 h-6 text-gray-500" />
        </div>

        {/* Book Cover */}
        <div className="mb-8 flex justify-center">
          <div className="relative">
            <img
              src={book.cover}
              alt={book.title}
              className="w-64 h-64 object-cover rounded-3xl shadow-2xl"
            />
            <div className="absolute inset-0 bg-gradient-to-t from-black/30 to-transparent rounded-3xl" />
          </div>
        </div>

        {/* Book Info */}
        <div className="text-center mb-6">
          <h2 className="text-xl mb-2 line-clamp-2">{book.title}</h2>
          <p className="text-gray-400">{book.author}</p>
          <p className="text-sm text-gray-500 mt-1">Chapter {book.currentChapter}</p>
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
        <div className="flex justify-between text-xs text-gray-400 mb-8">
          <span>{formatTime(currentTime)}</span>
          <span>{formatTime(duration)}</span>
        </div>

        {/* Playback Controls */}
        <div className="flex items-center justify-center gap-8 mb-8">
          <button
            onClick={onPrevious}
            className="w-16 h-16 rounded-full bg-[#2a2a3e] flex items-center justify-center hover:bg-[#3a3a4e] transition-colors active:scale-95"
          >
            <SkipBack className="w-6 h-6" fill="white" />
          </button>

          <button
            onClick={onPlayPause}
            className="w-20 h-20 rounded-full bg-[#6366f1] flex items-center justify-center hover:bg-[#818cf8] transition-colors active:scale-95 shadow-lg shadow-[#6366f1]/30"
          >
            {isPlaying ? (
              <Pause className="w-8 h-8 text-white" fill="white" />
            ) : (
              <Play className="w-8 h-8 text-white ml-1" fill="white" />
            )}
          </button>

          <button
            onClick={onNext}
            className="w-16 h-16 rounded-full bg-[#2a2a3e] flex items-center justify-center hover:bg-[#3a3a4e] transition-colors active:scale-95"
          >
            <SkipForward className="w-6 h-6" fill="white" />
          </button>
        </div>

        {/* Additional Controls */}
        <div className="flex justify-between items-center px-8">
          <button className="text-sm text-gray-400 hover:text-white transition-colors">
            1.0x
          </button>
          <button className="text-sm text-gray-400 hover:text-white transition-colors">
            -30s
          </button>
          <button className="text-sm text-gray-400 hover:text-white transition-colors">
            +30s
          </button>
          <button className="text-sm text-gray-400 hover:text-white transition-colors">
            Sleep
          </button>
        </div>
      </div>

      {/* Bottom indicator */}
      <div className="absolute bottom-8 w-32 h-1 bg-white/30 rounded-full" />
    </div>
  );
}