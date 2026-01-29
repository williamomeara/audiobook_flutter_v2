import { useState, useRef, useEffect } from 'react';
import { Play, Pause, SkipBack, SkipForward, BookOpen, Image as ImageIcon, MapPin, ChevronLeft, ChevronRight, Gauge, Timer } from 'lucide-react';

// Mock chapter data
const chapters = [
  {
    id: 1,
    title: "Chapter 1: The Letter",
    sentences: [
      "The envelope arrived on a Tuesday morning, its aged parchment standing out among the usual bills and advertisements.",
      "Emma's name was written in elegant cursive, a handwriting she recognized immediately as her grandmother's.",
      "With trembling fingers, she broke the wax seal and unfolded the letter inside.",
      "The words were brief but cryptic: 'Come to the old house. Find the hidden room. Your destiny awaits.'",
      "Emma hadn't visited the property in years, not since her grandmother's funeral.",
    ]
  },
  {
    id: 2,
    title: "Chapter 2: The Journey",
    sentences: [
      "The drive to the countryside took three hours, winding through forests and past forgotten villages.",
      "As Emma turned onto the overgrown driveway, memories flooded back—summer afternoons, her grandmother's stories, the smell of fresh-baked bread.",
      "The house loomed ahead, more decrepit than she remembered, nature slowly reclaiming what humans had built.",
      "She parked the car and sat for a moment, gathering her courage.",
      "Whatever waited inside, she was about to discover it.",
    ]
  },
  {
    id: 3,
    title: "Chapter 3: Discoveries",
    sentences: [
      "The old house stood at the edge of the forest, its weathered walls holding secrets from generations past.",
      "Emma had inherited the property from her grandmother, along with a mysterious letter that simply read: 'Find the hidden room.'",
      "As she stepped through the creaking front door, dust motes danced in the afternoon sunlight streaming through broken windows.",
      "The floorboards groaned beneath her feet, each step echoing through the empty halls like whispers of forgotten memories.",
      "She moved cautiously through the parlor, her eyes scanning every corner, every shadow, searching for clues.",
      "A portrait of her grandmother hung on the far wall, her painted eyes seeming to follow Emma's every movement.",
      "Behind the portrait, Emma noticed something odd—a slight discoloration in the wallpaper, barely visible in the dim light.",
      "Her fingers traced the edges of what appeared to be a seam, hidden beneath layers of yellowed paper and time.",
      "With trembling hands, she pressed against the wall, and to her amazement, a section swung inward with a soft click.",
      "Beyond the hidden door lay a narrow staircase descending into darkness, promising answers to questions she hadn't yet thought to ask.",
      "Emma hesitated at the threshold, her heart pounding with a mixture of fear and exhilaration.",
      "The air that wafted up from below was cool and carried the scent of old books and forgotten treasures.",
      "She pulled out her phone, activating its flashlight, and began her descent into the unknown depths of her inheritance.",
      "The stairs spiraled downward, much deeper than she had anticipated, leading her far beneath the foundation of the house.",
      "At the bottom, she found herself in a small chamber lined with shelves containing leather-bound journals and curious artifacts.",
      "In the center of the room sat an ornate wooden chest, its brass lock glinting in her phone's light.",
      "Emma approached the chest slowly, noticing an envelope resting on its lid with her name written in familiar handwriting.",
      "Inside the envelope was a small brass key and another note from her grandmother: 'The truth has been waiting for you.'",
      "With shaking fingers, she inserted the key into the lock, and the chest opened with a satisfying click that echoed through the chamber.",
      "What she found inside would change everything she thought she knew about her family's history and her own destiny."
    ]
  },
  {
    id: 4,
    title: "Chapter 4: The Truth Revealed",
    sentences: [
      "Inside the chest lay a collection of journals, each one bound in leather and filled with her grandmother's precise handwriting.",
      "Emma carefully lifted the first volume, its pages yellowed with age but still perfectly preserved.",
      "As she read, a story unfolded—a story of her family's true origins, of secrets kept for generations.",
      "Her grandmother hadn't been an ordinary woman at all.",
      "The truth was far more extraordinary than Emma could have ever imagined.",
    ]
  }
];

