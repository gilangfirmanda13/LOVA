// Fully removes a team member: deletes their auth.users row (profiles
// cascades via its FK to auth.users ON DELETE CASCADE), so both their
// login and their org membership are gone -- not just unlinked. Needs
// the service role since deleting an auth user is an admin-only
// operation the anon/publishable key can never perform, which is why
// this can't just be a client-side delete like the rest of the app's
// writes.
//
// Authorization is enforced here in code (not RLS, since auth.users
// deletion bypasses RLS entirely): the caller must be an 'owner' in
// the SAME org as the target, and can't remove themselves.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { targetProfileId } = await req.json()
    if (!targetProfileId) return json({ error: 'targetProfileId is required' }, 400)

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'missing Authorization header' }, 401)

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user: caller } } = await supabase.auth.getUser()
    if (!caller) return json({ error: 'unauthorized' }, 401)
    if (caller.id === targetProfileId) return json({ error: 'you cannot remove yourself' }, 400)

    const { data: callerProfile } = await supabase.from('profiles').select('org_id, role').eq('id', caller.id).maybeSingle()
    if (!callerProfile || callerProfile.role !== 'owner') {
      return json({ error: 'only the business owner can remove team members' }, 403)
    }

    const { data: targetProfile } = await supabase.from('profiles').select('org_id').eq('id', targetProfileId).maybeSingle()
    if (!targetProfile) return json({ error: 'member not found' }, 404)
    if (targetProfile.org_id !== callerProfile.org_id) {
      return json({ error: 'this member is not in your organization' }, 403)
    }

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { error: deleteError } = await admin.auth.admin.deleteUser(targetProfileId)
    if (deleteError) return json({ error: deleteError.message }, 500)

    return json({ ok: true })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
