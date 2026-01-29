import React, { useState } from 'react';
import { ArrowLeft, Search } from 'lucide-react';

export type GutenbergBook = {
  id: string;
  title: string;
  author: string;
  gutenbergId: string;
  cover: string;
  isInLibrary: boolean;
};

interface FreeBooksProps {
  onBack: () => void;
  onImport: (book: GutenbergBook) => void;
  onOpen: (book: GutenbergBook) => void;
}

const mockGutenbergBooks: GutenbergBook[] = [
  {
    id: 'g1',
    title: 'Frankenstein; Or, The Modern Prometheus',
    author: 'Shelley, Mary Wollstonecraft',
    gutenbergId: 'Gutenberg #84',
    cover: 'figma:asset/00d924de6567907cafe3f4b5c9179a509974a397.png',
    isInLibrary: true,
  },
  {
    id: 'g2',
    title: 'Moby Dick; Or, The Whale',
    author: 'Melville, Herman',
    gutenbergId: 'Gutenberg #2701',
    cover: 'figma:asset/0f233990b19ba13de06697d733cabe2b1e01d263.png',
    isInLibrary: false,
  },
  {
    id: 'g3',
    title: 'A Christmas Carol in Prose; Being a Ghost Story of Christmas',
    author: 'Dickens, Charles',
    gutenbergId: 'Gutenberg #46',
    cover: 'figma:asset/00d924de6567907cafe3f4b5c9179a509974a397.png',
    isInLibrary: false,
  },
  {
    id: 'g4',
    title: 'Pride and Prejudice',
    author: 'Austen, Jane',
    gutenbergId: 'Gutenberg #1342',
    cover: 'figma:asset/0f233990b19ba13de06697d733cabe2b1e01d263.png',
    isInLibrary: false,
  },
];

export function FreeBooks({ onBack, onImport, onOpen }: FreeBooksProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [books, setBooks] = useState(mockGutenbergBooks);

  const filteredBooks = books.filter(book =>
    book.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
    book.author.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleAction = (book: GutenbergBook) => {
    if (book.isInLibrary) {
      onOpen(book);
    } else {
      // Mark as imported
      setBooks(books.map(b => 
        b.id === book.id ? { ...b, isInLibrary: true } : b
      ));
      onImport(book);
    }
  };

  return (
    <div className="min-h-screen bg-[#0f1419] text-white pb-6">
      {/* Header */}
      <div className="px-5 pt-14 pb-6">
        <div className="flex items-center gap-4 mb-6">
          <button 
            onClick={onBack}
            className="w-10 h-10 rounded-full bg-[#1a2332] flex items-center justify-center"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-2xl">Free books</h1>
        </div>

        {/* Search */}
        <div className="relative mb-6">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-500" />
          <input
            type="text"
            placeholder="Search Project Gutenberg..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-[#1a2332] rounded-2xl pl-12 pr-4 py-4 text-white placeholder-gray-500 outline-none"
          />
        </div>

        {/* Section Title */}
        <h2 className="text-gray-400 mb-4">Top 100 (popular)</h2>
      </div>

      {/* Books List */}
      <div className="px-5 space-y-4">
        {filteredBooks.map((book) => (
          <div
            key={book.id}
            className="bg-[#1a2332] rounded-2xl p-4 flex gap-4 items-center"
          >
            <img
              src={book.cover}
              alt={book.title}
              className="w-20 h-28 object-cover rounded-lg flex-shrink-0"
            />
            
            <div className="flex-1 min-w-0">
              <h3 className="text-white mb-1 leading-tight">{book.title}</h3>
              <p className="text-sm text-gray-400 mb-1">{book.author}</p>
              <p className="text-xs text-gray-500">{book.gutenbergId}</p>
            </div>

            <button
              onClick={() => handleAction(book)}
              className="px-6 py-2 rounded-lg bg-transparent border-0 text-[#f59e0b] hover:text-[#fbbf24] transition-colors flex-shrink-0"
            >
              {book.isInLibrary ? 'Open' : 'Import'}
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