export default function App() {
  const [currentChapterIndex, setCurrentChapterIndex] = useState(2); // Start at chapter 3
  const [currentSentenceIndex, setCurrentSentenceIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [playbackSpeed, setPlaybackSpeed] = useState(1); // 1x speed
  const [showCover, setShowCover] = useState(false);
  const [showJumpButton, setShowJumpButton] = useState(false);
  const [sleepTimer, setSleepTimer] = useState<number | null>(null); // in minutes
  const [sleepTimeRemaining, setSleepTimeRemaining] = useState<number | null>(null); // in seconds
  const currentSentenceRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const isAutoScrolling = useRef(false);

  const currentChapter = chapters[currentChapterIndex];
  const chapterText = currentChapter.sentences;

  // Auto-advance sentences when playing
  useEffect(() => {
    if (!isPlaying) return;
    
    const interval = setInterval(() => {
      setCurrentSentenceIndex((prev) => {
        if (prev < chapterText.length - 1) {
          return prev + 1;
        } else {
          // Move to next chapter if available
          if (currentChapterIndex < chapters.length - 1) {
            setCurrentChapterIndex(currentChapterIndex + 1);
            return 0;
          } else {
            setIsPlaying(false);
            return prev;
          }
        }
      });
    }, 3000 / playbackSpeed); // Adjust speed based on playbackSpeed

    return () => clearInterval(interval);
  }, [isPlaying, playbackSpeed, chapterText.length, currentChapterIndex]);

  // Auto-scroll to current sentence
  useEffect(() => {
    if (currentSentenceRef.current && scrollContainerRef.current) {
      isAutoScrolling.current = true;
      currentSentenceRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'center',
      });
      
      // Reset auto-scrolling flag after animation
      setTimeout(() => {
        isAutoScrolling.current = false;
      }, 1000);
    }
  }, [currentSentenceIndex]);

  // Detect manual scrolling
  useEffect(() => {
    const scrollContainer = scrollContainerRef.current;
    if (!scrollContainer) return;

    const handleScroll = () => {
      if (isAutoScrolling.current) return;
      
      // Check if current sentence is in view
      if (currentSentenceRef.current) {
        const rect = currentSentenceRef.current.getBoundingClientRect();
        const containerRect = scrollContainer.getBoundingClientRect();
        
        const isInView = 
          rect.top >= containerRect.top &&
          rect.bottom <= containerRect.bottom;
        
        setShowJumpButton(!isInView);
      }
    };

    scrollContainer.addEventListener('scroll', handleScroll);
    return () => scrollContainer.removeEventListener('scroll', handleScroll);
  }, [currentSentenceIndex]);

  // Sleep timer
  useEffect(() => {
    if (sleepTimer !== null) {
      setSleepTimeRemaining(sleepTimer * 60);
    }
  }, [sleepTimer]);

  useEffect(() => {
    if (sleepTimeRemaining !== null && sleepTimeRemaining > 0) {
      const timer = setInterval(() => {
        setSleepTimeRemaining((prev) => (prev !== null ? prev - 1 : null));
      }, 1000);

      return () => clearInterval(timer);
    } else if (sleepTimeRemaining === 0) {
      setIsPlaying(false);
      setSleepTimeRemaining(null);
    }
  }, [sleepTimeRemaining]);

  const handlePlayPause = () => {
    setIsPlaying(!isPlaying);
  };

  const handleSkipBack = () => {
    setCurrentSentenceIndex((prev) => Math.max(0, prev - 1));
  };

  const handleSkipForward = () => {
    setCurrentSentenceIndex((prev) => Math.min(chapterText.length - 1, prev + 1));
  };

  const handleToggleView = () => {
    setShowCover(!showCover);
  };

  const handleJumpToCurrent = () => {
    if (currentSentenceRef.current) {
      isAutoScrolling.current = true;
      currentSentenceRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'center',
      });
      setTimeout(() => {
        isAutoScrolling.current = false;
        setShowJumpButton(false);
      }, 1000);
    }
  };

  const handleSpeedChange = (speed: number) => {
    setPlaybackSpeed(speed);
  };

  const handlePreviousChapter = () => {
    if (currentChapterIndex > 0) {
      setCurrentChapterIndex(currentChapterIndex - 1);
      setCurrentSentenceIndex(0);
    }
  };

  const handleNextChapter = () => {
    if (currentChapterIndex < chapters.length - 1) {
      setCurrentChapterIndex(currentChapterIndex + 1);
      setCurrentSentenceIndex(0);
    }
  };

  const handleSetSleepTimer = (minutes: number | null) => {
    setSleepTimer(minutes);
  };

  return (
    <div className="size-full flex flex-col bg-gradient-to-br from-slate-900 to-slate-800 text-white">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-slate-700">
        <div>
          <h1 className="text-xl">The Hidden Chamber</h1>
          <p className="text-sm text-slate-400">{currentChapter.title}</p>
        </div>
        <button
          onClick={handleToggleView}
          className="p-2 hover:bg-slate-700 rounded-lg transition-colors"
          aria-label="Toggle view"
        >
          {showCover ? <BookOpen className="w-5 h-5" /> : <ImageIcon className="w-5 h-5" />}
        </button>
      </div>

      {/* Content Area */}
      <div className="flex-1 overflow-hidden relative">
        {showCover ? (
          <div className="size-full flex items-center justify-center p-8">
            <div className="max-w-md w-full">
              <img
                src="https://images.unsplash.com/photo-1622701361340-7d066c90f59b?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w3Nzg4Nzd8MHwxfHNlYXJjaHwxfHxhdWRpb2Jvb2slMjBjb3ZlcnxlbnwxfHx8fDE3Njc4NDQwOTN8MA&ixlib=rb-4.1.0&q=80&w=1080&utm_source=figma&utm_medium=referral"
                alt="The Hidden Chamber audiobook cover"
                className="w-full rounded-lg shadow-2xl"
              />
              <div className="mt-6 text-center">
                <h2 className="text-2xl mb-2">The Hidden Chamber</h2>
                <p className="text-slate-400">By Sarah Mitchell</p>
              </div>
            </div>
          </div>
        ) : (
          <>
            <div
              ref={scrollContainerRef}
              className="size-full overflow-y-auto px-6 py-8 md:px-12 md:py-12 relative"
            >
              {/* Background Cover Image */}
              <div 
                className="fixed inset-0 flex items-center justify-center pointer-events-none"
                style={{
                  top: '64px', // Account for header height
                  bottom: '240px', // Account for controls height
                }}
              >
                <img
                  src="https://images.unsplash.com/photo-1622701361340-7d066c90f59b?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&ixid=M3w3Nzg4Nzd8MHwxfHNlYXJjaHwxfHxhdWRpb2Jvb2slMjBjb3ZlcnxlbnwxfHx8fDE3Njc4NDQwOTN8MA&ixlib=rb-4.1.0&q=80&w=1080&utm_source=figma&utm_medium=referral"
                  alt=""
                  className="max-w-md w-full opacity-5 blur-sm"
                />
              </div>

              <div className="max-w-3xl mx-auto text-lg leading-relaxed relative z-10">
                {chapterText.map((sentence, index) => {
                  const isCurrent = index === currentSentenceIndex;
                  const isPast = index < currentSentenceIndex;
                  // Only next 5 sentences are downloaded
                  const isDownloaded = index <= currentSentenceIndex + 5;

                  return (
                    <span
                      key={index}
                      ref={isCurrent ? currentSentenceRef : null}
                      className={`
                        transition-colors duration-300
                        ${isCurrent ? 'text-amber-400' : ''}
                        ${isPast ? 'text-slate-500' : ''}
                        ${!isPast && !isCurrent && isDownloaded ? 'text-slate-300' : ''}
                        ${!isPast && !isCurrent && !isDownloaded ? 'text-slate-700 opacity-50' : ''}
                      `}
                    >
                      {sentence}{' '}
                      {!isDownloaded && (
                        <span className="text-xs text-slate-600 opacity-70">(downloading...)</span>
                      )}
                    </span>
                  );
                })}
              </div>
            </div>

            {/* Jump to Current Sentence Button */}
            {showJumpButton && (
              <div className="absolute bottom-6 right-6 md:bottom-8 md:right-8">
                <button
                  onClick={handleJumpToCurrent}
                  className="flex items-center gap-2 px-4 py-3 bg-amber-500 hover:bg-amber-600 rounded-full shadow-lg transition-colors"
                  aria-label="Jump to current sentence"
                >
                  <MapPin className="w-5 h-5 text-slate-900" fill="currentColor" />
                  <span className="text-sm text-slate-900">Jump to current</span>
                </button>
              </div>
            )}
          </>
        )}
      </div>

      {/* Playback Controls */}
      <div className="border-t border-slate-700 bg-slate-900/80 backdrop-blur-sm">
        {/* Progress Bar */}
        <div className="px-6 pt-4">
          <div className="flex items-center gap-3 text-sm text-slate-400">
            <span>{currentSentenceIndex + 1}</span>
            <div className="flex-1 h-1 bg-slate-700 rounded-full overflow-hidden">
              <div
                className="h-full bg-amber-500 transition-all duration-300"
                style={{ width: `${((currentSentenceIndex + 1) / chapterText.length) * 100}%` }}
              />
            </div>
            <span>{chapterText.length}</span>
          </div>
        </div>

        {/* Speed and Sleep Timer Controls */}
        <div className="flex items-center justify-between px-6 pt-4 pb-2">
          {/* Speed Control */}
          <div className="flex items-center gap-2">
            <Gauge className="w-4 h-4 text-slate-400" />
            <button
              onClick={() => handleSpeedChange(Math.max(0.5, playbackSpeed - 0.5))}
              className="p-1 hover:bg-slate-700 rounded transition-colors"
              aria-label="Decrease speed"
            >
              <ChevronLeft className="w-4 h-4 text-slate-400" />
            </button>
            <span className="text-sm text-slate-300 min-w-[3rem] text-center">{playbackSpeed}x</span>
            <button
              onClick={() => handleSpeedChange(Math.min(2, playbackSpeed + 0.5))}
              className="p-1 hover:bg-slate-700 rounded transition-colors"
              aria-label="Increase speed"
            >
              <ChevronRight className="w-4 h-4 text-slate-400" />
            </button>
          </div>

          {/* Sleep Timer */}
          <div className="flex items-center gap-2">
            <Timer className="w-4 h-4 text-slate-400" />
            <select
              value={sleepTimer !== null ? sleepTimer.toString() : ''}
              onChange={(e) => handleSetSleepTimer(e.target.value ? Number(e.target.value) : null as any)}
              className="bg-slate-700 text-slate-300 text-sm px-3 py-1 rounded-lg border border-slate-600 focus:outline-none focus:border-amber-500"
            >
              <option value="">Off</option>
              <option value="5">5 min</option>
              <option value="10">10 min</option>
              <option value="15">15 min</option>
              <option value="30">30 min</option>
              <option value="60">1 hour</option>
            </select>
            {sleepTimeRemaining !== null && (
              <span className="text-xs text-amber-400 min-w-[3rem] text-right">
                {Math.floor(sleepTimeRemaining / 60)}:{String(sleepTimeRemaining % 60).padStart(2, '0')}
              </span>
            )}
          </div>
        </div>

        {/* Control Buttons */}
        <div className="flex items-center justify-center gap-4 px-6 py-6">
          <button
            onClick={handlePreviousChapter}
            className="p-3 hover:bg-slate-700 rounded-full transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            disabled={currentChapterIndex === 0}
            aria-label="Previous chapter"
          >
            <SkipBack className="w-6 h-6" />
          </button>
          
          <button
            onClick={handlePlayPause}
            className="p-5 bg-amber-500 hover:bg-amber-600 rounded-full transition-colors"
            aria-label={isPlaying ? 'Pause' : 'Play'}
          >
            {isPlaying ? (
              <Pause className="w-8 h-8 text-slate-900" fill="currentColor" />
            ) : (
              <Play className="w-8 h-8 text-slate-900" fill="currentColor" />
            )}
          </button>
          
          <button
            onClick={handleNextChapter}
            className="p-3 hover:bg-slate-700 rounded-full transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            disabled={currentChapterIndex === chapters.length - 1}
            aria-label="Next chapter"
          >
            <SkipForward className="w-6 h-6" />
          </button>
        </div>
      </div>
    </div>
  );
}