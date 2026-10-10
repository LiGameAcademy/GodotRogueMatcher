/** Select automatic references by stable metric/group/skill/level/H keys. */
export function referenceUpdates(inputs, previousRows) {
  const previous = new Map(previousRows.map(row=>[row[0],row]));
  const rows = [];
  const changes = [];
  for (const input of inputs) {
    const scope = JSON.stringify({skill_id:input.skill_id,level:input.level,H:input.H,
      stage_id:input.stage_id,action_type:input.action_type,build_hash:input.build_hash,
      pressure_band:input.pressure_band});
    const key = JSON.stringify([input.metric_id,input.group_hash,scope]);
    const old = previous.get(key);
    const eligible = input.selected && input.quality==='candidate' && Number.isFinite(input.value);
    const next = eligible ? input.value : old?.[3] ?? null;
    const reason = eligible ? 'updated' : old ? 'preserved_previous_reference' :
      !input.selected ? 'group_not_selected' : input.quality==='candidate' ? 'invalid_candidate' : input.quality;
    rows.push(eligible || !old ? [key,input.target,scope,next,input.unit,reason,input.dataset_hash,input.group_hash] : old);
    previous.delete(key);
    changes.push({metric_id:input.metric_id,skill_id:input.skill_id,level:input.level,H:input.H,
      group_hash:input.group_hash,old_value:old?.[3]??null,new_value:next,result:reason,
      method:input.method,n_runs:input.n_runs,n_events:input.n_events,dataset_hash:input.dataset_hash});
  }
  rows.push(...previous.values());
  return {rows,changes};
}
