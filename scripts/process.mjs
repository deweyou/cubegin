import {spawnSync} from 'node:child_process';
export function run(program,args,options={}) {
  console.log(program,...args);
  const result=spawnSync(program,args,{stdio:'inherit',...options});
  if(result.error) throw result.error;
  if(result.status!==0) throw new Error(`${program} exited with ${result.status}`);
}
