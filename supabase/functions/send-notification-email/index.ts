// Sends a LOVA notification as an email via Resend.
//
// Called from the client (notifyUser() in lenusa-flow-v65c-offline.html)
// whenever a real cross-user notification is created. Runs server-side
// because Resend has no browser CORS support and its API key must never
// reach client code — anyone who saw it in page source could send email
// as this account.
//
// The caller only ever supplies a recipient PROFILE id, never an email
// address directly — this function resolves the real address itself
// (via the admin API, using auth.users as the source of truth) and
// checks the recipient is in the same organization as the caller before
// sending anything, so a compromised or buggy client can't be used to
// spam arbitrary email addresses.
import { createClient } from 'jsr:@supabase/supabase-js@2.116.0'

const FROM_ADDRESS = 'LOVA <onboarding@resend.dev>'
// ^ Resend's shared testing domain. Works with zero setup, but only
// delivers to the email the Resend account itself was signed up with.
// To actually reach teammates, verify a real domain (e.g. lenusa.id) in
// the Resend dashboard, then change this to something like
// 'LOVA <notifications@lenusa.id>'.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { recipientProfileId, subject, bodyHtml } = await req.json()
    if (!recipientProfileId || !subject || !bodyHtml) {
      return json({ error: 'recipientProfileId, subject, and bodyHtml are required' }, 400)
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'missing Authorization header' }, 401)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user: caller } } = await supabase.auth.getUser()
    if (!caller) return json({ error: 'unauthorized' }, 401)

    const { data: callerProfile } = await supabase.from('profiles').select('org_id').eq('id', caller.id).maybeSingle()
    const { data: recipientProfile } = await supabase.from('profiles').select('org_id').eq('id', recipientProfileId).maybeSingle()
    if (!callerProfile || !recipientProfile || callerProfile.org_id !== recipientProfile.org_id) {
      return json({ error: 'recipient is not in your organization' }, 403)
    }

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    // RATE LIMIT: this function previously had no throttle at all -- any org
    // member could loop task reassignment/@mentions to trigger unlimited
    // Resend calls. Cap at 30 sends/hour per caller (generous for a genuinely
    // busy day of real notifications, tight enough to make a spam loop
    // pointless). The row is written after this check regardless of what
    // happens next, so a failed/retried send still counts.
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { count: recentCount } = await admin
      .from('email_rate_limit')
      .select('id', { count: 'exact', head: true })
      .eq('caller_id', caller.id)
      .eq('fn', 'send-notification-email')
      .gte('created_at', oneHourAgo)
    if ((recentCount || 0) >= 30) {
      return json({ error: 'too many notification emails sent recently, please wait a bit' }, 429)
    }
    await admin.from('email_rate_limit').insert({ caller_id: caller.id, fn: 'send-notification-email' })

    const { data: authUserData, error: userErr } = await admin.auth.admin.getUserById(recipientProfileId)
    const recipientEmail = authUserData?.user?.email
    if (userErr || !recipientEmail) return json({ error: 'recipient has no known email' }, 404)

    const resendResp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: FROM_ADDRESS, to: recipientEmail, subject, html: bodyHtml }),
    })
    const resendData = await resendResp.json()
    if (!resendResp.ok) {
      console.error('send-notification-email: Resend API error', resendResp.status, resendData)
      return json({ error: 'failed to send the notification email' }, 502)
    }

    return json({ ok: true, id: resendData.id })
  } catch (e) {
    console.error('send-notification-email: unexpected error', e)
    return json({ error: 'something went wrong, please try again' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
