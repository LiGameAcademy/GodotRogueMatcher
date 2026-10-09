import test from 'node:test';
import assert from 'node:assert/strict';
import {referenceUpdates} from './reference_updates.mjs';
const input = {metric_id:'score',group_hash:'group1',skill_id:'skill',level:1,H:20,
  value:5,selected:true,quality:'candidate',target:'auto_reference.score',unit:'points/window',dataset_hash:'d'};
test('valid zero is installed, missing candidate is rejected',()=>{
  assert.equal(referenceUpdates([{...input,value:0}],[]).rows[0][3],0);
  assert.equal(referenceUpdates([{...input,value:null}],[]).rows[0][3],null);
});
test('unselected or insufficient data preserves previous reference',()=>{
  const old=referenceUpdates([input],[]).rows;
  const update=referenceUpdates([{...input,value:100,quality:'insufficient_samples'}],old);
  assert.equal(update.rows[0][3],5);
  assert.equal(referenceUpdates([{...input,value:100,selected:false}],old).rows[0][3],5);
});
test('other group, level and H do not overwrite a reference',()=>{
  const old=referenceUpdates([input],[]).rows;
  for(const change of [{group_hash:'group2'},{level:2},{H:50}]) {
    const result=referenceUpdates([{...input,...change,value:100}],old);
    assert.equal(result.rows.length,2);
    assert.equal(result.rows[1][3],5);
  }
});
test('repeated import does not duplicate reference rows',()=>{
  const first=referenceUpdates([input],[]).rows;
  assert.deepEqual(referenceUpdates([input],first).rows,first);
});
