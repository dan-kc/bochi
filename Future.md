Give me ideas for a good formula for calculating:

- The cost of a reward
- The amount earned from a habit

# Habit formula draft

Total = 100 \* F \* D \* R \* G

where
G = General Difficulty; 0<G<1000;
D = Difficutly: 0<D<1;
R = Random: 0.9<R<1.1;
F = Frequency: 0<F<1;

All G, D,R,F can be made into different seperate fomulae.

G will be a variable stored on the users account. The user should be able to change this manually. It should store locally and be synced local-first like the habits.

D will be derived from the habits relative position among other habits in terms of difficulty. If it is the 2nd most difficult habit out of 51 habits then D = (51 - 1) / 51. This will have values linearly from 0 to 1, but I need you to edit it such that 0 is never hit. The habit reward amount should always be strictly positive.

R is a random number distributed linearly.

F is a calculation of actual frequency vs desired frequency. If a habit has been done too much then the reward price should decrease. I want this to be non-liner, not sure what to do. I want it to dramatically increase/decrease if the actual freq is wildly too big/small, but still stay within the range. I also want the formula to take into consideration the possibility that the habit was just created. In this case i do not want to dramatically influence the habits price, there needs to be some factor of when the habit was created too.


