import { useState, useEffect } from 'react';
import { Play, Pause, SkipBack, SkipForward, ChevronLeft, ChevronRight, ChevronUp, ChevronDown, RotateCcw, Clock, Share2 } from 'lucide-react';

export default function App() {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(24);
  const [totalTime] = useState(63);
  const [playbackSpeed, setPlaybackSpeed] = useState(1.0);
  const [sleepTimer, setSleepTimer] = useState('Off');
  const [isLandscape, setIsLandscape] = useState(false);

  useEffect(() => {
    const checkOrientation = () => {
      setIsLandscape(window.innerWidth > window.innerHeight);
    };
    
    checkOrientation();
    window.addEventListener('resize', checkOrientation);
    return () => window.removeEventListener('resize', checkOrientation);
  }, []);

  const progress = (currentTime / totalTime) * 100;

  const togglePlayPause = () => {
    setIsPlaying(!isPlaying);
  };

  const changeSpeed = (direction: 'up' | 'down') => {
    if (direction === 'up') {
      setPlaybackSpeed(prev => Math.min(prev + 0.1, 3.0));
    } else {
      setPlaybackSpeed(prev => Math.max(prev - 0.1, 0.5));
    }
  };

  return (
    <div className={`h-screen w-screen bg-[#0f1c2e] text-white overflow-hidden ${isLandscape ? 'flex' : 'flex flex-col'}`}>
      {/* Header - only show in portrait */}
      {!isLandscape && (
        <header className="flex items-center justify-between p-4 flex-shrink-0">
          <button className="p-2">
            <ChevronLeft className="w-6 h-6" />
          </button>
          <div className="flex-1 text-center">
            <h1 className="text-lg font-semibold">Alice's Adventures in Wonderland</h1>
            <p className="text-sm text-gray-400">CHAPTER I. Down the Rabbit-Hole</p>
          </div>
          <button className="p-2">
            <Share2 className="w-6 h-6" />
          </button>
        </header>
      )}

      {/* Content Area */}
      <div className={`flex-1 overflow-auto p-6 ${isLandscape ? 'pr-32 pb-32' : 'pb-4'}`}>
        <div className="text-gray-400 text-sm space-y-4 max-w-3xl">
          <p>
            curtsey as she spoke-fancy curtseying as you're falling through the air!
          </p>
          <p className="text-yellow-500">
            Do you think you could manage it?) "And what an ignorant little girl she'll think me for asking!
          </p>
          <p>
            No, it'll never do to ask: perhaps I shall see it written up somewhere." Down, down, down. There was nothing else to do, so Alice soon began talking again. "Dinah'll miss me very much to-night, I should think!" (Dinah was the cat.) "I hope they'll remember her saucer of milk at tea-time. Dinah my dear! I wish you were down here with me! (synthesizing...)
          </p>
          <p>
            There are no mice in the air, I'm afraid, but you might catch a bat, and that's very like a mouse, you know. But do cats eat bats, I wonder?" And here Alice began to get rather sleepy, and went on saying to herself, in a dreamy sort of way, "Do cats eat bats? Do cats eat bats?" and sometimes, "Do bats eat cats?" for, you see, as she couldn't answer either question, it didn't much matter which way she put it. She felt that she was dozing off, and had just begun to dream that she was walking hand in hand with Dinah, and saying to her very earnestly, "Now, Dinah, tell me the truth: did you ever eat a bat?" when suddenly, thump! thump! down she came upon a heap of sticks and dry leaves, and the fall was over.
          </p>
          <p>
            Alice was not a bit hurt, and she jumped up on to her feet in a moment: she looked up, but it was all dark overhead; before her was another long passage, and the White Rabbit was still in sight, hurrying down it. There was not a moment to be lost: away went Alice like the wind, and was just in time to hear it say, as it turned a corner, "Oh my ears and whiskers, how late it's getting!" She was close behind it when she turned the corner, but the Rabbit was no longer to be seen: she found herself in a long, low hall, which was lit up by a row of lamps hanging from the roof.
          </p>
        </div>

        {/* Resume auto-scroll button */}
        <button className={`fixed bg-yellow-500 text-black px-6 py-3 rounded-full flex items-center gap-2 shadow-lg ${isLandscape ? 'bottom-36 right-32' : 'bottom-32 right-6'}`}>
          <RotateCcw className="w-5 h-5" />
          Resume auto-scroll
        </button>
      </div>

      {/* Controls Section */}
      {isLandscape ? (
        /* Landscape: Vertical controls on the right */
        <div className="fixed right-0 top-0 bottom-0 w-28 bg-[#0a1420] flex flex-col items-center justify-center gap-6 py-8">
          {/* Skip to start */}
          <button className="text-white">
            <SkipBack className="w-8 h-8 fill-white" />
          </button>

          {/* Rewind - up arrow */}
          <button className="text-white">
            <ChevronUp className="w-8 h-8" strokeWidth={3} />
          </button>

          {/* Play/Pause */}
          <button 
            onClick={togglePlayPause}
            className="bg-yellow-500 rounded-full p-6"
          >
            {isPlaying ? (
              <Pause className="w-10 h-10 fill-black text-black" />
            ) : (
              <Play className="w-10 h-10 fill-black text-black" />
            )}
          </button>

          {/* Fast forward - down arrow */}
          <button className="text-white">
            <ChevronDown className="w-8 h-8" strokeWidth={3} />
          </button>

          {/* Skip to end */}
          <button className="text-white">
            <SkipForward className="w-8 h-8 fill-white" />
          </button>
        </div>
      ) : (
        /* Portrait: Horizontal controls at bottom */
        <>
          {/* Progress bar and controls */}
          <div className="bg-[#0a1420] px-6 pb-6 flex-shrink-0">
            {/* Progress bar */}
            <div className="mb-6">
              <div className="flex justify-between text-sm mb-2">
                <span>{currentTime}</span>
                <span>{totalTime}</span>
              </div>
              <div className="h-1 bg-gray-700 rounded-full overflow-hidden">
                <div 
                  className="h-full bg-yellow-500 rounded-full transition-all"
                  style={{ width: `${progress}%` }}
                />
              </div>
            </div>

            {/* Speed and timer controls */}
            <div className="flex justify-between items-center mb-6">
              <div className="flex items-center gap-2">
                <button onClick={() => changeSpeed('down')}>
                  <RotateCcw className="w-5 h-5" />
                </button>
                <button onClick={() => changeSpeed('down')}>
                  <ChevronLeft className="w-5 h-5" />
                </button>
                <span className="text-sm w-12 text-center">{playbackSpeed.toFixed(1)}x</span>
                <button onClick={() => changeSpeed('up')}>
                  <ChevronRight className="w-5 h-5" />
                </button>
              </div>

              <div className="flex items-center gap-2">
                <Clock className="w-5 h-5" />
                <button className="text-sm bg-gray-700 px-3 py-1 rounded">
                  {sleepTimer}
                  <ChevronRight className="w-4 h-4 inline ml-1" />
                </button>
              </div>
            </div>

            {/* Playback controls */}
            <div className="flex items-center justify-center gap-4">
              <button className="text-white">
                <SkipBack className="w-8 h-8 fill-white" />
              </button>

              <button className="text-white">
                <ChevronLeft className="w-8 h-8" strokeWidth={3} />
              </button>

              <button 
                onClick={togglePlayPause}
                className="bg-yellow-500 rounded-full p-5"
              >
                {isPlaying ? (
                  <Pause className="w-12 h-12 fill-black text-black" />
                ) : (
                  <Play className="w-12 h-12 fill-black text-black" />
                )}
              </button>

              <button className="text-white">
                <ChevronRight className="w-8 h-8" strokeWidth={3} />
              </button>

              <button className="text-white">
                <SkipForward className="w-8 h-8 fill-white" />
              </button>
            </div>
          </div>
        </>
      )}

      {/* Landscape: Progress bar at bottom */}
      {isLandscape && (
        <div className="fixed bottom-0 left-0 right-28 bg-[#0a1420] px-6 py-4">
          <div className="flex justify-between text-sm mb-2">
            <span>{currentTime}</span>
            <span>{totalTime}</span>
          </div>
          <div className="h-1 bg-gray-700 rounded-full overflow-hidden">
            <div 
              className="h-full bg-yellow-500 rounded-full transition-all"
              style={{ width: `${progress}%` }}
            />
          </div>

          {/* Speed and timer controls */}
          <div className="flex justify-between items-center mt-4">
            <div className="flex items-center gap-2">
              <button onClick={() => changeSpeed('down')}>
                <RotateCcw className="w-5 h-5" />
              </button>
              <button onClick={() => changeSpeed('down')}>
                <ChevronLeft className="w-5 h-5" />
              </button>
              <span className="text-sm w-12 text-center">{playbackSpeed.toFixed(1)}x</span>
              <button onClick={() => changeSpeed('up')}>
                <ChevronRight className="w-5 h-5" />
              </button>
            </div>

            <div className="flex items-center gap-2">
              <Clock className="w-5 h-5" />
              <button className="text-sm bg-gray-700 px-3 py-1 rounded">
                {sleepTimer}
                <ChevronRight className="w-4 h-4 inline ml-1" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}