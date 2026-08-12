// Shared XP -> Skill Point conversion, used on the Characters page and
// the Current Event Training tab. The conversion rate gets worse as a
// character invests more Skill Points overall (starting SP plus SP
// already spent), matching the tiered rates in the rulebook.
function faXpPerSp(investedSp){
  if(investedSp <= 40) return 10;
  if(investedSp <= 80) return 15;
  if(investedSp <= 150) return 20;
  if(investedSp <= 200) return 25;
  return 30;
}

// Converts a character's banked XP into spendable Skill Points.
//   rate           - XP required per SP at the character's current tier
//   xpConvertedSp  - whole SP unlocked so far by converting XP
//   leftoverXp     - XP banked but not yet enough for another SP
//   totalPool      - starting SP plus SP unlocked from XP
//   spendableSp    - totalPool minus SP already spent on skills
function faConvertXpToSp(xpBalance, startingSp, spentSp){
  const rate = faXpPerSp(startingSp + spentSp);
  const xpConvertedSp = Math.floor(xpBalance / rate);
  const leftoverXp = xpBalance - xpConvertedSp * rate;
  const totalPool = startingSp + xpConvertedSp;
  const spendableSp = Math.max(0, totalPool - spentSp);
  return { rate, xpConvertedSp, leftoverXp, totalPool, spendableSp, xpBalance };
}

window.faXpPerSp = faXpPerSp;
window.faConvertXpToSp = faConvertXpToSp;
