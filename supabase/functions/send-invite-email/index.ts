// Emails a LOVA team invite via Resend.
//
// The client only ever supplies the invite TOKEN, never the target
// email/role/org directly -- everything the email needs is looked up
// server-side from the `invites` row itself, after confirming the
// caller's own profile belongs to that invite's organization. Since
// only an org owner can INSERT into `invites` in the first place (see
// the identity_and_org migration's RLS policy), reaching this point at
// all already proves the caller legitimately created that invite.
import { createClient } from 'jsr:@supabase/supabase-js@2.116.0'

const FROM_ADDRESS = 'LOVA <onboarding@resend.dev>'
// Same sandbox-domain caveat as send-notification-email: only delivers
// to the Resend account's own verified address until a real domain
// (e.g. lenusa.id) is verified at resend.com/domains.

const DEFAULT_APP_ORIGIN = 'https://lova-lenusa.netlify.app'
const ALLOWED_APP_ORIGINS = [DEFAULT_APP_ORIGIN, 'http://localhost:8888', 'http://localhost:3000']

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { inviteToken, appUrl } = await req.json()
    if (!inviteToken) return json({ error: 'inviteToken is required' }, 400)

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'missing Authorization header' }, 401)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user: caller } } = await supabase.auth.getUser()
    if (!caller) return json({ error: 'unauthorized' }, 401)

    const { data: invite } = await supabase
      .from('invites')
      .select('email, role, org_id, accepted_at, expires_at, organizations(name)')
      .eq('token', inviteToken)
      .maybeSingle()
    if (!invite) return json({ error: 'invite not found' }, 404)
    if (invite.accepted_at) return json({ error: 'invite already accepted' }, 409)
    if (invite.expires_at && new Date(invite.expires_at) < new Date()) return json({ error: 'invite expired' }, 410)

    const { data: callerProfile } = await supabase.from('profiles').select('org_id, name').eq('id', caller.id).maybeSingle()
    if (!callerProfile || callerProfile.org_id !== invite.org_id) {
      return json({ error: 'this invite does not belong to your organization' }, 403)
    }

    // RATE LIMIT: this function previously had no throttle at all -- an org
    // owner could loop invite-creation to spam arbitrary addresses with no
    // limit. Cap at 15 invite emails/hour per caller.
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { count: recentCount } = await admin
      .from('email_rate_limit')
      .select('id', { count: 'exact', head: true })
      .eq('caller_id', caller.id)
      .eq('fn', 'send-invite-email')
      .gte('created_at', oneHourAgo)
    if ((recentCount || 0) >= 15) {
      return json({ error: 'too many invite emails sent recently, please wait a bit' }, 429)
    }
    await admin.from('email_rate_limit').insert({ caller_id: caller.id, fn: 'send-invite-email' })

    const orgName = (invite as any).organizations?.name || 'LOVA'
    const roleLabel: Record<string, string> = { owner: 'Business Owner', manager: 'Manager', staff: 'Staff', finance_admin: 'Finance Admin' }
    // SECURITY: appUrl comes from the client; only trust known app origins so
    // the emailed link can never point at an attacker-controlled site.
    const baseUrl = ALLOWED_APP_ORIGINS.includes(appUrl) ? appUrl : DEFAULT_APP_ORIGIN
    const link = `${baseUrl}/auth.html?invite=${encodeURIComponent(inviteToken)}`
    const html = `
      <p>Halo,</p>
      <p><b>${escapeHtml(callerProfile.name)}</b> mengundang kamu bergabung ke <b>${escapeHtml(orgName)}</b> di LOVA, sebagai <b>${roleLabel[invite.role] || invite.role}</b>.</p>
      <p><a href="${escapeHtml(link)}">Terima undangan &amp; buat akun</a></p>
      <p style="color:#8A9490;font-size:12px;">Kalau tombol di atas tidak berfungsi, salin link ini: ${escapeHtml(link)}</p>
    `

    const resendResp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: FROM_ADDRESS, to: invite.email, subject: `Undangan bergabung ke ${orgName} di LOVA`, html }),
    })
    const resendData = await resendResp.json()
    if (!resendResp.ok) {
      console.error('send-invite-email: Resend API error', resendResp.status, resendData)
      return json({ error: 'failed to send the invite email, please try again' }, 502)
    }

    return json({ ok: true, id: resendData.id })
  } catch (e) {
    console.error('send-invite-email: unexpected error', e)
    return json({ error: 'something went wrong, please try again' }, 500)
  }
})

function escapeHtml(s: string) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string))
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
