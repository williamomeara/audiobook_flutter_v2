import React, { useState } from 'react';
import { Library } from './components/Library';
import { BookDetail } from './components/BookDetail';
import { Reader } from './components/Reader';
import { FreeBooks } from './components/FreeBooks';
import { PlayerDemo } from './components/PlayerDemo';
import { Settings } from './components/Settings';
import type { GutenbergBook } from './components/FreeBooks';

export type Book = {
  id: string;
  title: string;
  author: string;
  cover: string;
  chapters: number;
  currentChapter: number;
  progress: number;
  description: string;
  genre: string;
  estimatedTime: string;
  isFavorite: boolean;
  chapterList: Chapter[];
};

export type Chapter = {
  id: string;
  title: string;
  isRead: boolean;
  progress: number;
};

function App() {
  const [currentView, setCurrentView] = useState<'library' | 'detail' | 'reader' | 'free' | 'player-demo' | 'settings'>('library');
  const [selectedBook, setSelectedBook] = useState<Book | null>(null);
  const [darkMode, setDarkMode] = useState(true);

  const handleBookSelect = (book: Book) => {
    setSelectedBook(book);
    setCurrentView('detail');
  };

  const handleBackToLibrary = () => {
    setCurrentView('library');
    setSelectedBook(null);
  };

  const handleStartReading = () => {
    setCurrentView('reader');
  };

  const handleBackToDetail = () => {
    setCurrentView('detail');
  };

  const handleShowFreeBooks = () => {
    setCurrentView('free');
  };

  const handleShowPlayerDemo = () => {
    setCurrentView('player-demo');
  };

  const handleShowPlayerDemoFromSettings = (book: Book) => {
    setSelectedBook(book);
    setCurrentView('player-demo');
  };

  const handleBackToDetailFromPlayer = () => {
    if (selectedBook) {
      setCurrentView('detail');
    } else {
      setCurrentView('settings');
    }
  };

  const handleShowSettings = () => {
    setCurrentView('settings');
  };

  const handleBackFromSettings = () => {
    setCurrentView('library');
  };

  const handleImportBook = (gutenbergBook: GutenbergBook) => {
    // In a real app, this would add the book to the library
    console.log('Importing book:', gutenbergBook);
  };

  const handleOpenGutenbergBook = (gutenbergBook: GutenbergBook) => {
    // Convert to Book type and open detail view
    // In a real app, you'd fetch full book details
    console.log('Opening book:', gutenbergBook);
  };

  return (
    <div className="min-h-screen bg-[#0f1419]">
      {currentView === 'library' && (
        <Library 
          onBookSelect={handleBookSelect} 
          onShowFreeBooks={handleShowFreeBooks}
          onShowSettings={handleShowSettings}
          darkMode={darkMode}
        />
      )}
      {currentView === 'free' && (
        <FreeBooks 
          onBack={handleBackToLibrary}
          onImport={handleImportBook}
          onOpen={handleOpenGutenbergBook}
        />
      )}
      {currentView === 'settings' && (
        <Settings 
          onBack={handleBackFromSettings}
          darkMode={darkMode}
          onToggleDarkMode={setDarkMode}
          onShowPlayerDemo={handleShowPlayerDemoFromSettings}
        />
      )}
      {currentView === 'detail' && selectedBook && (
        <BookDetail 
          book={selectedBook} 
          onBack={handleBackToLibrary}
          onStartReading={handleStartReading}
          onShowPlayerDemo={handleShowPlayerDemo}
          darkMode={darkMode}
        />
      )}
      {currentView === 'player-demo' && selectedBook && (
        <PlayerDemo 
          book={selectedBook}
          onBack={handleBackToDetailFromPlayer}
        />
      )}
      {currentView === 'reader' && selectedBook && (
        <Reader 
          book={selectedBook}
          onBack={handleBackToDetail}
        />
      )}
    </div>
  );
}

export default App;