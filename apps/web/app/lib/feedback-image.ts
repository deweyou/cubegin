export const maxScreenshots = 3
export const maxScreenshotBytes = 1_000_000

export async function compressScreenshot(file: File): Promise<Blob> {
  if (!['image/jpeg', 'image/png'].includes(file.type) || file.size > 25_000_000) {
    throw new Error('Unsupported screenshot')
  }

  const image = await createImageBitmap(file)
  const canvas = document.createElement('canvas')
  try {
    const context = canvas.getContext('2d', { alpha: false })
    if (!context) throw new Error('Could not initialize image processing')

    const longestSide = Math.max(image.width, image.height)
    let scale = Math.min(1, 2048 / longestSide)
    for (let attempt = 0; attempt < 6; attempt += 1) {
      canvas.width = Math.max(1, Math.round(image.width * scale))
      canvas.height = Math.max(1, Math.round(image.height * scale))
      context.fillStyle = '#fff'
      context.fillRect(0, 0, canvas.width, canvas.height)
      context.drawImage(image, 0, 0, canvas.width, canvas.height)
      const jpeg = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.87))
      if (jpeg?.type === 'image/jpeg' && jpeg.size <= maxScreenshotBytes) return jpeg
      scale *= 0.78
    }
    throw new Error('Could not compress screenshot')
  } finally {
    image.close()
  }
}
