# SpellingBeeHints
A Perl script to offer hints for solving the New York Times' Spelling Bee puzzle.

This is a hints generator for the New York Times' Spelling Bee (https://www.nytimes.com/puzzles/spelling-bee). It wont solve the puzzle for you, but it will offer you an escalating series of hints to help you narrow down the words you're missing — so you, too, can be a Genius or a Queen Bee.

The script grabs a list of that day's answers downloaded from the analysis site https://www.nytbee.com and compares them with the player's own answers, which the player must place in file called *words.txt*. Both files must be stored in a */lib* subfolder (these settings can, of course, be changed in the script).

## It offers four kinds of hints:

- How many more words of various lengths (4 letters, 5 letters, etc.) remain?
- How many more words remain that beginning with each letter?
- How many missing words remain in between the already-found answers? This hint will also tell you if you found the first and last words.
- How many more words remain that begin with various two-letter pairs?

## How to play:

1) Open up the Spelling Bee and start playing. After you've found some words, copy and paste your answers into */lib/words.txt*.
2) Run the script. It will download the answers from NYTBee and cache them in a file called */lib/answersYYYY-MM-DD.txt* (the YYYY-MM-DD is replaced by today's date).
3) After each hint, the script will ask you if you want the next hint. If not, simply type any word not starting in "Y."
4) As you find new words, copy them into the *words.txt* file and run the script again.
5) Rinse and repeat.

The script is flexible enough to add other hints that people may suggest. Any suggested adds? Let me know.
