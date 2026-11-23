import { DurableObject } from 'cloudflare:workers'

const hour = 60 * 60 * 1000
const maxPerHour = 30

export class FeedbackDeliveryLimit extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env)
    this.sql = ctx.storage.sql
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS deliveries (
        request_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    `)
    this.sql.exec('CREATE INDEX IF NOT EXISTS delivery_expiry ON deliveries(updated_at)')
    this.sql.exec('CREATE TABLE IF NOT EXISTS attempts (attempted_at INTEGER NOT NULL)')
  }

  reserve(requestId) {
    return this.ctx.storage.transactionSync(() => {
      const now = Date.now()
      this.sql.exec('DELETE FROM deliveries WHERE updated_at <= ?', now - 24 * hour)
      const previous = this.sql.exec('SELECT status FROM deliveries WHERE request_id = ?', requestId).toArray()[0]
      if (previous?.status === 'sent' || previous?.status === 'pending') return previous.status

      this.sql.exec('DELETE FROM attempts WHERE attempted_at <= ?', now - hour)
      const { count, oldest } = this.sql.exec('SELECT COUNT(*) AS count, MIN(attempted_at) AS oldest FROM attempts').one()
      if (count >= maxPerHour) {
        return { retryAfter: Math.max(1, Math.ceil((oldest + hour - now) / 1000)) }
      }
      this.sql.exec('INSERT INTO attempts VALUES (?)', now)
      this.sql.exec(`
        INSERT INTO deliveries VALUES (?, 'pending', ?)
        ON CONFLICT(request_id) DO UPDATE SET status = 'pending', updated_at = excluded.updated_at
      `, requestId, now)
      return 'reserved'
    })
  }

  finish(requestId, status) {
    this.sql.exec('UPDATE deliveries SET status = ?, updated_at = ? WHERE request_id = ?', status, Date.now(), requestId)
  }
}
