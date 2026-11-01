// 图片处理工具：浏览器端压缩 + 上传到 Supabase Storage
// 省流量策略：页面一律显示小缩略图（480px），点开预览/下载原图才加载大文件
import { ElMessage } from 'element-plus'
import { supabase } from './supabase'

// 用 canvas 把图片等比缩到最长边 maxEdge 以内，输出 JPEG
export async function compressImage(file, maxEdge = 480, quality = 0.75) {
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
    return file // 解码失败（如不支持的格式）时退回原文件
  }
}

// 上传评论配图：原图 + 小缩略图各存一份，返回 [{ thumb, original }]
// thumb（480px）用于页面展示和省流量；original 供"下载原图"和点击放大
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
    const thumb = await compressImage(file, 480, 0.75)
    const thumbPath = `thumbs/${ts}.jpg`
    const { error: e2 } = await supabase.storage.from('images').upload(thumbPath, thumb)
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

// 题目编辑器配图：只存一份 web 版（1600px），Markdown 里引用它
// 手机照片直传动辄 3~8MB，压完通常 100~300KB
export async function uploadProblemImage(file) {
  const compressed = await compressImage(file, 1600, 0.8)
  const path = `${Date.now()}-${compressed.name}`
  const { error } = await supabase.storage.from('images').upload(path, compressed)
  if (error) {
    ElMessage.error(`图片上传失败：${error.message}`)
    return null
  }
  const { data } = supabase.storage.from('images').getPublicUrl(path)
  return data.publicUrl
}
