import React, { useState, useEffect } from 'react';
import { LockScreenPlayer } from './LockScreenPlayer';
import { NotificationPlayer } from './NotificationPlayer';
import type { Book } from '../App';

interface PlayerDemoProps {
  book: Book;
  onBack: () => void;
}

export function PlayerDemo({ book, onBack }: PlayerDemoProps) {
  const [view, setView] = useState<'notification-collapsed' | 'notification-expanded' | 'lockscreen'>('notification-collapsed');
  const [isPlaying, setIsPlaying] = useState(true);
  const [currentTime, setCurrentTime] = useState(145); // 2:25
  const duration = 1847; // 30:47

  // Simulate playback
  useEffect(() => {
    if (!isPlaying) return;

    const interval = setInterval(() => {
      setCurrentTime(prev => {
        if (prev >= duration) return 0;
        return prev + 1;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [isPlaying, duration]);

  const handlePlayPause = () => setIsPlaying(!isPlaying);
  const handlePrevious = () => setCurrentTime(Math.max(0, currentTime - 30));
  const handleNext = () => setCurrentTime(Math.min(duration, currentTime + 30));

  return (
    <div className="min-h-screen bg-[#0f1419] text-white">
      {/* Demo Controls */}
      <div className="fixed top-0 left-0 right-0 bg-[#1a2332] p-4 z-50 border-b border-gray-700">
        <div className="flex items-center justify-between mb-3">
          <button
            onClick={onBack}
            className="px-4 py-2 bg-[#6366f1] rounded-lg text-white text-sm"
          >
            ← Back to Book
          </button>
          <span className="text-sm text-gray-400">Player UI Demo</span>
        </div>
        
        <div className="flex gap-2">
          <button
            onClick={() => setView('notification-collapsed')}
            className={`flex-1 px-3 py-2 rounded-lg text-sm ${
              view === 'notification-collapsed' 
                ? 'bg-[#6366f1] text-white' 
                : 'bg-[#0f1419] text-gray-400'
            }`}
          >
            Notification (Collapsed)
          </button>
          <button
            onClick={() => setView('notification-expanded')}
            className={`flex-1 px-3 py-2 rounded-lg text-sm ${
              view === 'notification-expanded' 
                ? 'bg-[#6366f1] text-white' 
                : 'bg-[#0f1419] text-gray-400'
            }`}
          >
            Notification (Expanded)
          </button>
          <button
            onClick={() => setView('lockscreen')}
            className={`flex-1 px-3 py-2 rounded-lg text-sm ${
              view === 'lockscreen' 
                ? 'bg-[#6366f1] text-white' 
                : 'bg-[#0f1419] text-gray-400'
            }`}
          >
            Lock Screen
          </button>
        </div>
      </div>

      {/* Player Views */}
      <div className="pt-32">
        {view === 'lockscreen' ? (
          <LockScreenPlayer
            book={book}
            isPlaying={isPlaying}
            onPlayPause={handlePlayPause}
            onPrevious={handlePrevious}
            onNext={handleNext}
            onDismiss={onBack}
            currentTime={currentTime}
            duration={duration}
          />
        ) : (
          <div className="p-4">
            <div className="mb-4 text-center text-sm text-gray-400">
              {view === 'notification-collapsed' 
                ? 'This is how the player appears in the notification shade (collapsed state)'
                : 'This is how the player appears when expanded in the notification shade'}
            </div>
            <NotificationPlayer
              book={book}
              isPlaying={isPlaying}
              onPlayPause={handlePlayPause}
              onPrevious={handlePrevious}
              onNext={handleNext}
              onClose={onBack}
              currentTime={currentTime}
              duration={duration}
              isExpanded={view === 'notification-expanded'}
            />
            
            {/* Mock notification shade background */}
            <div className="mt-4 space-y-2 opacity-50">
              <div className="bg-[#1a1a2e] rounded-2xl p-4 text-sm">
                <div className="flex items-center gap-2 mb-1">
                  <div className="w-6 h-6 bg-blue-500 rounded-full" />
                  <span>Messages</span>
                </div>
                <p className="text-xs text-gray-400">You have 2 new messages</p>
              </div>
              <div className="bg-[#1a1a2e] rounded-2xl p-4 text-sm">
                <div className="flex items-center gap-2 mb-1">
                  <div className="w-6 h-6 bg-green-500 rounded-full" />
                  <span>Email</span>
                </div>
                <p className="text-xs text-gray-400">New email from sender</p>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}