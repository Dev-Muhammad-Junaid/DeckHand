// Cloudflare Pages Function: POST /api/waitlist
//
// Stores one KV entry per address under the `WAITLIST` binding:
//   key   email:<address, lowercased>
//   value {"email","joinedAt","country","source"}
//
// Bind a KV namespace named WAITLIST to the Pages project (Settings →
// Bindings) before deploying. Export with:
//   npx wrangler kv key list --namespace-id <id>

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export async function onRequestPost({ request, env }) {
  const wantsJSON = (request.headers.get('content-type') || '').includes('application/json');

  if (!env.WAITLIST) {
    return reply(wantsJSON, { ok: false, error: 'not_configured' }, 503);
  }

  let data;
  try {
    data = wantsJSON ? await request.json() : Object.fromEntries(await request.formData());
  } catch {
    return reply(wantsJSON, { ok: false, error: 'bad_request' }, 400);
  }

  // People never see this field; form-filling bots do. Pretend it worked.
  if (data.company) {
    return reply(wantsJSON, { ok: true, already: false }, 200);
  }

  const email = String(data.email || '').trim().toLowerCase();
  if (email.length > 254 || !EMAIL.test(email)) {
    return reply(wantsJSON, { ok: false, error: 'invalid_email' }, 400);
  }

  const key = `email:${email}`;
  const existing = await env.WAITLIST.get(key);
  if (!existing) {
    await env.WAITLIST.put(key, JSON.stringify({
      email,
      joinedAt: new Date().toISOString(),
      country: request.cf?.country ?? null,
      source: String(data.source || '').slice(0, 40),
    }));
  }

  return reply(wantsJSON, { ok: true, already: Boolean(existing) }, 200);
}

// Without JavaScript the browser posts the form directly, so send it to a
// page instead of showing raw JSON.
function reply(wantsJSON, body, status) {
  if (wantsJSON) {
    return new Response(JSON.stringify(body), {
      status,
      headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
    });
  }
  const page = body.ok ? '/joined' : body.error === 'invalid_email' ? '/joined?error=email' : '/joined?error=server';
  return new Response(null, { status: 303, headers: { location: page } });
}
