import React, { useState } from 'react';
import { ArrowLeft, Heart, BookOpen, Clock, Eye } from 'lucide-react';
import type { Book } from '../App';

interface BookDetailProps {
  book: Book;
  onBack: () => void;
  onStartReading: () => void;
}

export function BookDetail({ book, onBack, onStartReading }: BookDetailProps) {
  const [isFavorite, setIsFavorite] = useState(book.isFavorite);
  const [showAllChapters, setShowAllChapters] = useState(false);

  const displayedChapters = showAllChapters 
    ? book.chapterList 
    : book.chapterList.slice(0, 6);

  return (
    <div className="min-h-screen bg-[#0f1419] text-white pb-20">
      {/* Header */}
      <div className="px-5 pt-14 pb-4 flex items-center justify-between">
        <button 
          onClick={onBack}
          className="w-10 h-10 rounded-full bg-[#1a2332] flex items-center justify-center"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-lg">Book Details</h1>
        <div className="flex gap-2">
          <button 
            onClick={() => setIsFavorite(!isFavorite)}
            className="w-10 h-10 rounded-full bg-[#1a2332] flex items-center justify-center"
          >
            <Heart 
              className={`w-5 h-5 ${isFavorite ? 'fill-[#f59e0b] text-[#f59e0b]' : ''}`} 
            />
          </button>
        </div>
      </div>

      {/* Book Info */}
      <div className="px-5 py-6">
        <div className="flex gap-5 mb-6">
          <div className="relative flex-shrink-0">
            <img
              src={book.cover}
              alt={book.title}
              className="w-[140px] h-[200px] object-cover rounded-xl shadow-2xl"
            />
            {book.progress > 0 && (
              <div className="absolute -bottom-2 left-0 right-0 mx-2">
                <div className="bg-[#1a2332] rounded-full p-2 text-center">
                  <div className="text-xs text-[#f59e0b]">{book.progress}%</div>
                </div>
              </div>
            )}
          </div>
          
          <div className="flex-1 min-w-0">
            <h2 className="text-xl mb-2 leading-tight">{book.title}</h2>
            <p className="text-gray-400 mb-3">{book.author}</p>
            
            {/* Stats */}
            <div className="space-y-2 mb-4">
              <div className="flex items-center gap-2 text-sm">
                <BookOpen className="w-4 h-4 text-[#f59e0b]" />
                <span className="text-gray-400">{book.chapters} Chapters</span>
              </div>
              <div className="flex items-center gap-2 text-sm">
                <Clock className="w-4 h-4 text-[#f59e0b]" />
                <span className="text-gray-400">{book.estimatedTime}</span>
              </div>
            </div>

            {/* Genre Tag */}
            <div className="inline-block px-3 py-1 bg-[#1a2332] rounded-full text-xs text-gray-400">
              {book.genre}
            </div>
          </div>
        </div>

        {/* Progress Bar */}
        {book.progress > 0 && (
          <div className="mb-6">
            <div className="flex justify-between text-sm mb-2">
              <span className="text-gray-400">Reading Progress</span>
              <span className="text-[#f59e0b]">Chapter {book.currentChapter} of {book.chapters}</span>
            </div>
            <div className="h-2 bg-[#1a2332] rounded-full overflow-hidden">
              <div 
                className="h-full bg-gradient-to-r from-[#f59e0b] to-[#fbbf24] transition-all duration-300"
                style={{ width: `${book.progress}%` }}
              />
            </div>
          </div>
        )}

        {/* Description */}
        <div className="mb-6">
          <h3 className="text-sm text-gray-400 mb-2">About this book</h3>
          <p className="text-gray-300 leading-relaxed">{book.description}</p>
        </div>

        {/* Action Button */}
        <button
          onClick={onStartReading}
          className="w-full bg-[#f59e0b] hover:bg-[#fbbf24] transition-colors rounded-2xl py-4 flex items-center justify-center gap-2 mb-6"
        >
          <BookOpen className="w-5 h-5" />
          <span className="text-black">
            {book.progress > 0 ? 'Continue Listening' : 'Start Listening'}
          </span>
        </button>

        {/* Chapters Section */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg">Chapters</h3>
            <div className="flex items-center gap-2 text-xs text-gray-400">
              <Eye className="w-4 h-4" />
              <span>{book.chapterList.filter(c => c.isRead).length} read</span>
            </div>
          </div>
          
          <div className="space-y-3">
            {displayedChapters.map((chapter, index) => (
              <button
                key={chapter.id}
                className="w-full bg-[#1a2332] hover:bg-[#212d3f] transition-colors rounded-xl p-4 text-left"
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-3">
                    <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm ${
                      chapter.isRead 
                        ? 'bg-[#f59e0b] text-black' 
                        : 'bg-[#0f1419] text-gray-400'
                    }`}>
                      {index + 1}
                    </div>
                    <span className="text-white">{chapter.title}</span>
                  </div>
                  {chapter.isRead && (
                    <div className="text-xs text-[#f59e0b]">✓ Read</div>
                  )}
                </div>
                
                {chapter.progress > 0 && chapter.progress < 100 && (
                  <div className="ml-11">
                    <div className="h-1 bg-[#0f1419] rounded-full overflow-hidden">
                      <div 
                        className="h-full bg-[#f59e0b]"
                        style={{ width: `${chapter.progress}%` }}
                      />
                    </div>
                  </div>
                )}
              </button>
            ))}
          </div>

          {book.chapterList.length > 6 && (
            <button
              onClick={() => setShowAllChapters(!showAllChapters)}
              className="w-full mt-3 py-3 text-sm text-[#f59e0b] hover:text-[#fbbf24] transition-colors"
            >
              {showAllChapters ? 'Show Less' : `Show All ${book.chapterList.length} Chapters`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}