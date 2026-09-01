// Emails a LOVA team invite via Resend.
//
// The client only ever supplies the invite TOKEN, never the target
// email/role/org directly -- everything the email needs is looked up
// server-side from the `invites` row itself, after confirming the
// caller's own profile belongs to that invite's organization. Since
// only an org owner can INSERT into `invites` in the first place (see
// the identity_and_org migration's RLS policy), reaching this point at
// all already proves the caller legitimately created that invite.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const FROM_ADDRESS = 'LOVA <onboarding@resend.dev>'
// Same sandbox-domain caveat as send-notification-email: only delivers
// to the Resend account's own verified address until a real domain
// (e.g. lenusa.id) is verified at resend.com/domains.

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

    const { data: callerProfile } = await supabase.from('profiles').select('org_id, name').eq('id', caller.id).maybeSingle()
    if (!callerProfile || callerProfile.org_id !== invite.org_id) {
      return json({ error: 'this invite does not belong to your organization' }, 403)
    }

    const orgName = (invite as any).organizations?.name || 'LOVA'
    const roleLabel: Record<string, string> = { owner: 'Business Owner', manager: 'Manager', staff: 'Staff', finance_admin: 'Finance Admin' }
    const link = `${appUrl || 'https://lova-lenusa.netlify.app'}/auth.html?invite=${inviteToken}`
    const html = `
      <p>Halo,</p>
      <p><b>${escapeHtml(callerProfile.name)}</b> mengundang kamu bergabung ke <b>${escapeHtml(orgName)}</b> di LOVA, sebagai <b>${roleLabel[invite.role] || invite.role}</b>.</p>
      <p><a href="${link}">Terima undangan &amp; buat akun</a></p>
      <p style="color:#8A9490;font-size:12px;">Kalau tombol di atas tidak berfungsi, salin link ini: ${link}</p>
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
    if (!resendResp.ok) return json({ error: resendData }, resendResp.status)

    return json({ ok: true, id: resendData.id })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

function escapeHtml(s: string) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string))
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
