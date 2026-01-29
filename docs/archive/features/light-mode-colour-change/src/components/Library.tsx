import React, { useState } from 'react';
import { Search, Settings, SlidersHorizontal, Heart, TrendingUp, Clock } from 'lucide-react';
import type { Book } from '../App';

const mockBooks: Book[] = [
  {
    id: '1',
    title: 'Frankenstein; Or, The Modern Prometheus',
    author: 'Mary Wollstonecraft Shelley',
    cover: 'figma:asset/00d924de6567907cafe3f4b5c9179a509974a397.png',
    chapters: 32,
    currentChapter: 5,
    progress: 15,
    rating: 4.5,
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
  },
  {
    id: '2',
    title: 'The Strange Case of Dr. Jekyll and Mr. Hyde',
    author: 'Robert Louis Stevenson',
    cover: 'figma:asset/0f233990b19ba13de06697d733cabe2b1e01d263.png',
    chapters: 15,
    currentChapter: 0,
    progress: 0,
    description: 'A London lawyer investigates strange occurrences between his old friend Dr. Jekyll and the evil Mr. Hyde.',
    genre: 'Gothic Fiction',
    estimatedTime: '4h 15m',
    isFavorite: false,
    chapterList: [],
  },
];

interface LibraryProps {
  onBookSelect: (book: Book) => void;
  onShowFreeBooks: () => void;
  onShowSettings: () => void;
  darkMode: boolean;
}

export function Library({ onBookSelect, onShowFreeBooks, onShowSettings, darkMode }: LibraryProps) {
  const [activeTab, setActiveTab] = useState<'all' | 'favorites'>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'recent' | 'title' | 'progress'>('recent');
  const [showFilters, setShowFilters] = useState(false);

  const filteredBooks = mockBooks.filter(book => {
    const matchesSearch = book.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      book.author.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesTab = activeTab === 'all' || (activeTab === 'favorites' && book.isFavorite);
    return matchesSearch && matchesTab;
  });

  return (
    <div className={`min-h-screen ${darkMode ? 'bg-[#0f1419] text-white' : 'bg-[#f5f5f5] text-gray-900'} pb-6`}>
      {/* Header */}
      <div className="px-5 pt-14 pb-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-4">
            <button 
              onClick={onShowSettings}
              className={`w-10 h-10 rounded-full ${darkMode ? 'bg-[#1a2332]' : 'bg-white'} flex items-center justify-center`}
            >
              <Settings className="w-5 h-5" />
            </button>
            <h1 className="text-2xl">Library</h1>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setShowFilters(!showFilters)}
              className={`px-4 py-2 rounded-lg flex items-center gap-2 transition-colors ${
                showFilters ? 'bg-[#6366f1] text-white' : darkMode ? 'bg-[#1a2332]' : 'bg-white'
              }`}
            >
              <SlidersHorizontal className="w-4 h-4" />
              <span className="text-sm">Filter</span>
            </button>
          </div>
        </div>

        {/* Tabs and Action Buttons */}
        <div className="flex items-center justify-between mb-4">
          <div className="flex gap-4">
            <button
              onClick={() => setActiveTab('all')}
              className={`text-sm ${activeTab === 'all' ? 'text-[#6366f1]' : darkMode ? 'text-gray-400' : 'text-gray-500'}`}
            >
              All
            </button>
            <button
              onClick={() => setActiveTab('favorites')}
              className={`text-sm ${activeTab === 'favorites' ? 'text-[#6366f1]' : darkMode ? 'text-gray-400' : 'text-gray-500'}`}
            >
              Favorites
            </button>
          </div>
          <div className="flex gap-2">
            <button
              onClick={onShowFreeBooks}
              className={`px-4 py-2 rounded-lg ${darkMode ? 'bg-[#1a2332] text-gray-400 hover:text-white' : 'bg-white text-gray-600 hover:text-gray-900'} text-sm transition-colors`}
            >
              Free Books
            </button>
            <button
              className={`px-4 py-2 rounded-lg ${darkMode ? 'bg-[#1a2332] text-gray-400 hover:text-white' : 'bg-white text-gray-600 hover:text-gray-900'} text-sm transition-colors`}
            >
              Import
            </button>
          </div>
        </div>

        {/* Search */}
        <div className="relative">
          <Search className={`absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`} />
          <input
            type="text"
            placeholder="Search library..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className={`w-full ${darkMode ? 'bg-[#1a2332] text-white placeholder-gray-400' : 'bg-white text-gray-900 placeholder-gray-500'} rounded-2xl pl-12 pr-4 py-4 outline-none`}
          />
        </div>

        {/* Sort Options */}
        {showFilters && (
          <div className={`mt-4 ${darkMode ? 'bg-[#1a2332]' : 'bg-white'} rounded-xl p-4`}>
            <div className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'} mb-3`}>Sort by</div>
            <div className="flex flex-wrap gap-2">
              {['recent', 'title', 'progress'].map((option) => (
                <button
                  key={option}
                  onClick={() => setSortBy(option as any)}
                  className={`px-4 py-2 rounded-lg text-sm capitalize ${
                    sortBy === option ? 'bg-[#6366f1] text-white' : darkMode ? 'bg-[#0f1419] text-gray-400' : 'bg-gray-100 text-gray-600'
                  }`}
                >
                  {option}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Book List */}
      <div className="px-5 space-y-4">
        {filteredBooks.map((book) => (
          <button
            key={book.id}
            onClick={() => onBookSelect(book)}
            className={`w-full ${darkMode ? 'bg-[#1a2332] hover:bg-[#212d3f]' : 'bg-white hover:bg-gray-50'} rounded-2xl p-4 flex gap-4 items-start transition-colors`}
          >
            <div className="relative flex-shrink-0">
              <img
                src={book.cover}
                alt={book.title}
                className="w-20 h-28 object-cover rounded-lg"
              />
              {book.progress > 0 && (
                <div className="absolute bottom-0 left-0 right-0 h-1 bg-gray-700 rounded-b-lg overflow-hidden">
                  <div 
                    className="h-full bg-[#6366f1]"
                    style={{ width: `${book.progress}%` }}
                  />
                </div>
              )}
            </div>
            
            <div className="flex-1 text-left min-w-0">
              <div className="flex items-start justify-between gap-2 mb-1">
                <h3 className={`${darkMode ? 'text-white' : 'text-gray-900'} line-clamp-2`}>{book.title}</h3>
                {book.isFavorite && (
                  <Heart className="w-4 h-4 text-[#6366f1] fill-[#6366f1] flex-shrink-0" />
                )}
              </div>
              <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'} mb-2`}>{book.author}</p>
              <div className={`flex items-center gap-3 text-xs ${darkMode ? 'text-gray-500' : 'text-gray-400'}`}>
                <span>{book.chapters} Chapters</span>
                {book.progress > 0 && (
                  <>
                    <span>•</span>
                    <span>{book.progress}% Complete</span>
                  </>
                )}
              </div>
              {book.progress > 0 && (
                <div className="mt-2 text-xs text-[#6366f1]">
                  Continue Listening • Chapter {book.currentChapter}
                </div>
              )}
            </div>
            
            <svg 
              className={`w-5 h-5 ${darkMode ? 'text-gray-400' : 'text-gray-500'} flex-shrink-0 mt-2`} 
              fill="none" 
              viewBox="0 0 24 24" 
              stroke="currentColor"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </button>
        ))}
      </div>
    </div>
  );
}