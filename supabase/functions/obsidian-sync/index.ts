// Generates an Obsidian vault (Team/, Projects/, Tasks/ markdown notes,
// cross-linked with [[wikilinks]]) from the current state of LOVA's
// data. Returns the whole vault as { files: { "path.md": "content" } }
// -- writing it to disk and pushing to git happens in the GitHub
// Actions workflow that calls this, not here (Edge Functions have no
// persistent filesystem or git binary).
//
// Auth: a shared secret header, not a user session -- this runs from
// a scheduled CI job with no browser/user context. Uses the service
// role key to read across the whole database (bypassing RLS), which
// is why the secret check matters: anyone holding it can read every
// org's data, so it must never leave Supabase secrets + the GitHub
// Actions secret it's mirrored into.
import { createClient } from 'jsr:@supabase/supabase-js@2.116.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'x-sync-secret, content-type',
}

const STATUS_LABEL: Record<string, string> = {
  todo: 'Belum Dikerjakan', progress: 'Sedang Dikerjakan', review: 'Review', revisi: 'Revisi', done: 'Selesai',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const secret = req.headers.get('x-sync-secret')
  const expected = Deno.env.get('OBSIDIAN_SYNC_SECRET') || ''
  if (!secret || !(await timingSafeEqual(secret, expected))) {
    return json({ error: 'unauthorized' }, 401)
  }

  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    // SECURITY: this function uses the service-role key, which bypasses RLS
    // entirely -- without an explicit org filter it would read and commit
    // EVERY organization's data into this one vault the moment a second org
    // signs up (the app supports self-serve org creation). Resolve exactly
    // one org (see the obsidian_sync_org_scope migration) and scope every
    // query to it.
    const { data: syncOrg, error: orgErr } = await admin
      .from('organizations')
      .select('id')
      .eq('obsidian_sync_enabled', true)
      .maybeSingle()
    if (orgErr || !syncOrg) {
      console.error('obsidian-sync: could not resolve the sync-enabled organization', orgErr)
      return json({ error: 'sync not configured' }, 500)
    }
    const orgId = syncOrg.id

    // divisions/profiles/projects/general_tasks all carry org_id directly.
    // phases and tasks don't (they only reference project_id/phase_id), so
    // they're scoped by first resolving this org's project/phase ids, then
    // filtering with plain .in() -- simpler and easier to verify correct
    // than a multi-level PostgREST embedded-filter expression.
    const [
      { data: divisions, error: e1 },
      { data: profiles, error: e2 },
      { data: projects, error: e3 },
      { data: generalTasks, error: e6 },
    ] = await Promise.all([
      admin.from('divisions').select('*').eq('org_id', orgId),
      admin.from('profiles').select('*').eq('org_id', orgId),
      admin.from('projects').select('*').eq('org_id', orgId),
      admin.from('general_tasks').select('*').eq('org_id', orgId),
    ])
    let firstError = e1 || e2 || e3 || e6
    if (firstError) {
      console.error('obsidian-sync: failed to load data', firstError)
      return json({ error: 'failed to load sync data' }, 500)
    }

    const projectIds = (projects || []).map((p: any) => p.id)
    const { data: phases, error: e4 } = projectIds.length
      ? await admin.from('phases').select('*').in('project_id', projectIds)
      : { data: [], error: null }
    firstError = e4
    if (firstError) {
      console.error('obsidian-sync: failed to load phases', firstError)
      return json({ error: 'failed to load sync data' }, 500)
    }

    const phaseIds = (phases || []).map((ph: any) => ph.id)
    const { data: tasks, error: e5 } = phaseIds.length
      ? await admin.from('tasks').select('*').in('phase_id', phaseIds)
      : { data: [], error: null }
    firstError = e5
    if (firstError) {
      console.error('obsidian-sync: failed to load tasks', firstError)
      return json({ error: 'failed to load sync data' }, 500)
    }

    const divisionById = new Map((divisions || []).map((d: any) => [d.id, d]))
    const profileById = new Map((profiles || []).map((p: any) => [p.id, p]))
    const projectById = new Map((projects || []).map((p: any) => [p.id, p]))
    const phaseById = new Map((phases || []).map((p: any) => [p.id, p]))

    const usedNames: Record<string, Set<string>> = { Team: new Set(), Projects: new Set(), Tasks: new Set() }
    function slug(s: string) {
      return (String(s || 'untitled').replace(/[\\/:*?"<>|#^[\]]/g, '').trim().replace(/\s+/g, ' ')) || 'untitled'
    }
    function uniqueName(folder: string, base: string, id: string) {
      let name = slug(base)
      if (usedNames[folder].has(name)) name = `${name} (${id.slice(0, 6)})`
      usedNames[folder].add(name)
      return name
    }

    const personFile = new Map<string, string>()
    ;(profiles || []).forEach((p: any) => personFile.set(p.id, uniqueName('Team', p.name, p.id)))

    const projectFile = new Map<string, string>()
    ;(projects || []).forEach((p: any) => projectFile.set(p.id, uniqueName('Projects', p.title, p.id)))

    const taskFile = new Map<string, string>()
    ;(tasks || []).forEach((t: any) => taskFile.set(t.id, uniqueName('Tasks', t.name, t.id)))
    ;(generalTasks || []).forEach((g: any) => taskFile.set(g.id, uniqueName('Tasks', g.name, g.id)))

    const files: Record<string, string> = {}

    // ---- Team notes ----
    ;(profiles || []).forEach((p: any) => {
      const div = divisionById.get(p.division_id)
      const myProjectIds = new Set<string>()
      const myTaskLinks: string[] = []
      ;(tasks || []).forEach((t: any) => {
        if (t.pic_id === p.id || (t.secondary_pic || []).includes(p.id)) {
          const ph = phaseById.get(t.phase_id)
          if (ph) myProjectIds.add((ph as any).project_id)
          myTaskLinks.push(`[[${taskFile.get(t.id)}]]`)
        }
      })
      ;(generalTasks || []).forEach((g: any) => {
        if (g.pic_id === p.id) myTaskLinks.push(`[[${taskFile.get(g.id)}]]`)
      })
      const projectLinks = [...myProjectIds].map((pid) => `[[${projectFile.get(pid)}]]`)

      const md = `# ${p.name}\n\n` +
        `**Jabatan:** ${p.job_title || '-'}\n` +
        `**Divisi:** ${div ? `[[${(div as any).name}]]` : '-'}\n` +
        `**Peran:** ${p.role}\n\n` +
        `## Projects\n${projectLinks.length ? projectLinks.map((l) => '- ' + l).join('\n') : '_Tidak ada_'}\n\n` +
        `## Tasks\n${myTaskLinks.length ? myTaskLinks.map((l) => '- ' + l).join('\n') : '_Tidak ada_'}\n`
      files[`Team/${personFile.get(p.id)}.md`] = md
    })

    // ---- Project notes ----
    ;(projects || []).forEach((pr: any) => {
      const div = divisionById.get(pr.division_id)
      const owner = profileById.get(pr.created_by)
      const taskLinks: string[] = []
      ;(phases || []).filter((ph: any) => ph.project_id === pr.id).forEach((ph: any) => {
        ;(tasks || []).filter((t: any) => t.phase_id === ph.id).forEach((t: any) => taskLinks.push(`[[${taskFile.get(t.id)}]]`))
      })
      const md = `# ${pr.title}\n\n` +
        `**Klien:** ${pr.client || '-'}\n` +
        `**Divisi:** ${div ? `[[${(div as any).name}]]` : '-'}\n` +
        `**Owner:** ${owner ? `[[${personFile.get((owner as any).id)}]]` : '-'}\n` +
        `**Prioritas:** ${pr.priority} · **Effort:** ${pr.effort}\n` +
        `**Status:** ${pr.active ? 'Aktif' : 'Nonaktif'}\n` +
        `**Mulai:** ${pr.start_date || '-'} · **Deadline:** ${pr.deadline || '-'}\n\n` +
        `## Tasks\n${taskLinks.length ? taskLinks.map((l) => '- ' + l).join('\n') : '_Belum ada task_'}\n\n` +
        `## Deskripsi\n${pr.description || '_Tidak ada deskripsi_'}\n`
      files[`Projects/${projectFile.get(pr.id)}.md`] = md
    })

    // ---- Task notes (project tasks) ----
    ;(tasks || []).forEach((t: any) => {
      const ph = phaseById.get(t.phase_id)
      const pr = ph ? projectById.get((ph as any).project_id) : null
      const pic = profileById.get(t.pic_id)
      const md = `# ${t.name}\n\n` +
        `**Assigned to:** ${pic ? `[[${personFile.get((pic as any).id)}]]` : '_Belum ditugaskan_'}\n` +
        `**Project:** ${pr ? `[[${projectFile.get((pr as any).id)}]]` : '-'}\n` +
        (ph ? `**Phase:** ${(ph as any).name}\n` : '') +
        `**Status:** ${STATUS_LABEL[t.status] || t.status}\n` +
        `**Deadline:** ${t.deadline || '-'}\n\n` +
        (t.notes ? `## Catatan\n${t.notes}\n` : '')
      files[`Tasks/${taskFile.get(t.id)}.md`] = md
    })

    // ---- Task notes (general tasks) ----
    ;(generalTasks || []).forEach((g: any) => {
      const div = divisionById.get(g.division_id)
      const pic = profileById.get(g.pic_id)
      const md = `# ${g.name}\n\n` +
        `**Assigned to:** ${pic ? `[[${personFile.get((pic as any).id)}]]` : '_Belum ditugaskan_'}\n` +
        `**Divisi:** ${div ? `[[${(div as any).name}]]` : '-'}\n` +
        `**Status:** ${STATUS_LABEL[g.status] || g.status}\n` +
        `**Deadline:** ${g.deadline || '-'}\n\n` +
        (g.notes ? `## Catatan\n${g.notes}\n` : '')
      files[`Tasks/${taskFile.get(g.id)}.md`] = md
    })

    return json({
      files,
      generatedAt: new Date().toISOString(),
      counts: { team: (profiles || []).length, projects: (projects || []).length, tasks: (tasks || []).length + (generalTasks || []).length },
    })
  } catch (e) {
    console.error('obsidian-sync: unexpected error', e)
    return json({ error: 'sync failed' }, 500)
  }
})

// Plain !== short-circuits as soon as characters differ, which leaks how
// many leading characters of a guessed secret were correct via response
// timing. Compares every character regardless of an early mismatch, and
// normalizes length first (via hashing) so unequal-length secrets don't
// leak length either.
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder()
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(a)),
    crypto.subtle.digest('SHA-256', enc.encode(b)),
  ])
  const va = new Uint8Array(ha)
  const vb = new Uint8Array(hb)
  let diff = 0
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i]
  return diff === 0
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
