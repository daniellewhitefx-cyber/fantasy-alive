function faXpPerSp(investedSp){
  if(investedSp <= 40) return 10;
  if(investedSp <= 80) return 15;
  if(investedSp <= 150) return 20;
  if(investedSp <= 200) return 25;
  return 30;
}

const FA_XP_SP_TIERS = [
  { ceiling: 40, rate: 10 },
  { ceiling: 80, rate: 15 },
  { ceiling: 150, rate: 20 },
  { ceiling: 200, rate: 25 },
  { ceiling: Infinity, rate: 30 }
];

function faConvertXpToSp(xpBalance, startingSp, spentSp){
  let currentSp = startingSp;
  let remainingXp = xpBalance;
  let xpConvertedSp = 0;

  for(const tier of FA_XP_SP_TIERS){
    if(remainingXp <= 0) break;
    if(currentSp >= tier.ceiling) continue;
    const capacitySp = tier.ceiling - currentSp;
    const affordableSp = Math.floor(remainingXp / tier.rate);
    const spThisTier = Math.min(capacitySp, affordableSp);
    xpConvertedSp += spThisTier;
    currentSp += spThisTier;
    remainingXp -= spThisTier * tier.rate;
  }

  const leftoverXp = remainingXp;
  const totalPool = startingSp + xpConvertedSp;
  const spendableSp = Math.max(0, totalPool - spentSp);
  const rate = faXpPerSp(totalPool);
  return { rate, xpConvertedSp, leftoverXp, totalPool, spendableSp, xpBalance };
}

function faXpCostForSp(currentTotalSp, additionalSp){
  let currentSp = currentTotalSp;
  let remainingSp = additionalSp;
  let totalXp = 0;

  for(const tier of FA_XP_SP_TIERS){
    if(remainingSp <= 0) break;
    if(currentSp >= tier.ceiling) continue;
    const spThisTier = Math.min(tier.ceiling - currentSp, remainingSp);
    totalXp += spThisTier * tier.rate;
    currentSp += spThisTier;
    remainingSp -= spThisTier;
  }

  return totalXp;
}

window.faXpPerSp = faXpPerSp;
window.faConvertXpToSp = faConvertXpToSp;
window.faXpCostForSp = faXpCostForSp;
