async function stripImageExif(file){
  if(!file || !file.type || !file.type.startsWith('image/')) return file;
  if(file.type === 'image/svg+xml' || file.type === 'image/gif') return file;
  if(typeof createImageBitmap !== 'function') return file;

  try{
    const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
    const canvas = document.createElement('canvas');
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(bitmap, 0, 0);
    bitmap.close();

    const outputType = file.type === 'image/png' ? 'image/png' : 'image/jpeg';
    const quality = outputType === 'image/jpeg' ? 0.92 : undefined;
    const blob = await new Promise(resolve => canvas.toBlob(resolve, outputType, quality));
    if(!blob) return file;

    const ext = outputType === 'image/png' ? 'png' : 'jpg';
    const baseName = (file.name || 'image').replace(/\.[^./\\]+$/, '');
    return new File([blob], baseName + '.' + ext, { type: outputType });
  } catch(err){
    return file;
  }
}
window.stripImageExif = stripImageExif;
