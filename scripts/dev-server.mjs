// Tiny stand-in for the Supabase API so the web app can run against the local
// Postgres from scripts/local-db.sh without Docker. Implements just enough of
// GoTrue (email+password) and PostgREST (POST /rest/v1/rpc/<fn>) for this game.
// Not for production. Usage: node scripts/dev-server.mjs   (listens on :54321)
import http from 'node:http'
import crypto from 'node:crypto'
import pg from 'pg'

const PORT = Number(process.env.PORT || 54321)
const SECRET = 'local-dev-secret'
const pool = new pg.Pool({
  host: process.env.PGHOST || 'localhost', port: Number(process.env.PGPORT || 54329),
  user: process.env.PGUSER || 'postgres', database: process.env.PGDATABASE || 'cartel',
})

const b64 = s => Buffer.from(s).toString('base64url')
function jwt(sub, email) {
  const now = Math.floor(Date.now() / 1000)
  const h = b64(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const p = b64(JSON.stringify({ sub, email, role: 'authenticated', aud: 'authenticated', iat: now, exp: now + 3600 }))
  const sig = crypto.createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url')
  return `${h}.${p}.${sig}`
}
function verify(token) {
  if (!token) return null
  const [h, p, sig] = token.split('.')
  const good = crypto.createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url')
  if (sig !== good) return null
  return JSON.parse(Buffer.from(p, 'base64url').toString())
}
const session = (u) => ({
  access_token: jwt(u.id, u.email), token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600,
  refresh_token: 'rt-' + u.id, user: userObj(u),
})
const userObj = (u) => ({ id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email, email_confirmed_at: u.created_at,
  app_metadata: { provider: 'email' }, user_metadata: u.raw_user_meta_data, created_at: u.created_at, updated_at: u.created_at, identities: [] })

// ensure a password column on the auth stub
await pool.query(`alter table auth.users add column if not exists password text`)

const argCache = new Map()
async function fnArgs(fn) {
  if (argCache.has(fn)) return argCache.get(fn)
  const { rows } = await pool.query(
    `select p.proargnames as names, array(select format_type(t, null) from unnest(p.proargtypes) t) as types
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = $1 limit 1`, [fn])
  const v = rows[0] ? { names: rows[0].names || [], types: rows[0].types } : null
  argCache.set(fn, v)
  return v
}

async function rpc(fn, args, claims) {
  const sig = await fnArgs(fn)
  if (!sig) throw Object.assign(new Error(`function ${fn} not found`), { status: 404 })
  const parts = [], vals = []
  sig.names.forEach((name, i) => {
    if (!(name in args)) return
    const v = args[name]
    vals.push(v === null || v === undefined ? null : typeof v === 'object' ? JSON.stringify(v) : String(v))
    parts.push(`${name} := $${vals.length}::${sig.types[i]}`)
  })
  const client = await pool.connect()
  try {
    await client.query('begin')
    await client.query(`select set_config('request.jwt.claims', $1, true)`, [claims ? JSON.stringify(claims) : ''])
    const { rows } = await client.query(`select public.${fn}(${parts.join(', ')}) as r`, vals)
    await client.query('commit')
    return rows[0].r
  } catch (e) {
    await client.query('rollback').catch(() => {})
    throw e
  } finally { client.release() }
}

const json = (res, status, body) => { res.writeHead(status, { 'content-type': 'application/json', ...cors }); res.end(body === undefined ? '' : JSON.stringify(body)) }
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS' }
const readBody = req => new Promise(r => { let s = ''; req.on('data', c => s += c); req.on('end', () => r(s ? JSON.parse(s) : {})) })

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x')
  if (req.method === 'OPTIONS') return json(res, 204)
  try {
    const token = (req.headers.authorization || '').replace(/^Bearer /, '')
    // ---- auth ----
    if (url.pathname === '/auth/v1/signup' && req.method === 'POST') {
      const b = await readBody(req)
      const id = crypto.randomUUID()
      await pool.query(`insert into auth.users (id, email, raw_user_meta_data, password) values ($1, $2, $3, $4)`, [id, b.email, b.data || {}, b.password])
      const { rows } = await pool.query(`select * from auth.users where id = $1`, [id])
      return json(res, 200, session(rows[0]))
    }
    if (url.pathname === '/auth/v1/token' && req.method === 'POST') {
      const b = await readBody(req)
      const grant = url.searchParams.get('grant_type')
      let rows
      if (grant === 'password') ({ rows } = await pool.query(`select * from auth.users where email = $1 and password = $2`, [b.email, b.password]))
      else if (grant === 'refresh_token') ({ rows } = await pool.query(`select * from auth.users where id = $1`, [String(b.refresh_token).replace(/^rt-/, '')]))
      if (!rows?.[0]) return json(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials', error_code: 'invalid_credentials' })
      return json(res, 200, session(rows[0]))
    }
    if (url.pathname === '/auth/v1/logout') return json(res, 204)
    if (url.pathname === '/auth/v1/user') {
      const c = verify(token); if (!c) return json(res, 401, { msg: 'invalid token' })
      const { rows } = await pool.query(`select * from auth.users where id = $1`, [c.sub])
      return json(res, 200, userObj(rows[0]))
    }
    // ---- rpc ----
    const m = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z_0-9]+)$/)
    if (m && req.method === 'POST') {
      const claims = verify(token)
      const args = await readBody(req)
      try {
        const r = await rpc(m[1], args, claims)
        return json(res, 200, r)
      } catch (e) {
        if (e.status) return json(res, e.status, { message: e.message, code: 'PGRST202', details: null, hint: null })
        return json(res, 400, { message: e.message, code: e.code || 'P0001', details: e.detail || null, hint: e.hint || null })
      }
    }
    json(res, 404, { message: 'not found' })
  } catch (e) {
    console.error(e)
    json(res, 500, { message: e.message })
  }
}).listen(PORT, () => console.log(`dev API on http://localhost:${PORT} → postgres ${pool.options.host}:${pool.options.port}/${pool.options.database}`))
