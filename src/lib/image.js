// 图片处理工具：浏览器端压缩 + 上传原图/缩略图到 Supabase Storage
import { ElMessage } from 'element-plus'
import { supabase } from './supabase'

// 用 canvas 把图片压缩到最长边 maxEdge 以内，输出 JPEG
export async function compressImage(file, maxEdge = 1600, quality = 0.82) {
  try {
    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement('canvas')
    canvas.width = Math.max(1, Math.round(bitmap.width * scale))
    canvas.height = Math.max(1, Math.round(bitmap.height * scale))
    canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality))
    if (!blob) return file
    return new File([blob], 'compressed.jpg', { type: 'image/jpeg' })
  } catch {
    return file // 非浏览器环境或解码失败时退回原文件
  }
}

// 上传一组图片：原图 + 压缩图各存一份，返回 [{ thumb, original }]
export async function uploadImages(files) {
  const results = []
  for (const file of files) {
    const ts = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
    const origPath = `originals/${ts}-${file.name}`
    const { error: e1 } = await supabase.storage.from('images').upload(origPath, file)
    if (e1) {
      ElMessage.error(`图片上传失败：${e1.message}`)
      continue
    }
    const compressed = await compressImage(file)
    const thumbPath = `thumbs/${ts}.jpg`
    const { error: e2 } = await supabase.storage.from('images').upload(thumbPath, compressed)
    if (e2) {
      ElMessage.error(`缩略图上传失败：${e2.message}`)
      continue
    }
    const { data: o } = supabase.storage.from('images').getPublicUrl(origPath)
    const { data: t } = supabase.storage.from('images').getPublicUrl(thumbPath)
    results.push({ thumb: t.publicUrl, original: o.publicUrl })
  }
  return results
}
