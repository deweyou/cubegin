export const uuidPattern = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i

export function feedbackText(message, fields, origin) {
  if (origin || fields.source === 'web') return message + '\n\n来源：Web'
  if (fields.source !== 'ios') return message + '\n\n来源：未知（客户端未提供）'

  const label = value => typeof value === 'string' && /^[\p{L}\p{N} .,()_-]{1,80}$/u.test(value) ? value : '未知'
  const id = value => typeof value === 'string' && uuidPattern.test(value) ? value : '不可用'
  return [message, '', `来源：${label(fields.deviceModel)} · ${label(fields.systemVersion)}`,
    `App 版本：${label(fields.appVersion)}`, `设备 ID：${id(fields.deviceId)}`,
    `用户 ID：${id(fields.userId)}`].join('\n')
}
