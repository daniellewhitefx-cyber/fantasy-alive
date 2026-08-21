function faXpPerSp(investedSp){
  if(investedSp <= 40) return 10;
  if(investedSp <= 80) return 15;
  if(investedSp <= 150) return 20;
  if(investedSp <= 200) return 25;
  return 30;
}

function faConvertXpToSp(xpBalance, startingSp, spentSp){
  const rate = faXpPerSp(spentSp);
  const xpConvertedSp = Math.floor(xpBalance / rate);
  const leftoverXp = xpBalance - xpConvertedSp * rate;
  const totalPool = startingSp + xpConvertedSp;
  const spendableSp = Math.max(0, totalPool - spentSp);
  return { rate, xpConvertedSp, leftoverXp, totalPool, spendableSp, xpBalance };
}

window.faXpPerSp = faXpPerSp;
window.faConvertXpToSp = faConvertXpToSp;
