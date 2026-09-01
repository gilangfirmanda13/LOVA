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
import { createClient } from 'jsr:@supabase/supabase-js@2'

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
  if (!secret || secret !== Deno.env.get('OBSIDIAN_SYNC_SECRET')) {
    return json({ error: 'unauthorized' }, 401)
  }

  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    const [
      { data: divisions, error: e1 },
      { data: profiles, error: e2 },
      { data: projects, error: e3 },
      { data: phases, error: e4 },
      { data: tasks, error: e5 },
      { data: generalTasks, error: e6 },
    ] = await Promise.all([
      admin.from('divisions').select('*'),
      admin.from('profiles').select('*'),
      admin.from('projects').select('*'),
      admin.from('phases').select('*'),
      admin.from('tasks').select('*'),
      admin.from('general_tasks').select('*'),
    ])
    const firstError = e1 || e2 || e3 || e4 || e5 || e6
    if (firstError) return json({ error: String(firstError) }, 500)

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
    return json({ error: String(e) }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
