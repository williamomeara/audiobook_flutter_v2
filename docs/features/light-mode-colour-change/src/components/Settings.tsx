import React, { useState } from 'react';
import { ArrowLeft, ChevronRight } from 'lucide-react';
import type { Book } from '../App';

interface SettingsProps {
  onBack: () => void;
  darkMode: boolean;
  onToggleDarkMode: (enabled: boolean) => void;
  onShowPlayerDemo?: (book: Book) => void;
}

export function Settings({ onBack, darkMode, onToggleDarkMode, onShowPlayerDemo }: SettingsProps) {
  const [showCoverBackground, setShowCoverBackground] = useState(true);
  const [smartSynthesis, setSmartSynthesis] = useState(true);
  const [autoAdvance, setAutoAdvance] = useState(true);
  const [playbackRate, setPlaybackRate] = useState(1.0);

  const mockBook: Book = {
    id: '1',
    title: 'Frankenstein; Or, The Modern Prometheus',
    author: 'Mary Wollstonecraft Shelley',
    cover: 'figma:asset/00d924de6567907cafe3f4b5c9179a509974a397.png',
    chapters: 32,
    currentChapter: 5,
    progress: 15,
    description: 'A young scientist creates a grotesque but sentient creature in an unorthodox scientific experiment.',
    genre: 'Gothic Fiction',
    estimatedTime: '8h 20m',
    isFavorite: true,
    chapterList: [
      { id: 'c1', title: 'Frankenstein;', isRead: true, progress: 100 },
      { id: 'c2', title: 'or, the Modern Prometheus', isRead: true, progress: 100 },
      { id: 'c3', title: 'CONTENTS', isRead: true, progress: 100 },
      { id: 'c4', title: 'Letter 1', isRead: true, progress: 100 },
      { id: 'c5', title: 'Letter 2', isRead: true, progress: 60 },
      { id: 'c6', title: 'Letter 3', isRead: false, progress: 0 },
    ],
  };

  return (
    <div className={`min-h-screen ${darkMode ? 'bg-[#0f1419] text-white' : 'bg-[#f5f5f5] text-gray-900'} pb-6`}>
      {/* Header */}
      <div className="px-5 pt-14 pb-6 flex items-center justify-center relative">
        <button 
          onClick={onBack}
          className={`absolute left-5 w-10 h-10 rounded-full ${darkMode ? 'bg-[#1a2332]' : 'bg-white'} flex items-center justify-center`}
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-xl font-medium">Settings</h1>
      </div>

      <div className="px-5">
        {/* Appearance Section */}
        <div className="mb-6">
          <h2 className={`text-sm mb-3 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Appearance</h2>
          <div className={`${darkMode ? 'bg-[#1a2332]' : 'bg-white'} rounded-2xl overflow-hidden`}>
            <button
              onClick={() => onToggleDarkMode(!darkMode)}
              className={`w-full px-5 py-4 flex items-center justify-between ${darkMode ? 'hover:bg-[#212d3f]' : 'hover:bg-gray-50'} transition-colors border-b ${darkMode ? 'border-[#2a3544]' : 'border-gray-100'}`}
            >
              <div className="text-left">
                <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-1`}>Dark mode</div>
                <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Use dark theme</div>
              </div>
              <div 
                className={`w-12 h-7 rounded-full transition-colors ${darkMode ? 'bg-[#6366f1]' : 'bg-gray-300'} relative`}
              >
                <div 
                  className={`absolute top-1 w-5 h-5 bg-white rounded-full transition-transform ${darkMode ? 'translate-x-6' : 'translate-x-1'}`}
                />
              </div>
            </button>

            <button
              onClick={() => setShowCoverBackground(!showCoverBackground)}
              className={`w-full px-5 py-4 flex items-center justify-between ${darkMode ? 'hover:bg-[#212d3f]' : 'hover:bg-gray-50'} transition-colors`}
            >
              <div className="text-left">
                <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-1`}>Book cover background</div>
                <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Show cover art behind text in playback</div>
              </div>
              <div 
                className={`w-12 h-7 rounded-full transition-colors ${showCoverBackground ? 'bg-[#6366f1]' : darkMode ? 'bg-gray-600' : 'bg-gray-300'} relative`}
              >
                <div 
                  className={`absolute top-1 w-5 h-5 bg-white rounded-full transition-transform ${showCoverBackground ? 'translate-x-6' : 'translate-x-1'}`}
                />
              </div>
            </button>
          </div>
        </div>

        {/* Voice Section */}
        <div className="mb-6">
          <h2 className={`text-sm mb-3 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Voice</h2>
          <div className={`${darkMode ? 'bg-[#1a2332]' : 'bg-white'} rounded-2xl overflow-hidden`}>
            <button className={`w-full px-5 py-4 flex items-center justify-between ${darkMode ? 'hover:bg-[#212d3f]' : 'hover:bg-gray-50'} transition-colors`}>
              <div className="text-left">
                <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-1`}>Selected voice</div>
                <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Supertonic Male 3</div>
              </div>
              <ChevronRight className={`w-5 h-5 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`} />
            </button>
          </div>
        </div>

        {/* Voice Downloads Section */}
        <div className="mb-6">
          <h2 className={`text-sm mb-3 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Voice Downloads</h2>
          <div className={`${darkMode ? 'bg-[#1a2332]' : 'bg-white'} rounded-2xl overflow-hidden`}>
            <button className={`w-full px-5 py-4 flex items-center justify-between ${darkMode ? 'hover:bg-[#212d3f]' : 'hover:bg-gray-50'} transition-colors`}>
              <div className="text-left">
                <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-1`}>Manage Voice Downloads</div>
                <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Download and manage voice models</div>
              </div>
              <ChevronRight className={`w-5 h-5 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`} />
            </button>
          </div>
        </div>

        {/* Playback Section */}
        <div className="mb-6">
          <h2 className={`text-sm mb-3 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Playback</h2>
          <div className={`${darkMode ? 'bg-[#1a2332]' : 'bg-white'} rounded-2xl overflow-hidden`}>
            <button
              onClick={() => setSmartSynthesis(!smartSynthesis)}
              className={`w-full px-5 py-4 flex items-center justify-between ${darkMode ? 'hover:bg-[#212d3f]' : 'hover:bg-gray-50'} transition-colors border-b ${darkMode ? 'border-[#2a3544]' : 'border-gray-100'}`}
            >
              <div className="text-left">
                <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-1`}>Smart synthesis</div>
                <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Pre-synthesize audio for instant playback</div>
              </div>
              <div 
                className={`w-12 h-7 rounded-full transition-colors ${smartSynthesis ? 'bg-[#6366f1]' : darkMode ? 'bg-gray-600' : 'bg-gray-300'} relative`}
              >
                <div 
                  className={`absolute top-1 w-5 h-5 bg-white rounded-full transition-transform ${smartSynthesis ? 'translate-x-6' : 'translate-x-1'}`}
                />
              </div>
            </button>

            <button
              onClick={() => setAutoAdvance(!autoAdvance)}
              className={`w-full px-5 py-4 flex items-center justify-between ${darkMode ? 'hover:bg-[#212d3f]' : 'hover:bg-gray-50'} transition-colors border-b ${darkMode ? 'border-[#2a3544]' : 'border-gray-100'}`}
            >
              <div className="text-left">
                <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-1`}>Auto-advance chapters</div>
                <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Automatically move to next chapter</div>
              </div>
              <div 
                className={`w-12 h-7 rounded-full transition-colors ${autoAdvance ? 'bg-[#6366f1]' : darkMode ? 'bg-gray-600' : 'bg-gray-300'} relative`}
              >
                <div 
                  className={`absolute top-1 w-5 h-5 bg-white rounded-full transition-transform ${autoAdvance ? 'translate-x-6' : 'translate-x-1'}`}
                />
              </div>
            </button>

            <div className="px-5 py-4">
              <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-4`}>Default playback rate</div>
              <input
                type="range"
                min="0.5"
                max="2.0"
                step="0.1"
                value={playbackRate}
                onChange={(e) => setPlaybackRate(parseFloat(e.target.value))}
                className="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-[#6366f1]"
                style={{
                  background: `linear-gradient(to right, #6366f1 0%, #6366f1 ${((playbackRate - 0.5) / 1.5) * 100}%, ${darkMode ? '#374151' : '#e5e7eb'} ${((playbackRate - 0.5) / 1.5) * 100}%, ${darkMode ? '#374151' : '#e5e7eb'} 100%)`
                }}
              />
              <div className={`text-center text-lg mt-3 ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>{playbackRate.toFixed(1)}x</div>
            </div>
          </div>
        </div>

        {/* Player UI Demo Section */}
        {onShowPlayerDemo && (
          <div className="mb-6">
            <h2 className={`text-sm mb-3 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Developer</h2>
            <div className={`${darkMode ? 'bg-[#1a2332]' : 'bg-white'} rounded-2xl overflow-hidden`}>
              <button
                onClick={() => onShowPlayerDemo(mockBook)}
                className={`w-full px-5 py-4 flex items-center justify-between ${darkMode ? 'hover:bg-[#212d3f]' : 'hover:bg-gray-50'} transition-colors`}
              >
                <div className="text-left">
                  <div className={`${darkMode ? 'text-white' : 'text-gray-900'} mb-1`}>Player UI Preview</div>
                  <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Lock screen & notification controls</div>
                </div>
                <ChevronRight className={`w-5 h-5 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`} />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
