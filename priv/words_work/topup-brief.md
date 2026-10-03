# Sketchy word dataset: TOP-UP writer brief

You are adding NEW words to ONE category of the word dataset for "Sketchy", a multiplayer party
drawing game with an imposter. The dataset already has ~1,490 words; a strict review removed ~250
weak ones, and your job is to add more GOOD ones. Your category, scope, how many to write, and
file names are in your task message.

## How the game uses the data
- Everyone is shown the CATEGORY.
- Every player except one (the imposter) is shown the secret WORD and must draw something that
  proves they know it, without making it too obvious to the imposter.
- The imposter is NOT shown the word. They get ONE random HINT of the 3, so they can blend in by
  drawing something plausible; the group tries to catch them.
So words must be FUN and QUICK TO DRAW, and hints must help the imposter without giving it away.
Real people will play this at parties: quality matters more than speed.

## Format
A JSON array, one entry per line, exactly:
{ "category": "Animals", "word": "Giraffe", "difficulty": "easy", "hints": ["tall", "savanna", "spots"] }
- "category": exactly your category name.
- "word": Title Case, 1 to 2 words (letters, spaces, hyphens only).
- "difficulty": "easy" (stick-figure sketch is instantly recognizable), "medium", or "hard".
  Aim for roughly 65% easy, 27% medium, 8% hard.
- "hints": exactly 3 strings, lowercase, 1 to 3 words each (letters, spaces, hyphens only).

## What a reviewer already rejected (learn from it, do NOT repeat these mistakes)
1. SAME DRAWING AS ANOTHER WORD. This was the #1 reason for cuts (about 60% of all cuts). If a
   non-artist would draw your word the same way as an existing word (any category), it is a
   duplicate even though the names differ. Examples of rejected pairs: Glasses/Sunglasses,
   Bus/Double Decker, Walrus/Manatee, Car/Taxi, Ballet/Ballerina, Hourglass/Sand Timer,
   Juggling/Juggler, Merry-Go-Round/Carousel, Kayaking/Canoe, Armor/Knight Armor.
   BEFORE you pick a word, think "what would the sketch look like?" and check the used list for
   anything that would look the same. Names that contain another word ("Toy Wagon", "Wedding Veil")
   are usually the same drawing too.
2. SHAPELESS BLOBS. Words that are a plain circle, rectangle, bean or lump with nothing
   distinctive (Cashew, Kidney, Scone, Mochi, Truffle, Blanket, Gold Coin). A good word has a
   signature feature you can sketch (a giraffe's neck, a pirate's eye patch).
3. DRINKS/BOTTLES/CUPS/BOXES that all look alike (a glass with a straw is a glass with a straw).
4. NEEDS A LABEL: shops/places that need a sign to be recognized, anything with text.
5. OBSCURE OR REGIONAL: words known mainly in one country (Clothes Peg, Takeaway Coffee,
   Jackalope). Use words most English-speaking teenagers and adults know.
6. OFF-CATEGORY filler. Stay inside your scope.
7. HINTS THAT GIVE IT AWAY IN ONE WORD: "carrot" for Rabbit, "gives milk" for Cow, "torch" for
   Statue of Liberty, "eighteen wheels" for Semi Truck, "skull flag" for Pirate Ship, "long
   race" for Marathon (defines the word). A hint should still leave SEVERAL plausible words.
8. HINTS THAT ALL DESCRIBE THE SAME ASPECT (all about looks). Mix: one about look/shape, one about
   where/when it is found, one about what it does or how it is used.

## Rules for words
- Easy-to-draw test: recognizable with 3-5 simple shapes by a non-artist in 15-30 seconds.
- Prefer iconic silhouettes, personality, and a bit of silliness, plus some plain everyday items.
- Spread across the whole scope of your category.
- Family-friendly; no brands, no real people; common knowledge.
- Must NOT be any word in the USED/REJECTED list (see task message), and must not be a
  plural/variant of one. Rejected words were rejected for a reason: do not bring them back.

## Rules for hints
- TRUE of the word but must NOT contain the word, any piece of it, a plural/variant, or a synonym.
- Each hint alone (plus the category) must leave several plausible words.
- Three DIFFERENT aspects; no lazy filler ("big", "common", "thing", "nice").

## Process
1. Read the USED/REJECTED words file and the dataset file (read-only) for your category and for
   neighboring categories, so you know what already exists and what would look the same.
2. Brainstorm MORE candidates than you need (about 2x). For each, picture the sketch; cut anything
   that would look like an existing word, is a blob, is obscure, or off-scope.
3. Write your entries with the Write tool, then validate:
   python3 <validator> --category "<Category>" --expect <N> --skip <dataset file> <your file>
   The validator checks structure, hint leaks, duplicates, and that none of your words is already
   in the dataset file. Fix every problem and re-run until it prints "OK".
4. Re-read your file once as a skeptical reviewer applying the rejection list above. Replace weak
   entries, then validate again.
